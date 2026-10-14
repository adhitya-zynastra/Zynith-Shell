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
//     nativeBlurStrength, paused: [what is paused, for the page to say] }
function resolve(style, glassStrength, blurStrength, env) {
    var st = styles.indexOf(style) >= 0 ? style : "glass";
    var e = env || {};
    var out = { style: st, paused: [] };
    if (st === "solid") {
        // opaque: the palette's own surface, depth from elevation and a defined edge
        out.fillAlpha = 1;
        out.raisedAlpha = 1;
        out.edgeAlpha = 0.14;
        out.sheenAlpha = 0;
        out.wellAlpha = 0.06;
        out.blurRequested = false;
        out.shadows = true;
        out.shadowDepth = 1;
        out.nativeBlurStrength = -1;
    } else if (st === "glass") {
        // clear tinted glass, no blur: the stronger, the clearer, with more light on its edge. Never thinner than
        // 0.44, so text on a busy wallpaper keeps its contrast.
        var g = clamp01(glassStrength);
        out.fillAlpha = Math.max(0.44, lerp(0.84, 0.44, g));
        out.raisedAlpha = Math.min(1, out.fillAlpha + 0.14);
        out.edgeAlpha = lerp(0.10, 0.34, g);
        out.sheenAlpha = lerp(0.03, 0.14, g);
        out.wellAlpha = lerp(0.05, 0.08, g);
        out.blurRequested = false;
        out.shadows = true;
        out.shadowDepth = lerp(0.6, 1, g);
        out.nativeBlurStrength = -1;
    } else {
        // frosted: the compositor blurs what is behind, the tint thins as the blur strengthens (the blur carries
        // the legibility), the edge stays quiet
        var b = clamp01(blurStrength);
        out.fillAlpha = lerp(0.68, 0.42, b);
        out.raisedAlpha = Math.min(1, out.fillAlpha + 0.12);
        out.edgeAlpha = 0.10;
        out.sheenAlpha = 0.05;
        out.wellAlpha = 0.06;
        out.blurRequested = true;
        out.shadows = false;
        out.shadowDepth = 0;
        // niri's blur (generated from the native shell's [shell.glass] blur_strength, 0..100)
        out.nativeBlurStrength = Math.round(lerp(14, 88, b));
    }
    out.blur = out.blurRequested && e.blurAvailable !== false;
    if (out.blurRequested && e.blurAvailable === false) {
        // no blur to be had: keep the frosted look legible with a denser tint instead of pretending
        out.fillAlpha = Math.max(out.fillAlpha, 0.86);
        out.paused.push("blur-unavailable");
    }
    if (e.easeEffects) {
        // temporary, while power is short; the choice itself is never changed
        if (out.blur) {
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
    return out;
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
