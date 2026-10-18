import QtQuick
import QtQuick.Shapes

// A concave fillet: an r×r square whose `solid` corner (tl tr br bl) is filled and the rest cut by a quarter
// circle, so a surface flows into the edge it meets.
//
// The path is built once, at a fixed size, and scaled to r: a fillet whose radius animates (a panel's join growing,
// a corner being dragged) re-triangulated its curve every frame when the path itself followed r — measured as
// ~60 ms stalls halfway through a panel's entrance, when its joins appear.
Item {
    id: root
    property real r: 16
    property color fill: "black"
    property string solid: "tl"
    width: r
    height: r

    Shape {
        readonly property real unit: 64
        width: unit
        height: unit
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation {
                origin.x: 32
                origin.y: 32
                angle: ({ tl: 0, tr: 90, br: 180, bl: 270 })[root.solid] ?? 0
            },
            Scale {
                xScale: root.r / 64
                yScale: root.r / 64
            }
        ]
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.fill
            startX: 0
            startY: 0
            PathLine { x: 64; y: 0 }
            PathArc {
                x: 0
                y: 64
                radiusX: 64
                radiusY: 64
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 0; y: 0 }
        }
    }
}
