#include "ui/semantic_color.h"

#include <algorithm>
#include <cmath>

namespace ui::color {

  ColorSpec spec(Semantic semantic) noexcept {
    switch (semantic) {
    case Semantic::Accent:
      return colorSpecFromRole(ColorRole::Primary);
    case Semantic::OnAccent:
      return colorSpecFromRole(ColorRole::OnPrimary);
    case Semantic::Surface:
      return colorSpecFromRole(ColorRole::Surface);
    case Semantic::OnSurface:
      return colorSpecFromRole(ColorRole::OnSurface);
    case Semantic::Muted:
      return colorSpecFromRole(ColorRole::OnSurfaceVariant);
    case Semantic::Hairline:
      return colorSpecFromRole(ColorRole::OnSurface, 0.12F);
    case Semantic::Error:
    case Semantic::Warning:
      return colorSpecFromRole(ColorRole::Error);
    case Semantic::OnError:
      return colorSpecFromRole(ColorRole::OnError);
    case Semantic::SelectionFill:
      // The Control Center navigation indicator's values: tinted enough to read as selected on any
      // wallpaper-derived palette, light enough that text on it keeps its own colour.
      return colorSpecFromRole(ColorRole::Primary, 0.16F);
    case Semantic::SelectionEdge:
      return colorSpecFromRole(ColorRole::Primary, 0.5F);
    case Semantic::Scrim:
      // The live modal backdrop's dimming strength.
      return colorSpecFromRole(ColorRole::Shadow, 0.46F);
    case Semantic::Count:
      break;
    }
    return colorSpecFromRole(ColorRole::OnSurface);
  }

  float contrastRatio(const Color& a, const Color& b) noexcept {
    const float la = ::relativeLuminance(a);
    const float lb = ::relativeLuminance(b);
    const float hi = std::max(la, lb);
    const float lo = std::min(la, lb);
    return (hi + 0.05F) / (lo + 0.05F);
  }

  Legible legibleOn(
      const Color& background, const Color& preferred, float minRatio, const Color& light, const Color& dark
  ) noexcept {
    const float preferredRatio = contrastRatio(preferred, background);
    if (preferredRatio >= minRatio) {
      return {.color = preferred, .ratio = preferredRatio, .meets = true, .needsScrim = false};
    }
    const float lightRatio = contrastRatio(light, background);
    const float darkRatio = contrastRatio(dark, background);
    const bool useLight = lightRatio >= darkRatio;
    const float best = useLight ? lightRatio : darkRatio;
    return {
        .color = useLight ? light : dark,
        .ratio = best,
        .meets = best >= minRatio,
        .needsScrim = best < minRatio,
    };
  }

  Legible legibleOn(const Color& background, ColorRole preferred, float minRatio) noexcept {
    const Color onSurface = colorForRole(ColorRole::OnSurface);
    const Color surface = colorForRole(ColorRole::Surface);
    const bool onSurfaceIsLight = ::relativeLuminance(onSurface) >= ::relativeLuminance(surface);
    return legibleOn(
        background, colorForRole(preferred), minRatio, onSurfaceIsLight ? onSurface : surface,
        onSurfaceIsLight ? surface : onSurface
    );
  }

} // namespace ui::color
