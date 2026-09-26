// zynith process hardening: the shell and its PAM helper must not produce core dumps (password material), the
// restriction must not leak into programs they execute, and crashes must stay diagnosable without a core.
//
// Every check that changes process state runs in a forked child, so the test binary itself is left untouched.

#include "security/process_hardening.h"

#include <array>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>

namespace {

  int failures = 0;

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
    return cond;
  }

  // Runs `body` in a child; returns the raw wait status.
  template <typename Fn> int inChild(Fn body) {
    const pid_t pid = ::fork();
    if (pid == 0) {
      _exit(body());
    }
    int status = 0;
    ::waitpid(pid, &status, 0);
    return status;
  }

  bool exitedWith(int status, int code) { return WIFEXITED(status) && WEXITSTATUS(status) == code; }

} // namespace

int main() {
  ::unsetenv("ZYNITH_ALLOW_COREDUMP");

  check(security::isDumpable(), "a fresh process is dumpable");

  check(exitedWith(inChild([] { return security::disableCoreDumps() && !security::isDumpable() ? 0 : 1; }), 0),
        "disableCoreDumps makes the process non-dumpable");

  check(exitedWith(inChild([] {
          ::setenv("ZYNITH_ALLOW_COREDUMP", "1", 1);
          return !security::disableCoreDumps() && security::isDumpable() ? 0 : 1;
        }), 0),
        "ZYNITH_ALLOW_COREDUMP=1 opts out");

  // Scope: a program executed by a non-dumpable process is dumpable again, so apps launched from the shell keep
  // their own core dumps. From inside, a dumpable process owns its /proc/self/fd; a non-dumpable one does not.
  check(exitedWith(inChild([] {
          security::disableCoreDumps();
          ::execl("/bin/sh", "sh", "-c", "test -O /proc/self/fd", static_cast<char*>(nullptr));
          return 99;
        }), 0),
        "an executed program is not affected (exec resets dumpability)");

  // Self-inspection works while non-dumpable (this is what `noctalia msg status` reports).
  check(exitedWith(inChild([] {
          security::disableCoreDumps();
          const auto res = security::readSelfResources();
          const bool ok = res.pid == static_cast<long>(::getpid()) && res.rssKb > 0 && res.threads >= 1
              && res.fds >= 3 && res.cpuTicks >= 0 && !res.dumpable;
          return ok ? 0 : 1;
        }), 0),
        "readSelfResources reports pid, rss, threads, fds and dumpable while non-dumpable");

  // The crash handler writes a backtrace, then the process still dies of the original signal.
  {
    int pipeFds[2];
    check(::pipe(pipeFds) == 0, "pipe");
    const pid_t pid = ::fork();
    if (pid == 0) {
      ::close(pipeFds[0]);
      ::dup2(pipeFds[1], STDERR_FILENO);
      security::disableCoreDumps(); // no core file from the deliberate crash
      security::installCrashBacktrace();
      ::raise(SIGSEGV);
      _exit(0);
    }
    ::close(pipeFds[1]);
    std::string out;
    std::array<char, 4096> buffer{};
    ssize_t n = 0;
    while ((n = ::read(pipeFds[0], buffer.data(), buffer.size())) > 0) {
      out.append(buffer.data(), static_cast<std::size_t>(n));
    }
    ::close(pipeFds[0]);
    int status = 0;
    ::waitpid(pid, &status, 0);
    check(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV, "the process still dies of SIGSEGV");
    check(out.find("[FATAL] noctalia: fatal signal 11 (SEGV)") != std::string::npos, "the signal is reported");
    check(out.find("backtrace") != std::string::npos && out.find("process_hardening_test") != std::string::npos,
          "a backtrace naming the executable is written");
  }

  if (failures == 0) {
    std::cout << "process hardening test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
