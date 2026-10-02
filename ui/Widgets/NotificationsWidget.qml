import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The bell: how many are waiting, a quiet bell under Do Not Disturb; hidden with nothing waiting if asked.
BarItem {
    id: root
    readonly property bool dnd: Notifications.serving ? Notifications.dnd : Core.dnd
    readonly property int count: Notifications.unread
    shown: !(opt("hide_when_no_unread") === true && count === 0)
    active: PanelRouter.isOpen("notifications", screen?.name ?? "")
    Item {
        width: Metrics.icon + 2
        height: Metrics.icon + 2
        BarGlyph {
            item: root
            anchors.centerIn: parent
            name: root.dnd ? "bell-off" : root.count > 0 ? "bell-ringing" : "bell"
            colour: root.dnd ? Theme.alpha(root.iconInk, 0.5) : root.iconInk
        }
        Rectangle {
            visible: root.count > 0 && !root.dnd
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -2
            width: Math.max(8, badge.implicitWidth + 4)
            height: 8
            radius: 4
            color: Theme.accent
            Text {
                id: badge
                anchors.centerIn: parent
                visible: root.count > 1
                text: root.count > 9 ? "9+" : root.count
                font.pixelSize: 7
                font.bold: true
                color: Theme.onAccent
            }
        }
    }
}
