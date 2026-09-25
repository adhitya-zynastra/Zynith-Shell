#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>

// The carousel's orbit, as pure arithmetic: no scene nodes, no renderer, so the responsive
// behaviour is unit-testable at display sizes the development machine does not have.
namespace ui::carousel {

  // Total angle of one side of the arc. The depth curve (scale, opacity, sink) is normalised over
  // it, so far-edge cards look the same whatever the viewport holds. How many cards share the angle
  // is resolved per layout by fitArc(): 1920 px with a 760 px card gives two per side at 21 degrees
  // each — the original tuning — and a wider output spreads the same arc over more cards.
  inline constexpr float kArcAngleRad = 3.0F * 0.3665F; // 63 degrees
  // Far-edge appearance.
  inline constexpr float kMinItemScale = 0.52F;
  // < 1 makes the first neighbour recede decisively instead of shadowing the focus.
  inline constexpr float kScaleFalloffExp = 0.6F;
  // Below this drawn scale a card is noise rather than a preview: the arc ends.
  inline constexpr float kLegibleScale = 0.42F;
  // Nearer cards paint over farther ones, so a neighbour only counts if at least this much of its
  // drawn width shows past the card in front of it (and inside the viewport). Anything less is a
  // sliver the eye does not read as a wallpaper. The laptop's outer pair shows about 25 %.
  inline constexpr float kMinExposedFraction = 0.2F;
  // Hard ceiling on the working set, whatever the geometry asks for. Six per side is already a
  // 13-card arc — past that a wider output gets a larger margin rather than more cards.
  inline constexpr std::size_t kMaxPerSide = 6;

  // 0 at the focus, 1 at the end of the arc.
  [[nodiscard]] inline float depthAt(float theta) noexcept {
    const float span = 1.0F - std::cos(kArcAngleRad);
    return span <= 0.0F ? 0.0F : std::clamp((1.0F - std::cos(theta)) / span, 0.0F, 1.0F);
  }

  [[nodiscard]] inline float scaleAt(float depth) noexcept {
    return 1.0F - (1.0F - kMinItemScale) * std::pow(depth, kScaleFalloffExp);
  }

  struct ArcFit {
    std::size_t perSide = 0; // visible cards on each side of the focus
    float angleStep = kArcAngleRad; // angle between neighbouring cards
  };

  // For a candidate N the arc is spread over N + 1 steps (the extra step is the preload card just
  // past the edge), with the orbit radius chosen so travel near the focus equals one stride. The
  // radius therefore grows with N and a wider viewport reaches further. A candidate fits when every
  // card on its side is legible and shows enough of itself past the card in front of it; the step
  // changes with N, so each candidate is checked in full. Keeps the largest N before the first
  // miss. At most kMaxPerSide^2 / 2 iterations, once per layout.
  [[nodiscard]] inline ArcFit fitArc(float viewportWidth, float cellW, float stride) noexcept {
    ArcFit fit;
    if (viewportWidth <= 0.0F || cellW <= 0.0F || stride <= 0.0F) {
      return fit;
    }
    const float centre = viewportWidth * 0.5F;
    for (std::size_t n = 1; n <= kMaxPerSide; ++n) {
      const float step = kArcAngleRad / static_cast<float>(n + 1);
      const float radius = stride / step;
      bool fits = true;
      float nearerEdge = centre + cellW * 0.5F; // outer edge of the card in front: the focus first
      for (std::size_t k = 1; k <= n && fits; ++k) {
        const float theta = static_cast<float>(k) * step;
        const float scale = scaleAt(depthAt(theta));
        const float half = cellW * scale * 0.5F;
        const float x = centre + radius * std::sin(theta);
        const float exposed = std::min(x + half, viewportWidth) - std::max(x - half, nearerEdge);
        fits = scale >= kLegibleScale && exposed >= kMinExposedFraction * 2.0F * half;
        nearerEdge = std::max(nearerEdge, x + half);
      }
      if (!fits) {
        break;
      }
      fit.perSide = n;
    }
    fit.angleStep = kArcAngleRad / static_cast<float>(fit.perSide + 1);
    return fit;
  }

} // namespace ui::carousel
