// Regression test for a use-after-free in Signal dispatch.
//
// A palette transition emits every animation frame, and a handler can tear down
// UI nodes that are themselves subscribed to the same signal. Dispatch used to
// iterate a *copy* of the slot list, so a subscriber destroyed earlier in the
// same emit was still invoked through the copied std::function — with its
// captured `this` already freed. Observed as SIGSEGV in Image::applyPalette()
// under Signal<>::emit() from ThemeService::startTransition.
//
// The test does not rely on a crash (freed memory may read back fine): every
// subscriber reports whether it was still alive when its callback ran, using a
// liveness registry keyed by pointer, so a stale invocation is detected exactly.

#include "ui/signal.h"

#include <iostream>
#include <memory>
#include <unordered_set>
#include <vector>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

  std::unordered_set<const void*> g_live;
  int g_staleCalls = 0;
  int g_liveCalls = 0;

  // Stands in for a subscribed UI node (e.g. Image): its connection dies with it.
  struct Subscriber {
    explicit Subscriber(Signal<>& signal) {
      g_live.insert(this);
      conn = signal.connect([this] {
        if (g_live.contains(this)) {
          ++g_liveCalls;
        } else {
          ++g_staleCalls; // would have been a use-after-free in the shell
        }
      });
    }
    ~Subscriber() { g_live.erase(this); }
    Signal<>::ScopedConnection conn;
  };

} // namespace

int main() {
  bool ok = true;

  // 1. A handler that tears down *later* subscribers: they must not be called.
  {
    Signal<> signal;
    std::vector<std::unique_ptr<Subscriber>> subs;
    // The destroyer is connected FIRST so the victims are still ahead of it in
    // the dispatch order — this is the ordering that crashed the shell.
    Signal<>::ScopedConnection killer = signal.connect([&subs] { subs.clear(); });
    for (int i = 0; i < 6; ++i) {
      subs.push_back(std::make_unique<Subscriber>(signal));
    }
    g_staleCalls = g_liveCalls = 0;
    signal.emit();
    ok = check(g_staleCalls == 0, "a subscriber destroyed during dispatch must not be invoked") && ok;

    g_staleCalls = g_liveCalls = 0;
    signal.emit();
    ok = check(g_staleCalls == 0 && g_liveCalls == 0, "no stale slots survive the teardown") && ok;
  }

  // 2. Connecting during dispatch must not invalidate the walk.
  {
    Signal<> signal;
    int hits = 0;
    std::vector<Signal<>::ScopedConnection> conns;
    Signal<>::ScopedConnection grower = signal.connect([&] {
      for (int i = 0; i < 8; ++i) {
        conns.push_back(signal.connect([&hits] { ++hits; }));
      }
    });
    signal.emit();
    ok = check(hits == 0, "slots connected during dispatch wait for the next emit") && ok;
    signal.emit();
    ok = check(hits == 8, "slots connected during dispatch fire on the next emit") && ok;
  }

  // 3. Self-disconnect mid-dispatch leaves the signal usable.
  {
    Signal<> signal;
    int after = 0;
    auto self = std::make_unique<Signal<>::ScopedConnection>();
    *self = signal.connect([&] { self->disconnect(); });
    Signal<>::ScopedConnection tail = signal.connect([&after] { ++after; });
    signal.emit();
    ok = check(after == 1, "later slots still run after a self-disconnect") && ok;
    signal.emit();
    ok = check(after == 2, "signal remains usable after a self-disconnect") && ok;
  }

  if (ok) {
    std::cout << "signal dispatch test passed\n";
  }
  return ok ? 0 : 1;
}
