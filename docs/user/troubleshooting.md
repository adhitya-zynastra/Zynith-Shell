# Troubleshooting

## Quick checks

```sh
zynith-ui status            # the UI (bars, panels, notifications)
zynith-ui native status     # the native shell (services, lock screen, wallpaper)
zynith-ui version           # which Zynith this is
zynith-ui log               # the UI's log
```

| Problem | What to do |
|---|---|
| No bars, panels or notifications | `zynith-ui restart` |
| No lock screen, wallpaper or volume and brightness controls | `zynith-ui native restart` |
| The native shell keeps crashing | after five quick failures its supervisor stops and shows a notification; read `$XDG_RUNTIME_DIR/zynith/native.log` and `coredumpctl info noctalia`, then `zynith-ui native start` |
| The desktop does not appear after logging in | press `Ctrl+Alt+F3`, log in on the text console, and read `journalctl --user -b`; `niri validate` checks the compositor's configuration. The **niri** session in the login screen starts niri with the same configuration. |
| A setting has no effect | the file may not parse: Settings says so, and `zynith-ui log` names the file and line |
| Everything looks wrong after editing files by hand | move `~/.config/zynith` aside and log in again; new accounts' defaults are copied back on login |

## Reporting a bug

Open an issue in this repository with:

- what you did, what you expected and what happened;
- `zynith-ui version` and your Fedora release (`cat /etc/fedora-release`);
- the logs above, and for a crash the backtrace from `coredumpctl info`.

Check logs and screenshots for anything private (network names, account names, file paths) before attaching them.
Security problems go through [SECURITY](../../SECURITY.md), not public issues.
