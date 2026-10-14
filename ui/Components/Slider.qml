import QtQuick
import qs.Common

// A thin track that thickens under the pointer. `value` is 0..1.
//   moved(v)      while it is being dragged (a preview: cheap to follow, not yet the setting)
//   committed(v)  when the user lets go, clicks, or steps it with the keyboard: the value to keep
//   canceled()    a drag that ended without a release (the grab was taken away): drop the preview
// It changes only when pressed on, or stepped with the keys while focused; the wheel is the page's unless
// wheelAdjusts is set (scrolling a
// page past a slider used to nudge it by 5 % a notch, and the page could not scroll there), hovering does nothing,
// and a press holds the pointer until it is released, so a page underneath cannot steal the drag.
Item {
    id: root

    property real value: 0
    property real displayed: value
    // one keyboard step, as a share of the track (SchemaForm passes the setting's own step)
    property real step: 0.01
    // the wheel steps it (5 steps a notch); off by default, so scrolling a page over a slider never changes it
    property bool wheelAdjusts: false
    signal moved(real value)
    signal committed(real value)
    signal canceled

    implicitHeight: 22
    implicitWidth: 200
    activeFocusOnTab: true

    Behavior on displayed {
        enabled: !area.pressed && !root.holding
        NumberAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }

    // After a release the track keeps showing what was chosen until `value` catches up (the setting comes back
    // through the config file a moment later), instead of springing back to the old value for a frame.
    property bool holding: false
    property real held: 0
    function hold(v: real): void {
        held = v;
        holding = true;
        displayed = v;
        letGo.restart();
    }
    function follow(): void {
        holding = false;
        displayed = Qt.binding(() => root.value);
    }
    onValueChanged: if (holding && Math.abs(value - held) < 0.0005)
        follow()
    Timer {
        id: letGo
        interval: 1500
        onTriggered: root.follow()
    }

    readonly property bool lit: area.containsMouse || area.pressed || root.activeFocus
    readonly property real track: lit ? 6 : 4

    Rectangle {
        id: groove

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.track
        radius: height / 2
        color: Theme.rule

        Behavior on height {
            NumberAnimation {
                duration: Motion.focus
            }
        }

        Rectangle {
            width: Math.max(height, parent.width * Math.min(1, root.displayed))
            height: parent.height
            radius: height / 2
            // the level in ink at rest; the accent only while it is being touched (the one live thing)
            color: root.lit ? Theme.accent : Theme.alpha(Theme.ink, 0.78)
            Behavior on color {
                ColorAnim {}
            }
        }
    }

    Rectangle {
        x: Math.min(1, root.displayed) * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: root.lit ? 14 : 0
        height: width
        radius: width / 2
        color: Theme.ink
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.accent

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
        // a drag that has started stays this slider's until release (a Flickable would otherwise take it over
        // as soon as the pointer drifts vertically)
        preventStealing: true
        property real last: 0
        function at(mx: real): real {
            return Math.max(0, Math.min(1, mx / width));
        }
        onPressed: mouse => {
            root.forceActiveFocus();
            root.letGoTimerStop();
            last = at(mouse.x);
            root.displayed = last;
            root.moved(last);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const v = at(mouse.x);
            if (v === last)
                return;
            last = v;
            root.displayed = v;
            root.moved(v);
        }
        onReleased: mouse => {
            root.hold(last);
            root.committed(last);
        }
        onCanceled: {
            root.follow();
            root.canceled();
        }
        // The wheel belongs to the page unless this slider asks for it (wheelAdjusts: a level in a panel that does
        // not scroll); not accepting it lets it go on to the Flickable underneath.
        onWheel: wheel => {
            if (!root.wheelAdjusts) {
                wheel.accepted = false;
                return;
            }
            root.stepBy(wheel.angleDelta.y > 0 ? 5 : -5);
        }
    }
    function letGoTimerStop(): void {
        letGo.stop();
        holding = false;
    }

    function stepBy(n: int): void {
        const v = Math.max(0, Math.min(1, (holding ? held : value) + n * step));
        hold(v);
        root.moved(v);
        root.committed(v);
    }
    // left / right step it, Home / End go to the ends; up, down and the page keys stay the page's (scrolling)
    Keys.onLeftPressed: stepBy(-1)
    Keys.onRightPressed: stepBy(1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            const v = event.key === Qt.Key_Home ? 0 : 1;
            hold(v);
            root.moved(v);
            root.committed(v);
            event.accepted = true;
        }
    }
}
