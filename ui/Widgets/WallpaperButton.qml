import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    active: PanelRouter.isOpen("wallpaper", screen?.name ?? "")
    onClicked: PanelRouter.toggle("wallpaper", screen?.name ?? "", { edge: "center" })

    Icon {
        name: "photo"
        tone: root.active ? "accent" : "ink"
    }
}
