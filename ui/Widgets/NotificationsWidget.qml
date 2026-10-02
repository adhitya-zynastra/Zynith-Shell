import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The bell: quiet when nothing is waiting, a dot when something is, crossed out under Do Not Disturb.
BarItem {
    id: root

    readonly property bool dnd: Notifications.serving ? Notifications.dnd : Core.dnd
    active: PanelRouter.isOpen("notifications", screen?.name ?? "")
    onClicked: bar?.openPanel("notifications", root)

    Item {
        width: 16
        height: 16

        Icon {
            anchors.centerIn: parent
            name: root.dnd ? "bell-off" : "bell"
            tone: root.dnd ? "faint" : root.active ? "accent" : "ink"
        }
        Rectangle {
            visible: Notifications.unread > 0 && !root.dnd
            anchors.right: parent.right
            anchors.top: parent.top
            width: 6
            height: 6
            radius: 3
            color: Theme.accent
        }
    }
}
