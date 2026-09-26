#include "shell/spatial/spatial_model.h"

#include <cmath>
#include <format>

namespace shell::spatial {

  Edge edgeFromBarPosition(std::string_view position) noexcept {
    if (position == "top") {
      return Edge::Top;
    }
    if (position == "bottom") {
      return Edge::Bottom;
    }
    if (position == "left") {
      return Edge::Left;
    }
    if (position == "right") {
      return Edge::Right;
    }
    return Edge::None;
  }

  std::string_view edgeName(Edge edge) noexcept {
    switch (edge) {
    case Edge::Top:
      return "top";
    case Edge::Bottom:
      return "bottom";
    case Edge::Left:
      return "left";
    case Edge::Right:
      return "right";
    case Edge::None:
      break;
    }
    return "none";
  }

  std::string_view kindName(OriginKind kind) noexcept {
    switch (kind) {
    case OriginKind::BarWidget:
      return "bar-widget";
    case OriginKind::BarArea:
      return "bar-area";
    case OriginKind::Command:
      return "command";
    case OriginKind::Surface:
      return "surface";
    case OriginKind::None:
      break;
    }
    return "none";
  }

  AttachedRevealDirection revealDirection(Edge edge) noexcept {
    if (edge == Edge::None) {
      return AttachedRevealDirection::Down;
    }
    return attached_panel::revealDirection(edgeName(edge));
  }

  namespace {
    std::string_view directionName(AttachedRevealDirection d) {
      switch (d) {
      case AttachedRevealDirection::Down:
        return "down";
      case AttachedRevealDirection::Up:
        return "up";
      case AttachedRevealDirection::Right:
        return "right";
      case AttachedRevealDirection::Left:
        return "left";
      }
      return "down";
    }
  } // namespace

  std::string describe(const Origin& origin) {
    std::string out(kindName(origin.kind));
    if (!origin.sourceBar.empty() || !origin.sourceId.empty()) {
      out += std::format(" {}/{}", origin.sourceBar, origin.sourceId);
    }
    if (origin.spatial()) {
      out += std::format(
          " @ {},{} {}x{}", std::lround(origin.rect.x), std::lround(origin.rect.y), std::lround(origin.rect.width),
          std::lround(origin.rect.height)
      );
    }
    if (origin.edge != Edge::None) {
      out += std::format(" edge={} reveal={}", edgeName(origin.edge), directionName(revealDirection(origin.edge)));
    }
    return out;
  }

  LifetimePolicy policy(surface::Lifetime lifetime) noexcept {
    if (lifetime == surface::Lifetime::Persistent) {
      return LifetimePolicy{
          .createdOnDemand = false,
          .destroyedAfterDismiss = false,
          .hasOrigin = false,
          .enter = motion::Role::SurfaceReveal, // only when returning from auto-hide
          .exit = motion::Role::SurfaceDismiss,
          .change = motion::Role::ElementMove,
      };
    }
    return LifetimePolicy{
        .createdOnDemand = true,
        .destroyedAfterDismiss = true,
        .hasOrigin = true,
        .enter = motion::Role::SurfaceReveal,
        .exit = motion::Role::SurfaceDismiss,
        .change = motion::Role::ElementMove,
    };
  }

} // namespace shell::spatial
