import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Opens the launcher.
BarItem {
    id: root

    active: PanelRouter.isOpen("launcher", screen?.name ?? "")
    onClicked: PanelRouter.toggle("launcher", screen?.name ?? "", { edge: "center" })

    Icon {
        name: "layout-grid"
        tone: root.active ? "accent" : "ink"
    }
}
