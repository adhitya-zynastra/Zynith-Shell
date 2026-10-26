# Using Zynith

Zynith runs on the [niri](https://github.com/YaLTeR/niri) compositor. Windows sit in columns on a horizontally
scrolling strip; each monitor has its own workspaces, stacked vertically. `Mod` is the Super (Windows) key.

## Key bindings

These are the defaults a new account gets (`~/.config/niri/rice/binds.kdl`). `Mod+H` shows them on screen.

| Keys | Action |
|---|---|
| `Mod+D` | app launcher (type `:` first for emoji) |
| `Mod+Shift+E` | Control Panel |
| `Mod+Shift+N` | notifications |
| `Mod+T` | Settings |
| `Mod+W` | wallpapers |
| `Mod+Alt+V` | clipboard history |
| `Mod+Alt+W` | edit desktop widgets |
| `Ctrl+Alt+L` | lock the screen |
| `Ctrl+Alt+P` | power menu |
| `Mod+Return` | terminal (kitty) |
| `Mod+B` / `Mod+E` | browser / file manager |
| `Mod+Q` | close the window |
| `Mod+Left` / `Mod+Right` | focus the column to the left / right |
| `Mod+Ctrl+Left` / `Mod+Ctrl+Right` | move the column |
| `Mod+F` / `Mod+Shift+F` | maximise the column / fullscreen |
| `Mod+R` | cycle the column's width |
| `Mod+Space` | float or tile the window |
| `Mod+A` | overview of every workspace |
| `Mod+1` … `Mod+9` | go to a workspace; with `Shift`, move the window there |
| `Mod+Ctrl+Alt+R` | restart Zynith (the shell and its UI) |

Volume, brightness and media keys work as labelled, with an on-screen display.

## The parts of the desktop

- **Bars** sit on any edge. Each bar holds components such as workspaces, the clock, media, system indicators and
  the Zynith Island. Settings → Bars has a visual editor and starting layouts (top bar, three top bars, side rail,
  right rail, dock, floating clock).
- **Zynith Island** is an optional bar component that changes shape to show what is happening: what is playing, a
  new notification, a device connecting, a power change.
- **The Control Panel** (`Mod+Shift+E`) gathers media, audio, network, Bluetooth, power, calendar and weather.
  Clicking an icon in a bar opens just that part, as a smaller panel.
- **The launcher** (`Mod+D`) finds applications, calculates, searches emoji and open windows, picks wallpapers and
  offers power actions.
- **Notifications** appear as popups and are kept in the notification centre, grouped by application, with
  do-not-disturb.
- **Desktop widgets** (a clock, media, weather, a visualiser …) are placed and edited with `Mod+Alt+W`.
- **The lock screen** asks for your password, through PAM.

## Settings

`Mod+T` opens Settings. Changes apply immediately and are written to the files in `~/.config/zynith/`
([Configuring Zynith](configuring.md)).
