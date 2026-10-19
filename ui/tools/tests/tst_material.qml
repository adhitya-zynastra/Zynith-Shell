import QtQuick
import QtTest
import "../../Common/MaterialModel.js" as M

// Common/MaterialModel.js: the three surface styles, their strengths, what pressure may pause, and the migration
// from the four Experience Profiles.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_material.qml
TestCase {
    name: "Material"

    readonly property var ok: ({ blurAvailable: true, easeEffects: false })

    function test_solid_is_opaque_with_depth_and_no_blur() {
        const m = M.resolve("solid", 0.5, 0.5, ok);
        compare(m.fillAlpha, 1);
        compare(m.raisedAlpha, 1);
        verify(!m.blur);
        verify(m.shadows);
        compare(m.nativeBlurStrength, -1, "solid leaves the compositor's blur alone");
    }
    function test_glass_strength_makes_a_visible_difference() {
        const subtle = M.resolve("glass", M.levels.subtle, 0.5, ok);
        const strong = M.resolve("glass", M.levels.strong, 0.5, ok);
        verify(subtle.fillAlpha - strong.fillAlpha >= 0.25, "clearer glass: " + subtle.fillAlpha + " → " + strong.fillAlpha);
        verify(strong.edgeAlpha - subtle.edgeAlpha >= 0.15, "more light on the edge");
        verify(strong.sheenAlpha > subtle.sheenAlpha);
        compare(strong.backdrop, "wallpaper", "glass shows the wallpaper (xray), not the windows behind");
        compare(strong.nativeBlurStrength, 0, "with niri's faintest blur");
    }
    function test_glass_never_gets_too_thin_to_read() {
        verify(M.resolve("glass", 1, 0.5, ok).fillAlpha >= 0.44);
    }
    function test_blur_strength_drives_the_compositor_and_the_tint() {
        const subtle = M.resolve("blur", 0.5, M.levels.subtle, ok);
        const strong = M.resolve("blur", 0.5, M.levels.strong, ok);
        verify(subtle.blur && strong.blur);
        verify(strong.nativeBlurStrength - subtle.nativeBlurStrength >= 40, subtle.nativeBlurStrength + " → " + strong.nativeBlurStrength);
        verify(strong.fillAlpha < subtle.fillAlpha, "a stronger blur carries more of the legibility");
    }
    function test_each_style_keeps_its_own_strength() {
        compare(M.resolve("glass", 0.2, 0.9, ok).fillAlpha, M.resolve("glass", 0.2, 0.1, ok).fillAlpha, "blur strength does not touch glass");
    }
    function test_each_style_names_its_backdrop_and_niri_rule() {
        compare(M.resolve("solid", 0.5, 0.5, ok).backdrop, "none");
        verify(!M.resolve("solid", 0.5, 0.5, ok).blur, "solid asks for nothing");
        compare(M.resolve("blur", 0.5, 0.5, ok).backdrop, "live");
        // Glass writes no rule (niri's own xray follows the blur region); an explicit `xray true` covered the whole
        // surface before its region arrived — a frame of bare wallpaper over the windows as a panel opened
        verify(M.niriFragment("wallpaper").indexOf("xray true") < 0);
        verify(M.niriFragment("wallpaper").indexOf("layer-rule") < 0);
        verify(M.niriFragment("live").indexOf("xray false") > 0);
        verify(M.niriFragment("live").indexOf("zynith-(bar-.+|panel|osd|notifications)") > 0);
        verify(M.niriFragment("live").indexOf("Zynith Settings") > 0);
    }
    function test_pressure_keeps_the_wallpaper_behind_glass() {
        const g = M.resolve("glass", 0.5, 0.5, { blurAvailable: true, easeEffects: true });
        verify(g.blur, "xray reuses one blurred wallpaper: nearly free, so it stays");
        verify(!g.shadows);
    }
    function test_blur_unavailable_is_said_not_pretended() {
        const m = M.resolve("blur", 0.5, 0.5, { blurAvailable: false, easeEffects: false });
        verify(!m.blur);
        verify(m.paused.includes("blur-unavailable"));
        verify(m.fillAlpha >= 0.86, "dense enough to read without the blur");
        compare(m.style, "blur", "the choice stays the user's");
    }
    function test_pressure_pauses_effects_without_changing_the_choice() {
        const m = M.resolve("blur", 0.5, 0.5, { blurAvailable: true, easeEffects: true });
        verify(!m.blur);
        verify(m.paused.includes("blur"));
        compare(m.style, "blur");
        const s = M.resolve("solid", 0.5, 0.5, { blurAvailable: true, easeEffects: true });
        verify(!s.shadows);
        compare(s.fillAlpha, 1, "solid stays solid");
        const back = M.resolve("blur", 0.5, 0.5, ok);
        verify(back.blur, "restored when the pressure is gone");
    }
    function test_unknown_style_and_strength_fall_back() {
        compare(M.resolve("frosted-neon", NaN, undefined, ok).style, "glass");
        compare(M.levelOf(0.9), "strong");
        compare(M.levelOf(0.1), "subtle");
        compare(M.levelOf(0.48), "balanced");
    }

    // migration from the four profiles
    function test_migrate_the_owners_performance_profile() {
        const m = M.migrate({ accent: "wallpaper", blur: "profile", surface_opacity: 0, tint: 0.05 }, { adaptive: true, profile: "performance", overrides: { visualizerBands: 64 } });
        compare(m.appearance.set.surface_style, "solid", "Performance drew near-opaque, unblurred surfaces");
        compare(m.appearance.remove, ["blur", "surface_opacity"]);
        compare(m.experience.set.efficiency, "save", "and spent little: kept as efficiency");
        compare(m.experience.remove, ["profile", "adaptive"]);
    }
    function test_migrate_other_profiles_and_explicit_choices() {
        compare(M.migrate({ blur: "profile" }, { profile: "max" }).appearance.set.surface_style, "blur");
        compare(M.migrate({}, {}).appearance.set.surface_style, "blur", "automatic profiles blurred");
        compare(M.migrate({ blur: "on" }, { profile: "performance" }).appearance.set.surface_style, "blur", "an explicit blur wins");
        const g = M.migrate({ blur: "off", surface_opacity: 0.64 }, {});
        compare(g.appearance.set.surface_style, "glass");
        compare(g.appearance.set.glass_strength, 0.5, "0.64 opacity is balanced glass");
        compare(M.migrate({ blur: "off", surface_opacity: 0 }, {}).appearance.set.surface_style, "solid");
        compare(M.migrate({ blur: "profile" }, { profile: "balanced" }).experience.set.efficiency, "auto");
    }
    function test_migrate_keeps_the_blur_the_owner_tuned() {
        const m = M.migrate({ blur: "profile" }, { profile: "max" }, 25);
        compare(m.appearance.set.blur_strength, 0.15);
        compare(M.resolve("blur", 0.5, m.appearance.set.blur_strength, ok).nativeBlurStrength, 25, "and draws the same blur again");
    }
    function test_migrate_is_idempotent() {
        compare(M.migrate({ surface_style: "glass" }, { profile: "max" }), null);
    }

    // in motion, without its backdrop, the style's own fill: a denser one read as a dark tint on every opening
    function test_motion_alpha_is_the_resting_fill() {
        for (const st of ["glass", "blur", "solid"]) {
            const m = M.resolve(st, 0.5, 0.5, ok);
            compare(m.motionAlpha, m.fillAlpha, st);
        }
        const paused = M.resolve("blur", 0.5, 0.15, { blurAvailable: true, easeEffects: true });
        compare(paused.motionAlpha, paused.fillAlpha, "no blur to wait for: nothing changes at rest");
    }
}
