#include "security/process_hardening.h"

#include "core/log.h"

#include <array>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <execinfo.h>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <sys/prctl.h>
#include <unistd.h>

namespace security {

  namespace {

    constexpr Logger kLog("security");

    // Alternate stack for the fatal-signal handler (a stack overflow must still be able to report).
    alignas(16) std::array<char, 64 * 1024> gAltStack{};

    void writeAll(int fd, const char* data, std::size_t size) noexcept {
      while (size > 0) {
        const ssize_t n = ::write(fd, data, size);
        if (n <= 0) {
          return;
        }
        data += n;
        size -= static_cast<std::size_t>(n);
      }
    }

    void writeString(int fd, const char* text) noexcept { writeAll(fd, text, std::strlen(text)); }

    // Async-signal-safe decimal formatting.
    void writeNumber(int fd, long value) noexcept {
      char buffer[24];
      int pos = static_cast<int>(sizeof(buffer));
      const bool negative = value < 0;
      unsigned long v = negative ? static_cast<unsigned long>(-value) : static_cast<unsigned long>(value);
      do {
        buffer[--pos] = static_cast<char>('0' + (v % 10));
        v /= 10;
      } while (v != 0 && pos > 1);
      if (negative) {
        buffer[--pos] = '-';
      }
      writeAll(fd, buffer + pos, sizeof(buffer) - static_cast<std::size_t>(pos));
    }

    void fatalSignalHandler(int sig) {
      void* frames[64];
      const int count = ::backtrace(frames, 64);
      const int targets[2] = {logFileDescriptor(), STDERR_FILENO};
      for (const int fd : targets) {
        if (fd < 0) {
          continue;
        }
        writeString(fd, "\n[FATAL] noctalia: fatal signal ");
        writeNumber(fd, sig);
        writeString(fd, " (");
        writeString(fd, sigabbrev_np(sig) != nullptr ? sigabbrev_np(sig) : "?");
        writeString(fd, "), pid ");
        writeNumber(fd, static_cast<long>(::getpid()));
        writeString(fd, "; backtrace (resolve executable offsets with addr2line -Cfe <binary> <offset>):\n");
        ::backtrace_symbols_fd(frames, count, fd);
      }
      // SA_RESETHAND restored the default action; re-raise so the process dies with the original signal.
      ::raise(sig);
    }

  } // namespace

  bool disableCoreDumps() {
    const char* optOut = std::getenv("ZYNITH_ALLOW_COREDUMP");
    if (optOut != nullptr && std::strcmp(optOut, "1") == 0) {
      kLog.warn("core dumps left enabled (ZYNITH_ALLOW_COREDUMP=1): password material could reach a core file");
      return false;
    }
    if (::prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0) {
      kLog.warn("could not make the process non-dumpable: {}", std::strerror(errno));
      return false;
    }
    return !isDumpable();
  }

  bool isDumpable() noexcept { return ::prctl(PR_GET_DUMPABLE, 0, 0, 0, 0) == 1; }

  void installCrashBacktrace() {
    // backtrace() loads libgcc on first use, which is not async-signal-safe: warm it up now.
    void* warm[1];
    (void)::backtrace(warm, 1);

    stack_t altStack{};
    altStack.ss_sp = gAltStack.data();
    altStack.ss_size = gAltStack.size();
    altStack.ss_flags = 0;
    (void)::sigaltstack(&altStack, nullptr);

    struct sigaction action{};
    action.sa_handler = fatalSignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND | SA_ONSTACK;
    for (const int sig : {SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT}) {
      (void)::sigaction(sig, &action, nullptr);
    }
  }

  ProcessResources readSelfResources() {
    ProcessResources out;
    out.pid = static_cast<long>(::getpid());
    out.dumpable = isDumpable();
    {
      std::ifstream status("/proc/self/status");
      std::string line;
      while (std::getline(status, line)) {
        if (line.rfind("VmRSS:", 0) == 0) {
          out.rssKb = std::strtol(line.c_str() + 6, nullptr, 10);
        } else if (line.rfind("Threads:", 0) == 0) {
          out.threads = std::strtol(line.c_str() + 8, nullptr, 10);
        }
      }
    }
    {
      // Fields after the parenthesised command name, starting at field 3 (state): utime and stime are fields
      // 14 and 15, i.e. tokens 11 and 12 of the remainder.
      std::ifstream stat("/proc/self/stat");
      std::string content((std::istreambuf_iterator<char>(stat)), std::istreambuf_iterator<char>());
      const auto close = content.rfind(')');
      if (close != std::string::npos && close + 2 < content.size()) {
        std::istringstream rest(content.substr(close + 2));
        std::string token;
        long long utime = 0;
        long long stime = 0;
        for (int index = 0; rest >> token && index <= 12; ++index) {
          if (index == 11) {
            utime = std::strtoll(token.c_str(), nullptr, 10);
          } else if (index == 12) {
            stime = std::strtoll(token.c_str(), nullptr, 10);
          }
        }
        out.cpuTicks = utime + stime;
      }
    }
    if (DIR* dir = ::opendir("/proc/self/fd"); dir != nullptr) {
      long count = 0;
      while (const dirent* entry = ::readdir(dir)) {
        if (entry->d_name[0] != '.') {
          ++count;
        }
      }
      ::closedir(dir);
      out.fds = count - 1; // the directory stream's own descriptor
    }
    return out;
  }

} // namespace security
