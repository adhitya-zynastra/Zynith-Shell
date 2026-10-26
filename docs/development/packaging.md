# Packaging

Zynith is packaged as RPMs for Fedora 44 from one spec, [`packaging/rpm/zynith.spec`](../../packaging/rpm/zynith.spec).

| Package | Contains | Notes |
|---|---|---|
| `zynith-shell` | the native shell (`/usr/bin/noctalia`), its assets and translations, the UI sounds | conflicts with Fedora's `noctalia`, which installs the same command |
| `zynith-ui` | the UI (`/usr/share/zynith/ui`), `/usr/bin/zynith-ui`, the `Zynith.Native` plugin, the Settings desktop entry, the icon | requires Quickshell ≥ 0.3.1 |
| `zynith-desktop` | the session (`zynith.desktop`, `zynith-session`, `zynith-firstrun`) and the defaults new accounts get | pulls in niri, portals, PipeWire, NetworkManager, Bluetooth, power profiles, a terminal (kitty) and a file manager (Thunar) |
| `zynith-live` | the live-image session setup (`livesys-zynith`) | only for the ISO |

## Building

```sh
packaging/rpm/build-rpms.sh                 # from the committed HEAD (git archive)
packaging/rpm/build-rpms.sh --rev v0.1.0    # from a tag or commit
packaging/rpm/build-rpms.sh --worktree      # from the working tree, uncommitted changes included (development only)
```

The build runs in a clean `fedora:44` container with rootless podman, at the lowest CPU priority on half the cores.
It installs the build dependencies from the spec, then runs `rpmbuild -ba`, including the spec's `%check`.

Output, in `build/release/` (never committed):

| Path | What |
|---|---|
| `rpms/` | the four binary RPMs and the source RPM |
| `repo/` | a dnf repository with the Zynith RPMs (no debug packages), the pinned Quickshell build and cpptrace |
| `rpms.sha256` | checksums of everything in `rpms/` and `repo/` |
| `rpmbuild.log` | the full build log |

The release field carries the source: `0.<date>git<commit>`, so every package says which commit it was built from.
A `--worktree` build ends its commit with `-dirty`.

## Quickshell

Fedora 44's `quickshell` package is an older snapshot. Zynith needs 0.3.1. `build-rpms.sh` downloads one pinned build,
`quickshell-0.3.1-2.fc44`, and the `cpptrace-1.0.4-1.patched.fc44` it links against (Fedora has no `cpptrace`), from the
[errornointernet/quickshell](https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell/) COPR. It checks each
build's signature against the COPR's signing key and adds them to the local repository. No COPR repository is
configured on systems installed from the ISO.

This Quickshell build uses Qt's private API and is tied to the Qt it was built for (6.11). A Fedora update to a
newer Qt can break it until the COPR is rebuilt; the pinned build must then be updated with it.

After building, `build-rpms.sh` checks that `zynith-desktop` and `zynith-live` install from the local repository and
Fedora alone.

## Installing the packages on an existing system

```sh
sudo dnf install build/release/repo/zynith-desktop-*.rpm build/release/repo/zynith-ui-*.rpm \
    build/release/repo/zynith-shell-*.rpm build/release/repo/quickshell-*.rpm build/release/repo/cpptrace-*.rpm
```

Then choose **Zynith** in the display manager's session list. When the session starts, `zynith-firstrun` copies the
default configuration into your home directory. It never replaces a file you already have. Run
`/usr/libexec/zynith/zynith-firstrun --list` first to see what it would copy. An existing
`~/.config/niri/config.kdl` is kept as it is, so it must start Zynith itself (see
[Building and running](building.md#starting-zynith-from-niri)).

## Updates

No package repository for Zynith is published yet. To update, build newer RPMs and install them with
`sudo dnf upgrade ./build/release/repo/*.rpm`.

Upgrades never change a file in a home directory. `zynith-firstrun` runs at every login and copies only the default
files an account does not have. A default file that a later version adds therefore reaches existing accounts, and a
file you changed is never replaced. A default file you delete comes back at the next login; to opt out of one,
leave an empty file in its place instead.
