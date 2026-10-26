#include "render/animation/motion_value.h"

#include <utility>

MotionValue::~MotionValue() { cancel(); }

void MotionValue::bind(
    AnimationManager* animations, const void* owner, motion::Role role, std::function<void(float)> onChange
) {
  if (animations != m_animations || owner != m_owner) {
    cancel();
  }
  m_animations = animations;
  m_owner = owner;
  m_role = role;
  m_onChange = std::move(onChange);
}

void MotionValue::cancel() {
  if (m_animations != nullptr && m_id != 0) {
    m_animations->cancel(m_id);
  }
  m_id = 0;
  ++m_generation;
}

void MotionValue::reset() {
  cancel();
  m_hasValue = false;
}

bool MotionValue::animating() const noexcept {
  return m_animations != nullptr && m_id != 0 && m_animations->sample(m_id).has_value();
}

float MotionValue::velocity() const {
  if (m_animations == nullptr || m_id == 0) {
    return 0.0F;
  }
  const auto s = m_animations->sample(m_id);
  return s.has_value() ? s->velocity : 0.0F;
}

void MotionValue::setImmediate(float value) {
  cancel();
  m_value = value;
  m_target = value;
  m_hasValue = true;
  if (m_onChange) {
    // Copy first: the callback may rebind or destroy this object.
    auto onChange = m_onChange;
    onChange(value);
  }
}

void MotionValue::setTarget(float target) {
  if (!m_hasValue || m_animations == nullptr) {
    setImmediate(target);
    return;
  }
  if (target == m_target && (m_id == 0 || m_animations->sample(m_id).has_value())) {
    return; // already there, or already heading there
  }
  m_target = target;
  if (m_id != 0 && m_animations->retarget(m_id, target)) {
    return;
  }
  // No live entry to bend: drop any stale handle before starting a new one, so two entries can never
  // drive this value at once.
  cancel();
  if (target == m_value) {
    return;
  }
  // The callables live in the manager's entry. The generation token makes a superseded entry inert: a
  // completion that runs after a newer entry started (both inside one tick) cannot clear the newer id,
  // and a superseded setter cannot write the value. The frame callable touches `this` only before
  // running the copied onChange, and the destructor cancels, so neither runs after destruction.
  const std::uint64_t generation = ++m_generation;
  m_id = m_animations->animate(
      m_role, m_value, target,
      [this, generation, onChange = m_onChange](float v) {
        if (m_generation != generation) {
          return;
        }
        m_value = v;
        if (onChange) {
          onChange(v);
        }
      },
      [this, generation]() {
        if (m_generation == generation) {
          m_id = 0;
        }
      },
      m_owner
  );
}

void MotionRect::bind(
    AnimationManager* animations, const void* owner, motion::Role role, std::function<void()> onChange
) {
  auto forward = [onChange = std::move(onChange)](float) {
    if (onChange) {
      onChange();
    }
  };
  m_x.bind(animations, owner, role, forward);
  m_y.bind(animations, owner, role, forward);
  m_width.bind(animations, owner, role, forward);
  m_height.bind(animations, owner, role, forward);
}

void MotionRect::setImmediate(const MotionRectValue& rect) {
  m_x.setImmediate(rect.x);
  m_y.setImmediate(rect.y);
  m_width.setImmediate(rect.width);
  m_height.setImmediate(rect.height);
}

void MotionRect::setTarget(const MotionRectValue& rect) {
  m_x.setTarget(rect.x);
  m_y.setTarget(rect.y);
  m_width.setTarget(rect.width);
  m_height.setTarget(rect.height);
}

void MotionRect::cancel() {
  m_x.cancel();
  m_y.cancel();
  m_width.cancel();
  m_height.cancel();
}

void MotionRect::reset() {
  m_x.reset();
  m_y.reset();
  m_width.reset();
  m_height.reset();
}

MotionRectValue MotionRect::value() const noexcept {
  return {.x = m_x.value(), .y = m_y.value(), .width = m_width.value(), .height = m_height.value()};
}

MotionRectValue MotionRect::target() const noexcept {
  return {.x = m_x.target(), .y = m_y.target(), .width = m_width.target(), .height = m_height.target()};
}

bool MotionRect::animating() const noexcept {
  return m_x.animating() || m_y.animating() || m_width.animating() || m_height.animating();
}
