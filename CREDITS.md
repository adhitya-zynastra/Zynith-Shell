# Credits

Zynith is made possible by many open-source projects and their contributors.

## Origins

- **[Noctalia](https://github.com/noctalia-dev/noctalia)** by noctalia-dev and its contributors — Zynith's native shell
  began as a fork of Noctalia 5.1.0 (MIT; notice kept in [`LICENSES/Noctalia-MIT.txt`](LICENSES/Noctalia-MIT.txt)).
  Much of the native shell's design and code comes from that work.
- **[niri](https://github.com/YaLTeR/niri)** — the compositor Zynith runs on (GPL-3.0).
- **[Quickshell](https://quickshell.org/)** — the QML toolkit the Zynith UI is written in (LGPL-3.0 / GPL-3.0).

## Design

- **[Tabler Icons](https://tabler.io/icons)** — the icon set used throughout the shell (MIT)
- **[Inter](https://rsms.me/inter/)**, **[Space Grotesk](https://github.com/floriankarsten/space-grotesk)** and
  **[Sora](https://github.com/sora-xor/sora-font)** — the UI's fonts (SIL Open Font License 1.1, `ui/assets/fonts/OFL.txt`)
- **[Riyan Resdian on Noun Project](https://thenounproject.com/creator/yaicon/)** — Plug icon

## Audio Assets

- **[Universfield on Pixabay](https://pixabay.com/users/universfield-28281460/)** — Notification & Volume change sound effects

## System Libraries

Provided by system packages at build time and linked dynamically where applicable:

- **[Wayland](https://wayland.freedesktop.org/)** (`wayland-client`, `wayland-protocols`, `wayland-egl`) — Display protocol
- **[Mesa / EGL / GLES2](https://www.mesa3d.org/)** (or **[libepoxy](https://github.com/anholt/libepoxy)** as fallback) — OpenGL ES context and dispatch
- **[Cairo](https://www.cairographics.org/)** — 2D graphics surface used for text and SVG rasterization
- **[Pango](https://pango.gnome.org/)** / **PangoCairo** — Text layout and shaping
- **[HarfBuzz](https://harfbuzz.github.io/)** — OpenType font metrics used for stable text alignment
- **[FreeType](https://freetype.org/)** — Font rasterization
- **[Fontconfig](https://www.fontconfig.org/)** — Font discovery
- **[librsvg](https://wiki.gnome.org/Projects/LibRsvg)** — SVG rendering (filters, clipPaths, masks)
- **[GLib / GObject / GIO](https://gitlab.gnome.org/GNOME/glib)** — Core utilities used by Pango/Cairo/librsvg
- **[libxkbcommon](https://xkbcommon.org/)** — Keyboard handling
- **[sdbus-c++](https://github.com/Kistler-Group/sdbus-cpp)** — D-Bus client bindings
- **[libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/)** — Secret Service client for credential and encrypted-state persistence
- **[libsodium](https://doc.libsodium.org/)** — Cryptography for credential and encrypted-state persistence
- **[PipeWire](https://pipewire.org/)** — Audio capture and playback
- **[WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/)** — PipeWire mixer and default-node integration
- **[libsndfile](https://libsndfile.github.io/libsndfile/)** — UI sound effect decoding
- **[libcurl](https://curl.se/libcurl/)** — HTTP client
- **[libwebp](https://developers.google.com/speed/webp)** — WebP decoding and thumbnail/notification image encoding
- **[libjxl](https://github.com/libjxl/libjxl)** — JPEG XL decoding
- **[libqalculate](https://qalculate.github.io/)** — Calculator engine for the launcher (arithmetic, unit and currency conversion) (GPL-2.0-or-later)
- **[libxml2](https://gitlab.gnome.org/GNOME/libxml2)** — XML parser used to read CalDAV responses (MIT)
- **[libical](https://libical.github.io/libical/)** — iCalendar parsing for calendar events (MPL-2.0)
- **[md4c](https://github.com/mity/md4c)** — CommonMark parser used to render plugin README files (MIT)
- **[nlohmann/json](https://github.com/nlohmann/json)** — JSON for Modern C++ (MIT)
- **[stb](https://github.com/nothings/stb)** — Header-only image resizing and writing utilities (MIT / public domain)
- **[toml++](https://github.com/marzer/tomlplusplus)** — TOML parser (MIT)
- **[polkit](https://gitlab.freedesktop.org/polkit/polkit)** (`polkit-agent`, `polkit-gobject`) — Authentication agent
- **[Linux-PAM](https://github.com/linux-pam/linux-pam)** — Lockscreen authentication
- **[jemalloc](https://jemalloc.net/)** — Optional memory allocator used on glibc builds when detected

## Vendored Libraries

Bundled in `third_party/` and built from source:

- **[fzy](https://github.com/jhawthorn/fzy)** — Fuzzy matching algorithm used by the launcher, search pickers, and other shell ranking (MIT)
- **[Luau](https://luau.org/)** — Lua dialect used for scripting (MIT)
- **[Material Color Utilities](https://github.com/material-foundation/material-color-utilities)** — Material 3 palette generation (Apache-2.0)
- **[Wuffs](https://github.com/google/wuffs)** — Memory-safe image decoders (Apache-2.0)

## System Integration

External tools the native shell integrates with at runtime when present:

- **[ddcutil](https://www.ddcutil.com/)** — External display brightness control

## Special Thanks

- The **Wayland** community for building the future of Linux desktop graphics
- The **Niri**, **Hyprland**, **Sway**, **Labwc**, and **MangoWC** teams for their excellent Wayland compositors
- Noctalia's contributors and users, whose work the native shell builds on

## License

Noctalia is licensed under the MIT License; its notice is kept in [LICENSES/Noctalia-MIT.txt](LICENSES/Noctalia-MIT.txt).
Zynith, which builds on it, is licensed under GPL-3.0-only; see [LICENSE](LICENSE).

Each dependency listed above is governed by its own respective license. Please refer to their individual projects for licensing information.
