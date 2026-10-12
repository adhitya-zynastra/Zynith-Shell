import QtQuick
import QtQuick.Shapes
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The spectrum, in one of its shapes: bars (mirrored around the middle or rising from an edge), a wave, rings
// that breathe with the bass, mids and highs, or a ring with bars or a wave. It holds the spectrum only while
// it exists and the profile allows a visualizer; silent, it hides unless asked not to.
Item {
    id: root
    property var settings: ({})
    // in the editor and the picker: a still pattern stands in for silence, so it can be seen and placed
    property bool preview: false
    function opt(key: string): var {
        return WidgetTypes.value("audio_visualizer", settings, key);
    }
    readonly property string mode: opt("visualization_mode") ?? "bars"
    readonly property bool hasBars: mode === "bars" || mode === "bars_rings" || mode === "all"
    readonly property bool hasWave: mode === "wave" || mode === "wave_rings" || mode === "all"
    readonly property bool hasRings: mode.indexOf("rings") >= 0 || mode === "all"
    readonly property int bars: Math.max(4, opt("bands") ?? 32)
    readonly property bool mirrored: opt("mirrored") !== false
    readonly property bool reversed: opt("reversed") === true
    readonly property bool centred: opt("centered") === true
    readonly property real gain: opt("sensitivity") ?? 1
    readonly property color from: Theme.colour(settings.color_1 ?? settings.color ?? "primary")
    readonly property color to: Theme.colour(opt("color_2"))
    // the edge the spectrum stands on: its baseline, and the side its bars grow away from (into the widget)
    readonly property string edge: ["bottom", "top", "left", "right"].includes(opt("edge")) ? opt("edge") : "bottom"
    readonly property bool alongHeight: edge === "left" || edge === "right"
    // lean the bars (degrees): each bar's tip shifts along the edge, its foot stays on the baseline
    readonly property real lean: Math.tan(Math.max(-45, Math.min(45, opt("skew") ?? 0)) * Math.PI / 180)
    // the shear for that lean, about the baseline
    readonly property matrix4x4 shear: {
        const k = lean, w = width, h = height;
        switch (edge) {
        case "top":
            return Qt.matrix4x4(1, k, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        case "left":
            return Qt.matrix4x4(1, 0, 0, 0, k, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        case "right":
            return Qt.matrix4x4(1, 0, 0, 0, -k, 1, 0, k * w, 0, 0, 1, 0, 0, 0, 0, 1);
        default:
            return Qt.matrix4x4(1, -k, 0, k * h, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        }
    }

    readonly property bool wanted: Spectrum.enabled
    property bool holding: false
    function sync(): void {
        if (wanted && !holding) {
            Spectrum.retain();
            holding = true;
        } else if (!wanted && holding) {
            Spectrum.release();
            holding = false;
        }
    }
    onWantedChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (holding)
        Spectrum.release()

    visible: preview || (wanted && (Spectrum.active || opt("show_when_idle") !== false))
    readonly property bool still: preview && !Spectrum.active

    // the analyser's bands, stretched to `count` positions
    function level(i: int, count: int): real {
        if (still) {
            const t = mirrored ? Math.abs((i + 0.5) / count * 2 - 1) : (i + 0.5) / count;
            return 0.2 + 0.6 * Math.pow(Math.sin((reversed ? 1 - t : t) * 2.6 + 0.4), 2);
        }
        const values = Spectrum.values;
        const n = values.length;
        if (n === 0)
            return 0;
        let t = mirrored ? Math.abs((i + 0.5) / count * 2 - 1) : (i + 0.5) / count;
        if (reversed)
            t = 1 - t;
        const x = t * (n - 1);
        const a = Math.floor(x), b = Math.min(n - 1, a + 1);
        return Math.min(1, (values[a] + (values[b] - values[a]) * (x - a)) * gain);
    }
    function band(from: real, to: real): real {
        if (still)
            return 0.3 + from * 0.4;
        const v = Spectrum.values, n = v.length;
        if (n === 0)
            return 0;
        let s = 0, c = 0;
        for (let i = Math.floor(from * n); i < Math.max(Math.floor(from * n) + 1, Math.floor(to * n)); i++) {
            s += v[Math.min(n - 1, i)];
            c++;
        }
        return Math.min(1, s / Math.max(1, c) * gain);
    }

    // ── bars: one scene-graph node for all of them (Zynith.Native SpectrumBars), not a node and a binding per bar ──
    SpectrumBars {
        visible: root.hasBars && !root.hasRings
        anchors.fill: parent
        edge: root.edge
        transform: Matrix4x4 {
            matrix: root.shear
        }
        values: Spectrum.values
        count: root.bars
        mirrored: root.mirrored
        reversed: root.reversed
        centred: root.centred
        gain: root.gain
        gap: 0.3
        minLength: 2
        colorFrom: root.from
        colorTo: root.to
        alpha: 0.85
        still: root.still
    }

    // ── wave: a smooth line through the bands from the edge (or about the middle line, when centred); built
    // only when shown, so its points are not worked out every frame for nothing ──
    Loader {
        anchors.fill: parent
        active: root.hasWave && !root.hasRings
        sourceComponent: Shape {
            id: wave
            preferredRendererType: Shape.CurveRenderer
            transform: Matrix4x4 {
                matrix: root.shear
            }
            readonly property int count: Math.min(64, root.bars)
            readonly property real along: root.alongHeight ? height : width
            readonly property real across: root.alongHeight ? width : height
            readonly property var points: {
                const out = [];
                for (let i = 0; i < count; i++) {
                    const u = along * i / (count - 1), l = root.level(i, count);
                    const w = root.centred ? across / 2 + l * across / 2 : l * across;
                    out.push(root.edge === "top" ? Qt.point(u, w) : root.edge === "left" ? Qt.point(w, u) : root.edge === "right" ? Qt.point(width - w, u) : Qt.point(u, height - w));
                }
                return out;
            }
            ShapePath {
                strokeWidth: 2.5 * (root.opt("wave_thickness") ?? 1)
                strokeColor: root.from
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    path: wave.points
                }
            }
        }
    }

    // ── rings: bars or a wave around a circle that breathes with the bass (built only when shown) ──
    Loader {
        anchors.fill: parent
        active: root.hasRings
        sourceComponent: rings
    }
    Component {
        id: rings
    Item {
    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        readonly property real r: width / 2
        readonly property real bass: root.band(0, 0.12)
        readonly property real mids: root.band(0.12, 0.5)
        readonly property real highs: root.band(0.5, 1)

        Repeater {
            model: [{ v: parent.bass, k: 0.5, c: root.from }, { v: parent.mids, k: 0.66, c: Theme.mix(root.from, root.to, 0.5) }, { v: parent.highs, k: 0.8, c: root.to }]
            delegate: Rectangle {
                required property var modelData
                anchors.centerIn: parent
                width: parent.width * modelData.k * (0.9 + modelData.v * 0.25)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1.5, parent.r * 0.02)
                border.color: Theme.alpha(modelData.c, 0.35 + modelData.v * 0.5)
            }
        }
        // radial bars round the outside
        Repeater {
            model: root.hasBars || root.mode === "rings" ? Math.min(96, root.bars) : 0
            delegate: Rectangle {
                required property int index
                readonly property int count: Math.min(96, root.bars)
                readonly property real v: root.level(index, count)
                width: Math.max(1.5, parent.r * 0.03)
                height: parent.r * (0.06 + v * 0.3)
                radius: width / 2
                x: parent.r - width / 2
                y: parent.r * 0.08 - height * 0.0
                color: Theme.mix(root.from, root.to, index / count)
                transform: Rotation {
                    origin.x: width / 2
                    origin.y: parent.r - parent.r * 0.08
                    angle: index * 360 / count
                }
            }
        }
    }
    }
    }
}
