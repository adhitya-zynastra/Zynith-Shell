#pragma once

#include "render/animation/animation.h"
#include "render/animation/motion_physics.h"

#include <array>
#include <cstdint>
#include <string_view>

// zynith motion language: the semantic roles every animation in the shell should be chosen by.
//
// A call site names WHY something moves (a surface arriving, an element travelling to a new slot, a
// hover state), and this table decides HOW: the model (a timed tween or a physical spring), its
// parameters, and what reduced motion does to it. Durations come from the Style motion tokens, so the
// numbers keep one owner, and [shell.animation].speed applies to every role exactly as it applied to
// raw animate() calls (tween durations divide by it; spring frequencies multiply by it).
//
// The role set was derived from what the shell actually animated before roles existed (72 call
// sites, grouped by duration and curve), then extended only where the motion evidence required it:
// ContentReveal/ContentDismiss for surface-first, content-second staging, and spring models for
// elements that can be retargeted mid-flight. See 02_Architecture/design/motion-language.md.
namespace motion {

  enum class Role : std::uint8_t {
    // Hover, press, toggle and focus-state changes: short, decelerating, never spatial.
    Focus,
    // A transient surface (panel, popover, OSD, toast) or returning chrome (an auto-hidden bar) arriving.
    SurfaceReveal,
    // The same leaving. Always shorter than the reveal and accelerating: nothing lingers once dismissed.
    SurfaceDismiss,
    // Content inside a surface that has just established itself: starts after a short delay.
    ContentReveal,
    // Content leaving a surface that stays (a section switching away).
    ContentDismiss,
    // A selection, indicator or item travelling to a new position. Retargetable with velocity kept.
    ElementMove,
    // A container reshaping to new content. Retargetable; settles slightly slower than a move.
    ElementResize,
    // The choreography of one surface changing state around a shared element (MorphTransition legs).
    Morph,
    // Whole-scene changes: wallpaper, full-screen compositions.
    SceneChange,
    // An overlay lifting off a scene that was already there (the unlock veil revealing the desktop). Symmetric
    // ease-in-out: the first frames change little, so what is underneath is uncovered rather than popped in.
    SceneReveal,
    Count,
  };

  enum class Model : std::uint8_t {
    Tween,  // duration + easing curve; retargets keep position, not velocity
    Spring, // damped oscillator; retargets keep position and velocity
  };

  // What reduced motion ([shell.animation].enabled = false) does to a role.
  enum class ReducedMotion : std::uint8_t {
    Snap,    // jump to the end state: spatial movement is removed
    Shorten, // keep the state change visible as a short fixed fade (reducedDurationMs), no movement
  };

  struct RoleSpec {
    std::string_view name;
    Model model = Model::Tween;
    float durationMs = 0.0F; // tweens; base value at tempo 1
    Easing easing = Easing::EaseOutCubic;
    SpringParams spring{}; // springs; omega at tempo 1
    float delayMs = 0.0F;  // start delay, scaled by tempo like the duration
    ReducedMotion reduced = ReducedMotion::Snap;
    float reducedDurationMs = 0.0F; // fixed; not scaled by tempo
  };

  [[nodiscard]] const RoleSpec& spec(Role role) noexcept;
  [[nodiscard]] std::string_view roleName(Role role) noexcept;

  inline constexpr std::size_t kRoleCount = static_cast<std::size_t>(Role::Count);

} // namespace motion
