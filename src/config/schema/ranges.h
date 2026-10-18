#pragma once

#include "config/config_limits.h"
#include "config/schema/field.h"

// Numeric ranges for settings that have a UI slider. Each constant is the SINGLE
// source for both the parser's clamp (the schema `Field`'s `Range`) and the
// settings GUI slider bounds — so the two can never drift. `min`/`max`/`step` are
// the curated UI range; the parser ignores `step` (GUI metadata only).
namespace noctalia::config::schema {

  // Shared ranges for concepts that recur verbatim across many settings.
  inline constexpr Range<float> kUnitRange{0.0F, 1.0F, 0.01F};          // opacities, intensities, 0..1 factors
  inline constexpr Range<float> kScaleRange{0.5F, 2.5F, 0.05F};         // ui_scale, notification/osd scale
  inline constexpr Range<std::int64_t> kRefreshMinutesRange{5, 240, 5}; // calendar/weather refresh interval

  // Shell.
  inline constexpr Range<std::int64_t> kHoverIntentRange{0, 2000, 50};   // clock hover-open delay (ms)
  inline constexpr Range<float> kAnimationSpeedRange{0.1F, 4.0F, 0.05F};
  // Per-category trim on a motion preset, as a percentage of its baseline. 100 = preset unmodified.
  // Floor of 50, not 0: niri durations are derived as base / (factor * trim), so a 0 % trim divides
  // by zero. 50 matches the range the retired Motion plugin enforced.
  inline constexpr Range<std::int64_t> kMotionTrimRange{50, 200, 5};
  // Glass: blur strength is an intent-level 0-100 scale mapped onto niri's global blur passes/offset.
  inline constexpr Range<std::int64_t> kGlassBlurStrengthRange{0, 100, 5};
  // Wallpaper browser: preferred focused-card width in logical px (resolved against the display).
  inline constexpr Range<std::int64_t> kLauncherWidthRange{420, 1200, 10};
  inline constexpr Range<std::int64_t> kLauncherHeightRange{320, 1000, 10};
  inline constexpr Range<std::int64_t> kLauncherIconSizeRange{20, 64, 2};
  inline constexpr Range<std::int64_t> kOsdDurationRange{600, 5000, 100};
  inline constexpr Range<std::int64_t> kCarouselCardWidthRange{400, 1400, 20};
  // zynith: live wallpaper renderer frame cap and volume (0 = silent).
  inline constexpr Range<std::int64_t> kLiveWallpaperFpsRange{1, 144, 1};
  inline constexpr Range<std::int64_t> kLiveWallpaperVolumeRange{0, 100, 5};
  inline constexpr Range<float> kCornerRadiusScaleRange{0.0F, 2.0F, 0.05F};
  inline constexpr Range<std::int64_t> kControlCenterWidthRange{600, 1200, 10};
  inline constexpr Range<std::int64_t> kScreenCornersSizeRange{1, 100, 1};
  inline constexpr Range<std::int64_t> kHotCornersDelayMsRange{0, 2000, 50};
  inline constexpr Range<std::int64_t> kClipboardHistoryMaxEntriesRange{
      noctalia::config::kClipboardHistoryMinEntries,
      noctalia::config::kClipboardHistoryMaxEntries,
      noctalia::config::kClipboardHistoryStepEntries,
  };
  inline constexpr Range<std::int64_t> kSessionGridColumnsRange{1, 5, 1};

  // Bar.
  inline constexpr Range<float> kBarFontScaleRange{0.2F, 2.5F, 0.01F};

  // Battery / wallpaper.
  inline constexpr Range<std::int64_t> kBatteryWarningThresholdRange{0, 100, 1};
  inline constexpr Range<float> kWallpaperTransitionDurationRange{100.0F, 30000.0F, 100.0F};
  inline constexpr Range<std::int64_t> kWallpaperAutomationIntervalRange{1, 86400, 1};

  // Dock.
  inline constexpr Range<std::int64_t> kDockIconSizeRange{16, 128, 1};
  inline constexpr Range<std::int64_t> kDockPaddingRange{0, 100, 1};
  inline constexpr Range<std::int64_t> kDockItemSpacingRange{0, 100, 1};
  inline constexpr Range<std::int64_t> kDockMarginEndsRange{0, 500, 1};
  inline constexpr Range<std::int64_t> kDockMarginEdgeRange{0, 100, 1};
  inline constexpr Range<std::int64_t> kDockRadiusRange{0, 80, 1}; // radius + each corner
  inline constexpr Range<float> kDockBorderWidthRange{0.0F, 20.0F, 0.5F};
  inline constexpr Range<float> kDockActiveScaleRange{0.1F, 1.75F, 0.05F};
  inline constexpr Range<float> kDockInactiveScaleRange{0.1F, 1.0F, 0.05F};
  inline constexpr Range<float> kDockMagnificationScaleRange{1.0F, 2.0F, 0.05F};

} // namespace noctalia::config::schema
