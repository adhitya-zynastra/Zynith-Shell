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
        color: root.checked ? Theme.accent : Theme.hover
        border.width: Metrics.hairline
        border.color: root.checked ? "transparent" : Theme.hairline

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
        color: root.checked ? Theme.onAccent : Theme.inkMuted

        Behavior on x {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.enterEasing
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
