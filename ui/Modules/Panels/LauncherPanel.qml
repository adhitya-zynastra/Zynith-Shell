import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Type to find an app, Enter opens the highlighted one. With an empty field, the apps used most lately.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    readonly property int preferredWidth: 560
    readonly property int rows: 8

    property string query: ""
    property int current: 0
    readonly property var results: active ? Apps.search(query, rows) : []
    onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))
    onQueryChanged: current = 0

    // a fresh field on every opening, warm or not
    onActiveChanged: if (active)
        reset()
    Component.onCompleted: reset()
    function reset(): void {
        field.text = "";
        current = 0;
        field.forceActiveFocus();
    }

    function open(i: int): void {
        const entry = results[i];
        if (!entry)
            return;
        Apps.launch(entry);
        PanelRouter.close(screen.name);
    }

    padding: Metrics.s4
    spacing: Metrics.s3
    readonly property real inner: width - padding * 2

    Item {
        width: root.inner
        height: 44

        Icon {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 18
            tone: "muted"
        }
        TextInput {
            id: field
            anchors.left: glass.right
            anchors.leftMargin: Metrics.s4
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.ink
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.ink
            font.family: Type.ui
            font.pixelSize: Type.headline
            clip: true
            onTextChanged: root.query = text

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
                tone: "faint"
                text: "Search apps"
            }
        }
    }

    Rectangle {
        width: root.inner
        height: Metrics.hairline
        color: Theme.hairline
    }

    Column {
        width: root.inner
        spacing: Metrics.s1

        Repeater {
            model: root.results

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === root.current

                width: root.inner
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
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = row.index
                    onClicked: root.open(row.index)
                }

                Image {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    sourceSize.width: 56
                    sourceSize.height: 56
                    asynchronous: true
                    source: Quickshell.iconPath(row.modelData.icon, true)
                }
                Icon {
                    anchors.centerIn: appIcon
                    visible: appIcon.source == "" || appIcon.status === Image.Error
                    name: "apps"
                    size: 20
                    tone: "muted"
                }
                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: Metrics.s4
                    anchors.right: hint.left
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        role: "body"
                        font.weight: row.selected ? Font.Medium : Font.Normal
                        text: row.modelData.name
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        role: "caption"
                        tone: "faint"
                        text: row.modelData.genericName || row.modelData.comment
                    }
                }
                Icon {
                    id: hint
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    name: "corner-down-left"
                    size: 14
                    tone: "faint"
                    opacity: row.selected ? 1 : 0
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
            text: "No app matches “" + root.query + "”"
        }
    }
}
