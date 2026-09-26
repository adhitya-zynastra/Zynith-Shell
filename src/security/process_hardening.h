#pragma once

#include <cstdint>

// zynith: process-level hardening for the shell and its PAM helper.
//
// The shell can hold password material — the lock screen's field, the PAM helper's copy, polkit and Wi-Fi prompts.
// A core dump would write that memory to disk (systemd-coredump keeps cores), so both processes make themselves
// non-dumpable at startup (PR_SET_DUMPABLE 0). The scope is exactly those processes: the kernel resets the attribute
// on execve(), so every application the shell launches keeps its own core-dump behaviour, and nothing system-wide
// changes. Consequences of a non-dumpable process: no core file, no ptrace attach by the same user (gdb -p), and
// /proc/<pid>/{fd,maps,environ,...} become root-owned — which is why the shell reports its own resources over IPC
// (`noctalia msg status`). Crashes stay diagnosable through installCrashBacktrace().
//
// For a debugging session, ZYNITH_ALLOW_COREDUMP=1 in the shell's environment skips the restriction.
namespace security {

  // Returns true when the process is non-dumpable afterwards (false when opted out or prctl failed).
  bool disableCoreDumps();
  [[nodiscard]] bool isDumpable() noexcept;

  // Fatal-signal handlers (SEGV, BUS, FPE, ILL, ABRT) that write the signal and a backtrace to the log file and
  // stderr, then re-raise with the default action. Uses an alternate signal stack so a stack overflow still reports.
  // Frames of the executable print as offsets; resolve with `addr2line -Cfe <noctalia binary> <offset>`.
  void installCrashBacktrace();

  struct ProcessResources {
    long pid = 0;
    long rssKb = 0;
    long threads = 0;
    long fds = 0;
    long long cpuTicks = 0; // utime + stime, in clock ticks
    bool dumpable = true;
  };
  // Reads /proc/self, which a process may always inspect, dumpable or not.
  [[nodiscard]] ProcessResources readSelfResources();

} // namespace security
