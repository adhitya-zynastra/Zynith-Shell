#include "shell/surface/glass.h"

#include "config/config_service.h"

#include <algorithm>

namespace shell::glass {

  ColorRole toColorRole(GlassTintRole role) noexcept {
    switch (role) {
    case GlassTintRole::Primary:
      return ColorRole::Primary;
    case GlassTintRole::Secondary:
      return ColorRole::Secondary;
    case GlassTintRole::Tertiary:
      return ColorRole::Tertiary;
    case GlassTintRole::SurfaceVariant:
      return ColorRole::SurfaceVariant;
    }
    return ColorRole::Primary;
  }

  ColorRole toColorRole(GlassBorderRole role) noexcept {
    switch (role) {
    case GlassBorderRole::Outline:
      return ColorRole::Outline;
    case GlassBorderRole::Primary:
      return ColorRole::Primary;
    case GlassBorderRole::Secondary:
      return ColorRole::Secondary;
    case GlassBorderRole::Tertiary:
      return ColorRole::Tertiary;
    case GlassBorderRole::SurfaceVariant:
      return ColorRole::SurfaceVariant;
    }
    return ColorRole::Outline;
  }

  float fillOpacity(const Config& config) noexcept {
    const auto mode = config.shell.panel.transparencyMode;
    if (mode == PanelTransparencyMode::Custom) {
      return std::clamp(config.shell.glass.opacity, 0.0F, 1.0F);
    }
    return detachedPanelBackgroundOpacityForTransparencyMode(mode);
  }

  float fillOpacity(const ConfigService* config) noexcept {
    if (config == nullptr) {
      return 1.0F;
    }
    return fillOpacity(config->config());
  }

  float cardOpacity(const ConfigService* config, float panelFillOpacity) noexcept {
    const auto mode = config != nullptr ? config->config().shell.panel.transparencyMode : PanelTransparencyMode::Solid;
    return panelCardOpacityForTransparencyMode(mode, panelFillOpacity);
  }

  bool blurEnabled(const Config& config, float fillOpacity) noexcept {
    return config.shell.glass.blur && fillOpacity < 1.0F;
  }

  SurfaceStyle panelSurface(const Config& config, float fillOpacity) noexcept {
    const auto& glass = config.shell.glass;
    SurfaceStyle out;
    out.fill = colorSpecFromRole(ColorRole::Surface, fillOpacity);
    if (glass.tint && glass.tintStrength > 0.0F) {
      out.fill = withTint(out.fill, toColorRole(glass.tintRole), glass.tintStrength);
    }
    out.border = config.shell.panel.borders;
    // The border has always taken the fill's alpha, so a glass panel's outline fades with it.
    // border_opacity scales that, rather than replacing it, so 1.0 reproduces the old look exactly.
    out.borderColor =
        colorSpecFromRole(toColorRole(glass.borderRole), fillOpacity * std::clamp(glass.borderOpacity, 0.0F, 1.0F));
    out.blur = blurEnabled(config, fillOpacity);
    return out;
  }

} // namespace shell::glass
