# Testing

## The checks

Every check the repository has is a stage of [`tools/ci/check.sh`](../../tools/ci/check.sh). The checks run the same
way in CI ([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), a Fedora 44 container) and on your
machine:

```sh
tools/ci/local.sh                       # every stage, each in a fresh Fedora 44 container (rootless podman)
tools/ci/local.sh hygiene packaging     # some stages
```

| Stage | What it checks |
|---|---|
| `hygiene` | no private keys, access tokens, personal home paths, machine-specific files or build output in the tracked tree, and no file over 5 MiB |
| `format` | the native shell's C++ is formatted with clang-format (`just format` fixes it), with no trailing whitespace |
| `packaging` | shellcheck on Zynith's scripts, `desktop-file-validate`, `rpmlint` on the spec, `ksvalidator` on the kickstart, `niri validate` on the default configuration, the translations parse and contain every key the code uses |
| `native` | the native shell builds (debug, with tests) and its unit tests pass |
| `ui` | the `Zynith.Native` plugin builds and the QML suites pass (offscreen) |

`local.sh` copies the working tree in as git sees it: tracked files, plus new files that are not ignored. Your build
directories never reach the container.

## Running tests directly

```sh
# QML suites, against the plugin built by deploy/install.sh (build/ui-native)
cd ui
for t in tools/tests/tst_*.qml; do
  case $t in *bar_store*|*display_session*) continue;; esac
  QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import ../build/ui-native/qml \
      -import tools/tests/stubs -input $t
done
bash tools/tests/run-store-tests.sh     # the config store (tst_bar_store) with its fixtures

# native shell
meson test -C build/shell --num-processes 2
```

Two suites need special handling:

- `tst_bar_store.qml` writes and recovers configuration files. It runs through `run-store-tests.sh`, which works on
  copies of the fixtures in a scratch directory.
- `tst_display_session.qml` drives a running niri. Run it only inside a nested test niri, never against your real
  display. CI skips it.

## Assets in tests

The native unit tests read translations, fonts and templates from this tree's `assets/` (`ZYNITH_ASSETS_DIR`, set by
`meson.build`), never from an installed copy, so they behave the same on a clean machine. Every test gates; there are
no known failures.

## Testing the packages and the image

- The RPMs are built and their own `%check` run (desktop entries validated, installed files present) by
  `packaging/rpm/build-rpms.sh`. See [Packaging](packaging.md).
- The ISO is tested in a virtual machine with `iso/test-vm.sh`: boot the live image, install it to a virtual disk,
  boot the installed system. See [The ISO](iso.md#testing-in-a-virtual-machine).
