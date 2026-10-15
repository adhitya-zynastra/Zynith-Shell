import QtQuick

// A sideways two-finger swipe (or a tilt wheel) over whatever it covers: `stepped(+1)` for a swipe to the left
// (the next page), `stepped(-1)` to the right. The travel adds up until it is clearly a swipe, then it steps once
// and waits for the fingers to rest before it can step again. It sits over the content and never takes the event:
// the slider or list under the pointer still gets the same wheel, and a mostly vertical gesture is left alone.
Item {
    id: root

    property real threshold: 90
    // how long the wheel must be still before another swipe can step
    property int rest: 220
    signal stepped(int by)

    property real travel: 0
    property bool spent: false

    z: 100

    WheelHandler {
        enabled: root.enabled
        blocking: false
        // only events with a sideways part reach it (a WheelHandler ignores those without travel on its axis)
        orientation: Qt.Horizontal
        onWheel: event => {
            const dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 2;
            const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2;
            if (Math.abs(dx) <= Math.abs(dy))
                return;
            settle.restart();
            if (root.spent)
                return;
            root.travel += dx;
            if (Math.abs(root.travel) >= root.threshold) {
                root.spent = true;
                const by = root.travel < 0 ? 1 : -1;
                root.travel = 0;
                root.stepped(by);
            }
        }
    }
    Timer {
        id: settle
        interval: root.rest
        onTriggered: {
            root.travel = 0;
            root.spent = false;
        }
    }
}
