import QtQuick
import qs.Common

// A labelled hairline gauge for system readouts.
Column {
    id: root

    property string label: ""
    property real value: 0
    property string readout: Math.round(value * 100) + "%"

    spacing: Metrics.s2

    Item {
        width: parent.width
        height: 16

        Label {
            anchors.left: parent.left
            role: "data"
            tone: "faint"
            text: root.label
        }
        Label {
            anchors.right: parent.right
            role: "label"
            numeric: true
            tone: "muted"
            text: root.readout
        }
    }

    Rectangle {
        width: parent.width
        height: 3
        radius: 1.5
        color: Theme.rule

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: parent.radius
            color: root.value > 0.85 ? Theme.danger : Theme.alpha(Theme.ink, 0.78)

            Behavior on width {
                NumberAnimation {
                    duration: Motion.morph
                    easing.type: Motion.standardEasing
                }
            }
        }
    }
}
