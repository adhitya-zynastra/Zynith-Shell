#include "theme/hook_runner.h"

#include "core/log.h"
#include "core/process/process.h"

#include <utility>

namespace noctalia::theme {

  namespace {
    constexpr Logger kLog("hook_runner");
    // Hook output is only read back for the failure warning.
    constexpr std::size_t kMaxHookOutputBytes = 8 * 1024;
    // zynith: how long shutdown waits for running hooks before leaving them to finish on their own
    constexpr std::chrono::milliseconds kShutdownWaitLimit{3000};
  } // namespace

  HookRunner::HookRunner(std::size_t maxConcurrent) : m_state(std::make_shared<State>()) {
    m_state->maxConcurrent = maxConcurrent > 0 ? maxConcurrent : kDefaultMaxConcurrent;
  }

  HookRunner::~HookRunner() {
    requestShutdown();
    std::unique_lock lock(m_state->mutex);
    // Hooks that already started own the shared state; wait them out instead of
    // killing a command halfway through rewriting an application's config.
    // zynith: for a while — a hook that never exits held the shell's shutdown for over a minute. Past the limit
    // it is left running; it holds its own reference to the state.
    if (!m_state->idleCv.wait_for(lock, kShutdownWaitLimit, [this]() { return m_state->running == 0; })) {
      for (const auto& [id, hook] : m_state->active) {
        kLog.warn("hook still running at shutdown, left to finish on its own (command: {})", hook.command);
      }
    }
  }

  void HookRunner::requestShutdown() {
    std::scoped_lock lock(m_state->mutex);
    m_state->shutdown = true;
    m_state->queue.clear();
    // Releases waitIdle() callers: the queued backlog is gone and running hooks
    // are awaited by the destructor, not by whoever was draining.
    m_state->idleCv.notify_all();
  }

  void HookRunner::enqueue(std::string command, std::uint64_t generation) {
    if (command.empty()) {
      return;
    }
    {
      std::scoped_lock lock(m_state->mutex);
      if (m_state->shutdown || generation < m_state->currentGeneration) {
        return;
      }
      m_state->queue.emplace_back(QueuedHook{std::move(command), generation});
    }
    pump(m_state);
  }

  void HookRunner::invalidateBefore(std::uint64_t generation) {
    std::scoped_lock lock(m_state->mutex);
    if (generation <= m_state->currentGeneration) {
      return;
    }
    m_state->currentGeneration = generation;
    std::erase_if(m_state->queue, [generation](const QueuedHook& hook) { return hook.generation < generation; });
    if (m_state->queue.empty() && awaited(*m_state) == 0) {
      m_state->idleCv.notify_all();
    }
  }

  bool HookRunner::waitIdle(std::chrono::milliseconds limit) {
    std::unique_lock lock(m_state->mutex);
    const auto idle = [this]() { return m_state->shutdown || (m_state->queue.empty() && awaited(*m_state) == 0); };
    if (m_state->idleCv.wait_for(lock, limit, idle)) {
      return true;
    }
    // stop waiting for what is running now; what is still queued gets the slots they held
    const auto now = std::chrono::steady_clock::now();
    for (auto& [id, hook] : m_state->active) {
      if (!hook.abandoned) {
        hook.abandoned = true;
        ++m_state->abandoned;
        const auto secs = std::chrono::duration_cast<std::chrono::seconds>(now - hook.started).count();
        kLog.warn("hook still running after {}s, no longer waited for (command: {})", secs, hook.command);
      }
    }
    lock.unlock();
    pump(m_state);
    return false;
  }

  std::size_t HookRunner::pendingCount() const {
    std::scoped_lock lock(m_state->mutex);
    return m_state->queue.size() + awaited(*m_state);
  }

  void HookRunner::pump(const std::shared_ptr<State>& state) {
    for (;;) {
      std::string command;
      std::uint64_t id = 0;
      {
        std::scoped_lock lock(state->mutex);
        while (!state->shutdown && awaited(*state) < state->maxConcurrent && !state->queue.empty()) {
          QueuedHook hook = std::move(state->queue.front());
          state->queue.pop_front();
          if (hook.generation < state->currentGeneration) {
            continue;
          }
          command = std::move(hook.command);
          ++state->running;
          id = state->nextId++;
          state->active.emplace(id, RunningHook{command, std::chrono::steady_clock::now(), false});
          break;
        }

        if (command.empty()) {
          if (state->queue.empty() && awaited(*state) == 0) {
            state->idleCv.notify_all();
          }
          return;
        }
      }

      if (!launch(state, command, id)) {
        std::scoped_lock lock(state->mutex);
        --state->running;
        state->active.erase(id);
      }
    }
  }

  bool HookRunner::launch(const std::shared_ptr<State>& state, const std::string& command, std::uint64_t id) {
    process::RunCallbacks callbacks;
    callbacks.onExit = [state, command, id](process::RunResult result) {
      if (!result) {
        kLog.warn("hook failed with exit code {}: {} (command: {})", result.exitCode, result.err, command);
      }
      {
        std::scoped_lock lock(state->mutex);
        --state->running;
        if (const auto it = state->active.find(id); it != state->active.end()) {
          if (it->second.abandoned) {
            --state->abandoned;
          }
          state->active.erase(it);
        }
      }
      pump(state);
    };

    process::RunOptions options;
    options.maxOutputBytes = kMaxHookOutputBytes;
    if (process::runAsync(command, std::move(callbacks), options)) {
      return true;
    }
    kLog.warn("failed to start hook (command: {})", command);
    return false;
  }

} // namespace noctalia::theme
