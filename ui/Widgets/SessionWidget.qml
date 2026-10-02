import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    active: PanelRouter.isOpen("session", screen?.name ?? "")
    onClicked: PanelRouter.toggle("session", screen?.name ?? "", { edge: "center" })

    Icon {
        name: "power"
        tone: root.active ? "accent" : "ink"
    }
}
