pragma Singleton

import QtQuick
import Quickshell
import qs.Services

// The native motion roles (src/render/animation/motion_role.cpp) as QML values, scaled by the policy.
// Things arrive decelerating and leave accelerating; an exit is about two thirds of an entrance.
Singleton {
    readonly property real scale: ExperiencePolicy.animationScale

    function ms(base: int): int {
        return Math.round(base * scale);
    }

    readonly property int focus: ms(130)
    readonly property int reveal: ms(300)
    readonly property int dismiss: ms(200)
    readonly property int contentIn: ms(150)
    readonly property int contentOut: ms(100)
    readonly property int contentDelay: ExperiencePolicy.stagger ? ms(50) : 0
    readonly property int morph: ms(300)
    readonly property int scene: ms(520)

    readonly property int enterEasing: Easing.OutQuint
    readonly property int exitEasing: Easing.InQuad
    readonly property int standardEasing: Easing.OutCubic

    // element travel: a critically damped spring where springs are on, the reveal tween otherwise
    readonly property bool springs: ExperiencePolicy.springs
    readonly property real spring: 3.2
    readonly property real damping: 0.32
    readonly property real springEpsilon: 0.25

    // how far a surface travels from its origin as it appears, and how small it starts
    readonly property real revealOffset: ExperiencePolicy.animationQuality === "reduced" ? 0 : 10
    readonly property real revealScale: ExperiencePolicy.animationQuality === "reduced" ? 1 : 0.97
}
