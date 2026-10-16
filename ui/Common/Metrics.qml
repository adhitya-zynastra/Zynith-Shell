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

    // a page's columns: as many as asked for, but never so many that one is narrower than this (a page in a
    // narrow card takes one column instead of squeezing two)
    readonly property int pageColumnMin: 280
    function pageColumns(width: real, wanted: int): int {
        const fit = Math.floor((width + s3) / (pageColumnMin + s3));
        return Math.max(1, Math.min(Math.max(1, wanted), fit));
    }
    readonly property int s6: 24
    readonly property int s7: 32

    readonly property int radiusSm: Math.round(6 * radiusScale)
    readonly property int radiusMd: Math.round(10 * radiusScale)
    readonly property int radiusLg: Math.round(16 * radiusScale)
    readonly property int radiusXl: Math.round(22 * radiusScale)
    // Optics families: a lens's outer shape, a plate inside it, a control
    readonly property int radiusSurface: Math.round(18 * radiusScale)
    readonly property int radiusPlate: Math.round(10 * radiusScale)
    readonly property int radiusControl: Math.round(8 * radiusScale)

    readonly property int barThickness: 34
    readonly property int control: 30
    readonly property int icon: 16
    readonly property int hairline: 1

    // room around a surface for its drawn shadow
    readonly property int shadowPad: 18
}
