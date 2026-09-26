#include "shell/wallpaper/live/live_renderer_process.h"

#include "core/log.h"

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <system_error>
#include <unistd.h>
#include <vector>

extern char** environ;

namespace {

  constexpr Logger kLog("live-renderer");
  // Keep the last few KB of renderer output for failure reports; lines are also logged at debug level.
  constexpr std::size_t kTailBytes = 4096;
  // terminateNow(): how long shutdown waits for a graceful exit before SIGKILL.
  constexpr int kShutdownWaitMs = 400;

  // Scratch dirs are only ever removed inside this subtree, whatever a LaunchSpec says.
  [[nodiscard]] bool isOwnScratchDir(const std::filesystem::path& dir) {
    const std::string text = dir.lexically_normal().string();
    return !dir.empty() && dir.is_absolute() && text.find("/zynith/live-wallpaper/") != std::string::npos;
  }

  // Direct syscall rather than glibc's pidfd_open(): Fedora 44's glibc 2.43 <sys/pidfd.h> declares it
  // without C linkage guards, so a C++ translation unit links against a mangled symbol that does not exist.
  [[nodiscard]] int openPidfd(pid_t pid) { return static_cast<int>(::syscall(SYS_pidfd_open, pid, 0U)); }

  void setCloexecNonblock(int fd) {
    (void)::fcntl(fd, F_SETFD, ::fcntl(fd, F_GETFD) | FD_CLOEXEC);
    (void)::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
  }

} // namespace

LiveRendererProcess::~LiveRendererProcess() { terminateNow(); }

std::chrono::milliseconds LiveRendererProcess::uptime() const {
  if (m_state == State::Idle) {
    return std::chrono::milliseconds{0};
  }
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - m_startedAt);
}

bool LiveRendererProcess::start(const live::LaunchSpec& spec, std::string& error) {
  if (m_state != State::Idle) {
    error = "a renderer is already running";
    return false;
  }
  if (spec.argv.empty() || spec.argv.front().empty()) {
    error = "no renderer command";
    return false;
  }
  if (::access(spec.argv.front().c_str(), X_OK) != 0) {
    error = "renderer is not executable: " + spec.argv.front();
    return false;
  }

  std::error_code ec;
  if (!spec.scratchDir.empty()) {
    std::filesystem::create_directories(spec.scratchDir, ec);
  }

  // Everything the child needs is prepared before fork(): after fork() in a multi-threaded process only
  // async-signal-safe calls are allowed until execve().
  std::vector<std::string> envStorage;
  for (char** e = environ; e != nullptr && *e != nullptr; ++e) {
    const std::string_view entry(*e);
    bool overridden = false;
    for (const auto& [name, value] : spec.env) {
      if (entry.size() > name.size() && entry.starts_with(name) && entry[name.size()] == '=') {
        overridden = true;
        break;
      }
    }
    if (!overridden) {
      envStorage.emplace_back(entry);
    }
  }
  for (const auto& [name, value] : spec.env) {
    envStorage.push_back(name + "=" + value);
  }
  std::vector<char*> envp;
  envp.reserve(envStorage.size() + 1);
  for (auto& entry : envStorage) {
    envp.push_back(entry.data());
  }
  envp.push_back(nullptr);

  std::vector<std::string> argStorage = spec.argv;
  std::vector<char*> argv;
  argv.reserve(argStorage.size() + 1);
  for (auto& arg : argStorage) {
    argv.push_back(arg.data());
  }
  argv.push_back(nullptr);
  const std::string workingDir = spec.workingDir.string();

  int pipeFds[2] = {-1, -1};
  if (::pipe2(pipeFds, O_CLOEXEC) != 0) {
    error = std::string("pipe failed: ") + std::strerror(errno);
    return false;
  }

  const pid_t parent = ::getpid();
  const pid_t pid = ::fork();
  if (pid < 0) {
    error = std::string("fork failed: ") + std::strerror(errno);
    ::close(pipeFds[0]);
    ::close(pipeFds[1]);
    return false;
  }

  if (pid == 0) {
    // Child. Own process group: stop() signals the renderer and every CEF helper it spawns at once.
    (void)::setpgid(0, 0);
    // If the shell dies (crash, restart), the renderer follows instead of lingering on the desktop.
    (void)::prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (::getppid() != parent) {
      ::_exit(127);
    }
    sigset_t none;
    ::sigemptyset(&none);
    ::sigprocmask(SIG_SETMASK, &none, nullptr);
    struct sigaction dfl {};
    dfl.sa_handler = SIG_DFL;
    for (const int sig : {SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGCHLD, SIGUSR1, SIGUSR2}) {
      ::sigaction(sig, &dfl, nullptr);
    }
    const int devNull = ::open("/dev/null", O_RDONLY);
    if (devNull >= 0) {
      ::dup2(devNull, STDIN_FILENO);
    }
    ::dup2(pipeFds[1], STDOUT_FILENO);
    ::dup2(pipeFds[1], STDERR_FILENO);
    ::close_range(3, ~0U, 0);
    if (!workingDir.empty() && ::chdir(workingDir.c_str()) != 0) {
      ::_exit(126);
    }
    ::execve(argv[0], argv.data(), envp.data());
    ::_exit(127);
  }

  // Parent. Set the group here too so a stop() racing the child's own setpgid() still hits the group.
  (void)::setpgid(pid, pid);
  ::close(pipeFds[1]);
  m_outFd = pipeFds[0];
  setCloexecNonblock(m_outFd);

  m_pidfd = openPidfd(pid);
  if (m_pidfd < 0) {
    // Without a pidfd the exit cannot be observed event-driven; refuse rather than poll.
    error = std::string("pidfd_open failed: ") + std::strerror(errno);
    ::kill(-pid, SIGKILL);
    siginfo_t info{};
    ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED);
    closeOutput();
    return false;
  }

  m_pid = pid;
  m_state = State::Starting;
  m_stopRequested = false;
  m_startedAt = std::chrono::steady_clock::now();
  m_scratchDir = spec.scratchDir;
  m_tail.clear();
  m_partialLine.clear();
  kLog.info("started renderer pid {}: {}", pid, spec.argv.size() > 1 ? spec.argv.back() : spec.argv.front());

  m_graceTimer.start(kStartupGrace, [this]() {
    if (m_state != State::Starting) {
      return;
    }
    m_state = State::Running;
    kLog.info("renderer pid {} is running", m_pid);
    if (m_onStarted) {
      m_onStarted();
    }
  });
  return true;
}

void LiveRendererProcess::stop() {
  if (m_state != State::Starting && m_state != State::Running) {
    return;
  }
  m_graceTimer.stop();
  m_stopRequested = true;
  m_state = State::Stopping;
  kLog.info("stopping renderer pid {}", m_pid);
  signalGroup(SIGTERM);
  m_killTimer.start(kStopGrace, [this]() {
    if (m_state == State::Stopping) {
      kLog.warn("renderer pid {} ignored SIGTERM for {} ms; killing its process group", m_pid, kStopGrace.count());
      signalGroup(SIGKILL);
    }
  });
}

void LiveRendererProcess::terminateNow() {
  if (m_state == State::Idle || m_pid <= 0) {
    return;
  }
  m_graceTimer.stop();
  m_killTimer.stop();
  signalGroup(SIGTERM);
  pollfd pfd{.fd = m_pidfd, .events = POLLIN, .revents = 0};
  if (::poll(&pfd, 1, kShutdownWaitMs) <= 0) {
    signalGroup(SIGKILL);
  }
  // Reap synchronously (SIGKILL cannot be ignored, so this returns promptly), without callbacks: the
  // owner is going away.
  m_onStarted = nullptr;
  m_onExit = nullptr;
  m_stopRequested = true;
  signalGroup(SIGKILL); // stragglers in the group, if the leader already exited
  siginfo_t info{};
  while (::waitid(P_PIDFD, static_cast<id_t>(m_pidfd), &info, WEXITED) < 0 && errno == EINTR) {
  }
  ::close(m_pidfd);
  m_pidfd = -1;
  closeOutput();
  removeScratchDir();
  kLog.info("renderer pid {} terminated at shutdown", m_pid);
  m_pid = -1;
  m_state = State::Idle;
}

void LiveRendererProcess::signalGroup(int sig) const {
  if (m_pid > 0) {
    // The group id is the leader's pid; the kernel does not recycle a pid while it is still in use as a
    // process group id, so this cannot hit an unrelated process.
    (void)::kill(-m_pid, sig);
  }
}

void LiveRendererProcess::doAddPollFds(std::vector<pollfd>& fds) {
  // Remember exactly what was registered: a source dispatched earlier in the same loop iteration (IPC, a
  // click) may start or stop the renderer before dispatch() runs, and dispatch() must only read the
  // entries this call appended.
  m_polledPidfd = m_pidfd;
  m_polledOutFd = m_outFd;
  if (m_polledPidfd >= 0) {
    fds.push_back({.fd = m_polledPidfd, .events = POLLIN, .revents = 0});
  }
  if (m_polledOutFd >= 0) {
    fds.push_back({.fd = m_polledOutFd, .events = POLLIN, .revents = 0});
  }
}

void LiveRendererProcess::dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) {
  std::size_t idx = startIdx;
  bool exited = false;
  bool readable = false;
  if (m_polledPidfd >= 0 && idx < fds.size()) {
    exited = fds[idx].fd == m_pidfd && (fds[idx].revents & (POLLIN | POLLHUP | POLLERR)) != 0;
    ++idx;
  }
  if (m_polledOutFd >= 0 && idx < fds.size()) {
    readable = fds[idx].fd == m_outFd && (fds[idx].revents & (POLLIN | POLLHUP | POLLERR)) != 0;
    ++idx;
  }
  m_polledPidfd = -1;
  m_polledOutFd = -1;
  if (readable) {
    readOutput();
  }
  // finishExit() re-checks with waitid(WNOHANG), so a stale readiness on a recycled fd number is harmless.
  if (exited && m_pidfd >= 0) {
    finishExit();
  }
}

void LiveRendererProcess::readOutput() {
  char buffer[8192];
  while (m_outFd >= 0) {
    const ssize_t n = ::read(m_outFd, buffer, sizeof(buffer));
    if (n > 0) {
      m_partialLine.append(buffer, static_cast<std::size_t>(n));
      std::size_t newline = 0;
      while ((newline = m_partialLine.find('\n')) != std::string::npos) {
        std::string line = m_partialLine.substr(0, newline);
        m_partialLine.erase(0, newline + 1);
        if (!line.empty()) {
          kLog.debug("pid {}: {}", m_pid, line);
          m_tail += line;
          m_tail.push_back('\n');
        }
      }
      if (m_partialLine.size() > kTailBytes) {
        m_partialLine.erase(0, m_partialLine.size() - kTailBytes);
      }
      if (m_tail.size() > kTailBytes) {
        m_tail.erase(0, m_tail.size() - kTailBytes);
      }
      continue;
    }
    if (n == 0) {
      closeOutput(); // every writer (renderer and helpers) is gone
      return;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      closeOutput();
    }
    return;
  }
}

void LiveRendererProcess::closeOutput() {
  if (m_outFd >= 0) {
    ::close(m_outFd);
    m_outFd = -1;
  }
}

void LiveRendererProcess::finishExit() {
  // Peek first (WNOWAIT): the leader stays a zombie, which keeps its process group id pinned while the
  // stragglers in it (CEF helpers) are killed. Only then reap.
  siginfo_t info{};
  int rc = 0;
  while ((rc = ::waitid(P_PIDFD, static_cast<id_t>(m_pidfd), &info, WEXITED | WNOHANG | WNOWAIT)) < 0
         && errno == EINTR) {
  }
  if (rc == 0 && info.si_pid == 0) {
    return; // not exited yet
  }
  signalGroup(SIGKILL);
  readOutput();
  if (rc == 0) {
    info = {};
    while (::waitid(P_PIDFD, static_cast<id_t>(m_pidfd), &info, WEXITED) < 0 && errno == EINTR) {
    }
  } else {
    // Already reaped elsewhere (should not happen: nothing in the shell waits on arbitrary children).
    // Treat it as exited with an unknown status rather than leave a readable pidfd spinning the loop.
    kLog.warn("waitid on renderer pid {} failed: {}", m_pid, std::strerror(errno));
    info = {};
    info.si_code = CLD_EXITED;
    info.si_status = -1;
  }

  Exit exit;
  exit.requested = m_stopRequested;
  exit.duringStartup = m_state == State::Starting;
  exit.uptime = uptime();
  if (info.si_code == CLD_EXITED) {
    exit.exitCode = info.si_status;
  } else {
    exit.signal = info.si_status;
  }
  if (!m_partialLine.empty()) {
    m_tail += m_partialLine;
    m_partialLine.clear();
  }
  exit.outputTail = std::move(m_tail);
  m_tail.clear();

  const pid_t pid = m_pid;
  m_graceTimer.stop();
  m_killTimer.stop();
  ::close(m_pidfd);
  m_pidfd = -1;
  closeOutput();
  removeScratchDir();
  m_pid = -1;
  m_state = State::Idle;
  m_stopRequested = false;

  if (exit.requested) {
    kLog.info("renderer pid {} stopped after {} ms", pid, exit.uptime.count());
  } else {
    kLog.warn(
        "renderer pid {} exited unexpectedly after {} ms (code {}, signal {})", pid, exit.uptime.count(),
        exit.exitCode, exit.signal
    );
    if (!exit.outputTail.empty()) {
      kLog.warn("renderer output tail:\n{}", exit.outputTail);
    }
  }

  // State is already Idle, so the callback may start the next renderer right away.
  if (m_onExit) {
    m_onExit(exit);
  }
}

void LiveRendererProcess::removeScratchDir() {
  if (m_scratchDir.empty()) {
    return;
  }
  if (isOwnScratchDir(m_scratchDir)) {
    std::error_code ec;
    std::filesystem::remove_all(m_scratchDir, ec);
    if (ec) {
      kLog.debug("could not remove renderer scratch dir {}: {}", m_scratchDir.string(), ec.message());
    }
  }
  m_scratchDir.clear();
}
