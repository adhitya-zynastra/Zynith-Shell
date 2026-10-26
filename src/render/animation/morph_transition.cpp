#include "render/animation/morph_transition.h"

#include <utility>

MorphTransition::~MorphTransition() { cancel(); }

void MorphTransition::bind(AnimationManager* animations, const void* owner) {
  m_animations = animations;
  m_owner = owner;
}

void MorphTransition::cancel() {
  if (m_animations != nullptr && m_id != 0) {
    m_animations->cancel(m_id);
  }
  m_id = 0;
  m_active = false;
}

void MorphTransition::start(
    int direction, float carry, float durationMs, Easing easing, std::function<void(float)> onFrame,
    std::function<void()> onSettle
) {
  startLeg(
      direction, carry, std::move(onFrame), std::move(onSettle),
      [durationMs, easing](AnimationManager& m, auto frame, auto settle, const void* owner) {
        return m.animate(0.0F, 1.0F, durationMs, easing, std::move(frame), std::move(settle), owner);
      }
  );
}

void MorphTransition::start(
    int direction, float carry, motion::Role role, std::function<void(float)> onFrame, std::function<void()> onSettle
) {
  startLeg(
      direction, carry, std::move(onFrame), std::move(onSettle),
      [role](AnimationManager& m, auto frame, auto settle, const void* owner) {
        return m.animate(role, 0.0F, 1.0F, std::move(frame), std::move(settle), owner);
      }
  );
}

void MorphTransition::startLeg(
    int direction, float carry, std::function<void(float)> onFrame, std::function<void()> onSettle,
    const std::function<
        AnimationManager::Id(AnimationManager&, std::function<void(float)>, std::function<void()>, const void*)>& launch
) {
  m_direction = direction;
  m_carry = carry;

  if (m_animations == nullptr) {
    // Animations unavailable: land in the settled layout rather than leaving a half-applied
    // one, then report completion. Mirrors what the manager does for a zero duration.
    m_active = false;
    m_progress = 1.0F;
    if (onFrame) {
      onFrame(1.0F);
    }
    if (onSettle) {
      onSettle();
    }
    return;
  }

  // Retarget: drop the in-flight leg. During a tick this only tombstones the entry, and a
  // tombstoned entry is never stepped again and never fires its completion — so the previous
  // leg's onSettle correctly does not run, and its callables stay alive until the tick
  // unwinds. That is why the callables below are owned by the manager rather than by this
  // object: releasing a member std::function here would destroy the very callable whose
  // operator() is on the stack when start() is re-entered from onFrame.
  cancel();

  m_progress = 0.0F;
  m_active = true;

  m_id = launch(
      *m_animations,
      [this, onFrame](float progress) {
        m_progress = progress;
        if (onFrame) {
          onFrame(progress);
        }
      },
      [this, onSettle]() {
        // Cleared before the callback: onSettle may start the next leg, and must not observe
        // this one as still running.
        m_id = 0;
        m_active = false;
        m_progress = 1.0F;
        if (onSettle) {
          onSettle();
        }
      },
      m_owner
  );
}
