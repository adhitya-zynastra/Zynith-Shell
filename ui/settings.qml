//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=basic

// Zynith Settings: a separate instance of the same project, started on demand and gone when closed.
import QtQuick
import Quickshell
import qs.Modules.Settings

ShellRoot {
    SettingsWindow {}
}
