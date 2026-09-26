#pragma once

#include "render/core/renderer.h"

#include <cstdint>
#include <string>
#include <string_view>

class Label;

// zynith typography: text chosen by what it IS (a title, a value, a technical readout), not by a size.
//
// Three faces, one role each:
//   Interface  all language: the configured [shell].font_family (Inter is the recommended face)
//   Display    large numerals and identity moments: [shell].display_font_family, else Space Grotesk,
//              falling back to the interface face when Space Grotesk is not installed
//   Data       literal technical values: JetBrains Mono
//
// A face is a Pango family LIST, so a missing font falls back to the next one instead of to an
// arbitrary system default. Tabular figures (digits of equal width, so a changing number does not
// jitter) are requested with a " #tnum=1" suffix, which the text renderer turns into an OpenType
// feature on the font description (Pango >= 1.56).
//
// Sizes: the ramp spans 11 -> 64 px (about 5.8x) so a surface can have a real focal point; the middle
// steps are the sizes the shell already used (Style::fontSize*), so existing text keeps its size.
namespace ui::type {

  enum class Face : std::uint8_t { Interface, Display, Data };

  enum class Role : std::uint8_t {
    Display,  // 64 light  display  hero numerals: a clock, the one big value of a surface
    Headline, // 32 normal display  a section's primary value (temperature, battery %)
    Title,    // 20 medium iface    surface and section titles
    Subtitle, // 16 medium iface    primary rows
    Body,     // 14 normal iface    everything else
    Label,    // 13 medium iface    control labels, captions
    Micro,    // 11 medium iface    tags, counts
    Numeric,  // 14 medium iface    numbers that change, in the UI voice (tabular)
    Data,     // 13 normal mono     literal technical values: rates, keys, ids (tabular)
    Count,
  };

  struct Spec {
    std::string_view name;
    float size = 14.0F; // logical px at scale 1
    FontWeight weight = FontWeight::Normal;
    Face face = Face::Interface;
    bool tabular = false;
  };

  [[nodiscard]] const Spec& spec(Role role) noexcept;
  [[nodiscard]] float size(Role role, float scale = 1.0F) noexcept;

  // Set by the shell whenever [shell].font_family / display_font_family change. Empty display = none
  // configured (use the default display list).
  void setFamilies(std::string interfaceFamily, std::string displayFamily);

  // The family list for a face, e.g. "Space Grotesk,Montserrat".
  [[nodiscard]] std::string family(Face face);
  // The family string for a role, including the tabular-figures request when the role asks for it.
  [[nodiscard]] std::string familyFor(Role role);

  // Applies a role to a label: size (x scale), weight and family.
  void apply(Label& label, Role role, float scale = 1.0F);

  inline constexpr std::size_t kRoleCount = static_cast<std::size_t>(Role::Count);

} // namespace ui::type
