# Contributing to Zynith

Thank you for your interest in Zynith. This guide covers setting up a development environment, the conventions the
code follows, how to test a change and how to propose it.

Zynith is pre-release software: interfaces and configuration can still change, and larger changes are best
discussed in an issue before you write them.

## Development setup

Zynith is developed on **Fedora 44** with **niri 26.04** and **Quickshell 0.3.1**.

```sh
git clone https://github.com/adhitya-zynastra/Zynith-Shell.git zynith && cd zynith
sudo dnf builddep packaging/rpm/zynith.spec        # every build dependency, from the spec
```

Quickshell 0.3.1 is newer than Fedora 44's `quickshell` package; install it from the
[errornointernet/quickshell](https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell/) COPR, which is the
build Zynith is tested against.

Build and install for your user (nothing is written outside your home, and no configuration is touched):

```sh
deploy/install.sh --check          # what is installed, from where
deploy/install.sh --shell          # build the UI plugin and the native shell, install them under ~/.local
deploy/install.sh --shell --restart
```

[`docs/development/building.md`](docs/development/building.md) explains the layout, how Zynith is started from niri,
and how to run the UI from your working tree with live reloading.

## Where things are

| Path | What |
|---|---|
| `src/` | the native shell (C++23, meson) |
| `ui/` | the Zynith UI (QML for Quickshell), its C++ plugin in `ui/native/` (cmake), and `ui/zynith-ui` |
| `tests/` | native shell tests (meson) |
| `ui/tools/tests/` | QML test suites |
| `assets/` | the native shell's assets: translations, templates, fonts, sounds |
| `deploy/` | the per-user install path |
| `packaging/` | RPM packaging, the session and its default configuration, the live-image setup |
| `iso/` | the Fedora-based live/install image |
| `docs/` | developer documentation |

[`docs/development/architecture.md`](docs/development/architecture.md) describes how the pieces fit together.

## Tests

Run the tests that cover what you changed, and say which you ran in your pull request.

```sh
# QML suites (offscreen; tst_display_session needs a nested niri and is skipped here)
cd ui && for t in tools/tests/tst_*.qml; do
  case $t in *bar_store*|*display_session*) continue;; esac
  QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import ../build/ui-native/qml -import tools/tests/stubs -input $t
done
bash tools/tests/run-store-tests.sh

# native shell
meson test -C build/shell --num-processes 2
```

Every test is expected to pass; a failure is a regression. [`docs/development/testing.md`](docs/development/testing.md)
has the details.

## Conventions

**C++** is formatted with clang-format (`just format`; `lefthook install` runs it before each commit). Naming:

| | Convention | Example |
|---|---|---|
| Files, directories | snake_case | `widget_factory.cpp`, `shell/bar/widgets/` |
| Types, classes | PascalCase | `WidgetFactory` |
| Functions, methods, variables | camelCase | `createWidget()`, `busName` |
| Private members | m_camelCase | `m_changeCallback` |
| Macros, enum values | SCREAMING_SNAKE_CASE | `MAX_SIZE` |

D-Bus wire names stay as the protocol defines them.

**QML** follows the existing files: one owner per piece of state (a `Services/` singleton), pure logic in tested
`Common/*.js` modules, and no polling — work is driven by events and stops when nothing is on screen.

**Names.** The product is Zynith. The native shell's command is `zynith-shell`; its files are in
`~/.config/zynith-shell/`, `~/.local/state/zynith-shell/` and `~/.cache/zynith-shell/`; its C++ namespace is `zynith`
and its D-Bus names are `dev.zynith.*`. The UI's files are in `~/.config/zynith/` and `~/.local/state/zynith/`.

**Strings.** New user-facing strings of the native shell go in `assets/translations/en.json` only; run
`python3 tools/i18n-check.py` after adding or renaming keys.

**Performance.** Zynith treats resource use as a feature. A change that adds work while the desktop is idle, or adds a
frame-time cost to an animation, should say what it costs and how that was measured.

## Commits and pull requests

- Small, focused commits with short messages: a subject line and, if needed, a few lines of why.
- No generated or build output in commits (`build/` is ignored).
- Never commit secrets, personal paths or machine-specific configuration.
- Fill in the pull request template; describe how you tested the change and on what hardware.

## Debugging the native shell

The native shell exposes a debug D-Bus service at runtime:

```sh
gdbus call --session --dest dev.zynith.Debug --object-path /dev/zynith/Debug \
  --method dev.zynith.Debug.SetVerboseLogs true
```

`zynith-ui log` prints the UI's log; `zynith-ui native status` and `zynith-ui status` show what is running. When
reporting a crash, include the full terminal output or the `coredumpctl` backtrace, not only "Segmentation fault".

## Licence

By contributing you agree that your contribution is licensed under the GNU General Public License v3.0 only, the
licence of this project.
