#pragma once

#include "shell/settings/settings_registry.h"

#include <string>
#include <string_view>
#include <vector>

class ConfigService;

// zynith: the native settings registry, offered to the Zynith Settings app. The registry is the single
// description of every native setting (section, group, title, path, control and its bounds or options);
// this serialises it and applies edits through ConfigService overrides — the same writer the native
// Settings window uses, so settings.toml keeps one owner.
namespace zynith::settings_bridge {

  // With an empty `section`: the sections (id, label, glyph, how many settings, how many Zynith can edit).
  // With a section id: that section's settings, each with its kind, value, bounds or options and whether
  // it is overridden in settings.toml.
  [[nodiscard]] std::string schemaJson(
      const std::vector<settings::SettingEntry>& entries, const ConfigService& config, std::string_view section
  );

  // `request` is {"path": [...], "value": <json>}; the value is converted as the setting's control
  // stores it and validated by the schema before it is written. Returns "ok\n" or "error: …\n".
  [[nodiscard]] std::string set(
      const std::vector<settings::SettingEntry>& entries, ConfigService& config, std::string_view request
  );

  // `request` is {"path": [...]}: back to the value below the override (rice.toml or the default).
  [[nodiscard]] std::string reset(
      const std::vector<settings::SettingEntry>& entries, ConfigService& config, std::string_view request
  );

} // namespace zynith::settings_bridge
