# Configuring Zynith

Everything is configured from **Settings** (`Mod+T`). Settings writes plain TOML files in `~/.config/zynith/`, which
you can also edit by hand; the running desktop picks up a change as soon as the file is saved. A file that cannot be
read is reported and left as it is. Nothing is replaced behind your back.

| File | What it holds |
|---|---|
| `appearance.toml` | surface style (glass, solid, blur), material strength, borders, corners, tint, accent, fonts |
| `experience.toml` | how much the desktop may spend: follow power, or save even when plugged in |
| `animation.toml` | motion style and speed |
| `bars.toml` | every bar: its edge, size, behaviour and components |
| `panels.toml` | the launcher, the Control Panel and the on-screen displays |
| `notifications.toml` | popups, grouping, timing, do-not-disturb |
| `wallpaper.toml` | how wallpapers are shown and changed |
| `widgets.toml` | desktop widgets |
| `window.toml` | window layout behaviour (written to niri's configuration after it is validated) |
| `zynith.toml` | which surfaces the Zynith UI draws, and your profile |

The compositor's own settings (outputs, input, key bindings) are in `~/.config/niri/`. The native shell keeps its
configuration in `~/.config/noctalia/`; that directory name is a compatibility name kept from the shell's origin.

## Official configurations

Zynith ships four curated starting points for how the desktop looks and how much it spends. Each sets a few keys in
`appearance.toml`, `experience.toml` and `animation.toml`, and nothing else.

| Configuration | Look | Resource use |
|---|---|---|
| **Zynith Glass** (`glass`) | clear, tinted glass that shows the wallpaper; the default look | follows power: full effects when plugged in, less on battery |
| **Zynith Solid** (`solid`) | opaque surfaces with defined edges, crisp motion | follows power |
| **Zynith Minimal** (`minimal`) | opaque, borderless, tighter corners, short motion | saves even when plugged in |
| **Zynith Max Experience** (`max-experience`) | frosted surfaces blurred by the compositor, stronger material, rounder shapes | keeps blur and shadows on battery too; needs a capable GPU |

They live in [`configs/official/`](../../configs/official/) of the source repository; packaged installs have them in
`/usr/share/zynith/configs/official/`.

```sh
zynith-config list                     # the official configurations
zynith-config show minimal             # what applying it would change (nothing is written)
zynith-config apply minimal            # apply it
zynith-config restore                  # undo the last apply
```

From a source checkout, run `configs/official/zynith-config.py` instead of `zynith-config`.

Applying merges only the configuration's keys into your files, keeping everything else (your accent, fonts, comments
and every other file). The files as they were are backed up first, in `~/.local/state/zynith/config-backups/`, and
`restore` puts them back. To return a single file to Zynith's defaults, delete it; it is created again when you
change something in Settings.

Bar layouts are chosen in Settings → Bars, which starts from the built-in layouts listed in
[Using Zynith](using.md#the-parts-of-the-desktop) and lets you edit them freely.

Community configurations are welcome as issues or pull requests. They are not official until they are reviewed and
added to `configs/official/`.
