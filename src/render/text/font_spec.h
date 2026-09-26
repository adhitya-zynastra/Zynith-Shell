#pragma once

#include <string_view>

// A font family string may carry OpenType features after " #", in Pango's own description syntax:
// "Inter #tnum=1" = the Inter family (or a comma-separated fallback list) with tabular figures.
// The text renderer splits it where it builds the Pango font description; ui::type produces it.
namespace font_spec {

  inline constexpr std::string_view kFeatureSeparator = " #";

  struct Parts {
    std::string_view family;
    std::string_view features; // e.g. "tnum=1"; empty when none
  };

  [[nodiscard]] constexpr Parts split(std::string_view spec) noexcept {
    const auto at = spec.find(kFeatureSeparator);
    if (at == std::string_view::npos) {
      return {.family = spec, .features = {}};
    }
    return {.family = spec.substr(0, at), .features = spec.substr(at + kFeatureSeparator.size())};
  }

} // namespace font_spec
