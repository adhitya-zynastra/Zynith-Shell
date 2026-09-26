#pragma once

#include "render/animation/animation_manager.h"
#include "render/animation/motion_role.h"

#include <cstdint>
#include <functional>

// zynith motion primitives for components: a value that moves by a motion role and can be pointed at a
// new target at any moment without a jump.
//
//   MotionValue  one scalar (an offset, an opacity, a width)
//   MotionRect   a rectangle as four MotionValues: the geometry of a shared element (a selection
//                indicator travelling between tabs, a container reshaping to new content)
//
// Neither is an engine. Each is bookkeeping around AnimationManager entries — the manager remains the
// only thing that advances time — and each follows MorphTransition's lifetime contract:
//   * entries are tagged with `owner`, so a scene node's destructor cancels them;
//   * the destructor cancels, so a running entry never calls back into a destroyed MotionValue;
//   * the change callback is owned by the manager's entry (copied at bind time), not invoked through a
//     member, so a callback that destroys its own MotionValue does not destroy the callable it is
//     running from.
//
// Retargeting (setTarget while animating) keeps position and velocity for spring roles, and position
// for tween roles (AnimationManager::retarget). Setting the same target again is a no-op, so layout
// passes may call setTarget every frame.
class MotionValue {
public:
  MotionValue() = default;
  ~MotionValue();

  MotionValue(const MotionValue&) = delete;
  MotionValue& operator=(const MotionValue&) = delete;
  MotionValue(MotionValue&&) = delete;
  MotionValue& operator=(MotionValue&&) = delete;

  // `onChange` receives every new value while animating, and the value set by setImmediate().
  void bind(AnimationManager* animations, const void* owner, motion::Role role, std::function<void(float)> onChange);

  // Jumps to `value` (cancelling any motion) and reports it.
  void setImmediate(float value);
  // Moves toward `target` by the bound role, starting or retargeting as needed. Before the first value
  // is known the target is applied immediately: there is no meaningful place to come from.
  void setTarget(float target);
  // Stops where it is. Idempotent.
  void cancel();
  // Stops and forgets the value, so the next setTarget() places immediately (a re-created element has
  // no meaningful place to travel from).
  void reset();

  [[nodiscard]] float value() const noexcept { return m_value; }
  [[nodiscard]] float target() const noexcept { return m_target; }
  [[nodiscard]] bool hasValue() const noexcept { return m_hasValue; }
  [[nodiscard]] bool animating() const noexcept;
  // Units per second; 0 when at rest.
  [[nodiscard]] float velocity() const;

private:
  AnimationManager* m_animations = nullptr;
  const void* m_owner = nullptr;
  motion::Role m_role = motion::Role::ElementMove;
  std::function<void(float)> m_onChange;
  AnimationManager::Id m_id = 0;
  std::uint64_t m_generation = 0;
  float m_value = 0.0F;
  float m_target = 0.0F;
  bool m_hasValue = false;
};

struct MotionRectValue {
  float x = 0.0F;
  float y = 0.0F;
  float width = 0.0F;
  float height = 0.0F;

  bool operator==(const MotionRectValue&) const = default;
};

class MotionRect {
public:
  MotionRect() = default;

  // `onChange` runs when any edge moves; read value() inside it. It may run up to four times per
  // frame (once per animating channel), so it should only store geometry and request a redraw.
  void bind(AnimationManager* animations, const void* owner, motion::Role role, std::function<void()> onChange);

  void setImmediate(const MotionRectValue& rect);
  void setTarget(const MotionRectValue& rect);
  void cancel();
  void reset();

  [[nodiscard]] MotionRectValue value() const noexcept;
  [[nodiscard]] MotionRectValue target() const noexcept;
  [[nodiscard]] bool hasValue() const noexcept { return m_x.hasValue(); }
  [[nodiscard]] bool animating() const noexcept;

private:
  MotionValue m_x;
  MotionValue m_y;
  MotionValue m_width;
  MotionValue m_height;
};
