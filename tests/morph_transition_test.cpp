// MorphTransition: the interruptible transition leg the Control Center's section
// navigation is built on, extracted so the launcher and lock screen can share it.
//
// The properties under test are the ones that make a retarget read as continuous rather
// than as a restart, plus the lifetime rules that keep a rapid retarget out of the
// use-after-free family already seen in this project (Signal::emit, AnimationManager::tick).

#include "render/animation/animation_manager.h"
#include "render/animation/morph_transition.h"
#include "render/animation/motion_service.h"

#include <chrono>
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

  // AnimationManager::tick() ignores its deltaMs argument and derives progress from wall
  // time (steady_clock), so a fixed duration stays correct when the compositor delivers
  // sparse frame callbacks. Tests therefore have to advance real time, not a synthetic clock.
  void step(AnimationManager& m, float totalMs, float sliceMs = 4.0F) {
    for (float t = 0.0F; t < totalMs; t += sliceMs) {
      std::this_thread::sleep_for(std::chrono::duration<float, std::milli>(sliceMs));
      m.tick(sliceMs);
    }
  }

} // namespace

int main() {
  resetMotion();

  // --- basic progression and settle -----------------------------------------------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    int frames = 0;
    bool settled = false;
    float last = -1.0F;
    morph.start(
        1, 0.0F, 40.0F, Easing::Linear,
        [&](float p) {
          ++frames;
          check(p >= last, "progress must be monotonic");
          last = p;
        },
        [&]() { settled = true; }
    );

    check(morph.active(), "morph is active after start");
    check(morph.direction() == 1, "direction is carried");
    step(anim, 70.0F);
    check(frames > 0, "frames were delivered");
    check(settled, "onSettle ran on completion");
    check(!morph.active(), "morph is inactive after settling");
    check(morph.progress() == 1.0F, "progress ends at 1.0");
  }

  // --- retarget: the previous leg does not settle, and carry/direction update ------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    bool firstSettled = false;
    bool secondSettled = false;
    morph.start(1, 0.0F, 40.0F, Easing::Linear, [](float) {}, [&]() { firstSettled = true; });
    step(anim, 16.0F);
    const float mid = morph.progress();
    check(mid > 0.0F && mid < 1.0F, "interrupted part-way through the first leg");

    // Retarget in the opposite direction, carrying the visual state observed at `mid`.
    morph.start(-1, mid, 40.0F, Easing::Linear, [](float) {}, [&]() { secondSettled = true; });
    check(morph.direction() == -1, "direction updated on retarget");
    check(morph.carry() == mid, "carry is the state handed in at retarget");
    check(morph.progress() == 0.0F, "the new leg restarts its own progress at 0");

    step(anim, 70.0F);
    check(!firstSettled, "a retargeted leg must NOT run its onSettle");
    check(secondSettled, "the leg that reaches 1.0 settles");
  }

  // --- reversal chain: A->B->C mid-flight, repeatedly ------------------------------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    int settles = 0;
    for (int i = 0; i < 60; ++i) {
      morph.start(
          (i % 2 == 0) ? 1 : -1, morph.progress(), 40.0F, Easing::EaseOutQuint, [](float) {}, [&]() { ++settles; }
      );
      step(anim, 8.0F); // never long enough to finish
    }
    check(settles == 0, "none of the 60 interrupted legs settled");
    check(morph.active(), "still active after rapid retargeting");
    step(anim, 70.0F);
    check(settles == 1, "exactly the final leg settles");
    check(!morph.active(), "inactive once the final leg completes");
  }

  // --- retarget from inside onFrame (the hazard that motivated the design) --------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    int retargets = 0;
    bool settled = false;
    std::function<void(float)> frame = [&](float p) {
      // Re-enter start() from the running leg's own setter, a few times.
      if (p > 0.3F && retargets < 3) {
        ++retargets;
        morph.start(-morph.direction(), p, 40.0F, Easing::Linear, frame, [&]() { settled = true; });
      }
    };
    morph.start(1, 0.0F, 40.0F, Easing::Linear, frame, [&]() { settled = true; });
    step(anim, 200.0F);
    check(retargets == 3, "re-entrant retargets from onFrame all took effect");
    check(settled, "the chain still settles");
  }

  // --- cancellation ---------------------------------------------------------------------
  {
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    bool settled = false;
    int frames = 0;
    morph.start(1, 0.0F, 40.0F, Easing::Linear, [&](float) { ++frames; }, [&]() { settled = true; });
    step(anim, 16.0F);
    const int framesAtCancel = frames;
    morph.cancel();
    check(!morph.active(), "inactive after cancel");
    step(anim, 70.0F);
    check(frames == framesAtCancel, "no frames after cancel");
    check(!settled, "cancel does not settle");
    morph.cancel(); // idempotent
  }

  // --- destruction during an active leg --------------------------------------------------
  {
    AnimationManager anim;
    bool settled = false;
    {
      MorphTransition morph;
      morph.bind(&anim, nullptr);
      morph.start(1, 0.0F, 40.0F, Easing::Linear, [](float) {}, [&]() { settled = true; });
      step(anim, 16.0F);
    } // destructor cancels the in-flight leg
    step(anim, 70.0F);
    check(!settled, "a destroyed MorphTransition's leg must not settle");
    check(!anim.hasActive(), "no animation outlives the MorphTransition");
  }

  // --- owner cancellation reaches the leg (Node destructor path) -------------------------
  {
    AnimationManager anim;
    MorphTransition morph;
    int owner = 0;
    morph.bind(&anim, &owner);

    bool settled = false;
    morph.start(1, 0.0F, 40.0F, Easing::Linear, [](float) {}, [&]() { settled = true; });
    step(anim, 16.0F);
    anim.cancelForOwner(&owner);
    step(anim, 70.0F);
    check(!settled, "cancelForOwner stops the leg");
    check(!anim.hasActive(), "no leftover animation after cancelForOwner");
  }

  // --- motion disabled --------------------------------------------------------------------
  {
    MotionService::instance().setEnabled(false);
    AnimationManager anim;
    MorphTransition morph;
    morph.bind(&anim, nullptr);

    bool settled = false;
    float lastProgress = -1.0F;
    morph.start(1, 0.0F, 40.0F, Easing::Linear, [&](float p) { lastProgress = p; }, [&]() { settled = true; });
    anim.tick(1.0F);
    check(settled, "with motion disabled the leg settles immediately");
    check(lastProgress == 1.0F, "and lands on the end state rather than a half-applied one");
    check(!morph.active(), "not left active");
    resetMotion();
  }

  // --- no manager bound --------------------------------------------------------------------
  {
    MorphTransition morph; // never bound
    bool settled = false;
    float lastProgress = -1.0F;
    morph.start(1, 0.0F, 40.0F, Easing::Linear, [&](float p) { lastProgress = p; }, [&]() { settled = true; });
    check(settled, "unbound morph settles synchronously");
    check(lastProgress == 1.0F, "unbound morph lands on the end state");
    check(!morph.active(), "unbound morph is not left active");
  }

  // --- several independent morphs on one manager -------------------------------------------
  {
    AnimationManager anim;
    std::vector<std::unique_ptr<MorphTransition>> morphs;
    int settles = 0;
    for (int i = 0; i < 8; ++i) {
      auto m = std::make_unique<MorphTransition>();
      m->bind(&anim, nullptr);
      m->start(1, 0.0F, 40.0F, Easing::Linear, [](float) {}, [&]() { ++settles; });
      morphs.push_back(std::move(m));
    }
    step(anim, 70.0F);
    check(settles == 8, "independent morphs all settle");
  }

  if (failures == 0) {
    std::cout << "morph transition test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
