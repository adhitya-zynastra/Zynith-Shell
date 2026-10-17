import QtQuick
import qs.Common
import qs.Services

// How a surface's material behaves while it moves, shared by every surface that moves (panels, popups, the OSD):
// the compositor's backdrop (blur, or Glass's wallpaper) only while it rests, and in motion a denser fill instead.
//
// Why: a backdrop region is sent to the compositor out of step with the picture it belongs to, by a frame or more,
// and a moving surface's edge travels up to ~45 px a frame. A region that follows the surface therefore shows past
// it (a pale rim) or short of it (a dark band), and a region that stays put leaves a frosted patch where the surface
// was. Neither can be timed away from QML. So: in motion, no backdrop and a fill dense enough that what is really
// behind does not show through sharp (Material.motionAlpha); at rest, the backdrop at once, and the fill thins to the
// material's own over a beat — the frost settles. Leaving, the surface condenses first (the fill thickens with the
// backdrop still on), then lets the backdrop go and moves.
//
//   moving      the surface's geometry or opacity is changing (the caller says)
//   settled     → the backdrop may be on
//   alpha(a)    → the fill alpha for a surface whose resting alpha is a
//   condense(f) → thicken, then call f (at once when there is nothing to condense)
Item {
    id: root
    visible: false

    property bool moving: false
    // nothing to settle without a backdrop: Solid, or blur paused or unavailable
    readonly property bool backdrop: Material.blur
    readonly property bool settled: !moving
    // 0: the material's own fill (at rest), 1: the motion fill
    property real frost: 0
    property bool condensing: false

    function alpha(rest: real): real {
        if (!backdrop)
            return rest;
        const dense = Math.max(rest, Material.motionAlpha);
        return rest + (dense - rest) * frost;
    }

    onMovingChanged: {
        if (moving) {
            // at once: the backdrop is already gone, so the fill must already be dense
            thin.stop();
            thicken.stop();
            condensing = false;
            frost = 1;
        } else if (!condensing) {
            settle();
        }
    }
    function settle(): void {
        thicken.stop();
        if (!backdrop || Motion.reduced) {
            frost = 0;
            return;
        }
        thin.restart();
    }
    property var after: null
    function condense(then: var): void {
        if (!backdrop || Motion.reduced || frost >= 1) {
            frost = backdrop ? 1 : 0;
            // never from inside the caller's own change handler: a leave that finished there at once (reduced
            // motion) set `closing` again while its change was still being handled — a binding loop
            Qt.callLater(then);
            return;
        }
        thin.stop();
        after = then;
        condensing = true;
        thicken.restart();
    }
    // a condense taken back (the surface asked for again before it left)
    function cancel(): void {
        if (!condensing)
            return;
        thicken.stop();
        condensing = false;
        after = null;
        settle();
    }
    Component.onCompleted: frost = moving ? 1 : 0

    NumberAnimation {
        id: thin
        target: root
        property: "frost"
        to: 0
        duration: Motion.effects * 1.5
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: thicken
        target: root
        property: "frost"
        to: 1
        // short: it delays the leaving it precedes
        duration: Math.max(1, Math.round(Motion.effects * 0.45))
        easing.type: Easing.OutQuad
        onFinished: {
            root.condensing = false;
            const f = root.after;
            root.after = null;
            if (f)
                f();
        }
    }
}
