pragma Singleton

import QtQuick
import Quickshell
import qs.Services

// Zynith's motion language. Durations are roles scaled by the Experience profile and the user's speed
// (animation.toml); 0 under reduced motion. Curves are Material 3's expressive and emphasized families (the
// same splines Caelestia and end-4's illogical-impulse build on), picked per style:
//   fluid  expressive: spatial moves overshoot a touch and settle; effects ease out
//   crisp  standard: short, even, no overshoot
//   calm   emphasized: long decelerating arrivals, soft departures
// Things arrive decelerating and leave accelerating; an exit is about two thirds of an entrance.
Singleton {
    id: root

    // the profile's scale times the user's speed; 0 under reduced motion
    readonly property real speed: Math.max(0.25, Math.min(3, Config.animation.speed ?? 1))
    readonly property real scale: ExperiencePolicy.animationScale * speed
    readonly property string style: Config.animation.style ?? "fluid"
    readonly property bool reduced: scale === 0

    function ms(base: int): int {
        return Math.round(base * scale);
    }

    // ── durations ────────────────────────────────────────────────────────────
    readonly property int focus: ms(130)
    readonly property int reveal: ms(300)
    readonly property int dismiss: ms(200)
    readonly property int contentIn: ms(150)
    readonly property int contentOut: ms(100)
    readonly property int contentDelay: ExperiencePolicy.stagger ? ms(50) : 0
    readonly property int morph: ms(300)
    readonly property int scene: ms(520)
    // spatial roles (position, size, scale) and effects (opacity, colour)
    readonly property int spatialFast: ms(style === "crisp" ? 220 : 350)
    readonly property int spatial: ms(style === "crisp" ? 300 : style === "calm" ? 600 : 500)
    readonly property int spatialSlow: ms(style === "crisp" ? 400 : 650)
    readonly property int effects: ms(style === "calm" ? 260 : 200)
    readonly property int enter: ms(style === "crisp" ? 260 : 400)
    readonly property int exit: ms(style === "crisp" ? 160 : 200)

    // ── curves (QtQuick bezierCurve lists) ───────────────────────────────────
    readonly property var curves: ({
            expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1],
            expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1],
            expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1],
            expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1],
            emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1],
            emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1],
            standard: [0.2, 0, 0, 1, 1, 1],
            standardAccel: [0.3, 0, 1, 1, 1, 1],
            standardDecel: [0, 0, 0, 1, 1, 1]
        })
    readonly property var spatialCurve: style === "crisp" ? curves.standard : style === "calm" ? curves.emphasized : curves.expressiveDefaultSpatial
    readonly property var spatialFastCurve: style === "crisp" ? curves.standard : style === "calm" ? curves.emphasizedDecel : curves.expressiveFastSpatial
    readonly property var spatialSlowCurve: style === "crisp" ? curves.standard : style === "calm" ? curves.emphasized : curves.expressiveSlowSpatial
    readonly property var effectsCurve: style === "crisp" ? curves.standard : curves.expressiveEffects
    readonly property var enterCurve: style === "crisp" ? curves.standardDecel : curves.emphasizedDecel
    readonly property var exitCurve: style === "crisp" ? curves.standardAccel : curves.emphasizedAccel

    // the curves as functions of 0..1, for progress-driven choreography (cubic béziers only)
    function bezier(c: var, t: real): real {
        if (t <= 0)
            return 0;
        if (t >= 1)
            return 1;
        // solve x(u) = t by Newton's method, then y(u)
        const x1 = c[0], y1 = c[1], x2 = c[2], y2 = c[3];
        let u = t;
        for (let i = 0; i < 6; i++) {
            const x = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u - t;
            const dx = 3 * (1 - u) * (1 - u) * x1 + 6 * (1 - u) * u * (x2 - x1) + 3 * u * u * (1 - x2);
            if (Math.abs(dx) < 1e-6)
                break;
            u = Math.max(0, Math.min(1, u - x / dx));
        }
        return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u;
    }
    function ease(name: string, t: real): real {
        const c = curves[name] ?? curves.standard;
        return c.length === 6 ? bezier(c, t) : bezier(curves.emphasizedDecel, t);
    }

    // named easings kept for older call sites
    readonly property int enterEasing: style === "crisp" ? Easing.OutCubic : style === "calm" ? Easing.OutSine : Easing.OutQuint
    readonly property int exitEasing: style === "crisp" ? Easing.InCubic : style === "calm" ? Easing.InSine : Easing.InQuad
    readonly property int standardEasing: style === "calm" ? Easing.InOutSine : Easing.OutCubic

    // element travel that can be retargeted mid-flight: a spring where springs are on
    readonly property bool springs: ExperiencePolicy.springs
    readonly property real spring: style === "crisp" ? 4.6 : style === "calm" ? 2.4 : 3.6
    readonly property real damping: style === "crisp" ? 0.42 : style === "calm" ? 0.3 : 0.34
    readonly property real springEpsilon: 0.25

    // how far a surface travels from its origin as it appears, and how small it starts
    readonly property real revealOffset: ExperiencePolicy.reducedMotion ? 0 : 10
    readonly property real revealScale: ExperiencePolicy.reducedMotion ? 1 : 0.97
}
