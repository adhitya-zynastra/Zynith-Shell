#include "render/animation/animation_manager.h"

#include "render/animation/motion_service.h"

#include <chrono>
#include <iterator>

namespace {
  constexpr float kReducedMotionDurationMs = 1.0F;
}

AnimationManager::AnimationManager() { MotionService::instance().registerManager(this); }

AnimationManager::~AnimationManager() { MotionService::instance().unregisterManager(this); }

AnimationManager::Id AnimationManager::animate(
    float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
    std::function<void()> onComplete, const void* owner
) {
  return animateInternal(from, to, durationMs, easing, std::move(setter), std::move(onComplete), owner, true, true);
}

AnimationManager::Id AnimationManager::animateTimer(
    float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
    std::function<void()> onComplete, const void* owner
) {
  return animateInternal(from, to, durationMs, easing, std::move(setter), std::move(onComplete), owner, false, false);
}

AnimationManager::Id AnimationManager::animateInternal(
    float from, float to, float durationMs, Easing easing, std::function<void(float)> setter,
    std::function<void()> onComplete, const void* owner, bool scaleDuration, bool respectMotionEnabled
) {
  const auto& motion = MotionService::instance();
  const bool reduceMotion = respectMotionEnabled && !motion.enabled();
  if (reduceMotion) {
    if (setter) {
      setter(to);
    }
    if (!onComplete) {
      return 0;
    }
  }

  float effectiveDurationMs = scaleDuration ? durationMs / motion.speed() : durationMs;
  if (reduceMotion) {
    effectiveDurationMs = kReducedMotionDurationMs;
  }

  if (effectiveDurationMs <= 0.0F) {
    if (setter) {
      setter(to);
    }
    if (onComplete) {
      onComplete();
    }
    return 0;
  }

  Id id = m_nextId++;
  const auto now = std::chrono::steady_clock::now();
  // Started from inside a setter? Park it until the tick finishes walking.
  std::vector<Entry>& sink = m_tickDepth > 0 ? m_pending : m_animations;
  sink.push_back(
      Entry{
          .id = id,
          .owner = owner,
          .respectMotionEnabled = respectMotionEnabled,
          .animation = Animation{
              .startValue = reduceMotion ? to : from,
              .endValue = to,
              .durationMs = effectiveDurationMs,
              .startedAt = reduceMotion ? now
                      - std::chrono::duration_cast<std::chrono::steady_clock::duration>(
                                              std::chrono::duration<float, std::milli>(kReducedMotionDurationMs)
                      )
                                        : now,
              .easing = easing,
              .setter = std::move(setter),
              .onComplete = std::move(onComplete),
          },
      }
  );
  return id;
}

void AnimationManager::killEntry(Entry& entry) {
  entry.animation.finished = true;
  entry.animation.setter = nullptr;
  entry.animation.onComplete = nullptr;
  entry.owner = nullptr;
}

void AnimationManager::cancel(Id id) {
  if (m_tickDepth > 0) {
    for (auto& entry : m_animations) {
      if (entry.id == id) {
        killEntry(entry);
      }
    }
    std::erase_if(m_pending, [id](const Entry& e) { return e.id == id; });
    return;
  }
  std::erase_if(m_animations, [id](const Entry& e) { return e.id == id; });
  std::erase_if(m_pending, [id](const Entry& e) { return e.id == id; });
}

void AnimationManager::cancelAll() {
  if (m_tickDepth > 0) {
    for (auto& entry : m_animations) {
      killEntry(entry);
    }
    m_pending.clear();
    return;
  }
  m_animations.clear();
  m_pending.clear();
}

void AnimationManager::reduceMotion() {
  const auto now = std::chrono::steady_clock::now();
  // Same reentrancy contract as tick(): setters run shell code, so nothing may
  // move this vector while we walk it.
  ++m_tickDepth;
  for (std::size_t i = 0; i < m_animations.size(); ++i) {
    if (!m_animations[i].respectMotionEnabled || m_animations[i].animation.finished) {
      continue;
    }
    const float endValue = m_animations[i].animation.endValue;
    if (m_animations[i].animation.setter) {
      auto setter = m_animations[i].animation.setter;
      setter(endValue);
    }
    if (i >= m_animations.size() || m_animations[i].animation.finished) {
      continue; // cancelled by its own setter
    }
    auto& anim = m_animations[i].animation;
    anim.startValue = anim.endValue;
    anim.durationMs = kReducedMotionDurationMs;
    anim.elapsedMs = 0.0F;
    anim.startedAt = now
        - std::chrono::duration_cast<std::chrono::steady_clock::duration>(
                         std::chrono::duration<float, std::milli>(kReducedMotionDurationMs)
        );
  }
  --m_tickDepth;
  if (!m_pending.empty()) {
    m_animations.insert(m_animations.end(), std::make_move_iterator(m_pending.begin()),
                        std::make_move_iterator(m_pending.end()));
    m_pending.clear();
  }
}

void AnimationManager::cancelForOwner(const void* owner) {
  if (owner == nullptr) {
    return;
  }
  // Node destructors call this. During a tick the node may be destroyed *by* a
  // setter, so the entry is marked dead rather than erased: erasing would move
  // the vector elements (and the callable) the tick is running from.
  if (m_tickDepth > 0) {
    for (auto& entry : m_animations) {
      if (entry.owner == owner) {
        killEntry(entry);
      }
    }
    std::erase_if(m_pending, [owner](const Entry& e) { return e.owner == owner; });
    return;
  }
  std::erase_if(m_animations, [owner](const Entry& e) { return e.owner == owner; });
  std::erase_if(m_pending, [owner](const Entry& e) { return e.owner == owner; });
}

void AnimationManager::tick(float /*deltaMs*/) {
  // Setters run arbitrary shell code: they can start animations, cancel others,
  // and destroy nodes (whose destructors cancel animations). None of that may
  // move the storage this loop is walking, so for the duration of the tick
  // additions go to m_pending and cancels only mark entries dead. Indexing (not
  // iterators or references held across a call) keeps this valid.
  ++m_tickDepth;

  // onComplete may do the same, so it runs after the walk.
  std::vector<std::function<void()>> completedCallbacks;
  const auto now = std::chrono::steady_clock::now();

  for (std::size_t i = 0; i < m_animations.size(); ++i) {
    if (m_animations[i].animation.finished) {
      continue;
    }

    // Progress from wall time so a fixed duration stays correct when the compositor
    // delivers sparse `wl_surface.frame` callbacks (common right after cold boot).
    const float wallElapsedMs =
        std::chrono::duration<float, std::milli>(now - m_animations[i].animation.startedAt).count();
    m_animations[i].animation.elapsedMs = wallElapsedMs;
    const float duration = m_animations[i].animation.durationMs;
    float t = duration > 0.0F ? wallElapsedMs / duration : 1.0F;

    bool finished = false;
    if (t >= 1.0F) {
      t = 1.0F;
      finished = true;
      m_animations[i].animation.finished = true;
    }

    const float easedT = applyEasing(m_animations[i].animation.easing, t);
    const float value = m_animations[i].animation.startValue
        + (m_animations[i].animation.endValue - m_animations[i].animation.startValue) * easedT;

    if (m_animations[i].animation.setter) {
      // Copy the callable before invoking: it may cancel itself, and a dead
      // entry's std::function is cleared while it would otherwise be running.
      auto setter = m_animations[i].animation.setter;
      setter(value);
    }

    // Re-read: the setter may have marked this entry dead (node destroyed, or an
    // explicit cancel), in which case its completion must not fire.
    if (finished && !m_animations.empty() && i < m_animations.size() && m_animations[i].animation.onComplete) {
      completedCallbacks.push_back(std::move(m_animations[i].animation.onComplete));
    }
  }

  --m_tickDepth;

  std::erase_if(m_animations, [](const Entry& e) { return e.animation.finished; });
  if (!m_pending.empty()) {
    m_animations.insert(m_animations.end(), std::make_move_iterator(m_pending.begin()),
                        std::make_move_iterator(m_pending.end()));
    m_pending.clear();
  }

  for (auto& cb : completedCallbacks) {
    cb();
  }
}

bool AnimationManager::hasActive() const { return !m_animations.empty() || !m_pending.empty(); }
