import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Common

// A control drawn as a camera iris: six blades close over the face while it is off and open — turning on their
// pivots at the rim — to show a lit core when it is on. Around it a readout ring carries the control's live value
// (signal bars, devices, a profile's position, a level). Only a change of state animates; at rest nothing moves.
// Turning one on fires the shutter: a ring of light leaves the rim. `awake` holds the iris shut while the panel
// arrives, so a panel's dials can open one after another rather than all at once.
// A reading that can be set (`set`) turns: dragging around the ring moves its level, the ring thickens, a knob
// rides its end and the number (`text`) takes the glyph's place until the hand lets go.
//   lit: on / off · glyph: the icon · reading: { value: 0..1, segments: n (0 = continuous), set, text } or null
Item {
    id: root

    property bool lit: false
    property string glyph: ""
    property var reading: null
    property bool hovered: false
    property bool pressed: false
    property real size: 54
    property bool awake: true
    property bool turning: false

    implicitWidth: size
    implicitHeight: size

    // 0 = closed, 1 = open; follows `lit` on the spatial curve (a touch of overshoot opening, none closing).
    // The pointer resting on a closed one opens it a little — a glimpse of what switching it on does.
    property real open: lit && awake ? 1 : hovered ? 0.24 : 0
    Behavior on open {
        NumberAnimation {
            duration: Motion.spatial * 1.4
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.lit ? Motion.spatialCurve : Motion.spatialFastCurve
        }
    }

    // where on the ring a point is: 0 at its start (bottom left), 1 at its end (bottom right), clockwise; the gap
    // at the bottom snaps to the nearer end
    function valueAt(x: real, y: real): real {
        const deg = Math.atan2(y - height / 2, x - width / 2) * 180 / Math.PI;
        const rel = ((deg - 135) % 360 + 360) % 360;
        return rel <= 270 ? rel / 270 : rel > 315 ? 0 : 1;
    }

    readonly property real r0: size / 2
    // the aperture: inside the readout ring and a hairline of bezel
    readonly property real ri: r0 - 6

    // ── the readout ring ──
    // thicker while it is being turned: it is the control then, not only a reading
    property real track: turning ? 4 : 2
    Behavior on track {
        NumberAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }
    Shape {
        id: ring
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real rr: root.r0 - root.track / 2 - 0.5
        readonly property int segments: root.reading?.segments ?? 0
        readonly property real value: Math.max(0, Math.min(1, root.reading?.value ?? 0))
        visible: root.reading !== null
        // the track
        ShapePath {
            strokeWidth: root.track
            strokeColor: Theme.alpha(Theme.ink, 0.10)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.r0
                centerY: root.r0
                radiusX: ring.rr
                radiusY: ring.rr
                startAngle: 135
                sweepAngle: 270
            }
        }
        // a continuous level: one arc from the start, as long as the value
        ShapePath {
            strokeWidth: root.track
            strokeColor: root.lit || root.turning ? Theme.accent : Theme.alpha(Theme.ink, 0.55)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.r0
                centerY: root.r0
                radiusX: ring.rr
                radiusY: ring.rr
                startAngle: 135
                sweepAngle: ring.segments > 0 ? 0 : 270 * ring.shown
            }
        }
        // the level eases to its value (a reading changing is a small motion, not a jump)
        property real shown: value
        Behavior on shown {
            // under the hand the level follows at once
            enabled: !root.turning
            NumberAnimation {
                duration: Motion.spatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spatialCurve
            }
        }
    }
    // segmented readings (signal bars, profile positions): ticks along the same arc, lit up to the value
    Repeater {
        model: ring.segments
        delegate: Shape {
            id: seg
            required property int index
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property real span: 270 / ring.segments
            readonly property bool on: (index + 1) <= Math.round(ring.shown * ring.segments)
            ShapePath {
                strokeWidth: 2
                strokeColor: seg.on ? (root.lit ? Theme.accent : Theme.alpha(Theme.ink, 0.6)) : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.r0
                    centerY: root.r0
                    radiusX: ring.rr
                    radiusY: ring.rr
                    startAngle: 135 + seg.index * seg.span + 4
                    sweepAngle: Math.max(1, seg.span - 8)
                }
            }
        }
    }

    // the knob at the level's end, while turning
    Rectangle {
        readonly property real a: (135 + 270 * ring.shown) * Math.PI / 180
        width: 10
        height: 10
        radius: 5
        x: root.r0 + ring.rr * Math.cos(a) - 5
        y: root.r0 + ring.rr * Math.sin(a) - 5
        color: Theme.ink
        border.width: 2
        border.color: Theme.accent
        visible: opacity > 0
        opacity: root.turning ? 1 : 0
        scale: root.turning ? 1 : 0.4
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.focus
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
    }

    // ── the face: a dark well, the lit core, the blades over it, all inside the aperture ──
    Item {
        id: face
        anchors.centerIn: parent
        width: root.ri * 2
        height: width
        scale: root.pressed ? 0.94 : root.hovered ? 1.03 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: apertureMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        // the well behind the blades
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.mix(Theme.base, Theme.surfaceHigh, 0.35)
        }
        // the core: light from inside, only as the iris opens
        Shape {
            anchors.fill: parent
            opacity: root.open
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: root.ri
                    centerY: root.ri
                    centerRadius: root.ri
                    focalX: root.ri
                    focalY: root.ri * 0.8
                    GradientStop {
                        position: 0
                        color: Theme.alpha(Theme.accent, 0.55)
                    }
                    GradientStop {
                        position: 0.6
                        color: Theme.alpha(Theme.accent, 0.18)
                    }
                    GradientStop {
                        position: 1
                        color: Theme.alpha(Theme.accent, 0.04)
                    }
                }
                PathAngleArc {
                    centerX: root.ri
                    centerY: root.ri
                    radiusX: root.ri
                    radiusY: root.ri
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
        // six blades: curved wedges meeting in the middle while closed; opening, each slides out along its own
        // bisector with a slight twist, so the opening grows as a hexagon — a lens's iris
        Repeater {
            model: 6
            delegate: Shape {
                id: blade
                required property int index
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property real a: index * Math.PI / 3
                readonly property real twist: root.open * 0.42
                readonly property real out: root.open * root.ri * 0.92
                function f(x: real, y: real): string {
                    return x.toFixed(2) + " " + y.toFixed(2);
                }
                readonly property string outline: {
                    const c = root.ri, R = root.ri * 1.5;
                    const a0 = a + twist, a1 = a + Math.PI / 3 + twist, mid = a + Math.PI / 6 + twist;
                    // the wedge's own centre, pushed out along its bisector
                    const ox = c + out * Math.cos(mid), oy = c + out * Math.sin(mid);
                    // the leading edge curves (a blade, not a slice); the trailing edge is straight
                    const ax = ox + R * Math.cos(a0), ay = oy + R * Math.sin(a0);
                    const bx = ox + R * Math.cos(a1), by = oy + R * Math.sin(a1);
                    const kx = ox + R * 0.55 * Math.cos(a0 + 0.42), ky = oy + R * 0.55 * Math.sin(a0 + 0.42);
                    return "M " + f(ox, oy) + " Q " + f(kx, ky) + " " + f(ax, ay) + " L " + f(bx, by) + " Z";
                }
                ShapePath {
                    strokeWidth: 1
                    strokeColor: Theme.alpha(Theme.ink, 0.11)
                    fillColor: Theme.mix(Theme.surfaceHighest, Theme.base, 0.2 + (blade.index % 2) * 0.07)
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        path: blade.outline
                    }
                }
            }
        }
    }
    Rectangle {
        id: apertureMask
        anchors.fill: face
        radius: width / 2
        visible: false
        layer.enabled: true
    }
    // the rim's catch-light, and the accent edge once lit
    Rectangle {
        anchors.centerIn: parent
        width: root.ri * 2 + 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: root.lit && root.awake ? Theme.alpha(Theme.accent, 0.55) : Theme.alpha(Theme.ink, 0.14)
        Behavior on border.color {
            ColorAnimation {
                duration: Motion.focus
            }
        }
    }

    // the shutter: switching on sends a ring of light out from the rim (only a change by hand; waking does not)
    Rectangle {
        id: flash
        anchors.centerIn: parent
        width: root.ri * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        opacity: 0
        scale: 1
    }
    ParallelAnimation {
        id: shutter
        NumberAnimation {
            target: flash
            property: "scale"
            from: 1
            to: (root.size + 14) / (root.ri * 2)
            duration: Motion.spatial * 1.6
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spatialFastCurve
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            from: 0.7
            to: 0
            duration: Motion.spatial * 1.6
            easing.type: Easing.OutQuad
        }
    }
    onLitChanged: if (lit && awake && Motion.spatial > 0)
        shutter.restart()

    // a shade behind the glyph so it reads over the blades' seams while the iris is shut
    Rectangle {
        anchors.centerIn: parent
        width: Math.round(root.size * 0.5)
        height: width
        radius: width / 2
        color: Theme.mix(Theme.base, Theme.surfaceHigh, 0.3)
        opacity: 0.85 * (1 - Math.min(1, root.open * 1.6))
    }

    // the number while it turns
    Label {
        anchors.centerIn: parent
        role: "label"
        numeric: true
        text: root.reading?.text ?? ""
        opacity: root.turning ? 1 : 0
        scale: root.turning ? 1 : 0.7
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.focus
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
    }

    // the glyph, over the iris: faint while closed, lit once open
    Icon {
        anchors.centerIn: parent
        name: root.glyph
        scale: root.turning ? 0.6 : 1
        visible: scale > 0.62 || !root.turning
        Behavior on scale {
            NumberAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
        size: Math.round(root.size * 0.36)
        color: root.lit && root.awake ? Theme.ink : Theme.inkMuted
        opacity: 0.75 + 0.25 * root.open
    }
}
