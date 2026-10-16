import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import "../../Common/NotificationGroups.js" as Groups

// The notification centre, laid out as a phone's shade: time sections (now, today, earlier), and in them one
// stack per app — its newest card on top, the rest as sheets beneath until the stack is opened. A card opens what
// it is about when tapped, opens up to show its whole text, actions and reply, and is cleared with a sideways
// swipe, its × or the middle button; an app's stack clears at once from its header, everything from Clear all.
// While the centre is open new notifications arrive here instead of popping up beside it (Notifications
// centerOpen), marked until it closes. The keyboard walks the cards (Up/Down), opens (Enter), shows more
// (Space or Right / Left), clears (Delete), and typing searches.
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
    property var opened: ({})          // app name -> true while its stack is open
    property var expanded: ({})        // entry key -> true while the card shows everything
    property bool confirmClear: false
    property string selected: ""       // the keyboard's stop (Groups.stops id)
    property real now: Date.now()

    // the list is where notifications arrive while this is open
    onActiveChanged: {
        Notifications.centerOpen = active && Notifications.serving;
        if (active) {
            query = "";
            search.text = "";
            confirmClear = false;
            selected = "";
            now = Date.now();
            keys.forceActiveFocus();
        } else {
            Notifications.arrived = [];
            expanded = {};
        }
    }
    Component.onCompleted: {
        Notifications.centerOpen = active && Notifications.serving;
        if (active)
            keys.forceActiveFocus();
    }
    Component.onDestruction: {
        Notifications.centerOpen = false;
        Notifications.arrived = [];
    }
    // ages ("4m") move on while it is open
    Timer {
        running: root.active
        repeat: true
        interval: 30000
        onTriggered: root.now = Date.now()
    }

    function toggleApp(app: string): void {
        const o = Object.assign({}, opened);
        o[app] = !o[app];
        opened = o;
    }
    function toggleEntry(key: int): void {
        const o = Object.assign({}, expanded);
        o[key] = !o[key];
        expanded = o;
    }
    function openEntry(key: int): void {
        if (Notifications.open(key))
            PanelRouter.close(root.screen?.name ?? "");
    }

    readonly property var rows: Groups.build(Notifications.history, {
        now: root.now,
        query: root.query,
        grouping: Config.notifications.grouping ?? true,
        opened: root.opened
    })
    readonly property var stops: Groups.stops(rows)
    readonly property var selectedStop: stops[Groups.indexOf(stops, selected)] ?? null
    // a stop that went away (its card cleared) hands the keyboard to the one now in its place
    property int selectedIndex: -1
    onStopsChanged: if (selected !== "" && Groups.indexOf(stops, selected) < 0)
        select(Groups.step(stops, selected, 0, selectedIndex))
    function select(id: string): void {
        selected = id;
        selectedIndex = Groups.indexOf(stops, id);
        const stop = stops[selectedIndex];
        if (!stop)
            return;
        for (let i = 0; i < rows.length; i++)
            if (rows[i].key === stop.group) {
                list.positionViewAtIndex(i, ListView.Contain);
                break;
            }
    }
    function move(by: int): void {
        select(selected === "" ? (stops[by > 0 ? 0 : stops.length - 1]?.id ?? "") : Groups.step(stops, selected, by));
    }
    function activate(): void {
        const s = selectedStop;
        if (!s)
            return;
        if (s.kind === "group")
            toggleApp(s.app);
        else
            openEntry(s.key);
    }
    function more(show: bool): void {
        const s = selectedStop;
        if (!s)
            return;
        if (s.kind === "group") {
            if (!!opened[s.app] !== show)
                toggleApp(s.app);
        } else if (!!expanded[s.key] !== show) {
            toggleEntry(s.key);
        }
    }
    function clearSelected(): void {
        const s = selectedStop;
        if (!s)
            return;
        if (s.kind === "group")
            Notifications.removeApp(s.app);
        else
            Notifications.dismiss(s.key);
    }

    // the keyboard, when it is not in the search field or a reply
    Item {
        id: keys
        width: 0
        height: 0
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                root.move(1);
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                root.move(-1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate();
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Right) {
                root.more(true);
            } else if (event.key === Qt.Key_Left) {
                root.more(false);
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                if (event.modifiers & Qt.ShiftModifier) {
                    if (root.confirmClear)
                        Notifications.clearAll();
                    root.confirmClear = !root.confirmClear;
                } else {
                    root.clearSelected();
                }
            } else if (event.key === Qt.Key_R && root.selectedStop?.kind === "entry") {
                // reply, where the sender takes one
                root.expanded = Object.assign({}, root.expanded, { [root.selectedStop.key]: true });
                Qt.callLater(() => list.replyTo(root.selectedStop?.key ?? -1));
            } else if (event.key === Qt.Key_Escape) {
                if (root.selected !== "")
                    root.selected = "";
                else
                    PanelRouter.close(root.screen?.name ?? "");
            } else if (event.text.length === 1 && event.text.trim() !== "" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) && search.visible) {
                search.append(event.text);
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    PanelHeader {
        width: root.inner
        title: "Notifications"
        caption: !Notifications.serving ? "Not handled here" : Notifications.history.length === 0 ? "All caught up" : Notifications.history.length + (Notifications.history.length === 1 ? " notification" : " notifications")
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
        radius: height / 2
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
                text: "Do Not Disturb — popups held back"
            }
        }
    }

    SearchField {
        id: search
        visible: Notifications.history.length > 3
        width: root.inner
        placeholder: "Search notifications"
        onTextChanged: root.query = text
        onEscaped: keys.forceActiveFocus()
        onMoved: delta => root.move(delta)
        onAccepted: root.activate()
    }

    // ── nothing to show: not ours, or all caught up ──
    Item {
        visible: !Notifications.serving || Notifications.history.length === 0
        width: root.inner
        height: 180
        Column {
            anchors.centerIn: parent
            width: parent.width - Metrics.s6 * 2
            spacing: Metrics.s3
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 28
                color: Notifications.serving ? Theme.plate : Theme.alpha(Theme.danger, 0.12)
                Icon {
                    anchors.centerIn: parent
                    name: !Notifications.serving ? "bell-off" : Notifications.dnd ? "moon" : "bell"
                    size: 24
                    tone: Notifications.serving ? "muted" : "danger"
                }
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "title"
                text: !Notifications.serving ? "Notifications aren't shown here" : "You're all caught up"
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                role: "label"
                tone: "muted"
                text: !Notifications.serving ? (Notifications.wanted ? "Another notification service holds the session's notifications, so they reach it instead. Close it, and this list fills from then on." : "The native shell shows notifications for now. Hand them to Zynith under Settings → Notifications.") : Notifications.dnd ? "Do Not Disturb is on — what arrives waits here quietly." : "New notifications gather here."
            }
        }
    }

    ListView {
        id: list
        visible: count > 0
        width: root.inner
        height: Math.min(contentHeight, 600)
        clip: true
        spacing: Metrics.s2
        boundsBehavior: Flickable.StopAtBounds
        // a reply asked for from the keyboard: the card, once opened, takes it
        signal replyTo(int key)
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
                from: list.contentY - 12
                role: "spatialFast"
            }
        }
        remove: Transition {
            Anim {
                property: "opacity"
                to: 0
                role: "exit"
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
            readonly property bool section: modelData.kind === "section"
            readonly property var entries: modelData.entries ?? []
            readonly property bool stacked: modelData.stacked ?? false
            readonly property bool headed: entries.length > 1
            readonly property bool headSelected: root.selected === modelData.key && !stacked
            width: list.width
            // sheets peek out under a closed stack
            readonly property real peek: stacked ? Math.min(2, entries.length - 1) * 6 : 0
            height: section ? 26 : stack.implicitHeight + peek
            Behavior on height {
                enabled: !row.section
                Anim {
                    role: "spatial"
                }
            }
            clip: !section
            // rows arrive one after another as the panel opens
            opacity: Math.min(1, Math.max(0, (root.visibleProgress - Math.min(0.5, index * 0.04)) / 0.5))

            // a time section
            Label {
                visible: row.section
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                role: "micro"
                caps: true
                tone: "faint"
                text: row.modelData.label ?? ""
            }

            // the sheets of a closed stack: only their lower edges show under the card (the cards are translucent,
            // so a whole sheet behind one showed through it), narrower and fainter the deeper they sit
            Repeater {
                model: row.stacked ? Math.min(2, row.entries.length - 1) : 0
                delegate: Rectangle {
                    required property int index
                    readonly property int depth: index + 1
                    x: depth * 10
                    width: row.width - depth * 20
                    y: stack.y + stack.implicitHeight + (depth - 1) * 6 + 1
                    height: 5
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: Metrics.radiusMd
                    bottomRightRadius: Metrics.radiusMd
                    color: Theme.plate
                    opacity: 1 - depth * 0.3
                }
            }

            Column {
                id: stack
                visible: !row.section
                width: parent.width
                spacing: Metrics.s1

                // an app's header: who, how many, open or close the stack, clear it
                Item {
                    visible: row.headed
                    width: parent.width
                    height: 30
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        color: headArea.containsMouse ? Theme.hover : "transparent"
                        border.width: row.headSelected || (row.stacked && root.selected === row.modelData.key) ? 1.5 : 0
                        border.color: Theme.focus
                    }
                    MouseArea {
                        id: headArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleApp(row.modelData.app)
                    }
                    Item {
                        id: headIcon
                        x: Metrics.s2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        Image {
                            id: headImage
                            anchors.fill: parent
                            sourceSize.width: 36
                            sourceSize.height: 36
                            asynchronous: true
                            source: Notifications.iconFor(row.entries[0] ?? null)
                        }
                        Rectangle {
                            visible: headImage.status !== Image.Ready
                            anchors.fill: parent
                            radius: width / 2
                            color: Theme.accentSoft
                            Label {
                                anchors.centerIn: parent
                                role: "micro"
                                tone: "accent"
                                text: (row.modelData.app ?? "?").charAt(0).toUpperCase()
                            }
                        }
                    }
                    Label {
                        anchors.left: headIcon.right
                        anchors.leftMargin: Metrics.s2
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        font.weight: Font.Medium
                        text: row.modelData.app ?? ""
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.s1
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s1
                        // how many, and which way the stack goes
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: countRow.implicitWidth + Metrics.s3 * 2
                            height: 22
                            radius: 11
                            color: Theme.plate
                            Row {
                                id: countRow
                                anchors.centerIn: parent
                                spacing: Metrics.s1
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "caption"
                                    numeric: true
                                    tone: "muted"
                                    text: row.stacked ? row.entries.length : "Show less"
                                }
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "chevron-down"
                                    size: 11
                                    tone: "muted"
                                    rotation: row.stacked ? 0 : 180
                                    Behavior on rotation {
                                        Anim {
                                            role: "spatialFast"
                                        }
                                    }
                                }
                            }
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 24
                            iconSize: 12
                            icon: "x"
                            tone: "muted"
                            onClicked: Notifications.removeApp(row.modelData.app)
                        }
                    }
                }

                Repeater {
                    model: row.stacked ? row.entries.slice(0, 1) : row.entries
                    delegate: NotificationTile {
                        id: tile
                        required property var modelData
                        width: stack.width
                        entry: modelData
                        now: root.now
                        showApp: !row.headed
                        expanded: !row.stacked && root.expanded[modelData.key] === true
                        selected: root.selected === "e" + modelData.key || (row.stacked && root.selected === row.modelData.key)
                        fresh: Notifications.arrived.includes(modelData.key)
                        onToggled: row.stacked ? root.toggleApp(row.modelData.app) : root.toggleEntry(modelData.key)
                        // a closed stack opens first; a card opens what it is about
                        onOpened: row.stacked ? root.toggleApp(row.modelData.app) : root.openEntry(modelData.key)
                        onDismissed: Notifications.dismiss(modelData.key)
                        Connections {
                            target: list
                            function onReplyTo(key: int): void {
                                if (key === tile.modelData.key)
                                    tile.focusReply();
                            }
                        }
                    }
                }
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
        text: "Nothing matches “" + root.query + "”"
    }

    Item {
        visible: Notifications.history.length > 0
        width: root.inner
        height: 30

        Label {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.selected !== ""
            role: "caption"
            tone: "faint"
            text: "Enter open  ·  Space more  ·  Del clear"
        }
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
