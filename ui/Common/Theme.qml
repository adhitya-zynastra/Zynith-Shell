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
    // a colour setting: a palette role ("primary", "on_surface"…) or a literal ("#b4c5ff")
    function colour(v: var): color {
        const s = String(v ?? "");
        return s.startsWith("#") || s.startsWith("rgb") ? Qt.color(s) : pal(s === "" ? "on_surface" : s);
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

    // ── the sheet every floating surface is cut from: its material is Material's (Glass / Solid / Blur) ────
    // Solid takes the palette's own surface tone, opaque; Glass and Blur a deeper tone, as translucent as the
    // style and its strength say
    readonly property real glassAlpha: Material.fillAlpha
    readonly property color sheetTone: Material.solid ? mix(surfaceLow, surfaceMid, 0.55) : mix(base, surfaceLow, 0.5)
    readonly property color glass: alpha(sheetTone, glassAlpha)
    readonly property color glassRaised: alpha(Material.solid ? surfaceHigh : surfaceHigh, Material.raisedAlpha)
    // a well inside a surface: rows, fields, tiles at rest
    readonly property color well: alpha(pal("on_surface"), highContrast ? Material.wellAlpha + 0.025 : Material.wellAlpha)

    // ── edges ───────────────────────────────────────────────────────────────
    // the edge of a sheet: its definition is the material's (glass catches more light the stronger it is)
    readonly property color hairline: look.border === "none" ? "transparent" : look.border === "defined" || highContrast ? alpha(pal("outline"), Math.max(0.62, Material.edgeAlpha * 2)) : alpha(mix(pal("outline_variant"), "#ffffff", Material.solid ? 0 : 0.25), Math.min(0.85, Material.edgeAlpha * 2.6))
    readonly property real hairlineWidth: look.border === "none" ? 0 : 1
    // the lit top edge of a sheet
    readonly property color sheen: alpha("#ffffff", Material.sheenAlpha)

    // ── interaction ─────────────────────────────────────────────────────────
    // Optics materials: a plate is a tone step inside a lens; the signal is the accent as light on an edge
    // (the one current selection of a surface), never a painted block
    readonly property color plate: alpha(mix(surfaceHigh, surfaceHighest, 0.5), 0.45)
    readonly property color signalFill: alpha(accent, 0.10)
    readonly property color signalEdge: alpha(accent, 0.62)
    readonly property color signalGlow: alpha(accent, 0.16)
    readonly property color rule: alpha(pal("on_surface"), 0.10)

    readonly property color hover: alpha(pal("on_surface"), 0.07)
    readonly property color press: alpha(pal("on_surface"), 0.12)
    readonly property color selected: accentSoft
    readonly property color focus: accent
    readonly property real disabledOpacity: 0.38

    // ── depth ───────────────────────────────────────────────────────────────
    readonly property color shadow: alpha(pal("shadow"), 0.42)
    readonly property color scrim: alpha(pal("scrim"), 0.22)
}
