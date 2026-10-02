pragma Singleton

import QtQuick
import Quickshell
import qs.Services

// The native motion roles (src/render/animation/motion_role.cpp) as QML values, scaled by the policy.
// Things arrive decelerating and leave accelerating; an exit is about two thirds of an entrance.
Singleton {
    // the profile's scale times the user's speed (animation.toml); 0 under reduced motion
    readonly property real speed: Math.max(0.25, Math.min(3, Config.animation.speed ?? 1))
    readonly property real scale: ExperiencePolicy.animationScale * speed
    // fluid: decelerate long, leave fast · crisp: short and even · calm: soft both ways
    readonly property string style: Config.animation.style ?? "fluid"

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

    readonly property int enterEasing: style === "crisp" ? Easing.OutCubic : style === "calm" ? Easing.OutSine : Easing.OutQuint
    readonly property int exitEasing: style === "crisp" ? Easing.InCubic : style === "calm" ? Easing.InSine : Easing.InQuad
    readonly property int standardEasing: style === "calm" ? Easing.InOutSine : Easing.OutCubic

    // element travel: a critically damped spring where springs are on, the reveal tween otherwise
    readonly property bool springs: ExperiencePolicy.springs
    readonly property real spring: 3.2
    readonly property real damping: 0.32
    readonly property real springEpsilon: 0.25

    // how far a surface travels from its origin as it appears, and how small it starts
    readonly property real revealOffset: ExperiencePolicy.animationQuality === "reduced" ? 0 : 10
    readonly property real revealScale: ExperiencePolicy.animationQuality === "reduced" ? 1 : 0.97
}
