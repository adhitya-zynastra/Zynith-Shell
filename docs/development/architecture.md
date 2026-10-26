# Architecture

Zynith is three programs on top of an unmodified compositor, plus the packaging that turns them into a desktop
session.

```
 niri (compositor, window manager)
  ├─ spawn-at-startup: zynith-ui native supervise ──► zynith-shell  (the native shell: services, lock, wallpaper)
  └─ spawn-at-startup: zynith-ui start ─────────────► quickshell -p ui/shell.qml  (the Zynith UI)
                                                         └─ Zynith.Native (C++ QML plugin)
```

| Part | Source | Runs as | Responsibility |
|---|---|---|---|
| **niri** | Fedora's `niri` package, unmodified | the compositor | windows, workspaces, outputs, input, blur, animations |
| **native shell** | `src/` (C++23, meson) | `zynith-shell` | long-running services (PipeWire audio, NetworkManager, UPower, Bluetooth, brightness, idle), the notification bus hand-over, the lock screen (PAM), the wallpaper renderer, the theme engine that derives a palette from the wallpaper, IPC (`zynith-shell msg …`) |
| **Zynith UI** | `ui/` (QML) | `quickshell -p …/shell.qml` | everything drawn on screen: bars, Zynith Island, Control Panel, launcher, notifications, OSD, desktop widgets; and the Settings app (`settings.qml`) |
| **Zynith.Native** | `ui/native/` (C++, cmake) | a QML plugin loaded by the UI | what QML cannot do cheaply or safely: niri state and config writes, display configuration, audio spectrum, network details, backlight, the config file store, thumbnails |
| **zynith-ui** | `ui/zynith-ui` (bash) | from niri and key bindings | starts and supervises both processes, restarts the native shell if it dies, routes commands to the UI (`zynith-ui ipc …`) |

The native shell includes MIT-licensed code from the shell it was first built from (see [CREDITS](../../CREDITS.md)).

## Source tree

| Path | What |
|---|---|
| `src/` | the native shell |
| `tests/` | the native shell's unit tests |
| `assets/` | the native shell's assets: translations, palette templates, shaders, fonts, the default wallpaper |
| `ui/shell.qml`, `ui/settings.qml` | the desktop UI and the Settings app |
| `ui/Common/` | the design and motion system as pure, tested JavaScript: materials, bar geometry, keyboard navigation, notification grouping and timing, section layout |
| `ui/Components/` | shared surfaces and controls (the Glass sheet, compositor blur regions, the material in motion, controls) |
| `ui/Services/` | one owner for each piece of state: `Config` (every `~/.config/zynith/*.toml`), `Material`, `Scheme` (palette), `Notifications`, `PanelRouter`, `ExperiencePolicy` … |
| `ui/Modules/` | the surfaces: `Bar/`, `Panels/`, `Notifications/`, `Osd/`, `Desktop/`, `Settings/` |
| `ui/native/` | the `Zynith.Native` plugin |
| `ui/tools/tests/` | QML test suites, fixtures and stubs |
| `deploy/` | the per-user install from source (`install.sh`), and the generator for the UI sounds |
| `packaging/` | RPM spec and build script, the session (`zynith-session`, first-run defaults), the live-image setup |
| `iso/` | the live/install image: kickstart and build script |
| `tools/` | developer tools and the CI checks (`tools/ci/`) |
| `docs/` | this documentation; `docs/reference/` has the native shell's full example configuration and the plugin API |

## Startup

1. The display manager starts the **Zynith** session (`/usr/share/wayland-sessions/zynith.desktop`), which runs
   `zynith-session`.
2. `zynith-session` runs `zynith-firstrun` — on a new account it copies the default configuration from
   `/usr/share/zynith/defaults/home/` into the home directory, file by file, never replacing an existing file — and
   then `niri-session`.
3. niri reads `~/.config/niri/config.kdl`, whose `spawn-at-startup` lines run `zynith-ui native supervise` (the native
   shell, supervised) and `zynith-ui start` (the UI).

On a source install (`deploy/install.sh`) the session is the user's own niri configuration with the same two
`spawn-at-startup` lines.

## Configuration and state

| Path | Owner | Notes |
|---|---|---|
| `~/.config/zynith/*.toml` | the user, through Settings (`Services/Config`) | the UI's configuration; an invalid file is reported, never replaced |
| `~/.config/niri/config.kdl`, `rice/binds.kdl`, `rice/rules.kdl` | the user | Zynith edits `config.kdl` only to change an output's orientation from Settings → Displays, after a backup and `niri validate` |
| `~/.config/niri/rice/{animations,glass,layout,materials,wallpaper}.kdl` | generated | written by the native shell or the UI from the user's settings |
| `~/.config/niri/zynith-shell.kdl` | generated | palette colours for niri; the last include |
| `~/.config/zynith-shell/*.toml` | the user | the native shell's configuration |
| `~/.local/state/zynith-shell/settings.toml` | the native shell's own settings window | |
| `~/.local/state/zynith/` | generated | palette, launcher usage counts, notification history (mode 0600), first-run marker |
| `$XDG_RUNTIME_DIR/zynith/` | runtime | pids, logs, the UI's command socket |

Packages never write into home directories. Defaults reach a user only through `zynith-firstrun`, which does not
overwrite.

## Names

| Name | What |
|---|---|
| `zynith-shell` | the native shell's command (`zynith-shell msg …`, `zynith-shell config validate`) and package |
| `~/.config/zynith-shell/`, `~/.local/state/zynith-shell/`, `~/.cache/zynith-shell/` | the native shell's configuration, state and cache |
| `~/.config/zynith/`, `~/.local/state/zynith/` | the UI's configuration and state |
| `zynith::` | the native shell's C++ namespace |
| `dev.zynith.*` | D-Bus names; the desktop file is `dev.zynith.Shell.desktop` |
| `zynith-shell-*` | the native shell's Wayland layer namespaces (`zynith-shell-wallpaper`, `zynith-shell-backdrop` …); the UI's are `zynith-*` |
| `zynith-shell.kdl` | the niri include the native shell generates |
| `ZYNITH_*` | environment variables passed to hooks |

## Resource use

Zynith treats resource use as a feature: nothing polls, surfaces that are not on screen do no work, animations are
measured frame by frame, and experience profiles reduce motion and materials on battery and with power saver on.
