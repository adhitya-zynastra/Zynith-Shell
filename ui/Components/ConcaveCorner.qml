import QtQuick
import QtQuick.Shapes

// A concave fillet: an r×r square whose `solid` corner (tl tr br bl) is filled and the rest cut by a quarter
// circle, so a surface flows into the edge it meets.
Shape {
    id: root
    property real r: 16
    property color fill: "black"
    property string solid: "tl"
    width: r
    height: r
    preferredRendererType: Shape.CurveRenderer
    rotation: ({ tl: 0, tr: 90, br: 180, bl: 270 })[solid] ?? 0
    ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.fill
        startX: 0
        startY: 0
        PathLine { x: root.r; y: 0 }
        PathArc {
            x: 0
            y: root.r
            radiusX: root.r
            radiusY: root.r
            direction: PathArc.Counterclockwise
        }
        PathLine { x: 0; y: 0 }
    }
}
