# Changelog

All notable changes to Zynith are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and versions follow [Semantic Versioning](https://semver.org/) once releases begin.

## [Unreleased] — 0.1.0

No version has been released yet. This is everything since development began on 2026-09-19 from Noctalia 5.1.0
(Fedora's `noctalia-5.1.0-1.fc44` source package; it is the repository's first commit).

### Added

- **Zynith UI**, a Quickshell (QML) interface that draws the desktop:
  - bars on any edge, any number of them, with a visual bar editor;
  - Zynith Island;
  - the Control Panel with per-icon panels;
  - a launcher with application, calculator, emoji, window, wallpaper and power providers;
  - notification popups and a notification centre;
  - on-screen displays;
  - desktop widgets with an editor;
  - a Settings app;
  - materials (Glass, Solid, Blur);
  - a measured motion system;
  - experience profiles for battery and power saver;
  - a frame-time probe for measuring animations.
- **`Zynith.Native`**, the UI's C++ plugin: niri state, display configuration (including rotation, with rollback), audio
  spectrum, network, backlight, the configuration store and thumbnails.
- **`zynith-ui`**, which starts and supervises the UI and the native shell, with key-binding routing and recovery
  from crashes.
- Native shell:
  - a design foundation (motion roles, design tokens, a spatial model);
  - the Zynith Control Center and lock screen compositions;
  - a single wallpaper state for the desktop, the overview, the lock screen and the palette.
- **Packaging**: RPMs for Fedora 44 (`zynith-shell`, `zynith-ui`, `zynith-desktop`, `zynith-live`), built in a clean
  container; a Zynith wayland session with first-run defaults that never overwrite user files.
- **The Zynith ISO** build: a Fedora 44 live image with Fedora's Anaconda installer, built by livemedia-creator in a
  disposable VM (`iso/build-iso.sh`).
- CI checks shared with local runs (`tools/ci/`), and this repository's documentation and contribution files.

### Changed

- The product presents itself as Zynith everywhere it is named to the user: notifications, window titles, About,
  translations, desktop entries, the default wallpaper and the icon. Compatibility identifiers keep their historical
  name (see [docs/development/architecture.md](docs/development/architecture.md#names)).
- Plugins from third-party sources update only on request (`notify` mode by default).

### Removed

- The inherited telemetry ping, and its toggle in the first-run wizard and Settings. Zynith sends no telemetry.
- Upstream's documentation site, release automation, Nix/Guix/AUR packaging and translation-sync tooling, which
  publish to services Zynith does not use.

### Security

- Plugins are restricted by capability permissions, and core dumps of the shell are disabled.
- Notification history is stored with mode 0600, and the clipboard history is encrypted at rest.
