import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Recent clipboard entries; Enter or a click puts one back on the clipboard. Typing filters.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    readonly property int preferredWidth: 520
    readonly property int rows: 7

    property string query: ""
    property int current: 0
    property bool confirmClear: false
    readonly property var results: {
        const q = query.trim().toLowerCase();
        const all = Clipboard.entries;
        return (q === "" ? all : all.filter(e => e.preview.toLowerCase().includes(q))).slice(0, 40);
    }
    onQueryChanged: current = 0
    onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))

    onActiveChanged: if (active)
        reset()
    Component.onCompleted: reset()
    function reset(): void {
        field.text = "";
        current = 0;
        confirmClear = false;
        Clipboard.refresh();
        field.forceActiveFocus();
    }

    function pick(i: int): void {
        const e = results[i];
        if (!e)
            return;
        Clipboard.select(e.id);
        PanelRouter.close(screen.name);
    }

    function ago(ms: real): string {
        const s = Math.max(0, (Date.now() - ms) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + " min";
        if (s < 86400)
            return Math.floor(s / 3600) + " h";
        return Math.floor(s / 86400) + " d";
    }
    function size(bytes: real): string {
        return bytes < 1024 ? bytes + " B" : bytes < 1048576 ? (bytes / 1024).toFixed(0) + " KB" : (bytes / 1048576).toFixed(1) + " MB";
    }

    padding: Metrics.s4
    spacing: Metrics.s3
    readonly property real inner: width - padding * 2

    Item {
        width: root.inner
        height: 40

        Icon {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: "clipboard"
            size: 18
            tone: "muted"
        }
        TextInput {
            id: field
            anchors.left: glyph.right
            anchors.leftMargin: Metrics.s4
            anchors.right: clear.left
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.ink
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.ink
            font.family: Type.ui
            font.pixelSize: Type.title
            clip: true
            onTextChanged: root.query = text

            Keys.onEscapePressed: PanelRouter.close(root.screen.name)
            Keys.onReturnPressed: root.pick(root.current)
            Keys.onEnterPressed: root.pick(root.current)
            Keys.onUpPressed: root.current = Math.max(0, root.current - 1)
            Keys.onDownPressed: root.current = Math.min(root.results.length - 1, root.current + 1)
            Keys.onTabPressed: root.current = (root.current + 1) % Math.max(1, root.results.length)
            Keys.onDeletePressed: event => {
                if (field.text === "" && root.results[root.current]) {
                    Clipboard.remove(root.results[root.current].id);
                } else {
                    event.accepted = false;
                }
            }

            Label {
                visible: field.text === ""
                anchors.verticalCenter: parent.verticalCenter
                role: "title"
                tone: "faint"
                text: "Clipboard"
            }
        }
        Label {
            id: clear
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            role: "caption"
            caps: true
            tone: root.confirmClear ? "accent" : "faint"
            text: root.confirmClear ? "Clear unpinned?" : "Clear"
            visible: Clipboard.entries.length > 0

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Metrics.s2
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.confirmClear)
                        Clipboard.clearUnpinned();
                    root.confirmClear = !root.confirmClear;
                }
            }
        }
    }

    Rectangle {
        width: root.inner
        height: Metrics.hairline
        color: Theme.hairline
    }

    ListView {
        id: list
        width: root.inner
        height: Math.min(contentHeight, root.rows * 52)
        clip: true
        spacing: Metrics.s1
        model: ScriptModel {
            values: root.results
            objectProp: "id"
        }
        currentIndex: root.current
        highlightFollowsCurrentItem: false
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: index === root.current

            width: list.width
            height: 48

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusMd
                color: row.selected ? Theme.accentSoft : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Motion.focus
                        easing.type: Motion.standardEasing
                    }
                }
            }
            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.current = row.index
                onClicked: root.pick(row.index)
            }

            Icon {
                id: kind
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s3
                anchors.verticalCenter: parent.verticalCenter
                name: row.modelData.image ? "photo" : "clipboard-list"
                tone: row.selected ? "accent" : "faint"
            }
            Column {
                anchors.left: kind.right
                anchors.leftMargin: Metrics.s4
                anchors.right: remove.left
                anchors.rightMargin: Metrics.s2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Label {
                    width: parent.width
                    role: "body"
                    maximumLineCount: 1
                    text: row.modelData.image ? "Image" : row.modelData.preview.replace(/\s+/g, " ").trim()
                }
                Label {
                    width: parent.width
                    role: "caption"
                    tone: "faint"
                    text: root.ago(row.modelData.time) + "  ·  " + root.size(row.modelData.bytes) + (row.modelData.image ? "  ·  " + row.modelData.mime.replace("image/", "").toUpperCase() : "") + (row.modelData.pinned ? "  ·  pinned" : "")
                }
            }
            IconButton {
                id: remove
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s1
                anchors.verticalCenter: parent.verticalCenter
                size: 26
                iconSize: 13
                icon: "x"
                tone: "faint"
                opacity: hover.containsMouse || row.selected ? 1 : 0
                onClicked: Clipboard.remove(row.modelData.id)
            }
        }
    }

    Label {
        visible: root.results.length === 0
        width: root.inner
        height: 48
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        role: "label"
        tone: "faint"
        text: Clipboard.error !== "" ? Clipboard.error : Clipboard.loading ? "" : root.query !== "" ? "Nothing matches" : "Nothing copied yet"
    }
}
