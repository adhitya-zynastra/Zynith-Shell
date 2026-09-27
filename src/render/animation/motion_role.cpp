#include "render/animation/motion_role.h"

#include "ui/style.h"

namespace motion {

  namespace {

    constexpr float kReducedFadeMs = 90.0F;

    // Spring frequencies were chosen so each spring settles (within 1 % of its travel) in about the
    // time the tween it replaces took to get there: EaseOutCubic over animNormal reaches 99 % at
    // ~235 ms; a critically damped spring at omega 30 settles in ~221 ms, at 26 in ~255 ms. Measured
    // references cluster at 180-240 ms for element travel (design-research-2026-09.md, M1/M2/M5/M10).
    // Critically damped: no overshoot. A selection or container should arrive, not bounce.
    const std::array<RoleSpec, kRoleCount> kSpecs = {{
        {.name = "focus",
         .model = Model::Tween,
         .durationMs = static_cast<float>(Style::animFast),
         .easing = Easing::EaseOutCubic,
         .reduced = ReducedMotion::Shorten,
         .reducedDurationMs = kReducedFadeMs},
        {.name = "surface-reveal",
         .model = Model::Tween,
         .durationMs = static_cast<float>(Style::animNormal),
         .easing = Easing::EaseOutQuint,
         .reduced = ReducedMotion::Snap},
        {.name = "surface-dismiss",
         .model = Model::Tween,
         .durationMs = static_cast<float>(Style::animExit),
         .easing = Easing::EaseInQuad,
         .reduced = ReducedMotion::Snap},
        {.name = "content-reveal",
         .model = Model::Tween,
         .durationMs = 150.0F,
         .easing = Easing::EaseOutCubic,
         .delayMs = 50.0F,
         .reduced = ReducedMotion::Shorten,
         .reducedDurationMs = kReducedFadeMs},
        {.name = "content-dismiss",
         .model = Model::Tween,
         .durationMs = 100.0F,
         .easing = Easing::EaseInQuad,
         .reduced = ReducedMotion::Shorten,
         .reducedDurationMs = kReducedFadeMs},
        {.name = "element-move",
         .model = Model::Spring,
         .spring = {.omega = 30.0F, .zeta = 1.0F},
         .reduced = ReducedMotion::Snap},
        {.name = "element-resize",
         .model = Model::Spring,
         .spring = {.omega = 26.0F, .zeta = 1.0F},
         .reduced = ReducedMotion::Snap},
        {.name = "morph",
         .model = Model::Tween,
         .durationMs = static_cast<float>(Style::animNormal),
         .easing = Easing::EaseOutQuint,
         .reduced = ReducedMotion::Snap},
        {.name = "scene-change",
         .model = Model::Tween,
         .durationMs = static_cast<float>(Style::animSlow),
         .easing = Easing::EaseOutCubic,
         .reduced = ReducedMotion::Shorten,
         .reducedDurationMs = 150.0F},
        {.name = "scene-reveal",
         .model = Model::Tween,
         .durationMs = 420.0F,
         .easing = Easing::EaseInOutCubic,
         .reduced = ReducedMotion::Shorten,
         .reducedDurationMs = 150.0F},
    }};

  } // namespace

  const RoleSpec& spec(Role role) noexcept {
    const auto index = static_cast<std::size_t>(role);
    return kSpecs[index < kRoleCount ? index : 0];
  }

  std::string_view roleName(Role role) noexcept { return spec(role).name; }

} // namespace motion
