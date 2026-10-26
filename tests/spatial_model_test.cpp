// zynith spatial model: origins, edges, reveal direction, persistent/transient policy.
//
// The model extends the existing coordinate model rather than replacing it, so the central checks are
// agreements: an origin's reveal direction must equal the attached-panel rule for the same bar position,
// and a request must carry its origin unchanged (placement stays PanelManager's).

#include "render/animation/motion_role.h"
#include "shell/panel/attached_panel_context.h"
#include "shell/panel/panel_manager.h"
#include "shell/spatial/spatial_model.h"
#include "shell/surface/surface_role.h"

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

} // namespace

int main() {
  namespace sp = shell::spatial;

  // --- edges and the agreement with attached panels ------------------------------------------------
  {
    check(sp::edgeFromBarPosition("top") == sp::Edge::Top, "top bar -> top edge");
    check(sp::edgeFromBarPosition("bottom") == sp::Edge::Bottom, "bottom bar -> bottom edge");
    check(sp::edgeFromBarPosition("left") == sp::Edge::Left, "left bar -> left edge");
    check(sp::edgeFromBarPosition("right") == sp::Edge::Right, "right bar -> right edge");
    check(sp::edgeFromBarPosition("floating") == sp::Edge::None, "an unknown position has no edge");
    for (const char* position : {"top", "bottom", "left", "right"}) {
      check(
          sp::revealDirection(sp::edgeFromBarPosition(position)) == attached_panel::revealDirection(position),
          "origin reveal direction = the attached-panel rule for the same bar"
      );
    }
    check(sp::revealDirection(sp::Edge::Bottom) == AttachedRevealDirection::Up, "from a bottom bar, surfaces rise");
    check(
        sp::revealDirection(sp::Edge::Left) == AttachedRevealDirection::Right, "from a left bar, surfaces move right"
    );
  }

  // --- origins --------------------------------------------------------------------------------------
  {
    const sp::Origin none;
    check(none.kind == sp::OriginKind::None && !none.spatial(), "the default origin is unknown and non-spatial");
    const sp::Origin clock{
        .kind = sp::OriginKind::BarWidget,
        .sourceBar = "Time",
        .sourceId = "clock",
        .rect = {.x = 880.0F, .y = 1170.0F, .width = 160.0F, .height = 30.0F},
        .edge = sp::Edge::Bottom,
    };
    check(clock.spatial() && clock.rect.centerX() == 960.0F, "a widget origin is a rectangle with a centre");
    check(
        sp::describe(clock) == "bar-widget Time/clock @ 880,1170 160x30 edge=bottom reveal=up",
        "origins describe themselves for logs"
    );
    check(sp::describe(sp::Origin{.kind = sp::OriginKind::Command}) == "command", "a command origin is non-spatial");
    const sp::Origin area{
        .kind = sp::OriginKind::BarArea,
        .sourceBar = "default",
        .rect = {.x = 19, .y = 600, .width = 1, .height = 1},
        .edge = sp::Edge::Left
    };
    check(
        area.spatial() && sp::describe(area).starts_with("bar-area default/ @ 19,600 1x1 edge=left"),
        "a bar-area origin is a point on the bar's edge"
    );
  }

  // --- requests carry origins unchanged ---------------------------------------------------------------
  {
    const PanelOpenRequest plain{};
    check(
        plain.origin.kind == sp::OriginKind::None,
        "requests default to an unknown origin (existing call sites unchanged)"
    );
    const PanelOpenRequest command{.context = "home", .origin = {.kind = sp::OriginKind::Command}};
    check(command.origin.kind == sp::OriginKind::Command && command.context == "home", "a request carries its origin");
    PanelOpenRequest copy = command;
    check(copy.origin == command.origin, "origins copy with the request (deferred opens keep them)");
  }

  // --- persistent vs transient ------------------------------------------------------------------------
  {
    using shell::surface::Lifetime;
    const auto persistent = sp::policy(Lifetime::Persistent);
    const auto transient = sp::policy(Lifetime::Transient);
    check(
        !persistent.createdOnDemand && !persistent.destroyedAfterDismiss && !persistent.hasOrigin,
        "persistent UI is always mapped and is an origin, not something with one"
    );
    check(
        transient.createdOnDemand && transient.destroyedAfterDismiss && transient.hasOrigin,
        "transient UI is created on demand, destroyed after dismissal, and has an origin"
    );
    check(
        motion::spec(transient.exit).durationMs < motion::spec(transient.enter).durationMs,
        "a transient surface leaves faster than it arrives"
    );
    for (std::size_t i = 0; i < shell::surface::kRoleCount; ++i) {
      const auto role = static_cast<shell::surface::Role>(i);
      const auto lifetime = shell::surface::info(role).lifetime;
      if (role == shell::surface::Role::Scene
          || role == shell::surface::Role::Atmosphere
          || role == shell::surface::Role::Frame) {
        check(lifetime == Lifetime::Persistent, "the environment roles are persistent");
      } else {
        check(lifetime == Lifetime::Transient, "surfaces, overlays and feedback are transient");
      }
    }
  }

  if (failures == 0) {
    std::cout << "spatial model test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
