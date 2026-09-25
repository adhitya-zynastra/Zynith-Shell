// Zynith responsive layout: the extent/fit/density primitives, and the wallpaper carousel's
// geometry at display widths the development laptop does not have.
//
// The carousel numbers mirror what WallpaperPanel does on layout: resolve the focused card from
// [wallpaper].carousel_card_width against the band, then let the orbit fit as many neighbours as
// the band can carry. Band widths are output width minus the panel's side margins (8 px each).

#include "config/config_types.h"
#include "ui/controls/carousel_geometry.h"
#include "ui/responsive.h"

#include <cmath>
#include <iostream>

namespace {

  int failures = 0;

  void check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
  }

  bool near(float a, float b, float eps = 1e-3F) { return std::fabs(a - b) < eps; }

  // The wallpaper panel's sizing, reproduced: preferred 760 px, bounds 320-1400, at most 40 % of
  // the band, stride 0.66 of the card.
  struct Carousel {
    float cardWidth;
    std::size_t perSide;
    float angleStep;
  };
  Carousel carouselFor(float band, float uiScale = 1.0F, float preferred = 760.0F) {
    const float card =
        ui::responsive::resolve({.min = 320.0F, .preferred = preferred, .max = 1400.0F}, band, uiScale, 0.40F);
    const auto fit = ui::carousel::fitArc(band, card, card * 0.66F);
    return {card, fit.perSide, fit.angleStep};
  }

} // namespace

int main() {
  using ui::responsive::Extent;

  // --- resolve ---------------------------------------------------------------------------------
  {
    const Extent e{.min = 320.0F, .preferred = 760.0F, .max = 1400.0F};
    check(near(ui::responsive::resolve(e, 1904.0F, 1.0F, 0.46F), 760.0F), "preference honoured when it fits");
    check(near(ui::responsive::resolve(e, 1350.0F, 1.0F, 0.46F), 621.0F), "narrow band caps at the fraction");
    check(near(ui::responsive::resolve(e, 1904.0F, 1.25F, 0.46F), 1904.0F * 0.46F), "UI scale grows it up to the cap");
    check(near(ui::responsive::resolve(e, 3000.0F, 1.25F, 1.0F), 950.0F), "UI scale multiplies the preference");
    check(near(ui::responsive::resolve(e, 200.0F, 1.0F, 1.0F), 200.0F), "the minimum yields to a smaller display");
    check(ui::responsive::resolve(e, 0.0F) == 760.0F, "no available size means the preference");
    check(ui::responsive::resolve({.min = 0, .preferred = 0, .max = 0}, 100.0F) >= 1.0F, "never below 1");
  }

  // --- fitCount ----------------------------------------------------------------------------------
  {
    check(ui::responsive::fitCount(1000.0F, 200.0F, 20.0F, 1, 10) == 4, "4 x 200 with 20 gaps fit in 1000");
    check(ui::responsive::fitCount(100.0F, 200.0F, 20.0F, 1, 10) == 1, "minCount wins when nothing fits");
    check(ui::responsive::fitCount(10000.0F, 200.0F, 0.0F, 1, 6) == 6, "maxCount caps it");
    check(ui::responsive::fitCount(1000.0F, 200.0F, -500.0F, 0, 99) == 5, "a negative gap is treated as zero");
  }

  // --- density ------------------------------------------------------------------------------------
  {
    check(layoutDensityFactor(LayoutDensity::Comfortable) == 1.0F, "comfortable is the old spacing");
    check(layoutDensityFactor(LayoutDensity::Compact) < 1.0F, "compact is tighter");
    check(layoutDensityFactor(LayoutDensity::Spacious) > 1.0F, "spacious is looser");
    check(near(ui::responsive::space(12.0F, 1.0F, 1.0F), 12.0F), "space at 1.0/1.0 is the token");
    check(near(ui::responsive::space(12.0F, 1.35F, 1.25F), 12.0F * 1.35F * 1.25F), "space scales by both");
  }

  // --- carousel: the laptop keeps its original tuning ----------------------------------------------
  {
    const auto c = carouselFor(1904.0F);
    check(near(c.cardWidth, 760.0F), "1920: focused card 760 px");
    check(c.perSide == 2, "1920: two cards per side (five visible)");
    check(near(c.angleStep, 0.3665F), "1920: 21 degree step, exactly the pre-responsive constant");
  }

  // --- carousel: wider outputs show more, not bigger -----------------------------------------------
  // A neighbour only counts once a fifth of it shows past the card in front, so the count steps up
  // roughly every two strides of width rather than as soon as a sliver reaches the edge.
  {
    const auto qhd = carouselFor(2544.0F);
    check(near(qhd.cardWidth, 760.0F), "2560: card stays 760 px");
    check(qhd.perSide == 2, "2560: a third card would show ~22 px past its neighbour, so still five");
    const auto wide = carouselFor(3184.0F);
    check(wide.perSide == 3, "3200: three per side (seven visible)");
    const auto uw = carouselFor(3424.0F);
    check(near(uw.cardWidth, 760.0F), "3440: card stays 760 px");
    check(uw.perSide == 3, "3440: three per side (seven visible)");
    const auto uhd = carouselFor(3824.0F);
    check(uhd.perSide == 4, "3840: four per side (nine visible)");
    check(uhd.angleStep < wide.angleStep && wide.angleStep < 0.3666F, "wider spreads the same arc over more cards");
    const auto huge = carouselFor(20000.0F);
    check(huge.perSide == ui::carousel::kMaxPerSide, "an absurd width is capped at kMaxPerSide");
  }

  // --- carousel: the count never drops as the output widens ---------------------------------------
  {
    std::size_t previous = 0;
    bool monotonic = true;
    for (float band = 784.0F; band <= 8000.0F; band += 8.0F) {
      const auto c = carouselFor(band);
      monotonic = monotonic && c.perSide >= previous;
      previous = c.perSide;
    }
    check(monotonic, "per-side count is non-decreasing in width");
  }

  // --- carousel: smaller outputs shrink the card, keep the composition ----------------------------
  {
    const auto small = carouselFor(1350.0F);
    check(near(small.cardWidth, 540.0F), "1366: card is the pre-responsive 40 % of the band");
    check(small.perSide == 2, "1366: still five visible");
    const auto scaled = carouselFor(1520.0F);
    check(near(scaled.cardWidth, 608.0F) && scaled.perSide == 2, "1920 at scale 1.25: five visible");
    const auto tiny = carouselFor(700.0F);
    check(tiny.perSide >= 1, "700 px: at least one neighbour per side");
  }

  // --- carousel: a larger preferred card means fewer neighbours on the same display --------------
  {
    const auto big = carouselFor(1904.0F, 1.0F, 1000.0F);
    check(near(big.cardWidth, 1904.0F * 0.40F), "a 1000 px preference is capped at 40 % of 1920");
    check(big.perSide <= 2, "a bigger card does not add neighbours");
  }

  // --- degenerate input ------------------------------------------------------------------------------
  {
    const auto fit = ui::carousel::fitArc(0.0F, 0.0F, 0.0F);
    check(fit.perSide == 0 && std::isfinite(fit.angleStep), "zero geometry is safe");
  }

  if (failures == 0) {
    std::cout << "responsive layout test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
