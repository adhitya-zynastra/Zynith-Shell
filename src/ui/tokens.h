#pragma once

#include <cstdint>

// zynith design tokens: geometry.
//
// One definition per decision, named by what it is FOR rather than by its size, so a surface asks for
// "the radius of a floating surface" or "the gap between groups" and every surface that asks gets the
// same answer. Values are logical pixels at scale 1; `scale` is the component's content scale, exactly
// as Style's scaled helpers take it.
//
// These are design-system constants, not settings. The one user preference they honour is the existing
// [shell].corner_radius_scale (via Style::scaledRadius*), so radii keep a single owner.
//
// Relationship to Style: Style's numeric constants remain the storage and stay valid for existing code;
// tokens name them, add the steps Style lacked (spacing above 16, icon containers) and give each a role.
// See 02_Architecture/design/design-tokens.md.
namespace ui::tokens {

  // ---- spacing ---------------------------------------------------------------------------------------
  // One scale; nothing between the steps. Density (compact/comfortable/spacious) multiplies spacing only
  // (ui::responsive), never type or radius.
  enum class Space : std::uint8_t {
    Inline,      //  4  glyph to its label, a value to its unit
    Related,     //  8  controls that belong together
    Control,     // 12  inside a control group, list row padding
    Group,       // 16  between groups inside a surface, surface padding
    Section,     // 24  between sections of a surface
    Surface,     // 32  between unrelated surfaces
    Composition, // 48  compositional margins (a stage)
    Stage,       // 64  full-screen composition margins
  };
  [[nodiscard]] float space(Space step, float scale = 1.0F) noexcept;

  // ---- radius ----------------------------------------------------------------------------------------
  enum class Radius : std::uint8_t {
    Surface, // floating and attached surfaces: panels, toasts, the wallpaper browser
    Plate,   // grouped content embedded in a surface (cards)
    Control, // buttons, fields, tiles
    Stage,   // full-bleed compositions: square
  };
  [[nodiscard]] float radius(Radius family, float scale = 1.0F) noexcept;
  // A capsule for an interactive element of the given height (chips, the search field, OSD bars).
  [[nodiscard]] constexpr float pill(float height) noexcept { return height * 0.5F; }
  // Nested corners that share a centre: a child inset uniformly by `inset` from a parent corner of
  // `parentRadius` takes parentRadius - inset, never less than `floor`.
  [[nodiscard]] float concentric(float parentRadius, float inset, float floor = 4.0F) noexcept;

  // ---- stroke ----------------------------------------------------------------------------------------
  inline constexpr float kHairline = 1.0F; // every edge and divider
  inline constexpr float kFocusRing = 2.0F;
  inline constexpr float kEmphasis = 3.0F; // the only thicker line: an armed/emphasised state

  // ---- controls and icons ----------------------------------------------------------------------------
  enum class Size : std::uint8_t { Small, Medium, Large };
  [[nodiscard]] float controlHeight(Size size, float scale = 1.0F) noexcept; // 32 / 38 / 44
  [[nodiscard]] float iconSize(Size size, float scale = 1.0F) noexcept;      // 16 / 20 / 24
  [[nodiscard]] float iconContainer(Size size, float scale = 1.0F) noexcept; // 32 / 40 / 48

} // namespace ui::tokens
