#pragma once

// zynith motion physics: the pure maths behind spatial motion roles.
//
// A damped harmonic oscillator pulled toward a target:  x'' = -w^2 (x - target) - 2 z w x'
// with natural frequency `omega` (rad/s) and damping ratio `zeta`. zeta = 1 is critically damped (the
// fastest approach with no overshoot), zeta < 1 overshoots by exp(-pi z / sqrt(1 - z^2)), zeta > 1 is
// overdamped.
//
// step() advances the state by `dt` with the closed-form solution for a constant target, so the result
// is exact for any dt: a long compositor frame gap lands where wall time says the motion should be,
// with no integrator error and no instability. That matches how AnimationManager already advances
// tweens (from wall time, not from a frame count).
//
// Nothing here allocates, holds state or knows about the scene. AnimationManager owns every running
// spring; this header is only arithmetic, which is what lets it be tested deterministically.
namespace motion {

  struct SpringParams {
    float omega = 30.0F; // natural frequency, rad/s at tempo 1
    float zeta = 1.0F;   // damping ratio
  };

  struct SpringState {
    float position = 0.0F;
    float velocity = 0.0F; // units per second
  };

  // Advances `state` toward `target` by `dtSeconds`. Non-positive dt returns the state unchanged.
  [[nodiscard]] SpringState step(SpringState state, float target, SpringParams params, float dtSeconds) noexcept;

  // True once the spring is visually at rest: within `positionEpsilon` of the target and moving slower
  // than `positionEpsilon * omega` per second (so a fast pass through the target is not mistaken for
  // rest).
  [[nodiscard]] bool atRest(SpringState state, float target, SpringParams params, float positionEpsilon) noexcept;

  // Peak overshoot as a fraction of the travelled distance for a spring released from rest (0 when
  // zeta >= 1).
  [[nodiscard]] float peakOvershoot(SpringParams params) noexcept;

  // Time for a spring released from rest to settle within `fraction` of the distance and stay there,
  // found by sampling the analytic response; used by tests and documentation, never per frame.
  [[nodiscard]] float settleTimeSeconds(SpringParams params, float fraction) noexcept;

} // namespace motion
