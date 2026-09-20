#pragma once

#include <chrono>
#include <cstdint>
#include <functional>

enum class Easing : std::uint8_t {
  Linear,
  EaseInQuad,
  EaseOutQuad,
  EaseInOutQuad,
  EaseOutCubic,
  EaseInOutCubic,
  EaseOutBack,
  // Long-tail curves: most of the distance is covered immediately, then the
  // motion settles slowly. Reads as responsive and liquid at the same time,
  // which shorter cubic curves cannot do at the same duration.
  EaseOutQuint,
  EaseInOutQuint,
  EaseOutExpo,
};

float applyEasing(Easing easing, float t);

struct Animation {
  float startValue = 0.0F;
  float endValue = 0.0F;
  float durationMs = 0.0F;
  float elapsedMs = 0.0F;
  std::chrono::steady_clock::time_point startedAt;
  Easing easing = Easing::EaseOutQuad;
  std::function<void(float)> setter;
  std::function<void()> onComplete;
  bool finished = false;
};
