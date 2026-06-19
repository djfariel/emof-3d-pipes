# EMOF 3D Pipes Overlay

Companion mod for **[Extensible Map Overlay Framework](https://mods.factorio.com/mod/extensible-map-overlay-framework)**. Renders a Windows 3D Pipes-inspired chart overlay using perspective-projected pipe segments. This is a demonstration. I cannot stress this enough: this is incredibly performance-heavy and should NOT be used in an actualy game you intend to play through.

**Requires [Extensible Map Overlay Framework](https://mods.factorio.com/mod/extensible-map-overlay-framework) >= 0.1.0.**

## Quick start

1. Enable **Extensible Map Overlay Framework** and **EMOF 3D Pipes Overlay**.
2. Open the map in chart view and open **Chart Controls**.
3. Toggle **3D Pipes** to watch the overlay grow around your charted area.

## How it works

- Pipe `x/y` positions follow Factorio chunk coordinates; `z` is a virtual height layer.
- Horizontal growth requires the target chunk to be charted for the player's force.
- The pipe network is shared per force/surface; rendering is per-player from each chart camera position.

Source: [github.com/djfariel/emof-3d-pipes](https://github.com/djfariel/emof-3d-pipes). Integration guide: [EMOF documentation.md](https://github.com/djfariel/extensible-map-overlay-framework/blob/main/documentation.md).
