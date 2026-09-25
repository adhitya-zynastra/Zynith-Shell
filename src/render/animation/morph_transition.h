#pragma once

#include "render/animation/animation.h"
#include "render/animation/animation_manager.h"

#include <functional>

// One interruptible, retargetable 0 -> 1 transition leg.
//
// This is deliberately NOT an animation engine. It owns no timer, no scheduler and no
// per-frame loop; it is a small amount of bookkeeping around a single
// AnimationManager::animate() call. The manager remains the only thing that advances time.
//
// What it adds over calling animate() directly is the one property that makes a transition
// read as continuous rather than as a restart: when the target changes mid-flight, the new
// leg begins from the state the content is ACTUALLY in, not from the original start state.
//
//   A ────────●──────> B          user reverses at ●
//             │
//             └────────> A        the reversal starts from ●, not from B
//
// The caller supplies that state as `carry`, read from the live scene immediately before
// calling start(). MorphTransition does not inspect the scene graph itself — it has no
// opinion about what is being morphed, which is what lets the Control Center, and later the
// launcher and lock screen, share it without sharing a layout model.
//
// Lifetime contract:
//
//   * start() tags the underlying animation with `owner`, so a Node destructor's
//     cancelForOwner() reaches it when the scene node being morphed goes away.
//   * The destructor cancels, so a running leg cannot call back into a destroyed
//     MorphTransition.
//   * The frame and settle callables are owned by AnimationManager, not by this object.
//     That is deliberate: start() may legitimately be re-entered from inside onFrame (a
//     rapid retarget), and a member std::function released at that moment would destroy the
//     callable whose operator() is on the stack. The manager already solves this — a cancel
//     during a tick only tombstones the entry, keeping its callables alive until the tick
//     unwinds, and a tombstoned entry is never stepped again and never fires its completion.
//   * Consequently a retargeted leg's onSettle does NOT run. Only the leg that reaches
//     progress 1.0 settles.
class MorphTransition {
public:
  MorphTransition() = default;
  ~MorphTransition();

  MorphTransition(const MorphTransition&) = delete;
  MorphTransition& operator=(const MorphTransition&) = delete;
  MorphTransition(MorphTransition&&) = delete;
  MorphTransition& operator=(MorphTransition&&) = delete;

  // `owner` is passed through to AnimationManager so node destruction cancels the leg.
  void bind(AnimationManager* animations, const void* owner);

  // Starts a leg, cancelling any leg already running. Safe to call from inside `onFrame`
  // of the running leg: the manager tombstones a cancelled entry and keeps its callables
  // alive until the tick unwinds.
  //
  // `direction` is carried for the caller's benefit only (+1 / -1 by convention); this class
  // never interprets it. `carry` likewise — it is stored and handed back, not applied.
  void start(
      int direction, float carry, float durationMs, Easing easing, std::function<void(float)> onFrame,
      std::function<void()> onSettle
  );

  // Stops the leg without running onSettle. Idempotent.
  void cancel();

  [[nodiscard]] bool active() const noexcept { return m_active; }
  [[nodiscard]] float progress() const noexcept { return m_progress; }
  [[nodiscard]] int direction() const noexcept { return m_direction; }
  [[nodiscard]] float carry() const noexcept { return m_carry; }

private:
  AnimationManager* m_animations = nullptr;
  const void* m_owner = nullptr;

  AnimationManager::Id m_id = 0;
  bool m_active = false;
  float m_progress = 1.0F;
  int m_direction = 1;
  float m_carry = 0.0F;

};
