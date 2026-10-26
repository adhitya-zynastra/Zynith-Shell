# Building and running

There are three ways to run Zynith. Each has its own section below.

| | For | Installs to |
|---|---|---|
| [From source, per user](#from-source-per-user) | developing Zynith on an existing Fedora + niri setup | your home directory |
| [RPM packages](packaging.md) | a system-wide install; what the ISO contains | `/usr` |
| [The ISO](iso.md) | a new machine | a whole system, through Fedora's installer |

## Requirements

- Fedora Linux 44, x86_64.
- niri 26.04 (`sudo dnf install niri`).
- Quickshell 0.3.1. Fedora 44's own `quickshell` package is an older snapshot. Zynith is developed and tested against
  the build in the [errornointernet/quickshell](https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell/)
  COPR:

  ```sh
  sudo dnf copr enable errornointernet/quickshell
  sudo dnf install quickshell
  ```

- The build dependencies, all listed in the spec:

  ```sh
  sudo dnf install dnf-plugins-core
  sudo dnf builddep packaging/rpm/zynith.spec
  ```

- The runtime pieces the UI calls: `socat`, `libnotify`, `zenity`, `pipewire-utils`, `xdg-utils`. The `Requires:` lines of
  `zynith-ui` and `zynith-desktop` in [the spec](../../packaging/rpm/zynith.spec) list them all.

## From source, per user

```sh
deploy/install.sh --check          # what is installed, from where, whether niri's configuration is valid
deploy/install.sh                  # build the UI plugin (build/ui-native) and link ~/.local/bin/zynith-ui
deploy/install.sh --shell          # also build the native shell (build/shell) and install it to ~/.local/opt/noctalia
deploy/install.sh --shell --restart
```

What `deploy/install.sh` does and does not do:

- It installs only into your home directory.
- It refuses to run while the session is locked.
- It never writes `~/.config/zynith`, `~/.config/niri` or `~/.local/state/noctalia`.
- When it replaces the native shell's binary it keeps the previous one beside it, as `noctalia.pre-install-<date>`.
- It builds at low priority on half the cores.

The UI runs straight from `ui/` in this tree: `~/.local/bin/zynith-ui` is a link to `ui/zynith-ui`, which starts
Quickshell on `ui/shell.qml`. Quickshell reloads QML files as you save them.

### Starting Zynith from niri

Add these two lines to `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "zynith-ui" "native" "supervise"
spawn-at-startup "zynith-ui" "start"
```

[`packaging/defaults/home/.config/niri/`](../../packaging/defaults/home/.config/niri/) is the configuration new
accounts get from the packages: the includes, key bindings and window rules. Use it as a reference for your own.

### Day to day

```sh
zynith-ui start | stop | restart | status | log
zynith-ui native start | stop | restart | status
zynith-ui settings [page]          # the Settings app, e.g. zynith-ui settings displays
zynith-ui ipc <method> [args]      # the UI's IPC
noctalia msg status                # the native shell
```

After a large change, such as switching branches, restart the UI (`zynith-ui restart`) rather than relying on the
live reload.

## Recovery

| Symptom | What to do |
|---|---|
| No bar, panels or notifications | `zynith-ui status`, then `zynith-ui log`; `zynith-ui restart` |
| No lock screen, wallpaper or audio controls | `zynith-ui native status`; `zynith-ui native restart` |
| The native shell keeps crashing | after five exits within seconds of starting, its supervisor stops and shows a notification; read `$XDG_RUNTIME_DIR/zynith/native.log` and `coredumpctl info noctalia`, then `zynith-ui native start` |
| The desktop does not come up at all | switch to a text console (Ctrl+Alt+F3), log in, and read `journalctl --user -b` and `$XDG_RUNTIME_DIR/zynith/*.log`; `niri validate` checks the compositor's configuration |
| A configuration file is broken | Settings reports it and leaves the file as it is; fix it, or move it aside to start from the defaults |

When reporting a crash, include the backtrace (`coredumpctl info`) and the logs, not only the last line.
