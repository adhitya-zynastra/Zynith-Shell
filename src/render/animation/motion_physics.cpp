#include "render/animation/motion_physics.h"

#include <algorithm>
#include <cmath>

namespace motion {

  SpringState step(SpringState state, float target, SpringParams params, float dtSeconds) noexcept {
    if (!(dtSeconds > 0.0F) || !(params.omega > 0.0F)) {
      return state;
    }
    const double w = params.omega;
    const double z = std::max(0.0F, params.zeta);
    const double t = dtSeconds;
    const double x0 = static_cast<double>(state.position) - target; // displacement from the target
    const double v0 = state.velocity;

    double x = 0.0;
    double v = 0.0;
    if (std::abs(z - 1.0) < 1e-4) {
      // Critically damped: x(t) = (x0 + (v0 + w x0) t) e^{-w t}
      const double e = std::exp(-w * t);
      const double b = v0 + w * x0;
      x = (x0 + b * t) * e;
      v = (b - w * (x0 + b * t)) * e;
    } else if (z < 1.0) {
      // Underdamped: oscillation at wd = w sqrt(1 - z^2) inside an e^{-z w t} envelope.
      const double wd = w * std::sqrt(1.0 - z * z);
      const double e = std::exp(-z * w * t);
      const double c = std::cos(wd * t);
      const double s = std::sin(wd * t);
      const double b = (v0 + z * w * x0) / wd;
      x = e * (x0 * c + b * s);
      v = e * ((-z * w) * (x0 * c + b * s) + (-x0 * wd * s + b * wd * c));
    } else {
      // Overdamped: two real decays r1, r2.
      const double root = w * std::sqrt(z * z - 1.0);
      const double r1 = -z * w + root;
      const double r2 = -z * w - root;
      const double c2 = (v0 - r1 * x0) / (r2 - r1);
      const double c1 = x0 - c2;
      const double e1 = std::exp(r1 * t);
      const double e2 = std::exp(r2 * t);
      x = c1 * e1 + c2 * e2;
      v = c1 * r1 * e1 + c2 * r2 * e2;
    }
    return SpringState{.position = static_cast<float>(target + x), .velocity = static_cast<float>(v)};
  }

  bool atRest(SpringState state, float target, SpringParams params, float positionEpsilon) noexcept {
    const float eps = std::max(positionEpsilon, 1e-6F);
    return std::abs(state.position - target) <= eps && std::abs(state.velocity) <= eps * std::max(params.omega, 1.0F);
  }

  float peakOvershoot(SpringParams params) noexcept {
    const float z = params.zeta;
    if (z >= 1.0F || z <= 0.0F) {
      return z <= 0.0F ? 1.0F : 0.0F;
    }
    return std::exp(-3.14159265F * z / std::sqrt(1.0F - z * z));
  }

  float settleTimeSeconds(SpringParams params, float fraction) noexcept {
    // Released from rest at distance 1: find the last sample outside the band.
    constexpr float kDt = 0.0005F;
    constexpr float kHorizon = 5.0F;
    SpringState s{.position = 0.0F, .velocity = 0.0F};
    float lastOutside = 0.0F;
    for (float t = kDt; t <= kHorizon; t += kDt) {
      s = step(s, 1.0F, params, kDt);
      if (std::abs(s.position - 1.0F) > fraction) {
        lastOutside = t;
      }
    }
    return lastOutside;
  }

} // namespace motion
