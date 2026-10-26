#!/usr/bin/env bash
# deploy/install.sh — build and install Zynith from this tree, safely.
#
#   deploy/install.sh            build the UI plugin, link the launcher; nothing restarts
#   deploy/install.sh --shell    also build the native shell and install it (the old binary is kept beside it)
#   deploy/install.sh --restart  also restart what was installed (native shell and/or UI), supervised
#   deploy/install.sh --check    only report what is installed and where it comes from
#
# It never writes user configuration (~/.config/zynith, ~/.config/niri, ~/.local/state/zynith-shell/settings.toml),
# refuses while the session is locked, and stops at the first failure.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PREFIX="${ZYNITH_PREFIX:-$HOME/.local/opt/zynith-shell}"
BIN="$HOME/.local/bin"
SHELL_BUILD="$ROOT/build/shell"
UI_BUILD="$ROOT/build/ui-native"
want_shell=0 want_restart=0 only_check=0
for a in "$@"; do
    case "$a" in
    --shell) want_shell=1 ;;
    --restart) want_restart=1 ;;
    --check) only_check=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1m%s\033[0m\n' "$*"; }

locked() { command -v zynith-shell >/dev/null && zynith-shell msg status 2>/dev/null | grep -q '"locked": true'; }

check() {
    say "Zynith at $ROOT ($(git -C "$ROOT" describe --always --dirty 2>/dev/null), branch $(git -C "$ROOT" branch --show-current))"
    echo "  launcher:     $(readlink -f "$BIN/zynith-ui" 2>/dev/null || echo 'not linked')"
    echo "  native shell: $PREFIX/bin/zynith-shell ($(stat -c %y "$PREFIX/bin/zynith-shell" 2>/dev/null | cut -c1-19))"
    if [[ -x "$SHELL_BUILD/zynith-shell" ]]; then
        cmp -s "$SHELL_BUILD/zynith-shell" "$PREFIX/bin/zynith-shell" && echo "                = this tree's build" || echo "                ≠ this tree's build ($SHELL_BUILD/zynith-shell)"
    fi
    echo "  UI plugin:    $UI_BUILD/qml"
    # every desktop UI running (a test niri may run its own); the one from this tree is the installed one
    local uis; uis=$(for p in $(pgrep -x quickshell); do tr '\0' ' ' </proc/$p/cmdline; echo; done | grep -o -- '-p [^ ]*/shell.qml' | cut -c4- | sort -u)
    if [[ -z "$uis" ]]; then echo "  running UI:   none"; fi
    while read -r u; do [[ -n "$u" ]] || continue
        [[ "$u" == "$ROOT/ui/shell.qml" ]] && echo "  running UI:   $u  (this tree)" || echo "  also running: $u"
    done <<<"$uis"
    niri validate >/dev/null 2>&1 && echo "  niri config:  valid" || echo "  niri config:  INVALID (niri validate)"
}
if ((only_check)); then check; exit 0; fi
if locked; then echo "The session is locked: not installing now." >&2; exit 1; fi

say "UI plugin → $UI_BUILD"
[[ -f "$UI_BUILD/build.ninja" ]] || cmake -S "$ROOT/ui/native" -B "$UI_BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
nice -n 15 cmake --build "$UI_BUILD" -j "$(nproc)" >/dev/null

say "Launcher → $BIN/zynith-ui"
mkdir -p "$BIN"
ln -sfn "$ROOT/ui/zynith-ui" "$BIN/zynith-ui"

if ((want_shell)); then
    say "Native shell → $SHELL_BUILD"
    [[ -f "$SHELL_BUILD/build.ninja" ]] || meson setup "$SHELL_BUILD" "$ROOT" --buildtype=release --prefix="$PREFIX" -Dtests=enabled >/dev/null
    # half the cores, lowest priority: a full build otherwise holds every core for minutes on the live desktop
    nice -n 19 meson compile -C "$SHELL_BUILD" -j "$(( $(nproc) / 2 > 1 ? $(nproc) / 2 : 1 ))" >/dev/null
    if [[ -x "$PREFIX/bin/zynith-shell" ]] && cmp -s "$SHELL_BUILD/zynith-shell" "$PREFIX/bin/zynith-shell"; then
        echo "  installed binary is already this build"
    else
        keep="$PREFIX/bin/zynith-shell.pre-install-$(date +%Y%m%d-%H%M%S)"
        [[ -x "$PREFIX/bin/zynith-shell" ]] && cp -p "$PREFIX/bin/zynith-shell" "$keep" && echo "  previous binary kept as $keep"
        # meson replaces files by unlinking first, so a running binary is not "busy"; assets (translations) come too
        meson install -C "$SHELL_BUILD" --quiet
        echo "  installed $(git -C "$ROOT" describe --always --dirty)"
    fi
fi

if ((want_restart)); then
    if locked; then echo "Locked now: not restarting." >&2; exit 1; fi
    if ((want_shell)); then say "Restarting the native shell (supervised)"; "$BIN/zynith-ui" native restart; sleep 3; fi
    say "Restarting the UI"; "$BIN/zynith-ui" restart
fi
check
