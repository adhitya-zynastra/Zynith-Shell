import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// What arrived while you were away, newest first. Kept in memory only; Do Not Disturb holds popups back
// (critical ones still show).
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true

    padding: Metrics.s6
    spacing: Metrics.s4
    readonly property real inner: width - padding * 2

    PanelHeader {
        width: root.inner
        title: "Notifications"
        caption: !Notifications.serving ? "Handled by the native shell for now" : Notifications.history.length === 0 ? "Nothing new" : Notifications.history.length + (Notifications.history.length === 1 ? " notification" : " notifications")
        canGoBack: root.canGoBack
        onBack: root.back()

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: Notifications.dnd ? "bell-off" : "bell"
            tone: Notifications.dnd ? "accent" : "muted"
            active: Notifications.dnd
            onClicked: Notifications.setDnd(!Notifications.dnd)
        }
    }

    Label {
        visible: Notifications.dnd
        width: root.inner
        role: "caption"
        tone: "accent"
        caps: true
        text: "Do not disturb  ·  popups held back"
    }

    ListView {
        id: list
        visible: count > 0
        width: root.inner
        height: Math.min(contentHeight, 520)
        clip: true
        spacing: Metrics.s1
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: Notifications.history
        }

        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: card.height

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusLg
                color: card.hovered ? Theme.hover : "transparent"
            }
            NotificationCard {
                id: card
                width: parent.width
                compact: true
                entry: row.modelData
            }
        }
    }

    Item {
        visible: Notifications.history.length > 0
        width: root.inner
        height: 24

        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            role: "caption"
            caps: true
            tone: clearArea.containsMouse ? "ink" : "faint"
            text: "Clear all"

            MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -Metrics.s2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifications.clearAll()
            }
        }
    }
}
