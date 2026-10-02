import QtQuick
import qs.Common

// A thin track that thickens under the pointer. `value` is 0..1; `moved` reports user changes only.
Item {
    id: root

    property real value: 0
    property real displayed: value
    signal moved(real value)

    implicitHeight: 22
    implicitWidth: 200

    Behavior on displayed {
        enabled: !area.pressed
        NumberAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }

    readonly property real track: area.containsMouse || area.pressed ? 6 : 4

    Rectangle {
        id: groove

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.track
        radius: height / 2
        color: Theme.hover

        Behavior on height {
            NumberAnimation {
                duration: Motion.focus
            }
        }

        Rectangle {
            width: Math.max(height, parent.width * Math.min(1, root.displayed))
            height: parent.height
            radius: height / 2
            color: Theme.accent
        }
    }

    Rectangle {
        x: Math.min(1, root.displayed) * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: area.containsMouse || area.pressed ? 14 : 0
        height: width
        radius: width / 2
        color: Theme.ink

        Behavior on width {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.enterEasing
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function update(mx: real): void {
            const v = Math.max(0, Math.min(1, mx / width));
            root.displayed = v;
            root.moved(v);
        }
        onPressed: mouse => update(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                update(mouse.x);
        }
        onReleased: root.displayed = Qt.binding(() => root.value)
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
