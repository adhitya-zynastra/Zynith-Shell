#pragma once

#include <string>

class IpcClient {
public:
  // Sends `command` to the running zynith-shell instance.
  // Prints the response to stdout. Returns 0 on success, 1 on error.
  static int send(const std::string& command);
};
