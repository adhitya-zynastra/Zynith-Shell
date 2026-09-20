#pragma once

#include "render/animation/animation.h"

#include <cstdint>
#include <functional>
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
    Animation animation;
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

  // Marks an entry dead instead of erasing it, so a cancel that happens inside
  // a tick cannot move the elements the tick is iterating.
  static void killEntry(Entry& entry);

  Id animateInternal(
      float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
      std::function<void()> onComplete, const void* owner, bool scaleDuration, bool respectMotionEnabled
  );
};
