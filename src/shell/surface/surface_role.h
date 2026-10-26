#pragma once

#include "config/config_types.h"
#include "ui/palette.h"

#include <cstdint>
#include <optional>
#include <string_view>

enum class LayerShellLayer : std::uint32_t;

// zynith surface hierarchy: every shell surface belongs to one role, and the role decides its depth,
// whether it is persistent or transient, the layer-shell layer it lives on, and its material.
//
//   depth  role        lifetime    layer       material
//   0      Scene       persistent  Background  the wallpaper itself
//   1      Atmosphere  persistent  Bottom      no chrome: text and graphics directly on the scene
//   2      Frame       persistent  Top         glass at the frame's own opacity (a bar's
//                                              background_opacity), no shadow unless the bar asks
//   3      Surface     transient   Top         panel glass ([shell.glass] + [shell.panel]), panel shadow
//   3      Embedded    (inherits)  (inherits)  a tone step inside a surface: no blur, no shadow
//   4      Overlay     transient   Top         a modal surface over a scrim (the power menu)
//   5      Floating    transient   Overlay     brief feedback that must stay visible above everything,
//                                              modals included: OSD, toasts (popup shadow)
//
// Not everything is glass: the scene and atmosphere have no chrome, embedded plates add tone rather
// than more transparency, and blur is only ever requested by glass levels whose fill is translucent.
//
// This is a model over the existing owners, not a new authority: materials come from shell::glass
// (the single owner of fill/tint/blur/border, ADR-0016) and shadows from the keys that already own
// them ([shell.panel].shadow, [shell].popup_shadows, a bar's or the dock's own `shadow`). Nothing here is
// a setting.
namespace shell::surface {

  enum class Role : std::uint8_t { Scene, Atmosphere, Frame, Surface, Embedded, Overlay, Floating, Count };
  enum class Lifetime : std::uint8_t { Persistent, Transient };

  struct RoleInfo {
    std::string_view name;
    std::uint8_t depth = 0;
    Lifetime lifetime = Lifetime::Transient;
  };

  [[nodiscard]] const RoleInfo& info(Role role) noexcept;
  // The layer-shell layer a surface of this role is created on. Embedded has no surface of its own and
  // reports its parent's usual layer (Top).
  [[nodiscard]] LayerShellLayer layer(Role role) noexcept;

  struct Material {
    ColorSpec fill;
    bool border = false;
    ColorSpec borderColor;
    bool blur = false;
    bool shadow = false;
  };

  // `ownOpacity`: a surface that owns its fill alpha elsewhere (a bar's background_opacity, the OSD's
  // background_opacity) passes it; otherwise the glass panel opacity applies. `ownShadow`: a Frame's own
  // shadow flag (bars and the dock have one); ignored by the other roles.
  [[nodiscard]] Material
  material(Role role, const Config& config, std::optional<float> ownOpacity = std::nullopt, bool ownShadow = false);

  inline constexpr std::size_t kRoleCount = static_cast<std::size_t>(Role::Count);

} // namespace shell::surface
