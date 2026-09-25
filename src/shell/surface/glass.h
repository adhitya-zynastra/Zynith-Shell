#pragma once

#include "config/config_types.h"
#include "ui/palette.h"

class ConfigService;

// Zynith glass: the shared surface model.
//
// Every translucent shell surface needs the same handful of decisions — how opaque its fill is,
// whether a palette tint is mixed into it, what its border looks like, and whether it asks the
// compositor for blur. Before this, each surface made them locally. This namespace makes them in
// one place, from [shell.glass] and [shell.panel], and returns palette ROLES (ColorSpec) rather
// than resolved colours, so everything here keeps following the wallpaper-derived palette.
//
// It is deliberately not a rendering layer: it draws nothing, owns no nodes, allocates nothing
// per frame and adds no surfaces. Blur itself stays the compositor's (ext-background-effect for
// shell surfaces; niri's global `blur {}` block, generated from blur_strength, for its strength).
namespace shell::glass {

  struct SurfaceStyle {
    ColorSpec fill;
    bool border = false;
    ColorSpec borderColor;
    bool blur = false; // request compositor blur behind this surface
  };

  // Fill alpha for panel-class surfaces: the named transparency mode's step, or
  // [shell.glass].opacity when the mode is "custom".
  [[nodiscard]] float fillOpacity(const ConfigService* config) noexcept;
  [[nodiscard]] float fillOpacity(const Config& config) noexcept;

  // Cards inside a panel sit one step more opaque than the panel itself.
  [[nodiscard]] float cardOpacity(const ConfigService* config, float panelFillOpacity) noexcept;

  // Whether shell surfaces should request compositor blur. Off when glass blur is disabled or
  // when the surface is fully opaque — blurring behind an opaque fill is invisible work.
  [[nodiscard]] bool blurEnabled(const Config& config, float fillOpacity) noexcept;

  // The style for a panel-class surface at the given fill opacity.
  [[nodiscard]] SurfaceStyle panelSurface(const Config& config, float fillOpacity) noexcept;

  [[nodiscard]] ColorRole toColorRole(GlassTintRole role) noexcept;
  [[nodiscard]] ColorRole toColorRole(GlassBorderRole role) noexcept;

} // namespace shell::glass
