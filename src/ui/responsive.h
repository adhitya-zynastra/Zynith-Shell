#pragma once

#include <algorithm>
#include <cstddef>

// Zynith responsive layout: the smallest set of rules components need to size themselves from the
// space they actually get, instead of from numbers tuned on one 1920x1200 laptop.
//
// Units are logical pixels, which already account for the output's scale factor (Wayland hands the
// shell logical sizes). `uiScale` is the separate accessibility scale the user can set, and it
// multiplies preferences, not available space.
//
// Deliberately small: an extent, a fit count and a density factor. No layout engine, no constraint
// solver, no per-frame work — callers resolve these when their available size or configuration
// changes and cache the result like any other layout value.
namespace ui::responsive {

  // What a component would like, and the bounds it tolerates, before the UI scale.
  struct Extent {
    float min = 0.0F;
    float preferred = 0.0F;
    float max = 0.0F;
  };

  // Resolves an extent against the space actually available.
  //
  //   1. The preference, scaled, clamped into [min, max] (also scaled).
  //   2. Never more than `maxFraction` of the available space, so a component cannot crowd out
  //      everything around it on a small display.
  //   3. Never more than the available space itself; never below 1.
  //
  // The minimum yields to the available space (step 3) rather than overflowing it: a too-small
  // display gets a smaller component, not one that spills off the edge.
  [[nodiscard]] constexpr float
  resolve(const Extent& extent, float available, float uiScale = 1.0F, float maxFraction = 1.0F) noexcept {
    const float s = uiScale > 0.0F ? uiScale : 1.0F;
    const float lo = extent.min * s;
    const float hi = std::max(lo, extent.max * s);
    float value = std::clamp(extent.preferred * s, lo, hi);
    if (available > 0.0F) {
      value = std::min(value, available * std::clamp(maxFraction, 0.0F, 1.0F));
      value = std::min(value, available);
    }
    return std::max(1.0F, value);
  }

  // How many items of `item` width, separated by `gap`, fit in `available`, bounded to
  // [minCount, maxCount]. `minCount` wins over the geometry: callers that must show at least one
  // item get one even if it is squeezed.
  [[nodiscard]] constexpr std::size_t
  fitCount(float available, float item, float gap, std::size_t minCount, std::size_t maxCount) noexcept {
    std::size_t n = 0;
    if (item > 0.0F && available >= item) {
      // A negative gap is treated as zero, so the step can never reach zero and divide by it.
      const float step = item + std::max(0.0F, gap);
      n = 1 + static_cast<std::size_t>((available - item) / step);
    }
    return std::clamp(n, minCount, std::max(minCount, maxCount));
  }

  // Spacing for a base token at a density factor (see layoutDensityFactor) and UI scale.
  [[nodiscard]] constexpr float space(float base, float densityFactor, float uiScale = 1.0F) noexcept {
    return base * std::max(0.0F, densityFactor) * (uiScale > 0.0F ? uiScale : 1.0F);
  }

} // namespace ui::responsive
