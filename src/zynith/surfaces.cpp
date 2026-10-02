#include "zynith/surfaces.h"

#include "core/toml.h"

#include <cstdlib>
#include <filesystem>
#include <string>

namespace zynith {

  bool uiOwns(std::string_view surface) {
    const char* config = std::getenv("XDG_CONFIG_HOME");
    const char* home = std::getenv("HOME");
    std::filesystem::path path;
    if (config != nullptr && *config == '/') {
      path = std::filesystem::path(config) / "zynith" / "zynith.toml";
    } else if (home != nullptr && *home != '\0') {
      path = std::filesystem::path(home) / ".config" / "zynith" / "zynith.toml";
    } else {
      return false;
    }
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) {
      return false;
    }
    try {
      const auto table = toml::parse_file(path.string());
      const auto value = table["surfaces"][surface].value<std::string>();
      return value.has_value() && *value == "zynith";
    } catch (const toml::parse_error&) {
      return false; // a broken file never takes a surface away
    }
  }

} // namespace zynith
