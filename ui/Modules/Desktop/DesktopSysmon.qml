import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Components
import qs.Services

// One or two system stats: a graph of the last minute, or a gauge. Samples only while it is on screen.
Item {
    id: root
    property var settings: ({})
    function opt(key: string): var {
        return WidgetTypes.value("sysmon", settings, key);
    }
    readonly property string stat: opt("stat")
    readonly property string stat2: opt("stat2") ?? ""
    readonly property var a: System.read(stat)
    readonly property var b: stat2 !== "" ? System.read(stat2) : null
    readonly property color c1: Theme.colour(opt("color"))
    readonly property color c2: Theme.colour(opt("color_2"))
    readonly property bool gauge: opt("display") === "gauge"
    readonly property bool labelled: opt("show_label") !== false

    implicitWidth: 300
    implicitHeight: 140
    Component.onCompleted: System.retain()
    Component.onDestruction: System.release()

    // ── graph: the last minute as filled lines ──
    component Line: Shape {
        id: line
        property var values: []
        property color colour: "white"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property var points: {
            const v = values, n = Math.max(2, System.historyLength);
            const out = [];
            for (let i = 0; i < v.length; i++)
                out.push(Qt.point(width * (n - v.length + i) / (n - 1), height * (1 - Math.max(0, Math.min(1, v[i])) * 0.92)));
            return out;
        }
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: line.height
                GradientStop {
                    position: 0
                    color: Theme.alpha(line.colour, 0.35)
                }
                GradientStop {
                    position: 1
                    color: Theme.alpha(line.colour, 0)
                }
            }
            startX: line.points.length > 0 ? line.points[0].x : 0
            startY: line.height
            PathLine {
                x: line.points.length > 0 ? line.points[0].x : 0
                y: line.points.length > 0 ? line.points[0].y : line.height
            }
            PathPolyline {
                path: line.points
            }
            PathLine {
                x: line.width
                y: line.height
            }
        }
        ShapePath {
            strokeWidth: 2
            strokeColor: line.colour
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline {
                path: line.points
            }
        }
    }

    Item {
        id: plot
        visible: !root.gauge
        anchors.fill: parent
        anchors.topMargin: root.labelled ? 26 : 0
        Line {
            visible: root.b !== null
            values: System.history[root.stat2] ?? []
            colour: root.c2
        }
        Line {
            values: System.history[root.stat] ?? []
            colour: root.c1
        }
    }

    // ── gauge: an arc for each stat, the second inside the first ──
    component Arc: Shape {
        id: arc
        property real level: 0
        property color colour: "white"
        property real inset: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real r: Math.min(width, height) / 2 - 6 - inset
        ShapePath {
            strokeWidth: 6
            strokeColor: Theme.alpha(arc.colour, 0.18)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: arc.width / 2
                centerY: arc.height / 2
                radiusX: arc.r
                radiusY: arc.r
                startAngle: 135
                sweepAngle: 270
            }
        }
        ShapePath {
            strokeWidth: 6
            strokeColor: arc.colour
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: arc.width / 2
                centerY: arc.height / 2
                radiusX: arc.r
                radiusY: arc.r
                startAngle: 135
                sweepAngle: 270 * Math.max(0.001, arc.level)
                Behavior on sweepAngle {
                    Anim {
                        role: "spatialFast"
                    }
                }
            }
        }
    }
    Item {
        visible: root.gauge
        anchors.fill: parent
        Arc {
            level: root.a.level
            colour: root.c1
        }
        Arc {
            visible: root.b !== null
            level: root.b?.level ?? 0
            colour: root.c2
            inset: 12
        }
        Text {
            anchors.centerIn: parent
            text: root.a.text
            font.family: Type.display
            font.pixelSize: Math.min(parent.width, parent.height) * 0.18
            color: root.c1
        }
    }

    // the label: what and how much
    Row {
        visible: root.labelled && !root.gauge
        spacing: Metrics.s4
        Text {
            text: root.a.label + "  " + root.a.text
            font.family: Type.ui
            font.pixelSize: 13
            font.features: Type.tabular
            color: root.c1
        }
        Text {
            visible: root.b !== null
            text: (root.b?.label ?? "") + "  " + (root.b?.text ?? "")
            font.family: Type.ui
            font.pixelSize: 13
            font.features: Type.tabular
            color: root.c2
        }
    }
}
