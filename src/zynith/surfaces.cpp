#include "zynith/surfaces.h"

#include "core/toml.h"

#include <cstdlib>
#include <filesystem>
#include <optional>
#include <string>

namespace zynith {

  namespace {

    std::filesystem::path configPath() {
      const char* config = std::getenv("XDG_CONFIG_HOME");
      const char* home = std::getenv("HOME");
      if (config != nullptr && *config == '/') {
        return std::filesystem::path(config) / "zynith" / "zynith.toml";
      }
      if (home != nullptr && *home != '\0') {
        return std::filesystem::path(home) / ".config" / "zynith" / "zynith.toml";
      }
      return {};
    }

    // Parsed once per change of the file: OSD events ask on every volume step.
    struct Cache {
      std::filesystem::path path;
      std::filesystem::file_time_type mtime{};
      std::optional<toml::table> table;
    };

  } // namespace

  bool uiOwns(std::string_view surface) {
    static Cache cache;
    const std::filesystem::path path = configPath();
    if (path.empty()) {
      return false;
    }
    std::error_code ec;
    const auto mtime = std::filesystem::last_write_time(path, ec);
    if (ec) {
      cache.table.reset();
      return false;
    }
    if (!cache.table.has_value() || cache.path != path || cache.mtime != mtime) {
      cache.path = path;
      cache.mtime = mtime;
      try {
        cache.table = toml::parse_file(path.string());
      } catch (const toml::parse_error&) {
        cache.table.reset(); // a broken file never takes a surface away
        return false;
      }
    }
    const auto value = (*cache.table)["surfaces"][surface].value<std::string>();
    return value.has_value() && *value == "zynith";
  }

} // namespace zynith
