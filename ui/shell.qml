//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=basic

// Zynith UI — Quickshell layer. Runs beside the native shell during migration and takes no exclusive
// role (no notification server, tray watcher, polkit/secret agents or session lock).
import QtQuick
import Quickshell
import qs.Modules.Bar
import qs.Modules.Panels
import qs.Modules.Osd
import qs.Modules.Notifications
import qs.Modules.Desktop
import qs.Services

ShellRoot {
    // singletons are created on first use; IPC must exist from the start
    readonly property var ipc: Ipc

    // this instance writes the generated niri layout fragment; Settings only edits shell.json
    Component.onCompleted: WindowBehaviour.writer = true

    Bars {}
    PanelHost {}
    Osd {}
    NotificationPopups {}
    DesktopLayer {}
}
