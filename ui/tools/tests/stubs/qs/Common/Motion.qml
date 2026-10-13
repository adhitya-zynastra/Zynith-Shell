pragma Singleton
import QtQuick
// test stand-in for Common/Motion: everything instant
QtObject {
    readonly property int focus: 0
    readonly property int spatial: 0
    readonly property int effects: 0
    readonly property int standardEasing: Easing.Linear
    readonly property var spatialCurve: [0.2, 0, 0, 1, 1, 1]
    readonly property var spatialFastCurve: spatialCurve
    readonly property var spatialSlowCurve: spatialCurve
    readonly property var effectsCurve: spatialCurve
    readonly property var enterCurve: spatialCurve
    readonly property var exitCurve: spatialCurve
}
