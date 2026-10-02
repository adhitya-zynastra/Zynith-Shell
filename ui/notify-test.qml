// Test harness: the notification server and popups alone, forced on. Run it only on a private bus
// (tools/notify-test.sh), never on the session bus while another server owns the name.
import QtQuick
import Quickshell
import qs.Modules.Notifications
import qs.Services

ShellRoot {
    readonly property var ipc: Ipc
    Component.onCompleted: Notifications.forceServer = true
    NotificationPopups {}
}
