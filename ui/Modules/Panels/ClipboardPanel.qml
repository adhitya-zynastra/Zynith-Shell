import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Clipboard history in two panes: the list (search, filters, pins) and the selected entry, whole. Enter puts
// it back on the clipboard and pastes it into the window you came from (as [shell] clipboard_auto_paste says);
// Shift+Enter only copies. The core keeps the history encrypted; this panel holds one entry's content at a
// time and drops it when it closes.
//
// Keys: ↑ ↓ move · Enter paste · Shift+Enter copy · Ctrl+P pin · Delete remove (empty search) ·
//       Tab next filter · Ctrl+Shift+Delete clear unpinned · Esc leaves
Item {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    property string context: ""
    readonly property int preferredWidth: Math.min(860, Math.round((screen?.width ?? 1600) * 0.6))
    readonly property real preferredTop: 0.14
    implicitHeight: body.implicitHeight + Metrics.s4 * 2

    property string query: ""
    property string filter: "all"
    property int current: 0
    property string confirm: ""      // "", "clear", "clear-all": a destructive action waiting for a second press

    readonly property var filters: [
        { key: "all", label: "All", icon: "clipboard-list" },
        { key: "text", label: "Text", icon: "letter-a" },
        { key: "link", label: "Links", icon: "external-link" },
        { key: "code", label: "Code", icon: "category" },
        { key: "colour", label: "Colours", icon: "palette" },
        { key: "image", label: "Images", icon: "photo" },
        { key: "pinned", label: "Pinned", icon: "pin" }
    ]
    function countOf(key: string): int {
        const all = Clipboard.entries;
        return key === "all" ? all.length : key === "pinned" ? all.filter(e => e.pinned).length : all.filter(e => e.kind === key).length;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        let list = Clipboard.entries;
        if (filter === "pinned")
            list = list.filter(e => e.pinned);
        else if (filter !== "all")
            list = list.filter(e => e.kind === filter);
        if (q !== "")
            list = list.filter(e => (e.preview ?? "").toLowerCase().includes(q) || (e.image && "image".includes(q)));
        // pinned first, then newest
        return list.slice().sort((a, b) => (b.pinned - a.pinned) || (b.time - a.time));
    }
    readonly property var selected: results[Math.min(current, results.length - 1)] ?? null
    onQueryChanged: current = 0
    onFilterChanged: current = 0
    onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))
    onSelectedChanged: detailTimer.restart()
    Timer {
        id: detailTimer
        interval: 60
        onTriggered: Clipboard.loadDetail(root.selected)
    }

    onActiveChanged: active ? open() : Clipboard.release()
    Component.onCompleted: if (active)
        open()
    Component.onDestruction: if (active)
        Clipboard.release()
    function open(): void {
        Clipboard.retain();
        search.text = "";
        query = "";
        current = 0;
        confirm = "";
        filter = ["text", "link", "code", "colour", "image", "pinned"].includes(context) ? context : "all";
        search.focusField();
    }

    function paste(e: var): void {
        if (!e)
            return;
        Clipboard.paste(e);
        PanelRouter.close(screen.name);
    }
    function copy(e: var): void {
        if (!e)
            return;
        Clipboard.select(e.id);
        PanelRouter.close(screen.name);
    }
    function cycleFilter(back: bool): void {
        const i = filters.findIndex(f => f.key === filter);
        filter = filters[(i + (back ? filters.length - 1 : 1)) % filters.length].key;
    }

    function ago(ms: real): string {
        const s = Math.max(0, (Date.now() - ms) / 1000);
        if (s < 60)
            return "just now";
        if (s < 3600)
            return Math.floor(s / 60) + " min ago";
        if (s < 86400)
            return Math.floor(s / 3600) + " h ago";
        return Math.floor(s / 86400) + " d ago";
    }
    function size(bytes: real): string {
        return bytes < 1024 ? bytes + " B" : bytes < 1048576 ? (bytes / 1024).toFixed(0) + " KB" : (bytes / 1048576).toFixed(1) + " MB";
    }
    function glyph(kind: string): string {
        return ({ image: "photo", link: "external-link", colour: "palette", code: "category", text: "letter-a" })[kind] ?? "clipboard-list";
    }

    Row {
        id: body
        x: Metrics.s4
        y: Metrics.s4
        width: parent.width - Metrics.s4 * 2
        spacing: Metrics.s4

        // ── the list ─────────────────────────────────────────────────────────
        Column {
            id: left
            width: Math.round(body.width * 0.46)
            spacing: Metrics.s3

            SearchField {
                id: search
                width: parent.width
                placeholder: "Search the clipboard"
                onTextChanged: root.query = text
                onMoved: delta => root.current = Math.max(0, Math.min(root.results.length - 1, root.current + delta))
                onTabbed: back => root.cycleFilter(back)
                onAccepted: modifiers => modifiers & Qt.ShiftModifier ? root.copy(root.selected) : root.paste(root.selected)
                onEscaped: PanelRouter.close(root.screen.name)
                onKeyPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
                    if (event.key === Qt.Key_P && ctrl && root.selected) {
                        Clipboard.pin(root.selected.id, !root.selected.pinned);
                    } else if (event.key === Qt.Key_Delete && ctrl && shift) {
                        if (root.confirm === "clear")
                            Clipboard.clearUnpinned();
                        root.confirm = root.confirm === "clear" ? "" : "clear";
                    } else if (event.key === Qt.Key_Delete && (search.text === "" || ctrl) && root.selected) {
                        Clipboard.remove(root.selected.id);
                    } else if (event.key === Qt.Key_PageDown) {
                        root.current = Math.min(root.results.length - 1, root.current + 6);
                    } else if (event.key === Qt.Key_PageUp) {
                        root.current = Math.max(0, root.current - 6);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            Flickable {
                width: parent.width
                height: 30
                contentWidth: chipRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: chipRow
                    spacing: 2
                    Repeater {
                        model: root.filters.filter(f => f.key === "all" || f.key === root.filter || root.countOf(f.key) > 0)
                        delegate: Chip {
                            required property var modelData
                            text: modelData.label
                            icon: modelData.icon
                            count: modelData.key === "all" ? -1 : root.countOf(modelData.key)
                            active: root.filter === modelData.key
                            onClicked: root.filter = modelData.key
                        }
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: 7 * 56
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.current
                highlightFollowsCurrentItem: true
                highlightMoveDuration: Motion.spatialFast
                highlightMoveVelocity: -1
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                model: ScriptModel {
                    values: root.results
                    objectProp: "id"
                }

                // the selection: one shape that glides between rows, with an accent mark
                highlight: Item {
                    width: list.width
                    height: 54
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        color: Theme.selected
                        border.width: Metrics.hairline
                        border.color: Theme.accentLine
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height * 0.5
                        radius: 1.5
                        color: Theme.accent
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
                        from: -12
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
                            to: 24
                            role: "exit"
                        }
                    }
                }
                displaced: Transition {
                    Anim {
                        properties: "x,y"
                        role: "spatialFast"
                    }
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current

                    width: list.width
                    height: 54

                    // rows arrive one after another when the panel opens
                    opacity: Math.min(1, Math.max(0, (root.visibleProgress - Math.min(0.5, index * 0.06)) / 0.5))
                    transform: Translate {
                        y: (1 - row.opacity) * 10
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onEntered: root.current = row.index
                        onClicked: mouse => mouse.button === Qt.MiddleButton ? root.copy(row.modelData) : root.paste(row.modelData)
                    }

                    // what it is: a colour shows itself, everything else its kind
                    Rectangle {
                        id: lead
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.s4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        radius: Metrics.radiusSm
                        color: row.modelData.kind === "colour" ? row.modelData.preview.trim() : Theme.well
                        border.width: Metrics.hairline
                        border.color: Theme.hairline
                        Icon {
                            anchors.centerIn: parent
                            visible: row.modelData.kind !== "colour"
                            name: root.glyph(row.modelData.kind)
                            size: 15
                            tone: row.selected ? "accent" : "muted"
                        }
                    }
                    Column {
                        anchors.left: lead.right
                        anchors.leftMargin: Metrics.s3
                        anchors.right: pinMark.left
                        anchors.rightMargin: Metrics.s2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Label {
                            width: parent.width
                            role: "body"
                            maximumLineCount: 1
                            font.family: row.modelData.kind === "code" ? Type.mono : Type.ui
                            text: row.modelData.image ? "Image · " + row.modelData.mime.replace("image/", "").toUpperCase() : row.modelData.preview.replace(/\s+/g, " ").trim()
                        }
                        Label {
                            width: parent.width
                            role: "caption"
                            tone: "faint"
                            text: root.ago(row.modelData.time) + "  ·  " + root.size(row.modelData.bytes)
                        }
                    }
                    Icon {
                        id: pinMark
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.pinned ? "pin-filled" : "pin"
                        size: 14
                        tone: row.modelData.pinned ? "accent" : "faint"
                        opacity: row.modelData.pinned || hover.containsMouse ? 1 : 0
                        scale: row.modelData.pinned ? 1 : 0.85
                        Glide on scale {
                            epsilon: 0.001
                        }
                        Behavior on opacity {
                            Anim {
                                role: "effects"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Clipboard.pin(row.modelData.id, !row.modelData.pinned)
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    role: "label"
                    tone: "faint"
                    text: Clipboard.error !== "" ? Clipboard.error : Clipboard.loading && Clipboard.entries.length === 0 ? "" : root.query !== "" ? "Nothing matches" : root.filter === "pinned" ? "Ctrl+P pins what you keep reaching for" : "Nothing copied yet"
                }
            }

            // housekeeping
            Row {
                spacing: Metrics.s2
                Chip {
                    icon: "trash"
                    text: root.confirm === "clear" ? "Clear unpinned — again to confirm" : "Clear unpinned"
                    active: root.confirm === "clear"
                    visible: Clipboard.entries.some(e => !e.pinned)
                    onClicked: {
                        if (root.confirm === "clear")
                            Clipboard.clearUnpinned();
                        root.confirm = root.confirm === "clear" ? "" : "clear";
                    }
                }
                Chip {
                    text: root.confirm === "clear-all" ? "Everything, pinned too — again to confirm" : "Clear all"
                    active: root.confirm === "clear-all"
                    visible: Clipboard.entries.some(e => e.pinned)
                    onClicked: {
                        if (root.confirm === "clear-all")
                            Clipboard.clearAll();
                        root.confirm = root.confirm === "clear-all" ? "" : "clear-all";
                    }
                }
            }
        }

        // ── the selected entry, whole ────────────────────────────────────────
        Rectangle {
            id: pane
            width: body.width - left.width - body.spacing
            height: left.height
            radius: Metrics.radiusLg
            color: Theme.well
            border.width: Metrics.hairline
            border.color: Theme.hairline
            clip: true

            readonly property var entry: root.selected
            readonly property var detail: Clipboard.detail?.id === entry?.id ? Clipboard.detail : null
            readonly property string kind: entry?.kind ?? ""

            // the content cross-fades and drifts a little as the selection changes
            property real swap: 1
            onEntryChanged: if (!Motion.reduced)
                swapIn.restart()
            SequentialAnimation {
                id: swapIn
                PropertyAction {
                    target: pane
                    property: "swap"
                    value: 0
                }
                Anim {
                    target: pane
                    property: "swap"
                    to: 1
                    role: "enter"
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: Metrics.s5
                anchors.bottomMargin: actions.height + Metrics.s5 * 2
                opacity: pane.swap
                transform: Translate {
                    y: (1 - pane.swap) * 8
                }

                // image
                Image {
                    anchors.fill: parent
                    visible: pane.kind === "image"
                    source: pane.kind === "image" ? (pane.detail?.image ?? "") : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 1200
                    smooth: true
                    mipmap: true
                }
                // colour
                Column {
                    anchors.centerIn: parent
                    visible: pane.kind === "colour"
                    spacing: Metrics.s4
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 140
                        height: 140
                        radius: 70
                        color: pane.kind === "colour" ? pane.entry.preview.trim() : "transparent"
                        border.width: Metrics.hairline
                        border.color: Theme.hairline
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        role: "headline"
                        numeric: true
                        text: pane.entry?.preview?.trim() ?? ""
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        role: "caption"
                        tone: "muted"
                        text: {
                            if (pane.kind !== "colour")
                                return "";
                            const c = Qt.color(pane.entry.preview.trim());
                            return "rgb " + Math.round(c.r * 255) + " " + Math.round(c.g * 255) + " " + Math.round(c.b * 255) + "  ·  hsl " + Math.round(Math.max(0, c.hslHue) * 360) + "° " + Math.round(c.hslSaturation * 100) + "% " + Math.round(c.hslLightness * 100) + "%";
                        }
                    }
                }
                // link
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: pane.kind === "link"
                    spacing: Metrics.s3
                    Icon {
                        name: "world"
                        size: 28
                        tone: "accent"
                    }
                    Label {
                        width: parent.width
                        role: "title"
                        text: {
                            const t = (pane.entry?.preview ?? "").trim();
                            const m = t.match(/^[a-z]+:\/\/([^/]+)/i);
                            return m ? m[1] : t;
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 6
                        elide: Text.ElideRight
                        color: Theme.inkMuted
                        font.family: Type.mono
                        font.pixelSize: Type.caption
                        text: pane.detail?.text ?? pane.entry?.preview ?? ""
                    }
                }
                // text and code
                Flickable {
                    anchors.fill: parent
                    visible: pane.kind === "text" || pane.kind === "code"
                    contentHeight: bodyText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: bodyText
                        width: parent.width
                        wrapMode: pane.kind === "code" ? Text.WrapAnywhere : Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.ink
                        font.family: pane.kind === "code" ? Type.mono : Type.ui
                        font.pixelSize: pane.kind === "code" ? Type.label : Type.body
                        lineHeight: 1.25
                        text: pane.detail?.text ?? pane.entry?.preview ?? ""
                    }
                }
                Label {
                    anchors.centerIn: parent
                    visible: pane.entry === null
                    role: "label"
                    tone: "faint"
                    text: "Select an entry to see it whole"
                }
                Label {
                    anchors.bottom: parent.bottom
                    visible: (pane.detail?.error ?? "") !== ""
                    role: "caption"
                    tone: "faint"
                    text: pane.detail?.error ?? ""
                }
            }

            // what can be done with it
            Item {
                id: actions
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Metrics.s4
                height: 36
                visible: pane.entry !== null

                Label {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    tone: "faint"
                    text: {
                        const e = pane.entry;
                        if (!e)
                            return "";
                        if (e.image)
                            return root.size(e.bytes) + "  ·  " + e.mime;
                        const t = pane.detail?.text ?? e.preview;
                        return t.length + " characters  ·  " + (t.split("\n").length) + " lines";
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pane.kind === "link"
                        icon: "external-link"
                        tone: "muted"
                        onClicked: {
                            const url = (pane.detail?.text ?? pane.entry.preview).trim();
                            Quickshell.execDetached(["xdg-open", /^[a-z]+:\/\//i.test(url) ? url : "https://" + url]);
                            PanelRouter.close(root.screen.name);
                        }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: pane.entry?.pinned ? "pin-filled" : "pin"
                        active: pane.entry?.pinned ?? false
                        tone: "muted"
                        onClicked: Clipboard.pin(pane.entry.id, !pane.entry.pinned)
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "trash"
                        tone: "muted"
                        onClicked: Clipboard.remove(pane.entry.id)
                    }
                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "copy"
                        text: "Copy"
                        onClicked: root.copy(pane.entry)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: pasteRow.implicitWidth + Metrics.s5 * 2
                        height: 32
                        radius: 16
                        color: Theme.accent
                        opacity: pasteArea.pressed ? 0.85 : 1
                        Row {
                            id: pasteRow
                            anchors.centerIn: parent
                            spacing: Metrics.s2
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "corner-down-left"
                                size: 14
                                color: Theme.onAccent
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "label"
                                font.weight: Font.Medium
                                color: Theme.onAccent
                                text: "Paste"
                            }
                        }
                        MouseArea {
                            id: pasteArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.paste(pane.entry)
                        }
                    }
                }
            }
        }
    }
}
