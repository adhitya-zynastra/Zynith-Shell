#pragma once

#include "render/animation/motion_role.h"
#include "shell/panel/attached_panel_context.h"
#include "shell/spatial/spatial_origin.h"
#include "shell/surface/surface_role.h"

#include <string>
#include <string_view>

// zynith spatial model: functions over Origin (spatial_origin.h).
namespace shell::spatial {

  [[nodiscard]] Edge edgeFromBarPosition(std::string_view position) noexcept;
  [[nodiscard]] std::string_view edgeName(Edge edge) noexcept;
  [[nodiscard]] std::string_view kindName(OriginKind kind) noexcept;

  // The direction a surface emerging from `edge` travels: away from the edge, into the screen. This is
  // the attached-panel rule (attached_panel::revealDirection) — reused, not re-derived — so every
  // origin-aware surface agrees with how attached panels already reveal.
  [[nodiscard]] AttachedRevealDirection revealDirection(Edge edge) noexcept;

  // One line for logs: "bar-widget Time/clock @ 880,1170 160x30 edge=bottom reveal=up".
  [[nodiscard]] std::string describe(const Origin& origin);

  // ---- persistent vs transient -----------------------------------------------------------------------
  // Persistent UI (the scene, desktop widgets, bars) is always mapped, never has an origin, and IS the
  // origin transient UI grows from; its changes are element motion. Transient UI (panels, popovers, OSD,
  // toasts) is created on demand and destroyed after dismissal, has an origin, enters by SurfaceReveal
  // away from its origin's edge and leaves by the shorter SurfaceDismiss.
  struct LifetimePolicy {
    bool createdOnDemand = false;
    bool destroyedAfterDismiss = false;
    bool hasOrigin = false;
    motion::Role enter = motion::Role::SurfaceReveal;
    motion::Role exit = motion::Role::SurfaceDismiss;
    motion::Role change = motion::Role::ElementMove;
  };
  [[nodiscard]] LifetimePolicy policy(surface::Lifetime lifetime) noexcept;

} // namespace shell::spatial
