.pragma library

// Zynith's surface materials as numbers: one function from what the user chose (a style and its strength) and what
// the system can afford right now, to everything a surface needs to draw itself. Services/Material.qml applies it;
// Theme, Glass and BlurRegion read Material; nothing else decides how a surface looks.
// Tested by tools/tests/tst_material.qml.

var styles = ["glass", "solid", "blur"];
// the named strengths the Appearance page offers; the stored value is a number in 0..1
var levels = { subtle: 0.15, balanced: 0.5, strong: 0.85 };

function clamp01(v) {
    var n = Number(v);
    return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0.5;
}
function lerp(a, b, t) {
    return a + (b - a) * t;
}
// the nearest named level for a stored strength (what the Appearance page highlights)
function levelOf(strength) {
    var s = clamp01(strength);
    var best = "balanced", d = 2;
    for (var k in levels) {
        var e = Math.abs(levels[k] - s);
        if (e < d) {
            d = e;
            best = k;
        }
    }
    return best;
}

// style: "glass" | "solid" | "blur"; strength: 0..1 for that style (glass and blur each keep their own)
// env: { blurAvailable: bool, easeEffects: bool }  (easeEffects: genuine pressure — power saver, battery low)
// → { style, fillAlpha, raisedAlpha, edgeAlpha, sheenAlpha, wellAlpha, blur, blurRequested, shadows, shadowDepth,
//     nativeBlurStrength, motionAlpha (the fill while moving, without a backdrop), paused: [what is paused, for the page to say] }
function resolve(style, glassStrength, blurStrength, env) {
    var st = styles.indexOf(style) >= 0 ? style : "glass";
    var e = env || {};
    // backdrop: what the compositor puts behind a surface (niri background-effect):
    //   "wallpaper"  xray — the wallpaper itself, even over windows, softened only by niri's faintest blur
    //   "live"       what is really behind the surface, blurred
    //   "none"       nothing: the surface is opaque
    var out = { style: st, paused: [] };
    if (st === "solid") {
        // opaque: the palette's own surface, depth from elevation and a defined edge
        out.fillAlpha = 1;
        out.raisedAlpha = 1;
        out.edgeAlpha = 0.14;
        out.sheenAlpha = 0;
        out.wellAlpha = 0.06;
        out.backdrop = "none";
        out.shadows = true;
        out.shadowDepth = 1;
        out.nativeBlurStrength = -1;
    } else if (st === "glass") {
        // clear tinted glass over the wallpaper: the stronger, the clearer, with more light on its edge. Never
        // thinner than 0.44, so text on a busy wallpaper keeps its contrast. niri's blur at its faintest (1 pass).
        var g = clamp01(glassStrength);
        out.fillAlpha = Math.max(0.44, lerp(0.84, 0.44, g));
        out.raisedAlpha = Math.min(1, out.fillAlpha + 0.14);
        out.edgeAlpha = lerp(0.10, 0.34, g);
        out.sheenAlpha = lerp(0.03, 0.14, g);
        out.wellAlpha = lerp(0.05, 0.08, g);
        out.backdrop = "wallpaper";
        out.shadows = true;
        out.shadowDepth = lerp(0.6, 1, g);
        out.nativeBlurStrength = 0;
    } else {
        // frosted: the compositor blurs what is really behind, the tint thins as the blur strengthens (the blur
        // carries the legibility), the edge stays quiet
        var b = clamp01(blurStrength);
        out.fillAlpha = lerp(0.68, 0.42, b);
        out.raisedAlpha = Math.min(1, out.fillAlpha + 0.12);
        out.edgeAlpha = 0.10;
        out.sheenAlpha = 0.05;
        out.wellAlpha = 0.06;
        out.backdrop = "live";
        out.shadows = false;
        out.shadowDepth = 0;
        // niri's blur (generated from the native shell's [shell.glass] blur_strength, 0..100)
        out.nativeBlurStrength = Math.round(lerp(14, 88, b));
    }
    // blurRequested: the surface asks the compositor for its backdrop; blur: it gets one now
    out.blurRequested = out.backdrop !== "none";
    out.blur = out.blurRequested && e.blurAvailable !== false;
    if (out.blurRequested && e.blurAvailable === false) {
        // no backdrop to be had: a denser tint keeps it legible instead of pretending (glass still shows what is
        // behind it, through its own translucency)
        if (st === "blur")
            out.fillAlpha = Math.max(out.fillAlpha, 0.86);
        out.paused.push(st === "blur" ? "blur-unavailable" : "wallpaper-unavailable");
    }
    if (e.easeEffects) {
        // temporary, while power is short; the choice itself is never changed. Glass keeps its wallpaper: niri
        // blurs the wallpaper once and reuses it, so it costs nearly nothing; a live blur is redrawn as the
        // content behind moves, so that is what pauses.
        if (out.blur && out.backdrop === "live") {
            out.blur = false;
            out.fillAlpha = Math.max(out.fillAlpha, 0.86);
            out.paused.push("blur");
        }
        if (out.shadows) {
            out.shadows = false;
            out.paused.push("shadows");
        }
    }
    out.raisedAlpha = Math.max(out.raisedAlpha, out.fillAlpha);
    // In motion a surface has no compositor backdrop: a backdrop region cannot follow a moving surface frame for
    // frame (it reaches the compositor out of step with the picture, by up to ~45 px a frame at a panel's fastest),
    // so it is set only once the surface rests. Meanwhile the surface carries motionAlpha, dense enough that what is
    // really behind it does not show through sharp, and thins to fillAlpha once its backdrop is in (Common/
    // MaterialSettle). The style's own legibility value without blur, as it already uses when blur is paused.
    out.motionAlpha = !out.blur ? out.fillAlpha : st === "blur" ? Math.max(out.fillAlpha, 0.86) : Math.min(1, out.fillAlpha + (1 - out.fillAlpha) * 0.5);
    return out;
}

// niri rules for the backdrop: xray on (the wallpaper) for glass, off (what is really behind) for blur. The
// namespaces are every Zynith surface that asks for a backdrop, and the Settings window by its title.
function niriFragment(backdrop) {
    // Glass needs no rule: niri turns xray on by itself wherever a surface asks for blur, exactly in the region
    // asked for. An explicit `xray true` applied xray to the whole surface, and before the region arrived (a panel's
    // first frames) the whole window showed the bare wallpaper over the windows for a frame.
    if (backdrop === "wallpaper")
        return "// Generated by the Zynith UI from appearance.toml surface_style (Settings -> Appearance). Edits are\n"
            + "// overwritten. Glass: no rule — niri's own xray shows the wallpaper behind each surface's blur region.\n";
    return "// Generated by the Zynith UI from appearance.toml surface_style (Settings -> Appearance). Edits are\n"
        + "// overwritten. xray false: Blur shows what is really behind each surface.\n\n"
        + "layer-rule {\n    match namespace=\"^zynith-(bar-.+|panel|osd|notifications)$\"\n    background-effect {\n        xray false\n    }\n}\n\n"
        + "window-rule {\n    match title=\"^Zynith Settings$\"\n    background-effect {\n        xray false\n    }\n}\n";
}

// experience.toml before materials → the new keys (appearance and efficiency apart). Returns null when there is
// nothing to migrate (already has surface_style), else { appearance: {set, remove}, experience: {set, remove} }.
//   appearance: the old appearance.toml table; experience: the old experience.toml table
// the Blur style's strength that draws niri's blur at `native` (0..100, the inverse of resolve's mapping)
function blurStrengthFromNative(native) {
    var n = Number(native);
    return isFinite(n) ? Math.round(clamp01((n - 14) / 74) * 100) / 100 : 0.5;
}

//   nativeBlur (optional): the native shell's current [shell.glass] blur_strength, kept as the Blur style's strength
function migrate(appearance, experience, nativeBlur) {
    var a = appearance || {};
    var x = experience || {};
    if (a.surface_style !== undefined)
        return null;
    var profile = x.profile;
    var oldBlur = a.blur;            // "profile" | "on" | "off"
    var opacity = Number(a.surface_opacity || 0);
    var style;
    if (oldBlur === "on")
        style = "blur";
    else if (oldBlur === "off")
        style = opacity > 0 && opacity < 0.95 ? "glass" : "solid";
    else
        // the profile decided: Performance drew near-opaque surfaces with no blur; the others blurred
        style = profile === "performance" ? "solid" : "blur";
    var set = { surface_style: style, glass_strength: 0.5, blur_strength: nativeBlur !== undefined ? blurStrengthFromNative(nativeBlur) : 0.5 };
    if (style === "glass" && opacity > 0)
        // the opacity the user set, as the glass strength that draws it (fill 0.84 → 0.44 over 0..1)
        set.glass_strength = Math.round(clamp01((0.84 - opacity) / 0.40) * 100) / 100;
    return {
        appearance: { set: set, remove: ["blur", "surface_opacity"] },
        // the profile was also a power choice: Performance meant "spend little" — that much is kept, as efficiency
        experience: { set: { efficiency: profile === "performance" ? "save" : "auto" }, remove: ["profile", "adaptive"] }
    };
}
