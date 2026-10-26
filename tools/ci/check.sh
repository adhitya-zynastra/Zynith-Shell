#!/usr/bin/env bash
# tools/ci/check.sh — the repository's checks, the same in CI (.github/workflows/ci.yml) and locally.
#
#   tools/ci/check.sh deps <stage>   install what a stage needs (Fedora; run as root in a container)
#   tools/ci/check.sh <stage>        run a stage
#   tools/ci/local.sh [stage …]      run stages in a Fedora 44 container on your machine
#
# Stages:
#   hygiene    no secrets, private keys, personal paths or large binaries in the tracked tree
#   format     clang-format of the native shell's sources
#   packaging  shellcheck, desktop entries, the RPM spec, the kickstart, the default niri configuration, translations
#   native     the native shell: build and unit tests
#   ui         the UI plugin and the QML test suites
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
cd "$ROOT"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

# Zynith's own scripts (the native shell's theme templates are checked where they are used)
shell_scripts() {
    printf '%s\n' ui/zynith-ui deploy/install.sh iso/build-iso.sh packaging/rpm/build-rpms.sh \
        packaging/session/zynith-session packaging/session/zynith-firstrun packaging/live/livesys-zynith \
        tools/ci/check.sh tools/ci/local.sh ui/tools/tests/run-store-tests.sh iso/test-vm.sh iso/fetch-packages.sh
}

deps() {
    local dnf=(dnf -y -q --setopt=install_weak_deps=False install)
    case "$1" in
    hygiene) "${dnf[@]}" git-core file ;;
    format) "${dnf[@]}" git-core clang-tools-extra ;;
    packaging) "${dnf[@]}" git-core ShellCheck desktop-file-utils pykickstart niri rpmlint python3 ;;
    native)
        "${dnf[@]}" git-core dnf-plugins-core
        dnf -y -q builddep packaging/rpm/zynith.spec
        "${dnf[@]}" dbus-daemon ;;
    ui) "${dnf[@]}" git-core cmake ninja-build gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg \
        qt6-rpm-macros diffutils "pkgconfig(libpipewire-0.3)" "pkgconfig(tomlplusplus)" ;;
    *) echo "unknown stage $1" >&2; exit 2 ;;
    esac
}

hygiene() {
    say "secrets and private keys"
    # high-confidence token formats only; a match is never a false positive worth keeping
    local secrets='-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|gh[ousr]_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}'
    if git grep -nIE -e "$secrets" -- . ':!tools/ci/check.sh'; then bad "a secret or private key is tracked"; fi

    say "personal paths and machine-specific files"
    # a developer's home directory written into the tree, or files that only exist on one machine
    if git grep -nIE '/home/[a-z_][a-z0-9_-]*/' -- . ':!tools/ci/check.sh' ':!third_party' \
        | grep -vE '/home/(u|user|username|you|me|liveuser|runner)/'; then
        bad "a personal home path is tracked"
    fi
    local f
    while IFS= read -r f; do bad "machine-specific file tracked: $f"; done < <(
        git ls-files | grep -E '(^|/)(\.env|id_[a-z0-9]+|.*\.pem|.*\.key|known_hosts|\.netrc|cookies\.sqlite|.*\.kdbx)$' || true)

    say "D-Bus object paths"
    # a path element may hold only [A-Za-z0-9_]; a hyphen makes registration fail at run time, not at build time
    if git grep -nIE '"/(org|dev/zynith)/[^"]*-[^"]*"' -- src ui; then bad "a D-Bus object path contains a hyphen"; fi

    say "large files"
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        (( $(stat -c %s "$f") > 5 * 1024 * 1024 )) && bad "file over 5 MiB (publish builds as release assets): $f"
        case "$f" in *.iso|*.qcow2|*.img|*.rpm) bad "build output tracked: $f" ;; esac
    done < <(git ls-files)
    return 0
}

format() {
    say "clang-format $(clang-format --version | grep -oE '[0-9]+\.[0-9.]+' | head -1)"
    git ls-files -z 'src/*.cpp' 'src/*.h' 'tests/*.cpp' 'tests/*.h' | xargs -0 clang-format --dry-run -Werror \
        || bad "the native sources are not formatted (just format)"
    if git grep -nIE '[[:space:]]+$' -- 'src/*.cpp' 'src/*.h' 'tests/*.cpp' 'tests/*.h'; then bad "trailing whitespace"; fi
    return 0
}

packaging() {
    say "shellcheck"
    shell_scripts | xargs shellcheck --severity=warning --shell=bash || bad "shellcheck"

    say "desktop entries"
    desktop-file-validate packaging/session/zynith-settings.desktop assets/dev.zynith.Shell.desktop \
        || bad "desktop-file-validate"
    # a wayland-session entry is not an application; validate what applies to it
    grep -q '^Exec=zynith-session$' packaging/session/zynith.desktop || bad "zynith.desktop: Exec"
    grep -q '^DesktopNames=niri$' packaging/session/zynith.desktop || bad "zynith.desktop: DesktopNames"

    say "RPM spec"
    rpmlint --info packaging/rpm/zynith.spec || bad "rpmlint"

    say "kickstart"
    ksvalidator -v F44 iso/zynith-live.ks || bad "ksvalidator"

    say "default niri configuration"
    niri validate -c packaging/defaults/home/.config/niri/config.kdl || bad "niri validate"

    say "official configurations"
    python3 configs/official/zynith-config.py validate || bad "official configurations do not validate"
    # apply and restore in a scratch home: only the preset's keys change, other files are untouched, restore is exact
    local scratch; scratch="$(mktemp -d)"
    mkdir -p "$scratch/cfg/zynith"
    printf '# kept\naccent = "#b4c5ff"\nsurface_style = "glass"\n' >"$scratch/cfg/zynith/appearance.toml"
    printf '[[bar]]\nid = "x"\n' >"$scratch/cfg/zynith/bars.toml"
    cp -a "$scratch/cfg/zynith" "$scratch/orig"
    if XDG_CONFIG_HOME="$scratch/cfg" XDG_STATE_HOME="$scratch/state" python3 configs/official/zynith-config.py apply solid >/dev/null \
        && grep -q '^accent = "#b4c5ff"$' "$scratch/cfg/zynith/appearance.toml" \
        && grep -q '^surface_style = "solid"$' "$scratch/cfg/zynith/appearance.toml" \
        && cmp -s "$scratch/orig/bars.toml" "$scratch/cfg/zynith/bars.toml" \
        && XDG_CONFIG_HOME="$scratch/cfg" XDG_STATE_HOME="$scratch/state" python3 configs/official/zynith-config.py restore >/dev/null \
        && diff -r "$scratch/orig" "$scratch/cfg/zynith" >/dev/null; then :; else bad "zynith-config.py apply/restore round trip"; fi
    rm -rf "$scratch"

    say "translations"
    local j
    for j in assets/translations/*.json; do
        python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" || bad "invalid JSON: $j"
    done
    python3 tools/i18n-check.py || bad "i18n-check"
    return 0
}

native() {
    say "native shell: build"
    local b=build/ci-native
    meson setup "$b" --buildtype=debug -Dcpp_std=c++23 -Dtests=enabled --wipe 2>/dev/null \
        || meson setup "$b" --buildtype=debug -Dcpp_std=c++23 -Dtests=enabled
    meson compile -C "$b" -j "${JOBS:-$(nproc)}"

    say "native shell: unit tests"
    meson test -C "$b" --print-errorlogs --num-processes "${JOBS:-2}" || bad "native unit tests"
    return 0
}

ui() {
    say "UI plugin: build"
    local b=build/ci-ui
    cmake -S ui/native -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$b" -j "${JOBS:-$(nproc)}"

    say "QML test suites"
    local runner=/usr/lib64/qt6/bin/qmltestrunner t
    for t in ui/tools/tests/tst_*.qml; do
        case "$t" in
        # needs a running niri (a nested test desktop); see docs/development/testing.md
        */tst_display_session.qml) echo "skip: $t (needs niri)"; continue ;;
        # runs through its wrapper, which prepares the config fixtures
        */tst_bar_store.qml) continue ;;
        esac
        (cd ui && QT_QPA_PLATFORM=offscreen "$runner" -import "../$b/qml" -import tools/tests/stubs \
            -input "${t#ui/}" -silent) || bad "$t"
    done
    ZYNITH_NATIVE_BUILD="$ROOT/$b" bash ui/tools/tests/run-store-tests.sh -silent || bad "tst_bar_store.qml"
    return 0
}

case "${1:-}" in
deps) deps "${2:?stage}" ;;
hygiene | format | packaging | native | ui) "$1" ;;
*) sed -n '2,15p' "$0"; exit 2 ;;
esac
((fail == 0)) || { echo "check $1: failed" >&2; exit 1; }
echo "check ${1}: ok"
