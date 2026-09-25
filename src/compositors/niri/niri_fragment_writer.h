#pragma once

#include "core/timer_manager.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>

// Owns one shell-generated niri configuration fragment — an `include`d .kdl file such as
// ~/.config/niri/rice/animations.kdl — and keeps it equal to what the configuration says.
//
// Guarantees:
//   * Coalescing. submit() only records the latest content; a single debounce timer writes it.
//     A slider dragged across twenty values produces one write, not twenty.
//   * No needless writes. Content identical to what is already installed is never rewritten, so
//     niri is not made to reload for nothing — including at shell startup.
//   * Validate before install. The candidate is written to a sibling temp file and checked with
//     `niri validate -c <temp>` (an argument vector, never a shell string) before it replaces the
//     live fragment, so niri is never pointed at a file that does not parse.
//   * Atomic install. The live fragment is replaced with writeTextFileAtomic (temp + rename), so a
//     reader — niri's config watcher — sees either the old file or the new one, never a torn one.
//   * Whole-config check with rollback. A fragment can be valid alone and still break the full
//     config (a duplicate top-level node, say). After installing, the full config is validated;
//     on failure the previous fragment is restored. niri itself refuses an invalid config and keeps
//     running the last good one, so the window in between is harmless.
//   * Lifetime. Validation runs on a worker thread; its result comes back through DeferredCall and
//     reaches the writer's state only through a weak_ptr, so a result that arrives after the
//     writer is gone is dropped. Results for a superseded generation are discarded.
//
// No polling, no resident process: one short-lived `niri validate` per real change.
class NiriFragmentWriter {
public:
  NiriFragmentWriter(std::filesystem::path path, std::string label);
  ~NiriFragmentWriter();

  NiriFragmentWriter(const NiriFragmentWriter&) = delete;
  NiriFragmentWriter& operator=(const NiriFragmentWriter&) = delete;

  void submit(std::string content);

  // Stats for tests and the documentation's validation record.
  struct Stats {
    std::uint32_t submits = 0;
    std::uint32_t skippedUnchanged = 0;
    std::uint32_t validations = 0;
    std::uint32_t installs = 0;
    std::uint32_t rejected = 0;
    std::uint32_t rolledBack = 0;
  };
  [[nodiscard]] Stats stats() const;
  [[nodiscard]] const std::filesystem::path& path() const noexcept;

  static constexpr std::chrono::milliseconds kDebounce{300};

private:
  struct State;
  std::shared_ptr<State> m_state;
  Timer m_debounce;
};
