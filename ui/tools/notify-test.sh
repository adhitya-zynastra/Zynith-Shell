#!/usr/bin/env bash
# Runs the notification server on a private D-Bus session and sends it a set of notifications, so popups
# can be checked without touching the session's notification owner. Popups appear on screen briefly.
set -euo pipefail
UI="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$UI/../../build-zynith-native/qml"
# a scratch config, so toggles made during the test never reach the real shell.json
export ZYNITH_CONFIG_DIR="$(mktemp -d)"
trap 'rm -rf "$ZYNITH_CONFIG_DIR"' EXIT
dbus-run-session -- bash -c '
    QS_DISABLE_CRASH_HANDLER=1 QML_IMPORT_PATH="'"$NATIVE"'" /usr/bin/quickshell -p "'"$UI"'/notify-test.qml" &
    qs=$!
    for _ in $(seq 1 50); do busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && break; sleep 0.1; done
    busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications GetServerInformation
    notify-send -a "Zynith test" "Plain notification" "A short body."
    sleep 0.4
    notify-send -a "Mail" -i mail-unread "Long body" "$(printf "Line one of a longer message that should wrap across lines.\nLine two.\nLine three.\nLine four.\nLine five should be cut.")"
    sleep 0.4
    notify-send -a "Backup" -u critical "Critical: disk almost full" "Critical notifications stay until handled."
    sleep 0.4
    notify-send -a "Calendar" -A "open=Open" -A "snooze=Snooze" "Meeting in 5 minutes" "Design review" &
    sleep '"${HOLD:-6}"'
    kill $qs; wait $qs 2>/dev/null || true
'
