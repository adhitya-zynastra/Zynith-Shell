import QtQuick
import qs.Common

// The accent as light: the edge of the one current thing glows faintly, and its face takes a breath of the
// accent. Put it behind (or fill it into) a control that is on or selected; `on` fades it in and out.
Item {
    id: root
    property bool on: true
    property real radius: Metrics.radiusControl
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity {
        Anim {
            role: "effects"
        }
    }
    // the glow: a wider, fainter edge just outside
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: root.radius + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.signalGlow
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.signalFill
        border.width: 1
        border.color: Theme.signalEdge
    }
}
