local OVERLAY_ID = "emof-3d-pipes-overlay"
local EMOF_INTERFACE = "extensible_map_overlay_framework"
local EMOF_OVERLAY_TOGGLED = "emof-on-map-overlay-toggled"

local CHUNK_SIZE = 32
local Z_LAYERS = 10
local CAMERA_Z = 30
local PIPE_RADIUS = 0.18
local CYLINDER_SIDES = 6

local GENERATION_INTERVAL = 3
local RENDER_INTERVAL = 4
local RENDER_RADIUS = 34
local MAX_HEADS = 8
local MAX_NETWORK_SEGMENTS = 1600
local MAX_RENDER_SEGMENTS = 1400
local MAX_RENDER_FACES = 7200

local RNG_MOD = 2147483647
local RNG_MULT = 48271

local DIRECTIONS = {
  {x = 1, y = 0, z = 0},
  {x = -1, y = 0, z = 0},
  {x = 0, y = 1, z = 0},
  {x = 0, y = -1, z = 0},
  {x = 0, y = 0, z = 1},
  {x = 0, y = 0, z = -1}
}

local PIPE_COLORS = {
  {r = 0.18, g = 0.95, b = 0.35},
  {r = 0.28, g = 0.85, b = 1.00},
  {r = 1.00, g = 0.72, b = 0.20},
  {r = 0.85, g = 0.45, b = 1.00},
  {r = 0.95, g = 0.95, b = 0.95}
}

local function ensure_storage()
  storage.players = storage.players or {}
  storage.networks = storage.networks or {}
end

local function network_key(force_name, surface_name)
  return force_name .. "\n" .. surface_name
end

local function cell_key(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

local function random_unit(network)
  network.rng = (network.rng * RNG_MULT) % RNG_MOD
  return network.rng / RNG_MOD
end

local function random_int(network, min_value, max_value)
  return min_value + math.floor(random_unit(network) * (max_value - min_value + 1))
end

local function get_player_state(player_index)
  ensure_storage()
  local state = storage.players[player_index]
  if not state then
    state = {
      enabled = false,
      objects = {},
      object_surface_name = nil
    }
    storage.players[player_index] = state
  end
  return state
end

local function destroy_player_objects(state)
  if not state or not state.objects then return end

  for _, object in pairs(state.objects) do
    if object and object.valid then
      object.destroy()
    end
  end

  state.objects = {}
  state.object_surface_name = nil
end

local function get_network(force, surface)
  ensure_storage()

  local key = network_key(force.name, surface.name)
  local network = storage.networks[key]

  if not network then
    local seed = force.index * 1000003 + surface.index * 9176 + 1337
    seed = seed % RNG_MOD
    if seed <= 0 then seed = 1 end

    network = {
      force_name = force.name,
      surface_name = surface.name,
      rng = seed,
      heads = {},
      segments = {},
      occupied = {}
    }

    storage.networks[key] = network
  end

  return network
end

local function is_cell_available(force, surface, network, x, y, z)
  if z < 0 or z >= Z_LAYERS then return false end
  if network.occupied[cell_key(x, y, z)] then return false end
  return force.is_chunk_charted(surface, {x = x, y = y})
end

local function reset_network(network)
  network.heads = {}
  network.segments = {}
  network.occupied = {}
end

local function spawn_head(network, force, surface, active_centers)
  if not active_centers or #active_centers == 0 then return false end

  for _ = 1, 48 do
    local center = active_centers[random_int(network, 1, #active_centers)]
    local x = center.x + random_int(network, -RENDER_RADIUS, RENDER_RADIUS)
    local y = center.y + random_int(network, -RENDER_RADIUS, RENDER_RADIUS)
    local z = random_int(network, 0, Z_LAYERS - 1)

    if is_cell_available(force, surface, network, x, y, z) then
      network.occupied[cell_key(x, y, z)] = true
      network.heads[#network.heads + 1] = {
        x = x,
        y = y,
        z = z,
        dx = 0,
        dy = 0,
        dz = 0,
        color_index = random_int(network, 1, #PIPE_COLORS)
      }
      return true
    end
  end

  return false
end

local function try_move_head(network, force, surface, head)
  for attempt = 1, 10 do
    local direction

    if attempt == 1 and (head.dx ~= 0 or head.dy ~= 0 or head.dz ~= 0) and random_unit(network) < 0.62 then
      direction = {x = head.dx, y = head.dy, z = head.dz}
    else
      direction = DIRECTIONS[random_int(network, 1, #DIRECTIONS)]
      if direction.z ~= 0 and random_unit(network) < 0.55 then
        direction = DIRECTIONS[random_int(network, 1, 4)]
      end
    end

    local nx = head.x + direction.x
    local ny = head.y + direction.y
    local nz = head.z + direction.z

    if is_cell_available(force, surface, network, nx, ny, nz) then
      network.occupied[cell_key(nx, ny, nz)] = true

      network.segments[#network.segments + 1] = {
        ax = head.x,
        ay = head.y,
        az = head.z,
        bx = nx,
        by = ny,
        bz = nz,
        color_index = head.color_index
      }

      head.x = nx
      head.y = ny
      head.z = nz
      head.dx = direction.x
      head.dy = direction.y
      head.dz = direction.z

      return true
    end
  end

  return false
end

local function advance_network(network, active_centers)
  local force = game.forces[network.force_name]
  local surface = game.surfaces[network.surface_name]
  if not force or not surface then return end

  if #network.segments >= MAX_NETWORK_SEGMENTS then
    reset_network(network)
  end

  while #network.heads < MAX_HEADS do
    if not spawn_head(network, force, surface, active_centers) then
      break
    end
  end

  local next_heads = {}
  for _, head in pairs(network.heads) do
    if try_move_head(network, force, surface, head) then
      next_heads[#next_heads + 1] = head
    end
  end

  network.heads = next_heads
end

local function project_point(point, camera)
  local depth = camera.z - point.z
  if depth <= 0.25 then return nil end

  local scale = camera.z / depth
  return {
    x = camera.x + (point.x - camera.x) * scale,
    y = camera.y + (point.y - camera.y) * scale,
    depth = depth
  }
end

local function cell_center(x, y, z)
  return {
    x = x + 0.5,
    y = y + 0.5,
    z = z + 0.75
  }
end

local function segment_basis(segment)
  local dx = segment.bx - segment.ax
  local dy = segment.by - segment.ay

  if dx ~= 0 then
    return {x = 0, y = 1, z = 0}, {x = 0, y = 0, z = 1}
  elseif dy ~= 0 then
    return {x = 1, y = 0, z = 0}, {x = 0, y = 0, z = 1}
  else
    return {x = 1, y = 0, z = 0}, {x = 0, y = 1, z = 0}
  end
end

local function offset_point(point, basis_a, basis_b, angle)
  local ca = math.cos(angle) * PIPE_RADIUS
  local sa = math.sin(angle) * PIPE_RADIUS

  return {
    x = point.x + basis_a.x * ca + basis_b.x * sa,
    y = point.y + basis_a.y * ca + basis_b.y * sa,
    z = point.z + basis_a.z * ca + basis_b.z * sa
  }
end

local function normal_for_angle(basis_a, basis_b, angle)
  local ca = math.cos(angle)
  local sa = math.sin(angle)

  return {
    x = basis_a.x * ca + basis_b.x * sa,
    y = basis_a.y * ca + basis_b.y * sa,
    z = basis_a.z * ca + basis_b.z * sa
  }
end

local function face_color(base_color, normal, depth)
  local light = 0.46 + math.max(0, normal.z) * 0.42
  local depth_fade = math.max(0.58, math.min(1.0, 1.08 - depth / 60))
  local shade = light * depth_fade

  return {
    r = base_color.r * shade,
    g = base_color.g * shade,
    b = base_color.b * shade,
    a = 0.78
  }
end

local function add_segment_faces(faces, segment, camera)
  if #faces >= MAX_RENDER_FACES then return end

  local a = cell_center(segment.ax, segment.ay, segment.az)
  local b = cell_center(segment.bx, segment.by, segment.bz)
  local basis_a, basis_b = segment_basis(segment)
  local base_color = PIPE_COLORS[segment.color_index] or PIPE_COLORS[1]

  for side = 1, CYLINDER_SIDES do
    if #faces >= MAX_RENDER_FACES then return end

    local angle_1 = ((side - 1) / CYLINDER_SIDES) * math.pi * 2
    local angle_2 = (side / CYLINDER_SIDES) * math.pi * 2
    local angle_mid = (angle_1 + angle_2) * 0.5
    local normal = normal_for_angle(basis_a, basis_b, angle_mid)

    -- The underside is not visible from the chart camera. This trims roughly a
    -- third of horizontal-cylinder faces without changing the perceived shape.
    if normal.z > -0.45 then
      local p1 = project_point(offset_point(a, basis_a, basis_b, angle_1), camera)
      local p2 = project_point(offset_point(b, basis_a, basis_b, angle_1), camera)
      local p3 = project_point(offset_point(a, basis_a, basis_b, angle_2), camera)
      local p4 = project_point(offset_point(b, basis_a, basis_b, angle_2), camera)

      if p1 and p2 and p3 and p4 then
        local depth = (p1.depth + p2.depth + p3.depth + p4.depth) * 0.25
        faces[#faces + 1] = {
          depth = depth,
          vertices = {
            {x = p1.x * CHUNK_SIZE, y = p1.y * CHUNK_SIZE},
            {x = p2.x * CHUNK_SIZE, y = p2.y * CHUNK_SIZE},
            {x = p3.x * CHUNK_SIZE, y = p3.y * CHUNK_SIZE},
            {x = p4.x * CHUNK_SIZE, y = p4.y * CHUNK_SIZE}
          },
          color = face_color(base_color, normal, depth)
        }
      end
    end
  end
end

local function ensure_render_object(player, state, index, surface)
  local object = state.objects[index]
  if object and object.valid then
    return object
  end

  object = rendering.draw_polygon{
    surface = surface,
    render_mode = "chart",
    color = {r = 1, g = 1, b = 1, a = 0},
    vertices = {{0, 0}, {0, 0}, {0, 0}, {0, 0}},
    players = {player.index},
    visible = false
  }

  state.objects[index] = object
  return object
end

local function render_player(player)
  local state = get_player_state(player.index)
  if not state.enabled or not player.connected then return end

  local surface = player.surface
  if not surface then return end

  if state.object_surface_name ~= surface.name then
    destroy_player_objects(state)
    state.object_surface_name = surface.name
  end

  local network = get_network(player.force, surface)
  local camera = {
    x = player.position.x / CHUNK_SIZE,
    y = player.position.y / CHUNK_SIZE,
    z = CAMERA_Z
  }

  local center_x = camera.x
  local center_y = camera.y
  local segments_used = 0
  local faces = {}

  for i = #network.segments, 1, -1 do
    if segments_used >= MAX_RENDER_SEGMENTS or #faces >= MAX_RENDER_FACES then
      break
    end

    local segment = network.segments[i]
    local mx = (segment.ax + segment.bx + 1) * 0.5
    local my = (segment.ay + segment.by + 1) * 0.5

    if math.abs(mx - center_x) <= RENDER_RADIUS and math.abs(my - center_y) <= RENDER_RADIUS then
      segments_used = segments_used + 1
      add_segment_faces(faces, segment, camera)
    end
  end

  table.sort(faces, function(a, b)
    return a.depth > b.depth
  end)

  for i, face in ipairs(faces) do
    local object = ensure_render_object(player, state, i, surface)
    object.vertices = face.vertices
    object.color = face.color
    object.visible = true
  end

  for i = #faces + 1, #state.objects do
    local object = state.objects[i]
    if object and object.valid then
      object.visible = false
    end
  end
end

local function set_player_enabled(player_index, enabled, silent)
  local player = game.get_player(player_index)
  if not player then return end

  local state = get_player_state(player_index)
  state.enabled = enabled and true or false

  if not state.enabled then
    destroy_player_objects(state)
  end

  if player.connected and not silent then
    player.print(state.enabled and {"emof-3d-pipes.enabled"} or {"emof-3d-pipes.disabled"})
  end
end

local function active_centers_by_network()
  local result = {}

  for _, player in pairs(game.connected_players) do
    local state = get_player_state(player.index)
    if state.enabled then
      local surface = player.surface
      if surface then
        local key = network_key(player.force.name, surface.name)
        local centers = result[key]
        if not centers then
          centers = {
            force_name = player.force.name,
            surface_name = surface.name,
            centers = {}
          }
          result[key] = centers
        end

        centers.centers[#centers.centers + 1] = {
          x = math.floor(player.position.x / CHUNK_SIZE),
          y = math.floor(player.position.y / CHUNK_SIZE)
        }
      end
    end
  end

  return result
end

local function is_overlay_enabled(player_index)
  return remote.call(EMOF_INTERFACE, "get_player_toggle", player_index, OVERLAY_ID) == true
end

local function sync_player(player)
  if not (player and player.valid) then
    return
  end

  set_player_enabled(player.index, is_overlay_enabled(player.index), true)
end

local function sync_all_players()
  for _, player in pairs(game.connected_players) do
    sync_player(player)
  end
end

local function on_overlay_toggled(event)
  if event.id ~= OVERLAY_ID then
    return
  end

  set_player_enabled(event.player_index, event.enabled == true, false)
end

local function register_emof_events()
  local overlay_proto = prototypes.custom_event[EMOF_OVERLAY_TOGGLED]
  if not (overlay_proto and overlay_proto.valid) then
    error("emof-3d-pipes requires Extensible Map Overlay Framework custom event: " .. EMOF_OVERLAY_TOGGLED)
  end

  script.on_event(overlay_proto.event_id, on_overlay_toggled)
end

register_emof_events()

script.on_init(function()
  ensure_storage()
end)

script.on_configuration_changed(function()
  ensure_storage()
  sync_all_players()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  sync_player(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_player_left_game, function(event)
  local state = get_player_state(event.player_index)
  destroy_player_objects(state)
end)

script.on_nth_tick(GENERATION_INTERVAL, function()
  ensure_storage()

  local active = active_centers_by_network()

  for _, active_info in pairs(active) do
    local force = game.forces[active_info.force_name]
    local surface = game.surfaces[active_info.surface_name]
    if force and surface then
      local network = get_network(force, surface)
      advance_network(network, active_info.centers)
    end
  end
end)

script.on_nth_tick(RENDER_INTERVAL, function()
  ensure_storage()

  for _, player in pairs(game.connected_players) do
    render_player(player)
  end
end)
