#pragma once

#include "render/core/color.h"
#include "ui/palette.h"

#include <cstdint>

// zynith semantic colour: colours named by MEANING, resolved to the existing wallpaper-derived palette
// roles. Nothing here adds palette entries or changes the theme engine; a semantic colour is a role
// (plus alpha) that every surface asking the same question receives — so "the selection" or "a
// hairline" is one decision instead of a value chosen per component.
//
// Contrast rules are WCAG 2.x relative-luminance ratios, evaluated only where a colour is resolved
// against a known background (text on the wallpaper, text on a sampled image). They are pure functions
// with no per-frame cost unless a caller evaluates them per frame, which callers must not do.
namespace ui::color {

  enum class Semantic : std::uint8_t {
    Accent,    // the one emphasised thing: primary
    OnAccent,  // content on a solid accent
    Surface,   // the base tone of surfaces
    OnSurface, // primary content
    Muted,     // secondary content: on_surface_variant
    Hairline,  // edges and dividers: on_surface at a low alpha
    Error,     // destructive, armed or failed states
    OnError,
    Warning,       // cautionary state; the palette has no warning role yet, so it is Error (as the
                   // battery widget already does) — see the design-token docs
    SelectionFill, // the selection/active material: a tint, not a solid block
    SelectionEdge, // its hairline
    Scrim,         // what dims the world behind a modal surface
    Count,
  };

  [[nodiscard]] ColorSpec spec(Semantic semantic) noexcept;

  // ---- contrast (WCAG 2.x) --------------------------------------------------------------------------
  inline constexpr float kContrastText = 4.5F;  // body text
  inline constexpr float kContrastLarge = 3.0F; // text >= 24 px, or >= 19 px bold; UI glyphs

  // Built on the existing ::relativeLuminance (render/core/color.h, WCAG sRGB linearisation), which
  // also backs readableTextColorForBackground; this adds the ratio and palette-aware fallback.
  [[nodiscard]] float contrastRatio(const Color& a, const Color& b) noexcept;

  struct Legible {
    Color color;
    float ratio = 1.0F;
    bool meets = false;      // `ratio` reaches the requested minimum
    bool needsScrim = false; // neither candidate reached it: put a local scrim behind the text
  };
  // The preferred colour if it reaches `minRatio` against `background`; otherwise whichever of
  // `light` / `dark` contrasts more (normally the palette's on-surface and surface, so the fallback
  // still belongs to the theme).
  [[nodiscard]] Legible legibleOn(
      const Color& background, const Color& preferred, float minRatio, const Color& light, const Color& dark
  ) noexcept;
  // The same against the current palette: preferred role first, then on_surface / surface.
  [[nodiscard]] Legible
  legibleOn(const Color& background, ColorRole preferred, float minRatio = kContrastText) noexcept;

} // namespace ui::color
