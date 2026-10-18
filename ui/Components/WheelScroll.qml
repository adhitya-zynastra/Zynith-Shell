import QtQuick
import qs.Common

// Scrolling a Flickable with a wheel or a touchpad, as a desktop page should: put it inside the Flickable.
// Measured in Settings (2026-10-18) with real wheel ticks and touchpad pans:
//   · Qt's own wheel handling moved ~55 px a notch — 110 notches to cross the 6182 px Bars page;
//   · touchpad scrolls whose events carry no "began" phase (what Qt received from a pan) moved the page 0 px.
// Here a touchpad moves the content with the fingers (any phase) and keeps the lift-off speed; a notch steps
// `step` px, eased, and rapid notches add up. Reduced motion jumps. Controls under the pointer that take the
// wheel themselves (a slider) still get it first.
WheelHandler {
    id: root

    required property Flickable flick
    // one notch, as a share of the visible height (at least 80 px)
    property real step: Math.max(80, flick.height * 0.3)

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    readonly property real most: Math.max(0, flick.contentHeight - flick.height)
    function clamp(y: real): real {
        return Math.max(0, Math.min(most, y));
    }

    // where a stepped scroll is heading (rapid notches add to it rather than restart from where the page is)
    property real target: 0
    readonly property NumberAnimation glide: NumberAnimation {
        target: root.flick
        property: "contentY"
        duration: 160
        easing.type: Easing.OutCubic
    }
    // the fingers' last few moves, for the speed they leave with
    property var trail: []

    onWheel: event => {
        const now = Date.now();
        // fingers carry pixel deltas; a wheel only angle (Qt on Wayland reports both as the same device type)
        if (event.pixelDelta.y !== 0) {
            root.glide.stop();
            root.flick.cancelFlick();
            const dy = event.pixelDelta.y;
            root.flick.contentY = root.clamp(root.flick.contentY - dy);
            root.trail = root.trail.filter(t => now - t[0] < 80).concat([[now, dy]]);
        } else if (event.phase === Qt.ScrollEnd) {
            // lifted: carry on at the speed the fingers had (px/s), as a flick
            const recent = root.trail.filter(t => now - t[0] < 80);
            root.trail = [];
            if (recent.length >= 2 && !Motion.reduced) {
                const span = Math.max(16, now - recent[0][0]);
                const v = recent.reduce((s, t) => s + t[1], 0) / span * 1000;
                if (Math.abs(v) > 200)
                    root.flick.flick(0, v);
            }
        } else if (event.angleDelta.y !== 0) {
            root.flick.cancelFlick();
            const from = root.glide.running ? root.target : root.flick.contentY;
            root.target = root.clamp(from - event.angleDelta.y / 120 * root.step);
            if (Motion.reduced) {
                root.glide.stop();
                root.flick.contentY = root.target;
            } else {
                root.glide.stop();
                root.glide.to = root.target;
                root.glide.start();
            }
        }
        event.accepted = true;
    }
}
