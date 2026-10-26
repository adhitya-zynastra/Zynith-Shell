#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace zynith::theme::firefox_theme::settings {

  // Wire-compatible with the Pywalfox extension (~/.config/pywalfox/config.json).
  [[nodiscard]] std::optional<std::string> get(std::string_view key);
  bool set(std::string_view key, std::string_view value);

} // namespace zynith::theme::firefox_theme::settings
