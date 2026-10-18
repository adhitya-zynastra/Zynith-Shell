# Zynith

Zynith is a Linux desktop built on **niri** (compositor and window manager, unmodified), a **native C++ shell**
(services, lock screen, wallpaper, IPC — a GPL-3.0 fork of Noctalia 5.1.0) and a **Quickshell/QML UI** (everything
you see and touch: bars, Dashboard, notification centre, launcher, OSD, widgets, Settings).

This directory is the one source tree for all of it. Open it in an editor and everything that runs is here; what
lives elsewhere is listed below with who owns it.

## The tree

| Path | What | Language |
|---|---|---|
| `src/` | the native shell: services (audio, network, power, notifications bus hand-over), lock screen, wallpaper renderer, theme engine, IPC (`noctalia msg …`) | C++ (meson) |
| `ui/` | the Zynith UI: `shell.qml` (the desktop), `settings.qml` (Settings app), `zynith-ui` (launcher/supervisor) | QML |
| `ui/Common/` | design and motion system as pure, tested JavaScript: materials (`MaterialModel.js`), the water drop (`Droplet.js`), bar geometry (`BarModel.js`), keyboard navigation, notification grouping, section layout | JS |
| `ui/Components/` | shared surfaces and controls: `Glass` (the sheet), `BlurRegion` (compositor backdrop), `MaterialSettle` (the material in motion), `WallpaperImage`, controls | QML |
| `ui/Services/` | one owner per piece of state: `Config` (all `~/.config/zynith/*.toml`), `Material`, `Scheme` (palette), `Notifications`, `PanelRouter`, `ExperiencePolicy` … | QML |
| `ui/Modules/` | the surfaces: `Bar/`, `Panels/` (Dashboard, notification centre, launcher, wallpaper …), `Notifications/` (popups), `Osd/`, `Desktop/` (widgets), `Settings/` | QML |
| `ui/native/` | `Zynith.Native`, the UI's C++ plugin: niri state and config writes, **display orientation** (`DisplayConfig`), audio spectrum, network, backlight, config file store, thumbnails | C++ (cmake) |
| `ui/templates/` | palette template the theme engine renders for the UI | — |
| `ui/tools/tests/` | QML test suites (`tst_*.qml`) and fixtures | QML |
| `tests/` | native shell tests | C++ |
| `assets/` | fonts, icons, sounds, shaders, translations | — |
| `deploy/install.sh` | the one build-and-install path | bash |
| `build/` | build output, never committed (`shell/`, `ui-native/`) | — |
| `record/` | → the engineering record (a separate git repository; local link, not committed) | Markdown |

Upstream Noctalia's layout (`src/`, `tests/`, `assets/`, `meson.build`) is kept as it is, so the patch series can
still be compared with and rebased onto upstream.

## Build, install, run

```sh
deploy/install.sh --check          # what is installed, from where, and whether niri's config is valid
deploy/install.sh                  # build the UI plugin, link ~/.local/bin/zynith-ui (no restart)
deploy/install.sh --shell          # also build and install the native shell (old binary kept beside it)
deploy/install.sh --shell --restart
```

The installer refuses while the session is locked and never writes user configuration.

Day to day:

```sh
zynith-ui start | stop | restart | status | log
zynith-ui native restart           # the native shell, through its supervisor
zynith-ui settings [route]         # e.g. zynith-ui settings displays
zynith-ui ipc <method> [args]      # the UI's IPC (panel, close, status, panelRect, captureBar …)
```

`zynith-ui` hot-reloads the QML it runs. After a large update, restart instead (a hot reload of many files at once
has been seen to come up without its `Config` singleton).

## Tests

```sh
cd ui
for t in tools/tests/tst_*.qml; do
  case $t in *bar_store*|*display_session*) continue;; esac   # these two have their own harness (below)
  QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import ../build/ui-native/qml -import tools/tests/stubs -input $t
done
bash tools/tests/run-store-tests.sh                       # the config store (tst_bar_store), with its fixtures
meson test -C ../build/shell                                 # native (one known third-party failure: upower_charge_limit_integration)
```

`tst_display_session.qml` drives a running niri. Run it only inside a test niri, never against your real display.

## What lives outside this tree, and who owns it

| Path | Owner | Notes |
|---|---|---|
| `~/.local/bin/zynith-ui` | `deploy/install.sh` | symlink → `ui/zynith-ui` here; niri's binds and autostart call it |
| `~/.local/opt/noctalia/` | `deploy/install.sh --shell` (`meson install`) | the installed native shell; earlier binaries kept as `bin/noctalia.pre-*` |
| `~/.config/zynith/*.toml` | **you**, via Settings (`Services/Config`) | the UI's configuration; an invalid file is reported, never replaced |
| `~/.config/zynith/templates/`, `scripts/` | you | templates; old measurement scripts (some still name the pre-2026‑10‑18 build paths) |
| `~/.config/niri/config.kdl`, `rice/binds.kdl`, `rice/rules.kdl` | **you** | Zynith edits `config.kdl` only for an output's orientation (Settings → Displays: backup + `niri validate` first) |
| `~/.config/niri/rice/{animations,glass,layout,materials,wallpaper}.kdl` | generated | by the native shell or the UI from your settings; hand edits are overwritten |
| `~/.config/niri/noctalia.kdl` | generated | palette colours; must stay the last include |
| `~/.config/noctalia/*.toml` | you | the native shell's design layer (`rice.toml`, `lockscreen.toml`) |
| `~/.local/state/noctalia/settings.toml` | the native Settings GUI only | never written by anything else |
| `~/.local/state/zynith/` | generated | `palette.json` (theme engine), launcher counts, notification history (0600) |
| `$XDG_RUNTIME_DIR/zynith/` | runtime | pids, logs, the UI's command socket |
| `~/.config/rice-backups/` | backups | every Zynith-made change to your config is copied here first |
| `~/.local/src/noctalia-lockfade/zynith-ui` | compatibility | symlink → this tree (its old location); other worktrees there are older branches |

## Branches

- `feature/zynith-ui` is the integration branch and this tree. Since 2026‑10‑18 it contains the native shell
  (`feature/zynith-core`, merged) and the UI.
- `zynith/signature-dashboard` is the development worktree (`~/.local/src/noctalia-lockfade/zynith-ui-dev`) that
  the nested test desktop runs.
- Nothing is pushed without the maintainer's say-so.

## Licence

Zynith is GPL-3.0-only. Noctalia's MIT notice is kept verbatim (`LICENSE`, `LICENSES/`). Third-party code keeps its
licence.
