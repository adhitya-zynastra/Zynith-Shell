#include "zynith/ui_events.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace zynith {

  bool notifyUi(std::string_view name, std::string_view payload) {
    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    if (runtime == nullptr || *runtime != '/') {
      return false;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    const std::string path = std::string(runtime) + "/zynith/ui.sock";
    if (path.size() >= sizeof(addr.sun_path)) {
      return false;
    }
    std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);

    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) {
      return false;
    }
    // A Unix stream connect either completes at once or fails (no listener, or its backlog is full).
    bool sent = false;
    if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) == 0) {
      std::string line = "event ";
      line.append(name);
      if (!payload.empty()) {
        line.push_back(' ');
        line.append(payload);
      }
      line.push_back('\n');
      sent = ::send(fd, line.data(), line.size(), MSG_NOSIGNAL | MSG_DONTWAIT) == static_cast<ssize_t>(line.size());
    }
    ::close(fd);
    return sent;
  }

} // namespace zynith
