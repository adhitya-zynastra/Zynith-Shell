// zynith design tokens: geometry, typography roles, semantic colour, contrast and the surface hierarchy.
//
// Two kinds of property are checked: that each token reproduces the value the shell used before tokens
// existed (so adopting a token is a no-op for existing surfaces), and the invariants the design system
// promises (ramp order, depth order, exit shorter than entrance, not-everything-is-glass).

#include "config/config_types.h"
#include "render/text/font_spec.h"
#include "shell/surface/glass.h"
#include "shell/surface/surface_role.h"
#include "ui/palette.h"
#include "ui/semantic_color.h"
#include "ui/style.h"
#include "ui/tokens.h"
#include "ui/typography.h"
#include "wayland/layer_surface.h"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <string>

namespace {

  int failures = 0;

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
    return cond;
  }

  bool near(float a, float b, float eps = 1e-4F) { return std::abs(a - b) <= eps; }

} // namespace

int main() {
  using namespace ui;

  // --- geometry -----------------------------------------------------------------------------------
  {
    const float expected[] = {4, 8, 12, 16, 24, 32, 48, 64};
    for (int i = 0; i < 8; ++i) {
      check(tokens::space(static_cast<tokens::Space>(i)) == expected[i], "spacing scale 4..64");
    }
    check(tokens::space(tokens::Space::Group, 1.5F) == 24.0F, "spacing scales with content scale");

    for (const float corner : {0.6F, 1.0F, 2.0F}) {
      Style::setCornerRadiusScale(corner);
      for (const float scale : {1.0F, 1.25F}) {
        // The rule the panel, toast and wallpaper-browser surfaces each carried before the token.
        const float before = std::max(Style::scaledRadiusXl(scale), 16.0F * scale);
        check(near(tokens::radius(tokens::Radius::Surface, scale), before), "Surface radius equals the old copies");
        check(near(tokens::radius(tokens::Radius::Plate, scale), Style::scaledRadiusXl(scale)), "Plate = scaled Xl");
        check(tokens::radius(tokens::Radius::Stage, scale) == 0.0F, "Stage is square");
      }
    }
    Style::setCornerRadiusScale(0.6F);
    check(tokens::radius(tokens::Radius::Surface) == 16.0F, "at the preset's 0.6 corner scale a surface is 16 px");
    check(tokens::concentric(16.0F, 12.0F) == 4.0F && tokens::concentric(20.0F, 8.0F) == 12.0F, "concentric radii");
    check(tokens::pill(38.0F) == 19.0F, "pill = half height");
    check(tokens::controlHeight(tokens::Size::Medium) == Style::controlHeight, "control heights are Style's");
    check(tokens::iconContainer(tokens::Size::Large) == 48.0F && tokens::iconSize(tokens::Size::Small) == 16.0F,
          "icon sizes and containers");
  }

  // --- typography ---------------------------------------------------------------------------------
  {
    using type::Role;
    const Role ramp[] = {Role::Display, Role::Headline, Role::Title, Role::Subtitle, Role::Body, Role::Label, Role::Micro};
    for (std::size_t i = 1; i < std::size(ramp); ++i) {
      check(type::spec(ramp[i - 1]).size > type::spec(ramp[i]).size, "the type ramp strictly descends");
    }
    check(type::spec(Role::Display).size / type::spec(Role::Micro).size >= 5.0F, "the ramp spans at least 5x");
    // Existing text keeps its size: the middle of the ramp is Style's sizes.
    check(type::spec(Role::Title).size == Style::fontSizeHeader, "title = the old header size");
    check(type::spec(Role::Body).size == Style::fontSizeBody, "body = the old body size");
    check(type::spec(Role::Micro).size == Style::fontSizeMini, "micro = the old mini size");
    check(type::spec(Role::Display).weight == FontWeight::Light, "display is set light");
    check(type::spec(Role::Data).face == type::Face::Data && type::spec(Role::Data).tabular, "data is mono + tabular");
    check(type::spec(Role::Numeric).tabular && type::spec(Role::Numeric).face == type::Face::Interface,
          "numeric is the interface face with tabular figures");

    type::setFamilies("Montserrat", "");
    check(type::family(type::Face::Interface) == "Montserrat", "interface face is the configured font");
    check(type::family(type::Face::Display) == "Space Grotesk,Montserrat",
          "display falls back through Space Grotesk to the interface face");
    type::setFamilies("Montserrat", "Sora");
    check(type::family(type::Face::Display) == "Sora,Montserrat", "a configured display face wins, still with fallback");
    check(type::familyFor(Role::Title) == "Montserrat", "non-tabular roles carry no feature suffix");
    const std::string numeric = type::familyFor(Role::Numeric);
    const auto parts = font_spec::split(numeric);
    check(parts.family == "Montserrat" && parts.features == "tnum=1", "tabular roles split into family + tnum");
    check(font_spec::split("Inter").features.empty(), "a plain family has no features");
    type::setFamilies("", "");
    check(type::family(type::Face::Interface) == "sans-serif", "an unset interface family falls back to sans-serif");
  }

  // --- semantic colour and contrast -------------------------------------------------------------------
  {
    using color::Semantic;
    const auto sel = color::spec(Semantic::SelectionFill);
    check(sel.role == ColorRole::Primary && near(sel.alpha, 0.16F), "selection fill = primary @ 0.16");
    check(color::spec(Semantic::SelectionEdge).role == ColorRole::Primary, "selection edge is primary");
    check(color::spec(Semantic::Warning).role == ColorRole::Error, "warning is the error role until the palette has one");
    check(color::spec(Semantic::Hairline).role == ColorRole::OnSurface && color::spec(Semantic::Hairline).alpha < 0.2F,
          "hairlines are faint on-surface");
    check(color::spec(Semantic::Muted).role == ColorRole::OnSurfaceVariant, "muted = on_surface_variant");

    const Color white = rgba(1, 1, 1, 1);
    const Color black = rgba(0, 0, 0, 1);
    check(near(color::contrastRatio(white, black), 21.0F, 0.01F), "white/black contrast is 21:1");
    check(near(color::contrastRatio(white, white), 1.0F), "identical colours contrast 1:1");
    const Color midGrey = rgba(0.46F, 0.46F, 0.46F, 1);
    const auto keep = color::legibleOn(black, white, color::kContrastText, white, black);
    check(keep.meets && keep.color.r == 1.0F, "a legible preferred colour is kept");
    const auto swap = color::legibleOn(white, rgba(0.9F, 0.9F, 0.9F, 1), color::kContrastText, white, black);
    check(swap.meets && swap.color.r == 0.0F, "an illegible colour falls back to the better candidate");
    const auto scrim =
        color::legibleOn(midGrey, rgba(0.5F, 0.5F, 0.5F, 1), 7.0F, rgba(0.62F, 0.62F, 0.62F, 1), rgba(0.35F, 0.35F, 0.35F, 1));
    check(!scrim.meets && scrim.needsScrim, "when nothing reaches the ratio, a scrim is requested");
  }

  // --- surface hierarchy ------------------------------------------------------------------------------
  {
    using shell::surface::Role;
    using shell::surface::Lifetime;
    namespace ss = shell::surface;
    const Role order[] = {Role::Scene, Role::Atmosphere, Role::Frame, Role::Surface, Role::Overlay, Role::Floating};
    for (std::size_t i = 1; i < std::size(order); ++i) {
      check(ss::info(order[i - 1]).depth < ss::info(order[i]).depth, "depth strictly rises through the hierarchy");
    }
    check(ss::info(Role::Embedded).depth == ss::info(Role::Surface).depth, "embedded plates sit in their surface's plane");
    check(ss::info(Role::Frame).lifetime == Lifetime::Persistent && ss::info(Role::Scene).lifetime == Lifetime::Persistent,
          "scene and frame are persistent");
    check(ss::info(Role::Surface).lifetime == Lifetime::Transient && ss::info(Role::Floating).lifetime == Lifetime::Transient,
          "surfaces and floating feedback are transient");
    // The layers the shell already used, now read from the roles.
    check(ss::layer(Role::Scene) == LayerShellLayer::Background, "the wallpaper is on Background");
    check(ss::layer(Role::Atmosphere) == LayerShellLayer::Bottom, "desktop widgets are on Bottom");
    check(ss::layer(Role::Surface) == LayerShellLayer::Top, "panels are on Top");
    check(ss::layer(Role::Floating) == LayerShellLayer::Overlay, "OSD and toasts are on Overlay, above modals");

    Config config;
    config.shell.glass.blur = true;
    config.shell.panel.transparencyMode = PanelTransparencyMode::Custom;
    config.shell.glass.opacity = 0.72F;
    config.shell.panel.shadow = true;
    config.shell.popupShadows = false;
    const auto glassStyle = shell::glass::panelSurface(config, shell::glass::fillOpacity(config));
    const auto surface = ss::material(Role::Surface, config);
    check(surface.fill == glassStyle.fill && surface.blur == glassStyle.blur && surface.border == glassStyle.border,
          "Surface material is exactly Glass's panel surface (one owner)");
    check(surface.shadow, "Surface shadow follows [shell.panel].shadow");
    check(!ss::material(Role::Floating, config).shadow, "Floating shadow follows [shell].popup_shadows");
    const auto atmosphere = ss::material(Role::Atmosphere, config);
    check(!atmosphere.blur && !atmosphere.shadow && atmosphere.fill.alpha == 1.0F && !atmosphere.fill.role.has_value()
              && atmosphere.fill.fixed.a == 0.0F,
          "atmosphere has no chrome at all (not everything is glass)");
    const auto embedded = ss::material(Role::Embedded, config);
    check(!embedded.blur && !embedded.shadow, "embedded plates add tone, not blur or shadow");
    check(!ss::material(Role::Frame, config, 1.0F).blur, "an opaque frame requests no blur");
    check(ss::material(Role::Frame, config, 0.5F).blur, "a translucent frame requests blur when glass blur is on");
    check(ss::material(Role::Frame, config, 0.5F, true).shadow && !ss::material(Role::Frame, config, 0.5F, false).shadow,
          "a frame's shadow is its own flag");
  }

  if (failures == 0) {
    std::cout << "design tokens test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
