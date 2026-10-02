import QtQuick
import qs.Common

// Moves a value with a spring where the profile allows springs (retargets mid-flight with its velocity),
// a tween on the spatial curve otherwise. Lighter profiles get shorter motion, never a jump.
//   Glide on x {}            Glide on scale { epsilon: 0.001 }
Behavior {
    id: root
    property string role: "spatialFast"
    property real epsilon: Motion.springEpsilon
    property SpringAnimation springMotion: SpringAnimation {
        spring: Motion.spring
        damping: Motion.damping
        epsilon: root.epsilon
    }
    property Anim tweenMotion: Anim {
        role: root.role
    }
    enabled: !Motion.reduced
    animation: Motion.springs ? springMotion : tweenMotion
}
