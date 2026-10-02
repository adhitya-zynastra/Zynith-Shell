import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The launcher. Type to find; a leading = > @ : ! switches to calculator, windows, wallpapers, emoji or
// session. Enter runs the highlighted result, Tab and the arrows move, Escape leaves.
Column {
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
    readonly property int preferredWidth: options.width ?? 600
    readonly property real preferredTop: options.position === "top" ? 0.1 : 0.22
    readonly property bool compact: options.density === "compact"
    readonly property int rows: options.rows ?? 8
    readonly property int rowHeight: compact ? 40 : 52

    property string text: ""
    property int current: 0
    property string armed: ""
    readonly property var mode: Launcher.modeOf(text)
    readonly property var results: active ? Launcher.search(text, rows) : []
    onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))
    onTextChanged: {
        current = 0;
        armed = "";
    }

    onActiveChanged: if (active)
        reset()
    Component.onCompleted: reset()
    function reset(): void {
        field.text = context;
        field.cursorPosition = context.length;
        current = 0;
        armed = "";
        field.forceActiveFocus();
    }

    function open(i: int): void {
        const r = results[i];
        if (!r)
            return;
        if (r.confirm && armed !== r.key) {
            armed = r.key;
            return;
        }
        r.run();
        PanelRouter.close(screen.name);
    }

    padding: Metrics.s4
    spacing: 0
    readonly property real inner: width - padding * 2

    // ── the search line ─────────────────────────────────────────────────────
    Item {
        width: root.inner
        height: 52

        Rectangle {
            id: chip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: 28
            width: root.mode.prefix ? chipRow.implicitWidth + Metrics.s4 * 2 : 28
            radius: 14
            color: root.mode.prefix ? Theme.accentSoft : "transparent"

            Behavior on width {
                NumberAnimation {
                    duration: Motion.morph
                    easing.type: Motion.enterEasing
                }
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
                    role: "caption"
                    caps: true
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
            // the mode character stays visible in the chip, not the field
            onTextChanged: root.text = text

            Keys.onEscapePressed: PanelRouter.close(root.screen.name)
            Keys.onReturnPressed: root.open(root.current)
            Keys.onEnterPressed: root.open(root.current)
            Keys.onUpPressed: root.current = Math.max(0, root.current - 1)
            Keys.onDownPressed: root.current = Math.min(root.results.length - 1, root.current + 1)
            Keys.onTabPressed: root.current = (root.current + 1) % Math.max(1, root.results.length)
            Keys.onBacktabPressed: root.current = (root.current - 1 + root.results.length) % Math.max(1, root.results.length)

            Label {
                visible: field.text === ""
                anchors.verticalCenter: parent.verticalCenter
                role: "headline"
                font.weight: Font.Light
                tone: "faint"
                text: "Search"
            }
        }
    }

    // an accent line that fades into the hairline: the launcher's one flourish
    Rectangle {
        width: root.inner
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

    Item {
        width: root.inner
        height: Metrics.s3
    }

    // ── results ─────────────────────────────────────────────────────────────
    Column {
        width: root.inner
        spacing: 2

        Repeater {
            model: ScriptModel {
                values: root.results
                objectProp: "key"
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === root.current
                readonly property bool armed: root.armed === modelData.key

                width: root.inner
                height: root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusMd
                    color: row.armed ? Theme.alpha(Theme.danger, 0.16) : row.selected ? Theme.selected : hover.containsMouse ? Theme.hover : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.focus
                            easing.type: Motion.standardEasing
                        }
                    }
                }
                // the selection mark
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: row.selected ? parent.height * 0.5 : 0
                    radius: 1.5
                    color: row.armed ? Theme.danger : Theme.accent

                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.focus
                            easing.type: Motion.enterEasing
                        }
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = row.index
                    onClicked: root.open(row.index)
                }

                Item {
                    id: lead
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s4
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.compact ? 22 : 30
                    height: width

                    readonly property string iconSource: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                    Image {
                        anchors.fill: parent
                        visible: source != ""
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
                    Icon {
                        anchors.centerIn: parent
                        visible: !row.modelData.emoji && !row.modelData.image && lead.iconSource === ""
                        name: row.modelData.glyph ?? "apps"
                        size: root.compact ? 16 : 20
                        tone: row.selected ? "accent" : "muted"
                    }
                }

                Column {
                    anchors.left: lead.right
                    anchors.leftMargin: Metrics.s4
                    anchors.right: hint.left
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        role: row.modelData.kind === "calc" ? "title" : "body"
                        numeric: row.modelData.kind === "calc"
                        font.weight: row.selected ? Font.Medium : Font.Normal
                        text: row.modelData.title
                    }
                    Label {
                        width: parent.width
                        visible: text !== "" && !root.compact
                        role: "caption"
                        tone: "faint"
                        text: row.armed ? "Press Enter again to confirm" : row.modelData.subtitle
                    }
                }
                Icon {
                    id: hint
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    name: "corner-down-left"
                    size: 13
                    tone: "faint"
                    opacity: row.selected ? 1 : 0
                }
            }
        }

        Label {
            visible: root.results.length === 0
            width: root.inner
            height: root.rowHeight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            role: "label"
            tone: "faint"
            text: root.mode.id === "calc" ? "Type an expression" : root.mode.id === "emoji" && Launcher.emojiTable.length === 0 ? "" : "Nothing matches"
        }
    }

    // ── the modes, as a quiet legend ────────────────────────────────────────
    Item {
        width: root.inner
        height: 36

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Metrics.s5

            Repeater {
                model: Launcher.modes.filter(m => m.prefix !== "")
                delegate: Row {
                    required property var modelData
                    spacing: Metrics.s1
                    Label {
                        role: "caption"
                        numeric: true
                        tone: root.mode.id === modelData.id ? "accent" : "muted"
                        text: modelData.prefix
                    }
                    Label {
                        role: "caption"
                        tone: root.mode.id === modelData.id ? "accent" : "faint"
                        text: modelData.label.toLowerCase()
                    }
                }
            }
        }
    }
}
