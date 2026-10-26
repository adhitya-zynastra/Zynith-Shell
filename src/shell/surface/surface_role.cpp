#include "shell/surface/surface_role.h"

#include "shell/surface/glass.h"
#include "ui/semantic_color.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"

#include <array>

namespace shell::surface {

  namespace {
    constexpr std::array<RoleInfo, kRoleCount> kInfo = {{
        {.name = "scene", .depth = 0, .lifetime = Lifetime::Persistent},
        {.name = "atmosphere", .depth = 1, .lifetime = Lifetime::Persistent},
        {.name = "frame", .depth = 2, .lifetime = Lifetime::Persistent},
        {.name = "surface", .depth = 3, .lifetime = Lifetime::Transient},
        {.name = "embedded", .depth = 3, .lifetime = Lifetime::Transient},
        {.name = "overlay", .depth = 4, .lifetime = Lifetime::Transient},
        {.name = "floating", .depth = 5, .lifetime = Lifetime::Transient},
    }};

    Material none() {
      return Material{
          .fill = clearColorSpec(), .border = false, .borderColor = clearColorSpec(), .blur = false, .shadow = false
      };
    }

    Material fromGlass(const glass::SurfaceStyle& s, bool shadow) {
      return Material{
          .fill = s.fill, .border = s.border, .borderColor = s.borderColor, .blur = s.blur, .shadow = shadow
      };
    }
  } // namespace

  const RoleInfo& info(Role role) noexcept {
    const auto index = static_cast<std::size_t>(role);
    return kInfo[index < kRoleCount ? index : 0];
  }

  LayerShellLayer layer(Role role) noexcept {
    switch (role) {
    case Role::Scene:
      return LayerShellLayer::Background;
    case Role::Atmosphere:
      return LayerShellLayer::Bottom;
    case Role::Frame:
    case Role::Surface:
    case Role::Embedded:
    case Role::Overlay:
      return LayerShellLayer::Top;
    case Role::Floating:
      return LayerShellLayer::Overlay;
    case Role::Count:
      break;
    }
    return LayerShellLayer::Top;
  }

  Material material(Role role, const Config& config, std::optional<float> ownOpacity, bool ownShadow) {
    switch (role) {
    case Role::Scene:
    case Role::Atmosphere:
      return none();
    case Role::Frame: {
      const float opacity = ownOpacity.value_or(1.0F);
      Material m = none();
      m.fill = glass::tinted(config, colorSpecFromRole(ColorRole::Surface, opacity));
      m.blur = glass::blurEnabled(config, opacity);
      m.shadow = ownShadow;
      return m;
    }
    case Role::Surface:
    case Role::Overlay:
      return fromGlass(
          glass::panelSurface(config, ownOpacity.value_or(glass::fillOpacity(config))), config.shell.panel.shadow
      );
    case Role::Floating:
      return fromGlass(
          glass::panelSurface(config, ownOpacity.value_or(glass::fillOpacity(config))), config.shell.popupShadows
      );
    case Role::Embedded: {
      const float panel = ownOpacity.value_or(glass::fillOpacity(config));
      Material m = none();
      m.fill = colorSpecFromRole(
          ColorRole::SurfaceVariant, panelCardOpacityForTransparencyMode(config.shell.panel.transparencyMode, panel)
      );
      m.border = Style::cardBordersEnabled();
      m.borderColor = ui::color::spec(ui::color::Semantic::Hairline);
      return m;
    }
    case Role::Count:
      break;
    }
    return none();
  }

} // namespace shell::surface
