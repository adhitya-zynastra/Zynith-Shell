import QtQuick
import qs.Common

// The keyboard's focus as a camera's autofocus point: four corner ticks just outside `target`, gliding to the
// next target. Shown while the keyboard is in use (`shown`); `armed` closes them in, in the error colour,
// for a destructive action waiting for its second press.
Item {
    id: root
    property Item target: null
    property bool shown: true
    property bool armed: false
    readonly property real gap: armed ? 1 : 3
    readonly property real tick: 6
    readonly property color ink: armed ? Theme.danger : Theme.accent

    readonly property point at: target ? target.mapToItem(parent, 0, 0) : Qt.point(0, 0)
    x: at.x - gap
    y: at.y - gap
    width: (target?.width ?? 0) + gap * 2
    height: (target?.height ?? 0) + gap * 2
    visible: target !== null && opacity > 0.01
    opacity: shown && target ? 1 : 0
    Behavior on opacity {
        Anim {
            role: "effects"
        }
    }
    Glide on x {}
    Glide on y {}
    Glide on width {}
    Glide on height {}

    Repeater {
        model: [[0, 0, 1, 1], [1, 0, -1, 1], [1, 1, -1, -1], [0, 1, 1, -1]]
        delegate: Item {
            required property var modelData
            x: modelData[0] * root.width
            y: modelData[1] * root.height
            Rectangle {
                x: modelData[2] > 0 ? 0 : -root.tick
                y: -1
                width: root.tick
                height: 2
                color: root.ink
            }
            Rectangle {
                x: -1
                y: modelData[3] > 0 ? 0 : -root.tick
                width: 2
                height: root.tick
                color: root.ink
            }
        }
    }
}
