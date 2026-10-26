#pragma once

namespace zynith::config {

  // Entry point for `zynith-shell config <command> [options]`. Returns a process
  // exit code. Pure CLI helper; does not start Application or mutate live config.
  int runCli(int argc, char* argv[]);

} // namespace zynith::config
