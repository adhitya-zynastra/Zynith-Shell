import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The launcher. Type to find; a leading = > @ : ! (or the native /calc /win /wall /emo /session) switches to
// calculator, windows, wallpapers, emoji or session. Apps can be browsed by category, pinned, and opened
// through their actions (New Window, Private Window…).
//
// Keys: ↑ ↓ / Tab move · Enter runs · → shows an app's actions, ← hides them · Alt+← → category ·
//       Ctrl+P pin · Esc leaves
Item {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    property string context: ""
    property int showings: 0
    onShowingsChanged: reset()
    onContextChanged: if (active)
        reset()
    readonly property var options: Config.launcher
    readonly property int preferredWidth: grid ? Math.max(options.width ?? 600, 640) : (options.width ?? 600)
    // center: in the middle of the screen (the card's own height, gliding as results change) | top
    readonly property real preferredTop: options.position === "top" ? 0.1 : -1
    readonly property bool compact: options.density === "compact"
    readonly property int rows: options.rows ?? 8
    readonly property int rowHeight: compact ? 42 : 54
    implicitHeight: column.implicitHeight

    property string text: ""
    property int current: 0
    property string armed: ""
    property string category: "all"
    property string expanded: ""      // the app whose actions are showing
    readonly property var mode: Launcher.modeOf(text)
    readonly property bool appsMode: mode.id === "apps"
    readonly property bool showCategories: appsMode && (options.categories ?? true) && Apps.presentCategories.length > 1
    readonly property bool grid: appsMode && options.layout === "grid" && text.trim() === ""
    readonly property int gridColumns: 6
    readonly property var results: active ? Launcher.search(text, grid ? gridColumns * 3 : rows, category) : []
    // the list as shown: an expanded app's actions follow it, indented
    readonly property var shown: {
        if (expanded === "" || !(options.actions ?? true))
            return results;
        const out = [];
        for (const r of results) {
            out.push(r);
            if (r.key === expanded)
                for (const a of r.actions ?? [])
                    out.push(Object.assign({}, a, {
                        child: true
                    }));
        }
        return out;
    }
    readonly property var selected: shown[Math.min(current, shown.length - 1)] ?? null
    onShownChanged: current = Math.min(current, Math.max(0, shown.length - 1))
    onTextChanged: {
        current = 0;
        armed = "";
        expanded = "";
    }
    onCategoryChanged: {
        current = 0;
        expanded = "";
    }

    onActiveChanged: if (active)
        reset()
    Component.onCompleted: reset()
    function reset(): void {
        field.text = context;
        field.cursorPosition = context.length;
        current = 0;
        armed = "";
        expanded = "";
        category = "all";
        field.forceActiveFocus();
    }

    function open(i: int): void {
        const r = shown[i];
        if (!r)
            return;
        if (r.confirm && armed !== r.key) {
            armed = r.key;
            return;
        }
        r.run();
        PanelRouter.close(screen.name);
    }
    function move(delta: int): void {
        if (shown.length > 0)
            current = (current + delta + shown.length) % shown.length;
    }
    function cycleCategory(delta: int): void {
        const keys = ["all"].concat(Apps.presentCategories.map(c => c.key));
        category = keys[(keys.indexOf(category) + delta + keys.length) % keys.length];
    }
    function toggleActions(show: bool): void {
        const r = selected;
        if (!r)
            return;
        if (show && r.kind === "app" && (r.actions ?? []).length > 0) {
            expanded = r.key;
            current = shown.findIndex(s => s.key === r.key) + 1;
        } else if (!show && expanded !== "") {
            const parent = expanded;
            expanded = "";
            current = Math.max(0, results.findIndex(s => s.key === parent));
        }
    }

    Column {
        id: column
        width: parent.width
        padding: Metrics.s4
        spacing: 0
        readonly property real inner: width - padding * 2

        // ── the search line ─────────────────────────────────────────────────
        Item {
            width: column.inner
            height: 52

            Rectangle {
                id: chip
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: 28
                width: root.mode.prefix ? chipRow.implicitWidth + Metrics.s4 * 2 : 28
                radius: 14
                color: root.mode.prefix ? Theme.signalFill : "transparent"
                border.width: root.mode.prefix ? 1 : 0
                border.color: Theme.signalEdge

                Behavior on width {
                    Anim {
                        role: "spatialFast"
                    }
                }
                Behavior on color {
                    ColorAnim {}
                }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Metrics.s2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.mode.prefix ? root.mode.glyph : "search"
                        size: root.mode.prefix ? 14 : 18
                        tone: root.mode.prefix ? "accent" : "muted"
                    }
                    Label {
                        visible: root.mode.prefix !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        role: "data"
                        tone: "accent"
                        text: root.mode.label
                    }
                }
            }

            TextInput {
                id: field
                anchors.left: chip.right
                anchors.leftMargin: Metrics.s4
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.ink
                selectionColor: Theme.accentSoft
                selectedTextColor: Theme.ink
                font.family: Type.ui
                font.pixelSize: Type.headline
                font.weight: Font.Light
                clip: true
                onTextChanged: root.text = text

                Keys.onEscapePressed: PanelRouter.close(root.screen.name)
                Keys.onReturnPressed: root.open(root.current)
                Keys.onEnterPressed: root.open(root.current)
                Keys.onUpPressed: root.move(root.grid ? -root.gridColumns : -1)
                Keys.onDownPressed: root.move(root.grid ? root.gridColumns : 1)
                Keys.onTabPressed: root.move(1)
                Keys.onBacktabPressed: root.move(-1)
                Keys.onPressed: event => {
                    const alt = event.modifiers & Qt.AltModifier, ctrl = event.modifiers & Qt.ControlModifier;
                    const atEnd = cursorPosition === text.length;
                    if (alt && (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && root.showCategories) {
                        root.cycleCategory(event.key === Qt.Key_Right ? 1 : -1);
                    } else if (root.grid && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                        root.move(event.key === Qt.Key_Right ? 1 : -1);
                    } else if (event.key === Qt.Key_Right && atEnd && root.selected?.kind === "app" && (root.selected.actions ?? []).length > 0) {
                        root.toggleActions(true);
                    } else if (event.key === Qt.Key_Left && atEnd && root.expanded !== "") {
                        root.toggleActions(false);
                    } else if (event.key === Qt.Key_P && ctrl && root.selected?.kind === "app") {
                        Apps.togglePin(root.selected.id);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Label {
                    visible: field.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    role: "headline"
                    font.weight: Font.Light
                    tone: "faint"
                    text: root.category === "all" ? "Search" : "Search " + (Apps.categories.find(c => c.key === root.category)?.label ?? "")
                }
            }
        }

        // an accent line that fades into the hairline: the launcher's one flourish
        Rectangle {
            width: column.inner
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Theme.accentLine
                }
                GradientStop {
                    position: 0.35
                    color: Theme.hairline
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        // ── categories ──────────────────────────────────────────────────────
        Item {
            width: column.inner
            height: root.showCategories ? 40 : Metrics.s3
            clip: true
            Behavior on height {
                Anim {
                    role: "spatialFast"
                }
            }
            Flickable {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 30
                visible: root.showCategories
                opacity: root.showCategories ? 1 : 0
                contentWidth: catRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                Behavior on opacity {
                    Anim {
                        role: "effects"
                    }
                }
                Item {
                    id: catRow
                    implicitWidth: tabs.implicitWidth
                    height: 30
                    readonly property var keys: ["all"].concat(Apps.presentCategories.map(c => c.key))
                    Row {
                        id: tabs
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s5
                        Repeater {
                            model: [{ key: "all", label: "All" }].concat(Apps.presentCategories)
                            delegate: Label {
                                id: tab
                                required property var modelData
                                role: "data"
                                tone: root.category === modelData.key ? "ink" : tabArea.containsMouse ? "muted" : "faint"
                                text: modelData.label
                                MouseArea {
                                    id: tabArea
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.category = tab.modelData.key
                                }
                            }
                        }
                    }
                    // the current tab's mark glides under it
                    Rectangle {
                        readonly property Item under: tabs.children[Math.max(0, catRow.keys.indexOf(root.category))] ?? null
                        x: under ? under.x : 0
                        width: under ? under.width : 0
                        y: tabs.y + tabs.height + 4
                        height: 1.5
                        radius: 1
                        color: Theme.accent
                        Glide on x {}
                        Glide on width {}
                    }
                }
            }
        }

        // ── results: a list ─────────────────────────────────────────────────
        ListView {
            id: list
            visible: !root.grid
            width: column.inner
            height: visible ? Math.min(root.rows, Math.max(1, root.shown.length)) * (root.rowHeight + spacing) : 0
            spacing: 2
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            // the view's own currentIndex shifts when rows are inserted ahead of it, so the selection is drawn
            // from root.current directly and the view only scrolls to it
            Connections {
                target: root
                function onCurrentChanged(): void {
                    list.positionViewAtIndex(root.current, ListView.Contain);
                }
            }
            Behavior on height {
                Anim {
                    role: "spatialFast"
                }
            }

            model: ScriptModel {
                values: root.shown
                objectProp: "key"
            }

            // the selection: one shape gliding between rows, an accent mark at its edge
            Item {
                parent: list.contentItem
                z: -1
                visible: root.shown.length > 0
                width: list.width
                height: root.rowHeight
                y: root.current * (root.rowHeight + list.spacing)
                Glide on y {}
                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusPlate
                    color: root.armed !== "" ? Theme.alpha(Theme.danger, 0.16) : Theme.plate
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height * 0.42
                    radius: 1
                    color: root.armed !== "" ? Theme.danger : Theme.accent
                }
            }

            add: Transition {
                Anim {
                    property: "opacity"
                    from: 0
                    to: 1
                    role: "effects"
                }
                Anim {
                    property: "x"
                    from: 10
                    to: 0
                    role: "spatialFast"
                }
            }
            displaced: Transition {
                Anim {
                    properties: "x,y"
                    role: "spatialFast"
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
                readonly property bool selected: index === root.current
                readonly property bool child: modelData.child === true

                width: list.width
                height: root.rowHeight
                // rows arrive one after another as the launcher opens
                opacity: Math.min(1, Math.max(0, (root.visibleProgress - Math.min(0.5, index * 0.05)) / 0.5))

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: root.current = row.index
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton && row.modelData.kind === "app") {
                            root.current = row.index;
                            root.expanded === row.modelData.key ? root.toggleActions(false) : root.toggleActions(true);
                        } else {
                            root.open(row.index);
                        }
                    }
                }

                Item {
                    id: lead
                    anchors.left: parent.left
                    anchors.leftMargin: row.child ? Metrics.s7 + Metrics.s2 : Metrics.s4
                    anchors.verticalCenter: parent.verticalCenter
                    // [launcher] icon_size (0 by density) and show_icons (apps' own icons; others keep their glyph)
                    readonly property bool iconsOff: root.options.show_icons === false && row.modelData.kind === "app"
                    width: row.child ? 20 : (root.options.icon_size ?? 0) > 0 ? root.options.icon_size : root.compact ? 24 : 32
                    height: width

                    readonly property string iconSource: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                    Image {
                        anchors.fill: parent
                        visible: source != "" && !lead.iconsOff
                        source: row.modelData.image ? row.modelData.image : lead.iconSource
                        sourceSize.width: 64
                        sourceSize.height: 64
                        fillMode: row.modelData.image ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !!row.modelData.emoji
                        text: row.modelData.emoji ?? ""
                        font.pixelSize: root.compact ? 18 : 22
                    }
                    // installed as a Flatpak, a Snap, an AppImage
                    Rectangle {
                        visible: (row.modelData.origin ?? "") !== "" && root.options.show_origin !== false && !lead.iconsOff
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: -3
                        width: 14
                        height: 14
                        radius: 7
                        color: Theme.surfaceHigh
                        border.width: 1
                        border.color: Theme.hairline
                        Icon {
                            anchors.centerIn: parent
                            name: row.modelData.origin === "flatpak" ? "stack-2" : row.modelData.origin === "snap" ? "category" : "app-window"
                            size: 9
                            tone: "muted"
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !row.modelData.emoji && !row.modelData.image && (lead.iconSource === "" || lead.iconsOff)
                        name: row.modelData.glyph ?? (row.child ? "corner-down-left" : "apps")
                        size: root.compact ? 16 : 20
                        tone: row.selected ? "accent" : "muted"
                    }
                }

                Column {
                    anchors.left: lead.right
                    anchors.leftMargin: Metrics.s4
                    anchors.right: trail.left
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        role: row.modelData.kind === "calc" ? "title" : row.child ? "label" : "body"
                        numeric: row.modelData.kind === "calc"
                        font.weight: row.selected ? Font.Medium : Font.Normal
                        text: row.modelData.title
                    }
                    Label {
                        width: parent.width
                        visible: text !== "" && (!root.compact || row.modelData.kind === "action" && !row.child)
                        role: "caption"
                        tone: "faint"
                        text: root.armed === row.modelData.key ? "Press Enter again to confirm" : row.modelData.subtitle
                    }
                }

                Row {
                    id: trail
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.pinned === true
                        name: "pin-filled"
                        size: 12
                        tone: "accent"
                    }
                    // an app with actions says so; → opens them
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.kind === "app" && (row.modelData.actions ?? []).length > 0 && (root.options.actions ?? true)
                        spacing: 2
                        opacity: row.selected ? 1 : 0.5
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "micro"
                            tone: "faint"
                            text: (row.modelData.actions ?? []).length
                        }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.expanded === row.modelData.key ? "chevron-down" : "chevron-right"
                            size: 12
                            tone: "faint"
                        }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "corner-down-left"
                        size: 13
                        tone: "faint"
                        opacity: row.selected ? 1 : 0
                        Behavior on opacity {
                            Anim {
                                role: "effects"
                            }
                        }
                    }
                }
            }
        }

        // ── results: a grid of apps, when asked for and nothing is typed ──────
        GridView {
            id: gridView
            visible: root.grid
            width: column.inner
            height: visible ? Math.ceil(Math.min(root.results.length, root.gridColumns * 3) / root.gridColumns) * cellHeight : 0
            cellWidth: Math.floor(width / root.gridColumns)
            cellHeight: 96
            interactive: false
            model: ScriptModel {
                values: root.grid ? root.results : []
                objectProp: "key"
            }
            Rectangle {
                parent: gridView.contentItem
                z: -1
                visible: root.results.length > 0
                x: (root.current % root.gridColumns) * gridView.cellWidth
                y: Math.floor(root.current / root.gridColumns) * gridView.cellHeight
                Glide on x {}
                Glide on y {}
                width: gridView.cellWidth
                height: gridView.cellHeight
                radius: Metrics.radiusLg
                color: Theme.selected
                border.width: Metrics.hairline
                border.color: Theme.accentLine
            }
            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                width: gridView.cellWidth
                height: gridView.cellHeight
                opacity: Math.min(1, Math.max(0, (root.visibleProgress - Math.min(0.5, index * 0.03)) / 0.5))
                scale: index === root.current ? 1.04 : 1
                Glide on scale {
                    epsilon: 0.001
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = tile.index
                    onClicked: root.open(tile.index)
                }
                Column {
                    anchors.centerIn: parent
                    spacing: Metrics.s2
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 40
                        height: 40
                        source: tile.modelData.icon ? Quickshell.iconPath(tile.modelData.icon, true) : ""
                        sourceSize.width: 80
                        sourceSize.height: 80
                        asynchronous: true
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: gridView.cellWidth - Metrics.s3 * 2
                        horizontalAlignment: Text.AlignHCenter
                        role: "caption"
                        tone: tile.index === root.current ? "ink" : "muted"
                        text: tile.modelData.title
                    }
                }
                Icon {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Metrics.s3
                    visible: tile.modelData.pinned === true
                    name: "pin-filled"
                    size: 11
                    tone: "accent"
                }
            }
        }

        Label {
            visible: root.shown.length === 0
            width: column.inner
            height: root.rowHeight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            role: "label"
            tone: "faint"
            text: root.mode.id === "calc" ? "Type an expression" : root.mode.id === "emoji" && Launcher.emojiTable.length === 0 ? "" : "Nothing matches"
        }

        // ── the modes and keys, as a quiet legend ───────────────────────────
        Item {
            width: column.inner
            height: 36

            Row {
                id: legend
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.s4

                Repeater {
                    model: Launcher.modes.filter(m => m.prefix !== "")
                    delegate: Row {
                        required property var modelData
                        spacing: Metrics.s1
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: root.mode.id === modelData.id ? Theme.signalEdge : Theme.rule
                            Label {
                                anchors.centerIn: parent
                                role: "data"
                                tone: root.mode.id === modelData.id ? "accent" : "muted"
                                text: modelData.prefix
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "data"
                            tone: root.mode.id === modelData.id ? "accent" : "faint"
                            text: ({ calc: "calc", windows: "win", wallpapers: "wall", emoji: "emoji", session: "power" })[modelData.id] ?? modelData.label
                        }
                    }
                }
                Label {
                    visible: root.appsMode && column.inner > 560
                    anchors.verticalCenter: parent.verticalCenter
                    role: "data"
                    tone: "faint"
                    text: "→ actions   ⌃P pin"
                }
            }
        }
    }
}
