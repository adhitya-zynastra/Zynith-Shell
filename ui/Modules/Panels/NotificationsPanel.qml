import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// What arrived while you were away. Sections by time (now, today, earlier), and within them one group per
// app, collapsed to its newest message until opened. Search finds across all of it. Do Not Disturb holds
// popups back (critical ones and filters with bypass_dnd still show); the history is kept across restarts
// when notifications.toml history_persist is on.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true

    padding: Metrics.s5
    spacing: Metrics.s3
    readonly property real inner: width - padding * 2

    property string query: ""
    property var opened: ({})          // app name -> true while its group is open
    property bool confirmClear: false
    onActiveChanged: if (active) {
        query = "";
        search.text = "";
        confirmClear = false;
    }

    function toggle(app: string): void {
        const o = Object.assign({}, opened);
        o[app] = !o[app];
        opened = o;
    }

    // rows for the list: section titles, group headers, entries
    readonly property var rows: {
        const q = query.trim().toLowerCase();
        const all = Notifications.history.filter(e => q === "" || (e.appName + " " + e.summary + " " + e.body).toLowerCase().includes(q));
        const now = Date.now();
        const startOfDay = new Date().setHours(0, 0, 0, 0);
        const sections = [
            { key: "now", label: "Now", test: e => now - e.time < 3600000 },
            { key: "today", label: "Today", test: e => e.time >= startOfDay },
            { key: "earlier", label: "Earlier", test: e => true }
        ];
        const grouping = Config.notifications.grouping ?? true;
        const used = new Set();
        const out = [];
        for (const s of sections) {
            const inSection = all.filter(e => !used.has(e.key) && s.test(e));
            if (inSection.length === 0)
                continue;
            inSection.forEach(e => used.add(e.key));
            out.push({ kind: "section", key: "s" + s.key, label: s.label });
            if (!grouping || q !== "") {
                for (const e of inSection)
                    out.push({ kind: "entry", key: "e" + e.key, entry: e });
                continue;
            }
            const order = [], groups = {};
            for (const e of inSection) {
                const app = e.appName || "Notification";
                if (!groups[app]) {
                    groups[app] = [];
                    order.push(app);
                }
                groups[app].push(e);
            }
            for (const app of order) {
                const list = groups[app];
                const open = opened[app] === true || list.length === 1;
                out.push({ kind: "group", key: "g" + s.key + app, app: app, count: list.length, open: open, icon: list[0].appIcon });
                const showing = open ? list : list.slice(0, 1);
                for (const e of showing)
                    out.push({ kind: "entry", key: "e" + e.key, entry: e, grouped: true });
                if (!open)
                    out.push({ kind: "more", key: "m" + s.key + app, app: app, count: list.length - 1 });
            }
        }
        return out;
    }

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

    Rectangle {
        visible: Notifications.dnd
        width: root.inner
        height: 30
        radius: 15
        color: Theme.accentSoft
        Row {
            anchors.centerIn: parent
            spacing: Metrics.s2
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "moon"
                size: 13
                tone: "accent"
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                tone: "accent"
                text: "Do Not Disturb — popups held back" + (Notifications.queue.length > 0 ? "" : "")
            }
        }
    }

    SearchField {
        id: search
        visible: Notifications.history.length > 3
        width: root.inner
        placeholder: "Search notifications"
        onTextChanged: root.query = text
        onEscaped: PanelRouter.close(root.screen.name)
    }

    ListView {
        id: list
        visible: count > 0
        width: root.inner
        height: Math.min(contentHeight, 560)
        clip: true
        spacing: Metrics.s1
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: root.rows
            objectProp: "key"
        }

        add: Transition {
            Anim {
                property: "opacity"
                from: 0
                to: 1
                role: "effects"
            }
            Anim {
                property: "y"
                from: list.contentY - 8
                role: "spatialFast"
            }
        }
        remove: Transition {
            ParallelAnimation {
                Anim {
                    property: "opacity"
                    to: 0
                    role: "exit"
                }
                Anim {
                    property: "x"
                    to: 40
                    role: "exit"
                }
            }
        }
        displaced: Transition {
            Anim {
                properties: "x,y"
                role: "spatial"
            }
            Anim {
                property: "opacity"
                to: 1
                role: "effects"
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind
            width: list.width
            height: kind === "section" ? 30 : kind === "group" ? 34 : kind === "more" ? 28 : card.height
            // rows arrive one after another as the panel opens
            opacity: Math.min(1, Math.max(0, (root.visibleProgress - Math.min(0.5, index * 0.04)) / 0.5))

            // a time section
            Label {
                visible: row.kind === "section"
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                role: "micro"
                caps: true
                tone: "faint"
                text: row.modelData.label ?? ""
            }

            // a group header: who, how many, open or closed, clear
            Item {
                visible: row.kind === "group"
                anchors.fill: parent
                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusMd
                    color: groupArea.containsMouse ? Theme.hover : "transparent"
                }
                MouseArea {
                    id: groupArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: (row.modelData.count ?? 0) > 1
                    onClicked: root.toggle(row.modelData.app)
                }
                Image {
                    id: groupIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    sourceSize.width: 36
                    sourceSize.height: 36
                    source: (row.modelData.icon ?? "") !== "" && !(row.modelData.icon ?? "").startsWith("/") ? Quickshell.iconPath(row.modelData.icon, true) : ""
                    asynchronous: true
                }
                Label {
                    anchors.left: groupIcon.right
                    anchors.leftMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    font.weight: Font.Medium
                    text: (row.modelData.app ?? "") + ((row.modelData.count ?? 0) > 1 ? "  ·  " + row.modelData.count : "")
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (row.modelData.count ?? 0) > 1
                        name: "chevron-down"
                        size: 13
                        tone: "faint"
                        rotation: row.modelData.open ? 180 : 0
                        Behavior on rotation {
                            Anim {
                                role: "spatialFast"
                            }
                        }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: 12
                        tone: clearGroup.containsMouse ? "ink" : "faint"
                        MouseArea {
                            id: clearGroup
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifications.removeApp(row.modelData.app)
                        }
                    }
                }
            }

            // a closed group's tail
            Label {
                visible: row.kind === "more"
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s7
                anchors.verticalCenter: parent.verticalCenter
                role: "caption"
                tone: moreArea.containsMouse ? "accent" : "faint"
                text: "+" + (row.modelData.count ?? 0) + " more"
                MouseArea {
                    id: moreArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle(row.modelData.app)
                }
            }

            // an entry
            Rectangle {
                visible: row.kind === "entry"
                anchors.fill: parent
                anchors.leftMargin: row.modelData.grouped ? Metrics.s3 : 0
                radius: Metrics.radiusLg
                color: card.hovered ? Theme.hover : "transparent"
                Behavior on color {
                    ColorAnim {}
                }
            }
            NotificationCard {
                id: card
                visible: row.kind === "entry"
                x: row.modelData.grouped ? Metrics.s3 : 0
                width: parent.width - x
                compact: true
                entry: row.kind === "entry" ? row.modelData.entry : ({ key: -1, actions: [], appName: "", appIcon: "", image: "", summary: "", body: "", time: 0, progress: -1, reply: "" })
            }
        }
    }

    Label {
        visible: Notifications.history.length > 0 && root.rows.length === 0
        width: root.inner
        height: 48
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        role: "label"
        tone: "faint"
        text: "Nothing matches"
    }

    Item {
        visible: Notifications.history.length > 0
        width: root.inner
        height: 30

        Chip {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "trash"
            text: root.confirmClear ? "Clear all — again to confirm" : "Clear all"
            active: root.confirmClear
            onClicked: {
                if (root.confirmClear)
                    Notifications.clearAll();
                root.confirmClear = !root.confirmClear;
            }
        }
    }
}
