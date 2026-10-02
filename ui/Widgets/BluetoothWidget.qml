import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    shown: Bluetooth.available
    active: PanelRouter.isOpen("bluetooth", screen?.name ?? "")
    onClicked: bar?.openPanel("bluetooth", root)

    Icon {
        name: !Bluetooth.enabled ? "bluetooth-off" : Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth"
        tone: !Bluetooth.enabled ? "faint" : root.active ? "accent" : "ink"
    }
}
