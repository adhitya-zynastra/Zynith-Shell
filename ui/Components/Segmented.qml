import QtQuick
import qs.Common

// A row of choices with one sliding selection mark.
Item {
    id: root

    property var options: []          // [{ key, label }]
    property string current: ""
    signal picked(string key)

    readonly property int index: Math.max(0, options.findIndex(o => o.key === current))
    readonly property real cell: options.length > 0 ? width / options.length : width

    implicitHeight: 34
    implicitWidth: 320

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusMd
        color: Theme.hover
    }

    Rectangle {
        visible: root.options.some(o => o.key === root.current)
        x: root.index * root.cell + 3
        y: 3
        width: root.cell - 6
        height: parent.height - 6
        radius: Metrics.radiusMd - 3
        color: Theme.glassRaised
        border.width: Metrics.hairline
        border.color: Theme.accentLine

        Behavior on x {
            enabled: Motion.springs
            SpringAnimation {
                spring: Motion.spring
                damping: Motion.damping
                epsilon: Motion.springEpsilon
            }
        }
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: root.options

            delegate: MouseArea {
                required property var modelData
                required property int index

                width: root.cell
                height: root.height
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(modelData.key)

                Label {
                    anchors.centerIn: parent
                    role: "label"
                    text: parent.modelData.label
                    tone: parent.modelData.key === root.current ? "ink" : "muted"
                    font.weight: parent.modelData.key === root.current ? Font.Medium : Font.Normal
                }
            }
        }
    }
}
