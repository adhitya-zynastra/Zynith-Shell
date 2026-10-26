#pragma once

#include "render/animation/animation.h"
#include "render/animation/motion_physics.h"
#include "render/animation/motion_role.h"

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

class AnimationManager {
public:
  using Id = std::uint32_t;

  AnimationManager();
  ~AnimationManager();

  AnimationManager(const AnimationManager&) = delete;
  AnimationManager& operator=(const AnimationManager&) = delete;
  AnimationManager(AnimationManager&&) = delete;
  AnimationManager& operator=(AnimationManager&&) = delete;

  Id animate(
      float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
      std::function<void()> onComplete = {}, const void* owner = nullptr
  );
  // Real elapsed-time driver: ignores global motion enable/speed. Use for timeouts,
  // and for visual effects with a deliberate fixed duration that must stay independent
  // of the global animation settings (e.g. the wallpaper crossfade).
  Id animateTimer(
      float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
      std::function<void()> onComplete = {}, const void* owner = nullptr
  );
  // zynith motion language. The role decides the model (tween or spring), its parameters, its start
  // delay and what reduced motion does (motion_role.h). Prefer this over raw animate() in new code.
  Id animate(
      motion::Role role, float from, float to, std::function<void(float)> setter, std::function<void()> onComplete = {},
      const void* owner = nullptr
  );
  // A damped spring from `from` toward `to`, starting with `initialVelocity` (units/s). Its frequency is
  // scaled by the global motion speed; reduced motion lands it on `to`. Same entry list, same tick,
  // same ownership rules as a tween: this is a second kind of entry, not a second engine.
  Id animateSpring(
      float from, float to, motion::SpringParams params, std::function<void(float)> setter,
      std::function<void()> onComplete = {}, const void* owner = nullptr, float initialVelocity = 0.0F
  );

  struct Sample {
    float value = 0.0F;
    float velocity = 0.0F; // units per second
    bool spring = false;
  };
  // Current value and velocity of a live animation, or nothing if it finished or was cancelled.
  [[nodiscard]] std::optional<Sample> sample(Id id) const;
  // Points a live animation at a new end value without restarting it. A spring keeps its position AND
  // velocity; a tween restarts its curve from its current value (position continuity only). Returns
  // false when `id` is no longer live, so callers start a new animation instead.
  bool retarget(Id id, float to);

  void cancel(Id id);
  void cancelAll();
  void reduceMotion();
  // Cancels any animations tagged with the given owner. Called from Node's destructor so that
  // animations holding a raw pointer to a scene node can never outlive their target.
  void cancelForOwner(const void* owner);
  void tick(float deltaMs);
  [[nodiscard]] bool hasActive() const;

private:
  struct Entry {
    Id id = 0;
    const void* owner = nullptr;
    bool respectMotionEnabled = true;
    // Cancelled while a tick was walking the list. The callables are kept until
    // the tick unwinds — an animation can be cancelled by its own setter.
    bool dead = false;
    Animation animation;
    // Spring entries advance a damped oscillator from wall time instead of evaluating a curve.
    // animation.endValue is the target; animation.startedAt is when it may start moving (a role
    // delay); lastStep is the wall time the state was last advanced to.
    bool spring = false;
    motion::SpringParams springParams{};
    motion::SpringState springState{};
    float restEpsilon = 0.0F;
    std::chrono::steady_clock::time_point lastStep{};
  };

  std::vector<Entry> m_animations;
  // Animations created while tick() is running. A setter can start a new
  // animation (directly, or by rebuilding UI that does), and appending to
  // m_animations mid-tick would reallocate the vector the tick is walking —
  // including the std::function it is currently executing. They are merged in
  // when the tick finishes.
  std::vector<Entry> m_pending;
  // Non-zero while tick() is dispatching setters.
  int m_tickDepth = 0;
  Id m_nextId = 1;

  // Marks an entry dead instead of erasing it, so a cancel inside a tick cannot
  // move the elements the tick is iterating, and never destroys a callable that
  // is currently running.
  static void killEntry(Entry& entry);

  Id animateInternal(
      float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
      std::function<void()> onComplete, const void* owner, bool scaleDuration, bool respectMotionEnabled,
      float delayMs = 0.0F
  );
  [[nodiscard]] Entry* findLive(Id id);
  [[nodiscard]] const Entry* findLive(Id id) const;
  [[nodiscard]] static Sample sampleEntry(const Entry& entry, std::chrono::steady_clock::time_point now);
};
