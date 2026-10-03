import QtQuick
import qs.Common

// A small switch with a sliding knob.
Item {
    id: root

    property bool checked: false
    signal toggled

    implicitWidth: 36
    implicitHeight: 20

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        // on: an edge-lit track and an accent knob (light, not a painted pill)
        color: root.checked ? Theme.signalFill : Theme.plate
        border.width: Metrics.hairline
        border.color: root.checked ? Theme.signalEdge : Theme.rule

        Behavior on color {
            ColorAnimation {
                duration: Motion.focus
            }
        }
    }

    Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.accent : Theme.inkFaint
        Behavior on color {
            ColorAnim {}
        }

        Glide on x {}
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
