#include "ui/typography.h"

#include "render/text/font_spec.h"
#include "ui/controls/label.h"
#include "ui/style.h"

#include <array>
#include <utility>

namespace ui::type {

  namespace {

    constexpr std::string_view kDefaultDisplayFace = "Space Grotesk";
    constexpr std::string_view kDataFaces = "JetBrains Mono,JetBrainsMono Nerd Font,monospace";

    const std::array<Spec, kRoleCount> kSpecs = {{
        {.name = "display", .size = 64.0F, .weight = FontWeight::Light, .face = Face::Display, .tabular = true},
        {.name = "headline", .size = 32.0F, .weight = FontWeight::Normal, .face = Face::Display, .tabular = true},
        {.name = "title", .size = Style::fontSizeHeader, .weight = FontWeight::Medium, .face = Face::Interface},
        {.name = "subtitle", .size = Style::fontSizeTitle, .weight = FontWeight::Medium, .face = Face::Interface},
        {.name = "body", .size = Style::fontSizeBody, .weight = FontWeight::Normal, .face = Face::Interface},
        {.name = "label", .size = Style::fontSizeCaption, .weight = FontWeight::Medium, .face = Face::Interface},
        {.name = "micro", .size = Style::fontSizeMini, .weight = FontWeight::Medium, .face = Face::Interface},
        {.name = "numeric",
         .size = Style::fontSizeBody,
         .weight = FontWeight::Medium,
         .face = Face::Interface,
         .tabular = true},
        {.name = "data",
         .size = Style::fontSizeCaption,
         .weight = FontWeight::Normal,
         .face = Face::Data,
         .tabular = true},
    }};

    std::string g_interface = "sans-serif";
    std::string g_display;

  } // namespace

  const Spec& spec(Role role) noexcept {
    const auto index = static_cast<std::size_t>(role);
    return kSpecs[index < kRoleCount ? index : static_cast<std::size_t>(Role::Body)];
  }

  float size(Role role, float scale) noexcept { return spec(role).size * scale; }

  void setFamilies(std::string interfaceFamily, std::string displayFamily) {
    g_interface = interfaceFamily.empty() ? std::string("sans-serif") : std::move(interfaceFamily);
    g_display = std::move(displayFamily);
  }

  std::string family(Face face) {
    switch (face) {
    case Face::Interface:
      return g_interface;
    case Face::Display:
      // A configured display face wins; otherwise Space Grotesk, then the interface face — so an
      // uninstalled display face degrades to the interface face, not to a random system default.
      if (!g_display.empty()) {
        return g_display + "," + g_interface;
      }
      return std::string(kDefaultDisplayFace) + "," + g_interface;
    case Face::Data:
      return std::string(kDataFaces);
    }
    return g_interface;
  }

  std::string familyFor(Role role) {
    const Spec& s = spec(role);
    std::string out = family(s.face);
    if (s.tabular) {
      out.append(font_spec::kFeatureSeparator);
      out.append("tnum=1");
    }
    return out;
  }

  void apply(Label& label, Role role, float scale) {
    const Spec& s = spec(role);
    label.setFontSize(s.size * scale);
    label.setFontWeight(s.weight);
    label.setFontFamily(familyFor(role));
  }

} // namespace ui::type
