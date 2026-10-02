import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import QtQuick.Shapes

// One system stat: a gauge, a small graph or just the value, its glyph before or after, in the highlight
// colour when high.
BarItem {
    id: root
    readonly property string stat: opt("stat") ?? "cpu_usage"
    readonly property var reading: System.read(stat)
    readonly property bool high: reading.level >= 0.85
    readonly property string viz: opt("visualization") ?? "gauge"
    readonly property color tint: high ? Theme.colour(opt("highlight_color") ?? "error") : root.iconInk
    readonly property string glyphName: (opt("glyph") || "") !== "" ? opt("glyph") : ({ cpu_usage: "cpu", cpu_temp: "temperature", cpu_freq: "gauge", ram_pct: "database", swap_pct: "database", net_rx: "arrow-down", net_tx: "arrow-up" })[stat] ?? "activity"
    Component.onCompleted: System.retain()
    Component.onDestruction: System.release()
    tooltip: reading.label + "  " + reading.text

    BarGlyph {
        item: root
        visible: root.opt("show_glyph") !== false && root.opt("glyph_position") !== "after"
        name: root.glyphName
        colour: root.tint
    }
    // a ring for the level
    Shape {
        visible: root.viz === "gauge"
        width: 14
        height: 14
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 2
            strokeColor: Theme.alpha(root.tint, 0.25)
            fillColor: "transparent"
            PathAngleArc {
                centerX: 7
                centerY: 7
                radiusX: 6
                radiusY: 6
                startAngle: -90
                sweepAngle: 360
            }
        }
        ShapePath {
            strokeWidth: 2
            strokeColor: root.tint
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: 7
                centerY: 7
                radiusX: 6
                radiusY: 6
                startAngle: -90
                sweepAngle: 360 * Math.max(0.01, root.reading.level)
            }
        }
    }
    // the last minute, small
    Shape {
        id: spark
        visible: root.viz === "graph" && !root.vertical
        width: 36
        height: 14
        preferredRendererType: Shape.CurveRenderer
        readonly property var values: System.history[root.stat] ?? []
        ShapePath {
            strokeWidth: 1.5
            strokeColor: root.tint
            fillColor: "transparent"
            PathPolyline {
                path: spark.values.map((v, i) => Qt.point(spark.width * (System.historyLength - spark.values.length + i) / (System.historyLength - 1), spark.height - 1 - v * (spark.height - 2)))
            }
        }
    }
    BarText {
        item: root
        visible: root.opt("show_value") !== false && !root.vertical
        width: Math.max(implicitWidth, root.opt("label_min_width") ?? 0)
        text: root.opt("label_show_units") === false ? root.reading.text.replace(/[^0-9.,]+$/, "") : root.reading.text
        color: root.high ? root.tint : root.ink
    }
    BarGlyph {
        item: root
        visible: root.opt("show_glyph") !== false && root.opt("glyph_position") === "after"
        name: root.glyphName
        colour: root.tint
    }
}
