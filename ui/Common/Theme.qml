pragma Singleton

import QtQuick
import Quickshell
import qs.Services
import "FallbackPalette.js" as Fallback

// Semantic colour roles over the wallpaper palette. Components use these names, never raw palette keys.
Singleton {
    id: root

    function pal(name: string): color {
        return (Palette.colors && Palette.colors[name]) || Fallback.colors[name] || "#808080";
    }
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    readonly property color surface: pal("surface")
    readonly property color surfaceLow: pal("surface_container_low")
    readonly property color surfaceMid: pal("surface_container")
    readonly property color surfaceHigh: pal("surface_container_high")
    readonly property color surfaceHighest: pal("surface_container_highest")

    // ink: text and glyphs, in three restrained tiers
    readonly property color ink: pal("on_surface")
    readonly property color inkMuted: alpha(pal("on_surface_variant"), 0.78)
    readonly property color inkFaint: alpha(pal("on_surface_variant"), 0.48)

    // the accent is spent sparingly: active state, focus, one highlight per surface
    readonly property color accent: pal("primary")
    readonly property color onAccent: pal("on_primary")
    readonly property color accentSoft: alpha(pal("primary"), 0.16)
    readonly property color accentLine: alpha(pal("primary"), 0.55)
    readonly property color danger: pal("error")

    // glass: a tinted, near-opaque sheet when blur is off; thinner when the compositor blurs behind it
    readonly property color glass: alpha(mix(pal("surface_container_lowest"), pal("surface_container_low"), 0.5),
        ExperiencePolicy.blur ? ExperiencePolicy.glassOpacity : Math.max(0.9, ExperiencePolicy.glassOpacity))
    readonly property color glassRaised: alpha(pal("surface_container_high"), ExperiencePolicy.blur ? 0.55 : 0.92)
    readonly property color hairline: alpha(pal("outline_variant"), 0.55)
    readonly property color sheen: alpha("#ffffff", ExperiencePolicy.richEffects ? 0.07 : 0.04)
    readonly property color hover: alpha(pal("on_surface"), 0.07)
    readonly property color press: alpha(pal("on_surface"), 0.12)
    readonly property color shadow: alpha(pal("shadow"), 0.42)
    readonly property color scrim: alpha(pal("scrim"), 0.18)
}
