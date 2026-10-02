import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Bluetooth: off, on, or connected (with the device's name if asked); hidden when off or with nothing
// connected if asked.
BarItem {
    id: root
    shown: Bluetooth.available && !(opt("hide_when_adapter_off") === true && !Bluetooth.enabled) && !(opt("hide_when_no_connected_device") === true && Bluetooth.connected.length === 0)
    active: PanelRouter.isOpen("bluetooth", screen?.name ?? "")
    BarGlyph {
        item: root
        name: !Bluetooth.enabled ? "bluetooth-off" : Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth"
        colour: Bluetooth.enabled ? root.iconInk : Theme.alpha(root.iconInk, 0.45)
    }
    BarText {
        item: root
        visible: root.opt("show_label") === true && !root.vertical && Bluetooth.connected.length > 0
        muted: true
        text: Bluetooth.summary
    }
}
