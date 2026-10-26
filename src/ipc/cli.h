#pragma once

namespace zynith::ipc {

  // Entry point for `zynith-shell msg <command> [args...]`. Returns a process exit
  // code. Forwards the command to the running instance over the IPC socket.
  int runCli(int argc, char* argv[]);

} // namespace zynith::ipc
