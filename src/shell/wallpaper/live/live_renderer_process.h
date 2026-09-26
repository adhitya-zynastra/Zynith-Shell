#pragma once

// zynith: supervises the one live-wallpaper renderer process.
//
// Why exactly one: a live wallpaper is a full GPU renderer. Measured on a test laptop (integrated GPU,
// 1920x1200, 30 fps): a scene wallpaper is ~225 MB RSS and ~5 % of a core, a 4K video ~360 MB and ~80 %
// (software decode), a web wallpaper 10 processes, ~1.3 GB and ~100 %. Two of them overlapping during a
// switch would double that for no visible benefit, so the controller always stops the old renderer, waits
// for it to exit, and only then starts the next.
//
// Event-driven, no polling: the child is watched through a pidfd and its stdout/stderr pipe, both on the
// main poll loop; the startup grace and the stop deadline are one-shot timers. Nothing runs while the
// renderer is simply running.
//
// No orphans: the child gets its own process group (linux-wallpaperengine's embedded CEF spawns helper
// processes, which all share it and are signalled together) and PR_SET_PDEATHSIG, so even a crash of the
// shell takes the renderer down with it.

#include "app/poll_source.h"
#include "core/timer_manager.h"
#include "shell/wallpaper/live/live_wallpaper_types.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <string>
#include <sys/types.h>

class LiveRendererProcess : public PollSource {
public:
  enum class State : std::uint8_t {
    Idle,     // no child
    Starting, // spawned; inside the startup grace period
    Running,  // survived the grace period
    Stopping, // SIGTERM sent; SIGKILL follows at the stop deadline
  };

  struct Exit {
    bool requested = false;       // stop() was called
    bool duringStartup = false;   // died inside the startup grace period
    int exitCode = -1;            // -1 when killed by a signal
    int signal = 0;               // 0 when it exited normally
    std::chrono::milliseconds uptime{0};
    std::string outputTail;       // last lines of stdout/stderr, for diagnostics
  };

  using StartedCallback = std::function<void()>;
  using ExitCallback = std::function<void(const Exit&)>;

  // linux-wallpaperengine prints no readiness line; a renderer that is still alive after this long has
  // created its layer surface (it appears in `niri msg layers` well under a second) and is rendering.
  // Failures (missing item, bad assets, no EGL) abort within ~200 ms.
  static constexpr std::chrono::milliseconds kStartupGrace{1500};
  // SIGTERM -> SIGKILL. Scene/video renderers exit in 0.1-0.3 s; a web renderer takes ~5 s and then
  // aborts inside CEF shutdown anyway, so waiting longer buys nothing.
  static constexpr std::chrono::milliseconds kStopGrace{2000};

  LiveRendererProcess() = default;
  ~LiveRendererProcess() override;

  LiveRendererProcess(const LiveRendererProcess&) = delete;
  LiveRendererProcess& operator=(const LiveRendererProcess&) = delete;

  void setOnStarted(StartedCallback callback) { m_onStarted = std::move(callback); }
  void setOnExit(ExitCallback callback) { m_onExit = std::move(callback); }

  // Spawns the renderer. Only valid while Idle. On failure returns false with a message.
  [[nodiscard]] bool start(const live::LaunchSpec& spec, std::string& error);
  // Asynchronous: SIGTERM to the process group now, SIGKILL at kStopGrace. The exit callback fires once
  // the child is gone. No-op unless Starting/Running.
  void stop();
  // Synchronous teardown for shell shutdown: TERM, a short bounded wait, then KILL and reap.
  void terminateNow();

  [[nodiscard]] State state() const noexcept { return m_state; }
  [[nodiscard]] pid_t pid() const noexcept { return m_pid; }
  [[nodiscard]] bool active() const noexcept { return m_state != State::Idle; }
  [[nodiscard]] std::chrono::milliseconds uptime() const;

  [[nodiscard]] int pollTimeoutMs() const override { return -1; }
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override;

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override;

private:
  void readOutput();
  void closeOutput();
  // The child has exited (pidfd readable): kill stragglers in its group, reap it, clean up, report.
  void finishExit();
  void signalGroup(int sig) const;
  void removeScratchDir();

  State m_state = State::Idle;
  pid_t m_pid = -1;
  int m_pidfd = -1;
  int m_outFd = -1;
  int m_polledPidfd = -1; // what the last doAddPollFds() registered
  int m_polledOutFd = -1;
  bool m_stopRequested = false;
  std::chrono::steady_clock::time_point m_startedAt{};
  std::filesystem::path m_scratchDir;
  std::string m_tail;
  std::string m_partialLine;
  Timer m_graceTimer;
  Timer m_killTimer;
  StartedCallback m_onStarted;
  ExitCallback m_onExit;
};
