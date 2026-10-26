#pragma once

#include <string>
#include <string_view>

namespace zynith::build_info {

  // the product's name wherever the shell names itself to the user (notification sender, window titles, audio
  // streams); the command, paths and identifiers use zynith-shell / zynith.
  inline constexpr const char* kProductName = "Zynith";

  [[nodiscard]] std::string_view version() noexcept;

  [[nodiscard]] std::string_view revision() noexcept;

  [[nodiscard]] std::string displayVersion();

} // namespace zynith::build_info
