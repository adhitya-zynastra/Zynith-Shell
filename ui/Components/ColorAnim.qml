import QtQuick
import qs.Common

// A ColorAnimation on the effects curve (or another motion role).
ColorAnimation {
    property string role: "effects"
    duration: Motion[role] ?? Motion.effects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: role === "effects" ? Motion.effectsCurve : role === "enter" ? Motion.enterCurve : Motion.spatialCurve
}
