// Regression test: a setter running inside AnimationManager::tick() may start
// animations, cancel others, or destroy nodes (whose destructors call
// cancelForOwner). Any of those used to mutate the vector tick() was walking —
// reallocating it, or erasing the entry whose std::function was executing.
//
// Same failure family as the Signal use-after-free seen in the field
// (Image::applyPalette under Signal::emit under a ThemeService transition
// driven by AnimationManager::tick).

#include "render/animation/animation_manager.h"
#include "render/animation/motion_service.h"

#include <iostream>
#include <vector>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

  void resetMotion() {
    auto& motion = MotionService::instance();
    motion.setSpeed(1.0F);
    motion.setEnabled(true);
  }

} // namespace

int main() {
  bool ok = true;
  resetMotion();

  // 1. A setter that cancels every other animation (the "a handler tore down
  //    the nodes" case) must not corrupt the walk.
  {
    AnimationManager mgr;
    std::vector<AnimationManager::Id> victims;
    int victimTicks = 0;
    for (int i = 0; i < 8; ++i) {
      victims.push_back(mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&victimTicks](float) { ++victimTicks; }));
    }
    bool fired = false;
    mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&](float) {
      if (fired) {
        return;
      }
      fired = true;
      for (auto id : victims) {
        mgr.cancel(id);
      }
    });
    mgr.tick(16.0F);
    mgr.tick(16.0F);
    ok = check(true, "cancelling other animations inside a setter does not crash");
    ok = check(mgr.hasActive(), "the cancelling animation itself survives") && ok;
  }

  // 2. A setter that starts new animations must not reallocate under the walk.
  {
    AnimationManager mgr;
    int spawned = 0;
    bool done = false;
    mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&](float) {
      if (done) {
        return;
      }
      done = true;
      for (int i = 0; i < 32; ++i) {
        mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&spawned](float) { ++spawned; });
      }
    });
    mgr.tick(16.0F);
    ok = check(spawned == 0, "animations started inside a tick wait for the next tick") && ok;
    mgr.tick(16.0F);
    ok = check(spawned == 32, "animations started inside a tick run on the next tick") && ok;
  }

  // 3. cancelForOwner from inside a setter (what a Node destructor does).
  {
    AnimationManager mgr;
    int owner = 0;
    int ticks = 0;
    for (int i = 0; i < 6; ++i) {
      mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&ticks](float) { ++ticks; }, {}, &owner);
    }
    bool fired = false;
    mgr.animate(0.0F, 1.0F, 500.0F, Easing::Linear, [&](float) {
      if (!fired) {
        fired = true;
        mgr.cancelForOwner(&owner);
      }
    });
    mgr.tick(16.0F);
    const int afterFirst = ticks;
    mgr.tick(16.0F);
    ok = check(ticks == afterFirst, "owner-cancelled animations stop immediately") && ok;
  }

  // 4. A setter that cancels itself: no completion, no crash, manager usable.
  {
    AnimationManager mgr;
    bool completed = false;
    AnimationManager::Id id = 0;
    id = mgr.animate(
        0.0F, 1.0F, 1.0F, Easing::Linear, [&](float) { mgr.cancel(id); }, [&completed]() { completed = true; }
    );
    mgr.tick(16.0F);
    mgr.tick(16.0F);
    ok = check(!completed, "a self-cancelled animation does not fire onComplete") && ok;
    int later = 0;
    mgr.animate(0.0F, 1.0F, 1.0F, Easing::Linear, [&later](float) { ++later; });
    mgr.tick(16.0F);
    ok = check(later > 0, "manager still works after a self-cancel") && ok;
  }

  if (ok) {
    std::cout << "animation reentrancy test passed\n";
  }
  return ok ? 0 : 1;
}
