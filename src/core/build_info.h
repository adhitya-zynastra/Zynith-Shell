#pragma once

#include <string>
#include <string_view>

namespace noctalia::build_info {

  // the product's name wherever the shell names itself to the user (notification sender, window titles, audio
  // streams). The code's own identifiers (namespace, command, configuration paths) keep their historical name.
  inline constexpr const char* kProductName = "Zynith";

  [[nodiscard]] std::string_view version() noexcept;

  [[nodiscard]] std::string_view revision() noexcept;

  [[nodiscard]] std::string displayVersion();

} // namespace noctalia::build_info
