// Zynith glass: the shared surface model and the palette tint it relies on.
//
// Checks that the model reproduces the pre-glass panel look by default, that every property does
// what it says, and that a tint stays a palette ROLE — resolved against whatever palette is live,
// so it follows a wallpaper change instead of freezing the colour it had when it was set.

#include "config/config_types.h"
#include "shell/surface/glass.h"
#include "ui/palette.h"

#include <cmath>
#include <iostream>

namespace {

  int failures = 0;

  void check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
  }

  bool near(float a, float b) { return std::fabs(a - b) < 1e-4F; }

  Palette testPalette(Color surface, Color primary, Color outline) {
    Palette p{};
    p.surface = surface;
    p.primary = primary;
    p.outline = outline;
    p.secondary = Color{0.0F, 1.0F, 0.0F, 1.0F};
    return p;
  }

} // namespace

int main() {
  using namespace shell::glass;
  setPalette(testPalette({0.0F, 0.0F, 0.0F, 1.0F}, {1.0F, 1.0F, 1.0F, 1.0F}, {0.5F, 0.5F, 0.5F, 1.0F}));

  // --- default reproduces the pre-glass panel look -----------------------------------------
  {
    Config c;
    c.shell.panel.transparencyMode = PanelTransparencyMode::Glass;
    const float fill = fillOpacity(c);
    check(near(fill, 0.55F), "glass mode keeps its 0.55 fill");
    const auto s = panelSurface(c, fill);
    check(s.fill == colorSpecFromRole(ColorRole::Surface, 0.55F), "default fill is exactly the old Surface@0.55");
    check(s.borderColor == colorSpecFromRole(ColorRole::Outline, 0.55F), "default border is exactly the old Outline@fill");
    check(s.blur, "translucent glass requests blur");
  }

  // --- named modes unchanged; custom honours [shell.glass].opacity -------------------------
  {
    Config c;
    c.shell.panel.transparencyMode = PanelTransparencyMode::Solid;
    check(near(fillOpacity(c), 1.0F), "solid = 1.0");
    c.shell.panel.transparencyMode = PanelTransparencyMode::Soft;
    check(near(fillOpacity(c), 0.80F), "soft = 0.80");
    c.shell.panel.transparencyMode = PanelTransparencyMode::Custom;
    c.shell.glass.opacity = 0.30F;
    check(near(fillOpacity(c), 0.30F), "custom uses glass.opacity");
    c.shell.glass.opacity = 1.7F;
    check(near(fillOpacity(c), 1.0F), "custom opacity is clamped");
    check(near(panelCardOpacityForTransparencyMode(PanelTransparencyMode::Custom, 0.30F), 0.40F),
          "custom cards sit one step more opaque than the panel");
  }

  // --- blur gate: switched off, or behind an opaque fill, means no blur request -------------
  {
    Config c;
    check(!blurEnabled(c, 1.0F), "no blur behind an opaque fill");
    check(blurEnabled(c, 0.55F), "blur behind a translucent fill");
    c.shell.glass.blur = false;
    check(!blurEnabled(c, 0.55F), "no blur when glass blur is off");
  }

  // --- tint is a live role and mixes by strength ---------------------------------------------
  {
    Config c;
    c.shell.glass.tint = true;
    c.shell.glass.tintRole = GlassTintRole::Primary;
    c.shell.glass.tintStrength = 0.25F;
    const auto s = panelSurface(c, 0.5F);
    check(s.fill.tint == ColorRole::Primary, "tint is stored as a role, not a baked colour");
    const Color resolved = resolveColorSpec(s.fill);
    check(near(resolved.r, 0.25F) && near(resolved.g, 0.25F) && near(resolved.b, 0.25F),
          "black surface + white primary at 0.25 resolves to 0.25 grey");
    check(near(resolved.a, 0.5F), "tint never changes opacity");

    // The wallpaper changes: the same spec now resolves against the new palette.
    setPalette(testPalette({0.0F, 0.0F, 0.0F, 1.0F}, {1.0F, 0.0F, 0.0F, 1.0F}, {0.5F, 0.5F, 0.5F, 1.0F}));
    const Color after = resolveColorSpec(s.fill);
    check(near(after.r, 0.25F) && near(after.g, 0.0F), "the same tint follows a palette change");
    setPalette(testPalette({0.0F, 0.0F, 0.0F, 1.0F}, {1.0F, 1.0F, 1.0F, 1.0F}, {0.5F, 0.5F, 0.5F, 1.0F}));

    c.shell.glass.tint = false;
    check(!panelSurface(c, 0.5F).fill.tint.has_value(), "tint off leaves the fill untinted");
    c.shell.glass.tint = true;
    c.shell.glass.tintStrength = 0.0F;
    check(!panelSurface(c, 0.5F).fill.tint.has_value(), "zero strength is no tint");
  }

  // --- border colour role and opacity --------------------------------------------------------
  {
    Config c;
    c.shell.glass.borderRole = GlassBorderRole::Secondary;
    c.shell.glass.borderOpacity = 0.5F;
    const auto s = panelSurface(c, 0.8F);
    check(s.borderColor.role == ColorRole::Secondary, "border role is honoured");
    check(near(s.borderColor.alpha, 0.4F), "border opacity scales the fill's alpha");
    c.shell.panel.borders = false;
    check(!panelSurface(c, 0.8F).border, "border on/off stays owned by shell.panel.borders");
  }

  // --- role mapping covers every option --------------------------------------------------------
  {
    check(toColorRole(GlassTintRole::SurfaceVariant) == ColorRole::SurfaceVariant, "tint surface_variant");
    check(toColorRole(GlassBorderRole::Outline) == ColorRole::Outline, "border outline");
  }

  // --- ColorSpec equality includes the tint (so a changed tint re-applies) -------------------
  {
    const auto a = colorSpecFromRole(ColorRole::Surface, 0.5F);
    check(!(a == withTint(a, ColorRole::Primary, 0.1F)), "a tinted spec is not equal to the untinted one");
    check(withTint(a, ColorRole::Primary, 4.0F).tintStrength == 1.0F, "tint strength is clamped");
  }

  if (failures == 0) {
    std::cout << "glass surface test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
