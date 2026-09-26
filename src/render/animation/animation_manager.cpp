#include "render/animation/animation_manager.h"

#include "render/animation/motion_service.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iterator>

namespace {
  constexpr float kReducedMotionDurationMs = 1.0F;

  // A spring is "at rest" within 0.4 % of its travel (never less than 0.001, never more than half a
  // unit): for pixel geometry that is at most half a pixel, so the final snap onto the target is
  // invisible, and the entry stops requesting frames promptly after it looks finished.
  float springRestEpsilon(float span) {
    return std::clamp(std::abs(span) * 0.004F, 0.001F, 0.5F);
  }

  std::chrono::steady_clock::duration msDuration(float ms) {
    return std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<float, std::milli>(ms));
  }
} // namespace

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
    std::function<void()> onComplete, const void* owner, bool scaleDuration, bool respectMotionEnabled,
    float delayMs
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
  // A role delay postpones the start; tick() holds the value at `from` until then.
  const float effectiveDelayMs = reduceMotion ? 0.0F : std::max(0.0F, scaleDuration ? delayMs / motion.speed() : delayMs);
  const auto now = std::chrono::steady_clock::now() + msDuration(effectiveDelayMs);
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

AnimationManager::Id AnimationManager::animate(
    motion::Role role, float from, float to, std::function<void(float)> setter, std::function<void()> onComplete,
    const void* owner
) {
  const auto& spec = motion::spec(role);
  if (!MotionService::instance().enabled()) {
    // Reduced motion. Snap roles land on the end state; Shorten roles keep the state change legible as
    // a short fade on real time, independent of the (disabled) motion settings.
    if (spec.reduced == motion::ReducedMotion::Shorten && spec.reducedDurationMs > 0.0F) {
      return animateInternal(
          from, to, spec.reducedDurationMs, Easing::EaseOutQuad, std::move(setter), std::move(onComplete), owner,
          false, false
      );
    }
    return animateInternal(from, to, 0.0F, spec.easing, std::move(setter), std::move(onComplete), owner, true, true);
  }
  if (spec.model == motion::Model::Spring) {
    return animateSpring(from, to, spec.spring, std::move(setter), std::move(onComplete), owner);
  }
  return animateInternal(
      from, to, spec.durationMs, spec.easing, std::move(setter), std::move(onComplete), owner, true, true, spec.delayMs
  );
}

AnimationManager::Id AnimationManager::animateSpring(
    float from, float to, motion::SpringParams params, std::function<void(float)> setter,
    std::function<void()> onComplete, const void* owner, float initialVelocity
) {
  if (!MotionService::instance().enabled() || !(params.omega > 0.0F)) {
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
  std::vector<Entry>& sink = m_tickDepth > 0 ? m_pending : m_animations;
  Entry entry{
      .id = id,
      .owner = owner,
      .respectMotionEnabled = true,
      .animation = Animation{
          .startValue = from,
          .endValue = to,
          .startedAt = now,
          .setter = std::move(setter),
          .onComplete = std::move(onComplete),
      },
  };
  entry.spring = true;
  entry.springParams = params;
  entry.springState = motion::SpringState{.position = from, .velocity = initialVelocity};
  entry.restEpsilon = springRestEpsilon(to - from);
  entry.lastStep = now;
  sink.push_back(std::move(entry));
  return id;
}

AnimationManager::Entry* AnimationManager::findLive(Id id) {
  if (id == 0) {
    return nullptr;
  }
  for (auto* list : {&m_animations, &m_pending}) {
    for (auto& entry : *list) {
      if (entry.id == id && !entry.dead && !entry.animation.finished) {
        return &entry;
      }
    }
  }
  return nullptr;
}

const AnimationManager::Entry* AnimationManager::findLive(Id id) const {
  return const_cast<AnimationManager*>(this)->findLive(id);
}

AnimationManager::Sample AnimationManager::sampleEntry(const Entry& entry, std::chrono::steady_clock::time_point now) {
  if (entry.spring) {
    return Sample{.value = entry.springState.position, .velocity = entry.springState.velocity, .spring = true};
  }
  const auto& anim = entry.animation;
  const float span = anim.endValue - anim.startValue;
  if (anim.durationMs <= 0.0F) {
    return Sample{.value = anim.endValue};
  }
  const float elapsed = std::chrono::duration<float, std::milli>(now - anim.startedAt).count();
  const float t = std::clamp(elapsed / anim.durationMs, 0.0F, 1.0F);
  // Velocity of a tween: the easing's slope (finite difference) times span per millisecond.
  constexpr float kProbe = 0.002F;
  const float t0 = std::max(0.0F, t - kProbe);
  const float t1 = std::min(1.0F, t + kProbe);
  const float slope = t1 > t0 ? (applyEasing(anim.easing, t1) - applyEasing(anim.easing, t0)) / (t1 - t0) : 0.0F;
  return Sample{
      .value = anim.startValue + span * applyEasing(anim.easing, t),
      .velocity = slope * span / anim.durationMs * 1000.0F,
  };
}

std::optional<AnimationManager::Sample> AnimationManager::sample(Id id) const {
  const Entry* entry = findLive(id);
  if (entry == nullptr) {
    return std::nullopt;
  }
  return sampleEntry(*entry, std::chrono::steady_clock::now());
}

bool AnimationManager::retarget(Id id, float to) {
  Entry* entry = findLive(id);
  if (entry == nullptr) {
    return false;
  }
  auto& anim = entry->animation;
  if (entry->spring) {
    // Position and velocity are untouched: the motion bends toward the new target from where, and as
    // fast as, it is actually going. The rest threshold follows the larger of the old and new travel.
    entry->restEpsilon = std::max(entry->restEpsilon, springRestEpsilon(to - entry->springState.position));
    anim.endValue = to;
    return true;
  }
  const auto now = std::chrono::steady_clock::now();
  const float current = sampleEntry(*entry, now).value;
  anim.startValue = current;
  anim.endValue = to;
  anim.elapsedMs = 0.0F;
  anim.startedAt = now;
  return true;
}

void AnimationManager::killEntry(Entry& entry) {
  // Keep the callables: this can be called from inside the very setter that is
  // running (a node destroyed by its own animation). They die with the entry
  // when the tick reaps it.
  entry.dead = true;
  entry.animation.finished = true;
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
      m_animations[i].animation.setter(endValue);
    }
    if (i >= m_animations.size() || m_animations[i].dead || m_animations[i].animation.finished) {
      continue; // cancelled by its own setter
    }
    auto& anim = m_animations[i].animation;
    if (m_animations[i].spring) {
      // The next tick finds it at rest on its target and finishes it.
      m_animations[i].springState = motion::SpringState{.position = anim.endValue, .velocity = 0.0F};
      continue;
    }
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

    if (m_animations[i].spring) {
      Entry& e = m_animations[i];
      if (now < e.animation.startedAt) {
        continue; // role delay: not moving yet
      }
      const float dt = std::chrono::duration<float>(now - std::max(e.lastStep, e.animation.startedAt)).count();
      e.lastStep = now;
      motion::SpringParams params = e.springParams;
      params.omega *= MotionService::instance().speed();
      e.springState = motion::step(e.springState, e.animation.endValue, params, dt);
      bool springDone = false;
      if (motion::atRest(e.springState, e.animation.endValue, params, e.restEpsilon)) {
        e.springState = motion::SpringState{.position = e.animation.endValue, .velocity = 0.0F};
        e.animation.finished = true;
        springDone = true;
      }
      if (e.animation.setter) {
        e.animation.setter(e.springState.position);
      }
      if (springDone && i < m_animations.size() && !m_animations[i].dead && m_animations[i].animation.onComplete) {
        completedCallbacks.push_back(std::move(m_animations[i].animation.onComplete));
      }
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

    // Invoked in place: the vector cannot move during a tick (additions are
    // parked in m_pending, cancels only mark entries dead), so no copy of the
    // callable is needed — that copy was a heap allocation per animation per
    // frame.
    if (m_animations[i].animation.setter) {
      m_animations[i].animation.setter(value);
    }

    // Re-read: the setter may have marked this entry dead (node destroyed, or an
    // explicit cancel), in which case its completion must not fire.
    if (finished && i < m_animations.size() && !m_animations[i].dead
        && m_animations[i].animation.onComplete) {
      completedCallbacks.push_back(std::move(m_animations[i].animation.onComplete));
    }
  }

  --m_tickDepth;

  std::erase_if(m_animations, [](const Entry& e) { return e.animation.finished || e.dead; });
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
