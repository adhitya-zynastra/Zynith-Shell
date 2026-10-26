#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <string>

namespace zynith::theme {

  // Runs template hooks concurrently with bounded parallelism. The runner owns no
  // threads: each hook is spawned through process::runAsync and reports completion
  // on that call's own thread, which keeps the shared state alive past destruction.
  class HookRunner {
  public:
    static constexpr std::size_t kDefaultMaxConcurrent = 4;

    explicit HookRunner(std::size_t maxConcurrent = kDefaultMaxConcurrent);
    ~HookRunner();

    HookRunner(const HookRunner&) = delete;
    HookRunner& operator=(const HookRunner&) = delete;

    // Starts a hook, or queues it while maxConcurrent hooks are already running.
    // Hooks whose generation predates the current one are discarded so superseded
    // requests cannot leave stale state.
    void enqueue(std::string command, std::uint64_t generation);
    // Discards queued hooks from older generations. Hooks that already started
    // keep running; waitIdle() waits them out.
    void invalidateBefore(std::uint64_t generation);
    // zynith: waits for the queue to drain and the running hooks to finish, at most `limit`. A hook still running
    // then is logged and no longer waited for (nor counted against maxConcurrent): it keeps running, but one that
    // never exits (a hook that launched an application) cannot hold up every later theme pass. False on timeout.
    static constexpr std::chrono::milliseconds kDefaultWaitLimit{15000};
    bool waitIdle(std::chrono::milliseconds limit = kDefaultWaitLimit);
    // Drops the queued backlog and releases waitIdle() callers. Running hooks keep
    // going; the destructor waits for them.
    void requestShutdown();
    [[nodiscard]] std::size_t pendingCount() const;

  private:
    struct QueuedHook {
      std::string command;
      std::uint64_t generation = 0;
    };

    struct RunningHook {
      std::string command;
      std::chrono::steady_clock::time_point started;
      bool abandoned = false;
    };

    struct State {
      std::mutex mutex;
      std::condition_variable idleCv;
      std::deque<QueuedHook> queue;
      std::size_t running = 0;
      // zynith: the running hooks by launch id; `abandoned` ones outlived a bounded wait
      std::map<std::uint64_t, RunningHook> active;
      std::uint64_t nextId = 0;
      std::size_t abandoned = 0;
      std::size_t maxConcurrent = kDefaultMaxConcurrent;
      std::uint64_t currentGeneration = 0;
      bool shutdown = false;
    };

    static void pump(const std::shared_ptr<State>& state);
    [[nodiscard]] static bool launch(const std::shared_ptr<State>& state, const std::string& command, std::uint64_t id);
    // running hooks still waited for (callers hold the mutex)
    [[nodiscard]] static std::size_t awaited(const State& state) { return state.running - state.abandoned; }

    std::shared_ptr<State> m_state;
  };

} // namespace zynith::theme
