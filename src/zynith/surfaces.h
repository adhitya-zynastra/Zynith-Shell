#pragma once

// zynith: which visible surfaces the Zynith UI (Quickshell) draws instead of this shell. Read from
// ~/.config/zynith/zynith.toml:
//
//   [surfaces]
//   bar = "zynith"        # or "native" (the default for every surface)
//
// The shell keeps every service behind those surfaces; only its own windows step aside.

#include <string_view>

namespace zynith {

  [[nodiscard]] bool uiOwns(std::string_view surface);

} // namespace zynith
