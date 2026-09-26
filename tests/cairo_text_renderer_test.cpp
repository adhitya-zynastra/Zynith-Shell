#include "render/text/cairo_text_renderer.h"

#include <array>
#include <cmath>
#include <print>
#include <string_view>

namespace {

  bool sameMetrics(const CairoTextRenderer::TextMetrics& lhs, const CairoTextRenderer::TextMetrics& rhs) {
    constexpr float epsilon = 0.0001F;
    return std::abs(lhs.width - rhs.width) < epsilon
        && std::abs(lhs.top - rhs.top) < epsilon
        && std::abs(lhs.bottom - rhs.bottom) < epsilon
        && lhs.lineCount == rhs.lineCount;
  }

  // Wrapping-boundary cache correctness: a cached measurement at one width must
  // not reuse metrics computed for a different width.
  int wrappingBoundaryCase(CairoTextRenderer& renderer) {
    constexpr std::string_view text =
        "Error: Error while parsing table header: expected a comment or whitespace, saw 't'";
    constexpr float fontSize = 14.0F;
    const float naturalWidth = renderer.measure(1.0F, text, fontSize).width;
    constexpr std::array deltas{0.0005F, 0.001F, 0.002F, 0.003F, 0.004F, 0.006F};

    for (const float delta : deltas) {
      renderer.notifyFontConfigChanged();
      const auto above = renderer.measure(1.0F, text, fontSize, FontWeight::Normal, naturalWidth + delta, 3);
      renderer.notifyFontConfigChanged();
      const auto expectedBelow = renderer.measure(1.0F, text, fontSize, FontWeight::Normal, naturalWidth - delta, 3);
      if (above.lineCount == expectedBelow.lineCount) {
        continue;
      }

      renderer.notifyFontConfigChanged();
      [[maybe_unused]] const auto cachedAbove =
          renderer.measure(1.0F, text, fontSize, FontWeight::Normal, naturalWidth + delta, 3);
      const auto cachedBelow = renderer.measure(1.0F, text, fontSize, FontWeight::Normal, naturalWidth - delta, 3);
      if (cachedBelow.lineCount != expectedBelow.lineCount) {
        std::println(
            stderr,
            "cairo_text_renderer_test: FAIL: cached measurement at width {} reused metrics from width {} "
            "(expected {} lines, got {})",
            naturalWidth - delta, naturalWidth + delta, expectedBelow.lineCount, cachedBelow.lineCount
        );
        return 1;
      }
      return 0;
    }

    std::println(stderr, "cairo_text_renderer_test: FAIL: could not establish a wrapping boundary");
    return 1;
  }

  // The metrics cache is keyed by content scale: interleaving 1.0x and 1.25x
  // measurements of the same text must return per-scale-repeatable results, and
  // an intervening call at the other scale must not corrupt the cached result.
  int scaleKeyedCacheCase(CairoTextRenderer& renderer) {
    constexpr std::string_view text = "The quick brown fox";
    constexpr float fontSize = 16.0F;

    const auto oneA = renderer.measure(1.0F, text, fontSize);
    const auto hiA = renderer.measure(1.25F, text, fontSize);
    const auto oneB = renderer.measure(1.0F, text, fontSize); // cache hit at 1.0x
    const auto hiB = renderer.measure(1.25F, text, fontSize); // cache hit at 1.25x

    if (!sameMetrics(oneA, oneB)) {
      std::println(
          stderr,
          "cairo_text_renderer_test: FAIL: 1.0x measurement not repeatable across a 1.25x call "
          "(width {} vs {}, lines {} vs {})",
          oneA.width, oneB.width, oneA.lineCount, oneB.lineCount
      );
      return 1;
    }
    if (!sameMetrics(hiA, hiB)) {
      std::println(
          stderr,
          "cairo_text_renderer_test: FAIL: 1.25x measurement not repeatable across a 1.0x call "
          "(width {} vs {}, lines {} vs {})",
          hiA.width, hiB.width, hiA.lineCount, hiB.lineCount
      );
      return 1;
    }
    return 0;
  }


  // zynith typography: a family may carry " #tnum=1" (tabular figures). The renderer must split it
  // into family + OpenType features. Two properties, measured:
  //   1. the featured family is still the same font — letters (unaffected by tnum) measure identically,
  //      which fails if the suffix were taken as part of the family name and fontconfig fell back;
  //   2. with tnum, digits have equal advance widths, so a changing number cannot jitter.
  int tabularFiguresCase(CairoTextRenderer& renderer) {
    constexpr float fontSize = 20.0F;
    constexpr std::string_view plain = "Montserrat";
    constexpr std::string_view tabular = "Montserrat #tnum=1";
    const float lettersPlain = renderer.measure(1.0F, "Wolf", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, plain).width;
    const float lettersTab = renderer.measure(1.0F, "Wolf", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, tabular).width;
    if (std::abs(lettersPlain - lettersTab) > 0.01F) {
      std::println(stderr, "cairo_text_renderer_test: FAIL: featured family resolved to a different font ({} vs {})",
                   lettersPlain, lettersTab);
      return 1;
    }
    const float onesPlain = renderer.measure(1.0F, "1111", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, plain).width;
    const float zerosPlain = renderer.measure(1.0F, "0000", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, plain).width;
    const float onesTab = renderer.measure(1.0F, "1111", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, tabular).width;
    const float zerosTab = renderer.measure(1.0F, "0000", fontSize, FontWeight::Normal, 0.0F, 0, TextAlign::Start, tabular).width;
    if (std::abs(onesPlain - zerosPlain) < 0.5F) {
      // The resolved font already has tabular digits (Montserrat absent): nothing to distinguish.
      std::println("cairo_text_renderer_test: note: proportional digits unavailable; tnum check skipped");
      return 0;
    }
    if (std::abs(onesTab - zerosTab) > 0.01F) {
      std::println(stderr, "cairo_text_renderer_test: FAIL: tnum digits not tabular (1111 {} vs 0000 {})", onesTab, zerosTab);
      return 1;
    }
    return 0;
  }
} // namespace

int main() {
  CairoTextRenderer renderer;
  renderer.initialize(nullptr, nullptr);

  if (const int rc = scaleKeyedCacheCase(renderer); rc != 0) {
    return rc;
  }
  if (const int rc = tabularFiguresCase(renderer); rc != 0) {
    return rc;
  }
  return wrappingBoundaryCase(renderer);
}
