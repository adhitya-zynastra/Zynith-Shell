#include "zynith/settings_bridge.h"

#include "config/config_service.h"
#include "i18n/i18n.h"
#include "ui/palette.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <nlohmann/json.hpp>
#include <optional>
#include <type_traits>
#include <variant>

namespace zynith::settings_bridge {

  namespace {

    using json = nlohmann::json;
    using Overrides = std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>;

    json optionsJson(const std::vector<settings::SelectOption>& options) {
      json out = json::array();
      for (const auto& o : options) {
        json item{{"value", o.value}, {"label", o.label}};
        if (!o.description.empty()) {
          item["description"] = o.description;
        }
        out.push_back(std::move(item));
      }
      return out;
    }

    std::string_view selectValueType(settings::SelectValueType t) {
      switch (t) {
      case settings::SelectValueType::Integer:
        return "int";
      case settings::SelectValueType::Boolean:
        return "bool";
      case settings::SelectValueType::String:
        break;
      }
      return "string";
    }

    // the control as the Zynith Settings draws it; kinds it cannot draw stay "native"
    json controlJson(const settings::SettingControl& control) {
      return std::visit(
          [](const auto& c) -> json {
            using T = std::decay_t<decltype(c)>;
            if constexpr (std::is_same_v<T, settings::ToggleSetting>) {
              return {{"kind", "toggle"}, {"value", c.checked}, {"enabled", c.enabled}};
            } else if constexpr (std::is_same_v<T, settings::SelectSetting>) {
              return {
                  {"kind", "select"},
                  {"value", c.selectedValue},
                  {"options", optionsJson(c.options)},
                  {"segmented", c.segmented},
                  {"valueType", selectValueType(c.valueType)},
              };
            } else if constexpr (std::is_same_v<T, settings::SearchPickerSetting>) {
              return {
                  {"kind", "select"}, {"value", c.selectedValue}, {"options", optionsJson(c.options)}, {"search", true}
              };
            } else if constexpr (std::is_same_v<T, settings::SliderSetting>) {
              return {
                  {"kind", "slider"}, {"value", c.value},          {"min", c.minValue},       {"max", c.maxValue},
                  {"step", c.step},   {"integer", c.integerValue}, {"suffix", c.valueSuffix},
              };
            } else if constexpr (std::is_same_v<T, settings::RangeSliderSetting>) {
              return {
                  {"kind", "range"},           {"low", c.lowValue},       {"high", c.highValue},
                  {"min", c.minValue},         {"max", c.maxValue},       {"step", c.step},
                  {"integer", c.integerValue}, {"suffix", c.valueSuffix}, {"highPath", c.highPath},
              };
            } else if constexpr (std::is_same_v<T, settings::TextSetting>) {
              return {
                  {"kind", "text"},
                  {"value", c.value},
                  {"placeholder", c.placeholder},
                  {"browse",
                   c.browseMode == settings::TextSettingBrowseMode::SelectFolder   ? "folder"
                       : c.browseMode == settings::TextSettingBrowseMode::OpenFile ? "file"
                                                                                   : ""},
              };
            } else if constexpr (std::is_same_v<T, settings::OptionalNumberSetting>) {
              return {
                  {"kind", "number"},
                  {"value", c.value ? json(*c.value) : json(nullptr)},
                  {"min", c.minValue},
                  {"max", c.maxValue},
                  {"placeholder", c.placeholder},
              };
            } else if constexpr (std::is_same_v<T, settings::OptionalStepperSetting>) {
              return {
                  {"kind", "stepper"}, {"value", c.value ? json(*c.value) : json(nullptr)},
                  {"min", c.minValue}, {"max", c.maxValue},
                  {"step", c.step},    {"fallback", c.fallbackValue},
                  {"optional", true},  {"unsetLabel", c.unsetLabel},
              };
            } else if constexpr (std::is_same_v<T, settings::StepperSetting>) {
              return {
                  {"kind", "stepper"}, {"value", c.value}, {"min", c.minValue},
                  {"max", c.maxValue}, {"step", c.step},   {"suffix", c.valueSuffix},
              };
            } else if constexpr (std::is_same_v<T, settings::ListSetting>) {
              return {{"kind", "list"}, {"value", c.items}, {"options", optionsJson(c.suggestedOptions)}};
            } else if constexpr (std::is_same_v<T, settings::MultiSelectSetting>) {
              return {
                  {"kind", "multi"},
                  {"value", c.selectedValues},
                  {"options", optionsJson(c.options)},
                  {"requireOne", c.requireAtLeastOne},
              };
            } else if constexpr (std::is_same_v<T, settings::ColorSpecPickerSetting>) {
              json roles = json::array();
              for (const auto role : c.roles) {
                roles.push_back(std::string(colorRoleToken(role)));
              }
              return {{"kind", "color"}, {"value", c.selectedValue}, {"roles", roles}, {"allowNone", c.allowNone}};
            } else {
              return {{"kind", "native"}};
            }
          },
          control
      );
    }

    const settings::SettingEntry* findEntry(
        const std::vector<settings::SettingEntry>& entries, const std::vector<std::string>& path, bool* isHighPath
    ) {
      for (const auto& e : entries) {
        if (e.path == path) {
          *isHighPath = false;
          return &e;
        }
        if (const auto* range = std::get_if<settings::RangeSliderSetting>(&e.control);
            range != nullptr && range->highPath == path) {
          *isHighPath = true;
          return &e;
        }
      }
      return nullptr;
    }

    std::optional<std::vector<std::string>> pathOf(const json& request) {
      if (!request.is_object() || !request.contains("path") || !request["path"].is_array()) {
        return std::nullopt;
      }
      std::vector<std::string> path;
      for (const auto& p : request["path"]) {
        if (!p.is_string()) {
          return std::nullopt;
        }
        path.push_back(p.get<std::string>());
      }
      if (path.empty()) {
        return std::nullopt;
      }
      return path;
    }

    std::optional<double> number(const json& v) {
      if (v.is_number()) {
        return v.get<double>();
      }
      if (v.is_string()) {
        try {
          return std::stod(v.get<std::string>());
        } catch (const std::exception&) {
        }
      }
      return std::nullopt;
    }

    std::optional<std::vector<std::string>> strings(const json& v) {
      if (!v.is_array()) {
        return std::nullopt;
      }
      std::vector<std::string> out;
      for (const auto& s : v) {
        if (!s.is_string()) {
          return std::nullopt;
        }
        out.push_back(s.get<std::string>());
      }
      return out;
    }

    // what to write for `value`, as the entry's control stores it; nullopt + clear = remove the override
    struct Converted {
      Overrides set;
      bool clear = false;
      std::string error;
    };

    Converted convert(const settings::SettingEntry& entry, const std::vector<std::string>& path, const json& v) {
      Converted out;
      const auto put = [&](ConfigOverrideValue value) { out.set.emplace_back(path, std::move(value)); };
      std::visit(
          [&](const auto& c) {
            using T = std::decay_t<decltype(c)>;
            if constexpr (std::is_same_v<T, settings::ToggleSetting>) {
              if (!v.is_boolean()) {
                out.error = "a toggle takes true or false";
                return;
              }
              put(v.get<bool>());
            } else if constexpr (std::is_same_v<T, settings::SelectSetting>) {
              const std::string chosen = v.is_string() ? v.get<std::string>() : v.dump();
              if (chosen.empty() && c.clearOnEmpty) {
                out.clear = true;
                return;
              }
              if (!c.options.empty()
                  && std::ranges::none_of(c.options, [&](const auto& o) { return o.value == chosen; })) {
                out.error = "not one of the options";
                return;
              }
              if (c.groupedCommit) {
                out.set = c.groupedCommit(chosen, path);
                return;
              }
              switch (c.valueType) {
              case settings::SelectValueType::Integer:
                if (const auto n = number(v)) {
                  put(static_cast<std::int64_t>(std::llround(*n)));
                } else {
                  out.error = "a number";
                }
                break;
              case settings::SelectValueType::Boolean:
                put(chosen == "true");
                break;
              case settings::SelectValueType::String:
                put(chosen);
                break;
              }
            } else if constexpr (std::is_same_v<T, settings::SearchPickerSetting>) {
              if (!v.is_string()) {
                out.error = "a picker takes a string";
                return;
              }
              if (c.onSelect) {
                c.onSelect(v.get<std::string>()); // it commits by itself
                return;
              }
              put(v.get<std::string>());
            } else if constexpr (
                std::is_same_v<T, settings::SliderSetting> || std::is_same_v<T, settings::RangeSliderSetting>
            ) {
              const auto n = number(v);
              if (!n) {
                out.error = "a slider takes a number";
                return;
              }
              const double clamped = std::clamp(*n, c.minValue, c.maxValue);
              if (c.integerValue) {
                put(static_cast<std::int64_t>(std::llround(clamped)));
              } else {
                put(clamped);
              }
              if constexpr (std::is_same_v<T, settings::SliderSetting>) {
                if (c.linkedCommit) {
                  for (auto& extra : c.linkedCommit(clamped)) {
                    out.set.push_back(std::move(extra));
                  }
                }
              }
            } else if constexpr (std::is_same_v<T, settings::TextSetting>) {
              if (!v.is_string()) {
                out.error = "text";
                return;
              }
              put(v.get<std::string>());
            } else if constexpr (std::is_same_v<T, settings::OptionalNumberSetting>) {
              if (v.is_null()) {
                out.clear = true;
                return;
              }
              const auto n = number(v);
              if (!n) {
                out.error = "a number or null";
                return;
              }
              put(std::clamp(*n, c.minValue, c.maxValue));
            } else if constexpr (
                std::is_same_v<T, settings::OptionalStepperSetting> || std::is_same_v<T, settings::StepperSetting>
            ) {
              if (v.is_null()) {
                if constexpr (std::is_same_v<T, settings::OptionalStepperSetting>) {
                  out.clear = true;
                } else {
                  out.error = "a number";
                }
                return;
              }
              const auto n = number(v);
              if (!n) {
                out.error = "a number";
                return;
              }
              put(static_cast<std::int64_t>(std::clamp<long long>(std::llround(*n), c.minValue, c.maxValue)));
            } else if constexpr (std::is_same_v<T, settings::ListSetting>) {
              const auto list = strings(v);
              if (!list) {
                out.error = "a list of strings";
                return;
              }
              put(*list);
            } else if constexpr (std::is_same_v<T, settings::MultiSelectSetting>) {
              const auto chosen = strings(v);
              if (!chosen) {
                out.error = "a list of strings";
                return;
              }
              if (c.requireAtLeastOne && chosen->empty()) {
                out.error = "at least one";
                return;
              }
              if (c.persistUnselected) {
                std::vector<std::string> unselected;
                for (const auto& o : c.options) {
                  if (std::ranges::find(*chosen, o.value) == chosen->end()) {
                    unselected.push_back(o.value);
                  }
                }
                put(unselected);
              } else {
                put(*chosen);
              }
            } else if constexpr (std::is_same_v<T, settings::ColorSpecPickerSetting>) {
              if (!v.is_string()) {
                out.error = "a colour role or #hex";
                return;
              }
              if (v.get<std::string>().empty() && c.allowNone) {
                out.clear = true;
                return;
              }
              put(v.get<std::string>());
            } else {
              out.error = "this one is edited in the native Settings";
            }
          },
          entry.control
      );
      return out;
    }

  } // namespace

  std::string schemaJson(
      const std::vector<settings::SettingEntry>& entries, const ConfigService& config, std::string_view section
  ) {
    if (section.empty()) {
      std::map<std::string, std::pair<int, int>> counts; // id -> (all, editable here)
      for (const auto& e : entries) {
        auto& c = counts[std::string(settings::settingsSectionId(e.section))];
        ++c.first;
        if (controlJson(e.control)["kind"] != "native") {
          ++c.second;
        }
      }
      json sections = json::array();
      for (const auto& d : settings::settingsSectionDescriptors()) {
        const std::string id(d.id);
        const auto it = counts.find(id);
        sections.push_back({
            {"id", id},
            {"label", i18n::tr(settings::settingsSectionLabelKey(d.section))},
            {"glyph", std::string(d.glyph)},
            {"count", it != counts.end() ? it->second.first : 0},
            {"editable", it != counts.end() ? it->second.second : 0},
        });
      }
      return json{{"sections", sections}}.dump(-1, ' ', false, json::error_handler_t::replace) + "\n";
    }

    json out = json::array();
    for (const auto& e : entries) {
      if (settings::settingsSectionId(e.section) != section) {
        continue;
      }
      json item = controlJson(e.control);
      item["group"] = e.group;
      item["groupLabel"] = e.group.empty() ? std::string() : i18n::tr("settings.navigation.groups." + e.group);
      item["title"] = e.title;
      item["subtitle"] = e.subtitle;
      item["path"] = e.path;
      item["advanced"] = e.advanced;
      item["visible"] = !e.visibleWhen || e.visibleWhen(config.config());
      item["overridden"] = !e.path.empty() && config.hasOverride(e.path);
      out.push_back(std::move(item));
    }
    return json{{"section", section}, {"entries", out}}.dump(-1, ' ', false, json::error_handler_t::replace) + "\n";
  }

  std::string set(const std::vector<settings::SettingEntry>& entries, ConfigService& config, std::string_view request) {
    const json req = json::parse(request, nullptr, false);
    const auto path = pathOf(req);
    if (!path || !req.contains("value")) {
      return "error: settings-set {\"path\": [...], \"value\": …}\n";
    }
    bool isHigh = false;
    const auto* entry = findEntry(entries, *path, &isHigh);
    if (entry == nullptr) {
      return "error: no such setting\n";
    }
    Converted c = convert(*entry, *path, req["value"]);
    if (!c.error.empty()) {
      return "error: " + c.error + "\n";
    }
    if (c.clear) {
      return config.clearOverride(*path) ? "ok\n" : "error: not cleared\n";
    }
    if (c.set.empty()) {
      return "ok\n"; // committed by the control itself
    }
    for (const auto& [p, v] : c.set) {
      std::string why;
      if (!config.validateOverride(p, v, &why)) {
        return "error: " + (why.empty() ? std::string("rejected by the schema") : why) + "\n";
      }
    }
    return config.setOverrides(std::move(c.set)) ? "ok\n" : "error: not written\n";
  }

  std::string
  reset(const std::vector<settings::SettingEntry>& entries, ConfigService& config, std::string_view request) {
    const json req = json::parse(request, nullptr, false);
    const auto path = pathOf(req);
    if (!path) {
      return "error: settings-reset {\"path\": [...]}\n";
    }
    bool isHigh = false;
    if (findEntry(entries, *path, &isHigh) == nullptr) {
      return "error: no such setting\n";
    }
    if (!config.hasOverride(*path)) {
      return "ok\n";
    }
    return config.clearOverride(*path) ? "ok\n" : "error: not cleared\n";
  }

} // namespace zynith::settings_bridge
