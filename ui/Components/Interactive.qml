import QtQuick
import qs.Common
import qs.Services

// Hover/press feedback shared by every clickable thing: a soft state layer, never a colour flip.
MouseArea {
    id: root

    property real radius: Metrics.radiusMd
    property bool active: false

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? Theme.press : root.active ? Theme.accentSoft : root.containsMouse ? Theme.hover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
    }
}
