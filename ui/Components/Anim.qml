import QtQuick
import qs.Common

// A NumberAnimation in one of the motion roles: spatial | spatialFast | spatialSlow | effects | enter | exit.
// Spatial roles carry the style's spatial curve (expressive overshoot when fluid); effects ease out.
NumberAnimation {
    property string role: "spatial"
    duration: Motion[role] ?? Motion.spatial
    easing.type: Easing.BezierSpline
    easing.bezierCurve: ({
            spatial: Motion.spatialCurve,
            spatialFast: Motion.spatialFastCurve,
            spatialSlow: Motion.spatialSlowCurve,
            effects: Motion.effectsCurve,
            enter: Motion.enterCurve,
            exit: Motion.exitCurve
        })[role] ?? Motion.spatialCurve
}
