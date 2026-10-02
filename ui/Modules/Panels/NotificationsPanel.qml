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

    // grouped by app (notifications.toml grouping): the newest group first, a header over each
    readonly property var rows: {
        const history = Notifications.history;
        if (!(Config.notifications.grouping ?? true))
            return history.map(e => ({ kind: "entry", key: "e" + e.key, entry: e }));
        const order = [], groups = {};
        for (const e of history) {
            const app = e.appName || "Notification";
            if (!groups[app]) {
                groups[app] = [];
                order.push(app);
            }
            groups[app].push(e);
        }
        const out = [];
        for (const app of order) {
            out.push({ kind: "header", key: "h" + app, app: app, count: groups[app].length, entries: groups[app] });
            for (const e of groups[app])
                out.push({ kind: "entry", key: "e" + e.key, entry: e });
        }
        return out;
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
            values: root.rows
            objectProp: "key"
        }

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool header: modelData.kind === "header"
            width: list.width
            height: header ? 30 : card.height

            Item {
                visible: row.header
                anchors.fill: parent

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s2
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.s1
                    role: "caption"
                    caps: true
                    tone: "muted"
                    text: row.header ? row.modelData.app + (row.modelData.count > 1 ? "  ·  " + row.modelData.count : "") : ""
                }
                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s2
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.s1
                    name: "x"
                    size: 12
                    tone: clearGroup.containsMouse ? "ink" : "faint"

                    MouseArea {
                        id: clearGroup
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            for (const e of row.modelData.entries)
                                Notifications.dismiss(e.key);
                        }
                    }
                }
            }

            Rectangle {
                visible: !row.header
                anchors.fill: parent
                radius: Metrics.radiusLg
                color: card.hovered ? Theme.hover : "transparent"
            }
            NotificationCard {
                id: card
                visible: !row.header
                width: parent.width
                compact: true
                entry: row.header ? ({ key: -1, actions: [], appName: "", appIcon: "", image: "", summary: "", body: "", time: 0 }) : row.modelData.entry
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
