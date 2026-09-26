// zynith motion language: spring physics, semantic roles, interruption/retargeting, reduced motion,
// tempo, lifetime and idle behaviour of the motion primitives built on AnimationManager.
//
// The physics checks are deterministic (motion::step is pure). The manager checks advance real time,
// like morph_transition_test, because AnimationManager derives progress from the steady clock.

#include "render/animation/animation_manager.h"
#include "render/animation/morph_transition.h"
#include "render/animation/motion_physics.h"
#include "render/animation/motion_role.h"
#include "render/animation/motion_service.h"
#include "render/animation/motion_value.h"

#include <chrono>
#include <cmath>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

namespace {

  int failures = 0;

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
    return cond;
  }

  void resetMotion() {
    auto& motion = MotionService::instance();
    motion.setSpeed(1.0F);
    motion.setEnabled(true);
  }

  void step(AnimationManager& m, float totalMs, float sliceMs = 4.0F) {
    for (float t = 0.0F; t < totalMs; t += sliceMs) {
      std::this_thread::sleep_for(std::chrono::duration<float, std::milli>(sliceMs));
      m.tick(sliceMs);
    }
  }

  bool near(float a, float b, float eps) { return std::abs(a - b) <= eps; }

} // namespace

int main() {
  resetMotion();

  // --- physics: closed form is exact for any step size ------------------------------------------
  {
    const motion::SpringParams p{.omega = 22.0F, .zeta = 0.85F};
    motion::SpringState one = motion::step({.position = 0.0F, .velocity = 0.0F}, 100.0F, p, 0.12F);
    motion::SpringState many{.position = 0.0F, .velocity = 0.0F};
    for (int i = 0; i < 120; ++i) {
      many = motion::step(many, 100.0F, p, 0.001F);
    }
    check(near(one.position, many.position, 0.01F), "underdamped: one 120 ms step equals 120 x 1 ms steps");
    check(near(one.velocity, many.velocity, 0.05F), "underdamped: velocity agrees across step sizes");

    for (const float zeta : {1.0F, 1.6F}) {
      const motion::SpringParams q{.omega = 30.0F, .zeta = zeta};
      const auto a = motion::step({.position = 10.0F, .velocity = -40.0F}, 60.0F, q, 0.2F);
      auto b = motion::SpringState{.position = 10.0F, .velocity = -40.0F};
      for (int i = 0; i < 200; ++i) {
        b = motion::step(b, 60.0F, q, 0.001F);
      }
      check(near(a.position, b.position, 0.01F), "critical/overdamped: step size does not change the path");
    }
    check(motion::step({.position = 3.0F, .velocity = 1.0F}, 9.0F, p, 0.0F).position == 3.0F, "dt 0 changes nothing");
  }

  // --- physics: the numbers the roles are specified by --------------------------------------------
  {
    const float move = motion::settleTimeSeconds({.omega = 30.0F, .zeta = 1.0F}, 0.01F);
    check(move > 0.20F && move < 0.24F, "element-move (w30, critical) settles within 1% in ~221 ms");
    const float resize = motion::settleTimeSeconds({.omega = 26.0F, .zeta = 1.0F}, 0.01F);
    check(resize > move, "element-resize settles slower than element-move");
    check(motion::peakOvershoot({.omega = 30.0F, .zeta = 1.0F}) == 0.0F, "critical damping never overshoots");
    const float ov = motion::peakOvershoot({.omega = 22.0F, .zeta = 0.85F});
    check(ov > 0.005F && ov < 0.008F, "zeta 0.85 overshoots ~0.6%");
  }

  // --- role table invariants ------------------------------------------------------------------------
  {
    for (std::size_t i = 0; i < motion::kRoleCount; ++i) {
      const auto& s = motion::spec(static_cast<motion::Role>(i));
      check(!s.name.empty(), "every role is named");
      if (s.model == motion::Model::Tween) {
        check(s.durationMs > 0.0F, "every tween role has a duration");
      } else {
        check(s.spring.omega > 0.0F, "every spring role has a frequency");
        check(s.spring.zeta >= 1.0F, "element springs never overshoot");
      }
      if (s.reduced == motion::ReducedMotion::Shorten) {
        check(s.reducedDurationMs > 0.0F && s.reducedDurationMs <= 150.0F, "a shortened role keeps a brief fade");
      }
    }
    using motion::Role;
    check(motion::spec(Role::SurfaceDismiss).durationMs < motion::spec(Role::SurfaceReveal).durationMs,
          "a dismissal is always shorter than the reveal");
    check(motion::spec(Role::ContentDismiss).durationMs < motion::spec(Role::ContentReveal).durationMs,
          "content leaves faster than it arrives");
    check(motion::spec(Role::ContentReveal).delayMs > 0.0F, "content waits for its surface");
    check(motion::spec(Role::ElementMove).reduced == motion::ReducedMotion::Snap, "spatial roles snap when reduced");
  }

  // --- spring entry: reaches the target, then the manager goes idle -------------------------------
  {
    AnimationManager anim;
    float value = 0.0F;
    bool done = false;
    anim.animate(motion::Role::ElementMove, 0.0F, 100.0F, [&](float v) { value = v; }, [&]() { done = true; });
    check(anim.hasActive(), "a spring keeps the manager active while moving");
    step(anim, 400.0F);
    check(done, "the spring completes");
    check(value == 100.0F, "the spring lands exactly on its target");
    check(!anim.hasActive(), "nothing stays active after settling: idle UI stays idle");
  }

  // --- interruption: A -> B, halfway B -> C keeps position and velocity ---------------------------
  {
    AnimationManager anim;
    float value = 0.0F;
    const auto id = anim.animate(motion::Role::ElementMove, 0.0F, 100.0F, [&](float v) { value = v; });
    step(anim, 70.0F);
    const auto before = anim.sample(id);
    check(before.has_value() && before->spring, "a live spring can be sampled");
    check(anim.retarget(id, 300.0F), "a live spring can be retargeted");
    const auto after = anim.sample(id);
    check(after.has_value() && after->value == before->value, "retargeting does not move the value");
    check(after.has_value() && after->velocity == before->velocity, "retargeting keeps the velocity");

    // Discriminating check: the path after the retarget must follow the physics of the KEPT state, not
    // of a state whose velocity was reset. Advance one real interval, then compare the observed value
    // with both predictions for that interval. (A loose bound on frame-to-frame velocity change cannot
    // tell these apart: a reset of ~770 px/s is smaller than the legitimate pull toward 300.)
    const auto t0 = std::chrono::steady_clock::now();
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    anim.tick(20.0F);
    const float dt = std::chrono::duration<float>(std::chrono::steady_clock::now() - t0).count();
    const motion::SpringParams p = motion::spec(motion::Role::ElementMove).spring;
    const float kept =
        motion::step({.position = before->value, .velocity = before->velocity}, 300.0F, p, dt).position;
    const float reset = motion::step({.position = before->value, .velocity = 0.0F}, 300.0F, p, dt).position;
    const auto observed = anim.sample(id);
    check(observed.has_value(), "the retargeted spring is still moving");
    if (observed.has_value()) {
      check(std::abs(reset - kept) > 5.0F, "the two hypotheses are distinguishable at this interval");
      check(std::abs(observed->value - kept) < std::abs(observed->value - reset),
            "after a retarget the motion continues with its velocity (no reset to rest)");
      check(std::abs(observed->value - kept) < 3.0F, "the retargeted path matches the kept-state physics");
    }
    step(anim, 400.0F);
    check(value == 300.0F, "the retargeted spring lands on the new target");
    check(!anim.retarget(id, 1.0F), "a finished animation cannot be retargeted (caller starts a new one)");
  }

  // --- tween retarget keeps position -----------------------------------------------------------------
  {
    AnimationManager anim;
    float value = 0.0F;
    const auto id = anim.animate(motion::Role::Focus, 0.0F, 1.0F, [&](float v) { value = v; });
    step(anim, 50.0F);
    const float mid = value;
    check(mid > 0.0F && mid < 1.0F, "tween is mid-flight");
    check(anim.retarget(id, 0.0F), "a live tween can be retargeted");
    anim.tick(0.0F);
    check(near(value, mid, 0.05F), "tween retarget continues from the current value (no snap to the start)");
    step(anim, 250.0F);
    check(value == 0.0F, "tween lands on the new target");
  }

  // --- reduced motion: spatial roles snap, state changes keep a short fade ---------------------------
  {
    auto& motionService = MotionService::instance();
    motionService.setEnabled(false);
    AnimationManager anim;
    float moved = -1.0F;
    anim.animate(motion::Role::ElementMove, 0.0F, 50.0F, [&](float v) { moved = v; });
    check(moved == 50.0F, "reduced motion: an element move lands immediately");

    float faded = 0.0F;
    anim.animate(motion::Role::ContentReveal, 0.0F, 1.0F, [&](float v) { faded = v; });
    step(anim, 40.0F);
    check(faded > 0.0F && faded < 1.0F, "reduced motion: content still fades (state change stays visible)");
    step(anim, 120.0F);
    check(faded == 1.0F, "reduced motion: the fade completes in ~90 ms");

    float r = -1.0F;
    anim.animateSpring(0.0F, 7.0F, {.omega = 30.0F, .zeta = 1.0F}, [&](float v) { r = v; });
    check(r == 7.0F, "reduced motion: a raw spring lands immediately");
    motionService.setEnabled(true);

    // reduceMotion() while a spring runs lands it on its target on the next tick.
    AnimationManager live;
    float lv = 0.0F;
    live.animate(motion::Role::ElementResize, 0.0F, 80.0F, [&](float v) { lv = v; });
    step(live, 30.0F);
    live.reduceMotion();
    live.tick(0.0F);
    check(lv == 80.0F && !live.hasActive(), "reduceMotion() settles running springs");
  }

  // --- tempo: speed scales springs and tweens alike ---------------------------------------------------
  {
    MotionService::instance().setSpeed(2.0F);
    AnimationManager anim;
    bool done = false;
    anim.animate(motion::Role::ElementMove, 0.0F, 100.0F, [](float) {}, [&]() { done = true; });
    step(anim, 180.0F);
    check(done, "at double speed a ~250 ms spring settles well within 180 ms");
    resetMotion();
  }

  // --- MotionValue: start, retarget without restart, no-op repeats, destruction ----------------------
  {
    AnimationManager anim;
    std::vector<float> seen;
    MotionValue mv;
    mv.bind(&anim, nullptr, motion::Role::ElementMove, [&](float v) { seen.push_back(v); });
    mv.setTarget(10.0F);
    check(mv.value() == 10.0F && !mv.animating(), "the first target is applied immediately");
    mv.setTarget(110.0F);
    check(mv.animating(), "a new target animates");
    step(anim, 60.0F);
    const float mid = mv.value();
    const float vMid = mv.velocity();
    check(mid > 10.0F && mid < 110.0F && vMid > 0.0F, "mid-flight value and velocity are available");
    mv.setTarget(110.0F);
    check(mv.animating() && mv.value() == mid, "repeating the same target does not restart the motion");
    mv.setTarget(-50.0F);
    check(mv.value() == mid && mv.velocity() == vMid, "retargeting keeps value and velocity");
    step(anim, 500.0F);
    check(mv.value() == -50.0F && !anim.hasActive(), "MotionValue settles and the manager goes idle");

    // Destroyed mid-flight: no callback may reach it afterwards.
    auto dying = std::make_unique<MotionValue>();
    int after = 0;
    bool destroyed = false;
    dying->bind(&anim, nullptr, motion::Role::ElementMove, [&](float) {
      if (destroyed) {
        ++after;
      }
    });
    dying->setTarget(0.0F);
    dying->setTarget(100.0F);
    step(anim, 30.0F);
    dying.reset();
    destroyed = true;
    step(anim, 100.0F);
    check(after == 0, "a destroyed MotionValue receives no further frames");
    check(!anim.hasActive(), "destroying a MotionValue releases its entry");

    // A callback that destroys its own MotionValue must not crash (callable owned by the manager).
    auto self = std::make_unique<MotionValue>();
    self->bind(&anim, nullptr, motion::Role::ElementMove, [&](float v) {
      if (v > 5.0F) {
        self.reset();
      }
    });
    self->setTarget(0.0F);
    self->setTarget(50.0F);
    step(anim, 120.0F);
    check(self == nullptr, "a MotionValue may be destroyed from inside its own change callback");

    // Owner cancellation (a node destructor) leaves the value restartable.
    MotionValue owned;
    int token = 0;
    owned.bind(&anim, &token, motion::Role::ElementMove, [](float) {});
    owned.setTarget(0.0F);
    owned.setTarget(40.0F);
    step(anim, 20.0F);
    anim.cancelForOwner(&token);
    const float frozen = owned.value();
    owned.setTarget(40.0F);
    check(owned.animating(), "after owner cancellation the same target restarts from where it stopped");
    check(owned.value() == frozen, "the restart begins at the frozen value (no jump)");
    step(anim, 400.0F);
    check(owned.value() == 40.0F, "the restarted motion completes");
  }

  // --- MotionRect: a shared element travelling and being redirected ---------------------------------
  {
    AnimationManager anim;
    int changes = 0;
    MotionRect rect;
    rect.bind(&anim, nullptr, motion::Role::ElementMove, [&]() { ++changes; });
    rect.setImmediate({.x = 0.0F, .y = 0.0F, .width = 30.0F, .height = 30.0F});
    rect.setTarget({.x = 200.0F, .y = 0.0F, .width = 60.0F, .height = 30.0F});
    step(anim, 60.0F);
    const auto mid = rect.value();
    check(mid.x > 0.0F && mid.x < 200.0F && mid.width > 30.0F && mid.width < 60.0F, "rect interpolates x and width");
    rect.setTarget({.x = 40.0F, .y = 0.0F, .width = 30.0F, .height = 30.0F});
    check(rect.value() == mid, "redirecting the rect does not move it");
    step(anim, 500.0F);
    check(rect.value() == (MotionRectValue{.x = 40.0F, .y = 0.0F, .width = 30.0F, .height = 30.0F}),
          "the rect settles on the redirected target");
    check(changes > 0 && !rect.animating() && !anim.hasActive(), "rect settles and the manager goes idle");
  }

  // --- MorphTransition with a role ------------------------------------------------------------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);
    bool settled = false;
    float last = 0.0F;
    morph.start(1, 0.0F, motion::Role::Morph, [&](float p) { last = p; }, [&]() { settled = true; });
    step(anim, 400.0F);
    check(settled && last == 1.0F, "a role-timed morph leg settles at progress 1");

    MotionService::instance().setEnabled(false);
    bool snapSettled = false;
    morph.start(1, 0.0F, motion::Role::Morph, [&](float p) { last = p; }, [&]() { snapSettled = true; });
    step(anim, 10.0F);
    check(snapSettled && last == 1.0F, "reduced motion: a morph leg snaps to its end");
    resetMotion();
  }

  if (failures == 0) {
    std::cout << "motion language test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
