#pragma once

#include <cstdint>
#include <string>
#include <string_view>

// zynith spatial model ("Optics"): where a transient surface came from, which way it travels, and how
// it relates to the persistent environment.
//
// It extends the existing coordinate model instead of replacing it. Coordinates stay what they already
// are — output-local logical pixels, in the same space as PanelOpenRequest's anchor — and placement stays
// PanelManager's (position references, anchor_bar, the centring rule). What this adds is MEANING: an
// Origin records the relationship "opened from the Time bar's clock widget, on the bottom edge", not a
// coordinate to hard-code. A surface can then derive its reveal direction, and later its entrance
// geometry, from its origin — so a Control Center opened from a bottom bar rises from it, while the same
// panel opened by a keyboard shortcut has no widget to grow from and uses its placement's default.
//
// The functions over these types live in spatial_model.h; this header is types only, so requests can
// carry an origin without pulling in the rest of the model. See 02_Architecture/design/spatial-model.md.
namespace shell::spatial {

  // What summoned a surface.
  enum class OriginKind : std::uint8_t {
    None,      // unknown (internal opens that do not state one)
    BarWidget, // a widget on a bar: the strongest origin — it has an identity and a rectangle
    BarArea,   // an empty part of a bar (dead-zone gesture): a point on the bar's edge
    Command,   // IPC or a keybinding (Shift+Super+E runs IPC): no spatial source
    Surface,   // another surface (a Control Center card opening a section)
  };

  enum class Edge : std::uint8_t { None, Top, Bottom, Left, Right };

  struct OriginRect {
    float x = 0.0F;
    float y = 0.0F;
    float width = 0.0F;
    float height = 0.0F;

    [[nodiscard]] bool valid() const noexcept { return width > 0.0F && height > 0.0F; }
    [[nodiscard]] float centerX() const noexcept { return x + width * 0.5F; }
    [[nodiscard]] float centerY() const noexcept { return y + height * 0.5F; }
    bool operator==(const OriginRect&) const = default;
  };

  struct Origin {
    OriginKind kind = OriginKind::None;
    std::string sourceBar;  // bar name for BarWidget / BarArea
    std::string sourceId;   // widget config name (or type) / surface id
    OriginRect rect;        // output-local logical px, captured when the request is made
    Edge edge = Edge::None; // the screen edge the origin sits on

    [[nodiscard]] bool spatial() const noexcept { return rect.valid(); }
    bool operator==(const Origin&) const = default;
  };

} // namespace shell::spatial
