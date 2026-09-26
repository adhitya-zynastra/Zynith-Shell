#include "ui/tokens.h"

#include "ui/style.h"

#include <algorithm>
#include <array>

namespace ui::tokens {

  namespace {
    constexpr std::array<float, 8> kSpace = {4.0F, 8.0F, 12.0F, 16.0F, 24.0F, 32.0F, 48.0F, 64.0F};
    // Before tokens, panels, toasts and the wallpaper browser each carried this rule as a private copy.
    constexpr float kSurfaceRadiusFloor = 16.0F;
  } // namespace

  float space(Space step, float scale) noexcept {
    const auto index = static_cast<std::size_t>(step);
    return kSpace[std::min(index, kSpace.size() - 1)] * scale;
  }

  float radius(Radius family, float scale) noexcept {
    switch (family) {
    case Radius::Surface:
      // Clearly rounded at any corner scale: the themed radius, with a floor so a low
      // corner_radius_scale never turns a floating surface into a hard rectangle.
      return std::max(Style::scaledRadiusXl(scale), kSurfaceRadiusFloor * scale);
    case Radius::Plate:
      return Style::scaledRadiusXl(scale);
    case Radius::Control:
      return Style::scaledRadiusLg(scale);
    case Radius::Stage:
      return 0.0F;
    }
    return Style::scaledRadiusXl(scale);
  }

  float concentric(float parentRadius, float inset, float floor) noexcept {
    return std::max(parentRadius - inset, floor);
  }

  float controlHeight(Size size, float scale) noexcept {
    switch (size) {
    case Size::Small:
      return Style::controlHeightSm * scale;
    case Size::Medium:
      return Style::controlHeight * scale;
    case Size::Large:
      return Style::controlHeightLg * scale;
    }
    return Style::controlHeight * scale;
  }

  float iconSize(Size size, float scale) noexcept {
    constexpr std::array<float, 3> kIcon = {16.0F, 20.0F, 24.0F};
    return kIcon[static_cast<std::size_t>(size)] * scale;
  }

  float iconContainer(Size size, float scale) noexcept {
    constexpr std::array<float, 3> kContainer = {32.0F, 40.0F, 48.0F};
    return kContainer[static_cast<std::size_t>(size)] * scale;
  }

} // namespace ui::tokens
