# Zynith UI (Quickshell layer)

The QML half of Zynith 2.0. It runs **beside** the native shell during the migration and takes no exclusive
role: no notification server, tray watcher, polkit or secret agent, and no session lock. Those stay with the
native shell until each one is moved deliberately.

```sh
ui/zynith-ui start      # builds Zynith.Native if needed, then starts /usr/bin/quickshell
ui/zynith-ui stop       # rollback: the native shell is untouched and keeps running
ui/zynith-ui ipc status
ui/zynith-ui ipc panel home
ui/zynith-ui ipc profile balanced     # performance | balanced | enhanced | max | auto
ui/zynith-ui log
```

Config: `~/.config/zynith/shell.json` (created with defaults on first run; edits reload live).
Palette: `~/.local/state/zynith/palette.json`, written by the native theme engine from `templates/palette.json`.

## Layout

| Directory | Holds | Rule |
|---|---|---|
| `Common/` | tokens: Theme, Type, Metrics, Motion, Icons, Paths | values only, no behaviour |
| `Services/` | one singleton per domain (Audio, Media, Network, Power, Workspaces, System, Config, ExperiencePolicy, PanelRouter…) | the only place that touches the system; surfaces read these |
| `Components/` | primitives: Glass, Label, Icon, Interactive, Slider, Segmented, Tile, Meter, BlurRegion | presentation only |
| `Widgets/` | widget types and their Registry | read services, never poll, never spawn |
| `Modules/` | surfaces: Bar, Panels | compose components and widgets |
| `native/` | Zynith.Native, the in-process C++ QML module (niri model; later spectrum, sampler) | Qt public API only |

Every quality/cost decision goes through `Services/ExperiencePolicy.qml` (Performance, Balanced, Enhanced,
Max Experience). Components read knobs such as `ExperiencePolicy.blur` or `Motion.reveal`; none of them checks the
profile name. Per-knob overrides go in `shell.json` under `experience.overrides`.

Icons: `tools/gen-icons.py` writes `Common/IconMap.js` from the repository's Tabler map; add names there.
Fonts in `assets/fonts/` are OFL (see `OFL.txt`); the icon font is the repository's `assets/fonts` (MIT).
