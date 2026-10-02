pragma Singleton

import Quickshell
import qs.Services

// Spacing on a 4 px rhythm, radii scaled by appearance.toml.
Singleton {
    readonly property real radiusScale: Math.max(0, Math.min(2, Config.appearance.radius ?? 1))

    readonly property int s1: 2
    readonly property int s2: 4
    readonly property int s3: 8
    readonly property int s4: 12
    readonly property int s5: 16
    readonly property int s6: 24
    readonly property int s7: 32

    readonly property int radiusSm: Math.round(6 * radiusScale)
    readonly property int radiusMd: Math.round(10 * radiusScale)
    readonly property int radiusLg: Math.round(16 * radiusScale)
    readonly property int radiusXl: Math.round(22 * radiusScale)

    readonly property int barThickness: 34
    readonly property int control: 30
    readonly property int icon: 16
    readonly property int hairline: 1

    // room around a surface for its drawn shadow
    readonly property int shadowPad: 18
}
