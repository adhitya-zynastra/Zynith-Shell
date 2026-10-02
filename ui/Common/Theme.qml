pragma Singleton

import QtQuick
import Quickshell
import qs.Services
import "FallbackPalette.js" as Fallback

// Zynith's semantic colours. Wallpaper → palette (theme engine) → these roles → every surface; nothing else in
// the UI names a palette key or a literal colour. appearance.toml adjusts tint, accent, contrast and borders.
Singleton {
    id: root

    function pal(name: string): color {
        return (Scheme.colors && Scheme.colors[name]) || Fallback.colors[name] || "#808080";
    }
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    readonly property var look: Config.appearance
    readonly property bool highContrast: look.contrast === "high"
    // how far surfaces lean toward the wallpaper's own colour instead of neutral grey
    readonly property real tint: Math.max(0, Math.min(1, look.tint ?? 0.35))

    // ── accent ──────────────────────────────────────────────────────────────
    // spent sparingly: active state, focus, one highlight per surface
    readonly property color accent: (look.accent && look.accent !== "wallpaper") ? look.accent : pal("primary")
    readonly property color onAccent: (look.accent && look.accent !== "wallpaper") ? (Qt.color(look.accent).hslLightness > 0.6 ? "#101114" : "#f4f5f8") : pal("on_primary")
    readonly property color accentSoft: alpha(accent, 0.16)
    readonly property color accentLine: alpha(accent, 0.55)
    readonly property color secondary: pal("tertiary")
    readonly property color danger: pal("error")
    readonly property color warning: mix(pal("error"), pal("tertiary"), 0.5)

    // ── surfaces, darkest to lightest, tinted by the wallpaper ───────────────
    readonly property color tintSource: pal("primary_container")
    function tinted(c: color, amount: real): color {
        return mix(c, tintSource, amount * tint);
    }
    readonly property color base: tinted(pal("surface_container_lowest"), 0.30)
    readonly property color surface: tinted(pal("surface"), 0.26)
    readonly property color surfaceLow: tinted(pal("surface_container_low"), 0.24)
    readonly property color surfaceMid: tinted(pal("surface_container"), 0.22)
    readonly property color surfaceHigh: tinted(pal("surface_container_high"), 0.20)
    readonly property color surfaceHighest: tinted(pal("surface_container_highest"), 0.18)

    // ── ink: text and glyphs in three restrained tiers ──────────────────────
    readonly property color ink: pal("on_surface")
    readonly property color inkMuted: alpha(pal("on_surface_variant"), highContrast ? 0.95 : 0.78)
    readonly property color inkFaint: alpha(pal("on_surface_variant"), highContrast ? 0.72 : 0.50)

    // ── glass: the sheet every floating surface is cut from ─────────────────
    // near-opaque without a blur behind it (even 6 % of bright text shows through); thinner with one
    readonly property real glassAlpha: ExperiencePolicy.blur ? ExperiencePolicy.glassOpacity : Math.max(0.97, ExperiencePolicy.glassOpacity)
    readonly property color glass: alpha(mix(base, surfaceLow, 0.5), glassAlpha)
    readonly property color glassRaised: alpha(surfaceHigh, ExperiencePolicy.blur ? 0.58 : 0.94)
    // a well inside a surface: rows, fields, tiles at rest
    readonly property color well: alpha(pal("on_surface"), highContrast ? 0.07 : 0.045)

    // ── edges ───────────────────────────────────────────────────────────────
    readonly property color hairline: look.border === "none" ? "transparent" : look.border === "defined" || highContrast ? alpha(pal("outline"), 0.62) : alpha(pal("outline_variant"), 0.5)
    readonly property real hairlineWidth: look.border === "none" ? 0 : 1
    // the lit top edge of a sheet
    readonly property color sheen: alpha("#ffffff", ExperiencePolicy.richEffects ? 0.08 : 0.045)

    // ── interaction ─────────────────────────────────────────────────────────
    readonly property color hover: alpha(pal("on_surface"), 0.07)
    readonly property color press: alpha(pal("on_surface"), 0.12)
    readonly property color selected: accentSoft
    readonly property color focus: accent
    readonly property real disabledOpacity: 0.38

    // ── depth ───────────────────────────────────────────────────────────────
    readonly property color shadow: alpha(pal("shadow"), 0.42)
    readonly property color scrim: alpha(pal("scrim"), 0.22)
}
