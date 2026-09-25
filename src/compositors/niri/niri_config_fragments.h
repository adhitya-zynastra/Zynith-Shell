#pragma once

#include "config/config_types.h"

#include <string>

// Pure renderers for the niri configuration fragments Zynith owns. No I/O and no global state:
// config in, KDL text out, so the output is deterministic and unit-testable. Writing, validating
// and installing the text is NiriFragmentWriter's job.
//
// Motion (ADR-0015). The derivation is a faithful port of the retired Motion plugin's
// `derive()` / `renderNiri()` in panel.luau, so a migrated configuration produces the same
// animation body it produced before — verified against the plugin's last output. One global
// speed and one preset shape BOTH halves of the desktop's motion:
//
//   shell surfaces   MotionService speed = kShellBase x preset factor x speed
//   niri             slowdown = 1 / speed; springs and durations scaled by preset factor x trim
namespace niri_fragments {

  // The plugin's BASE.shell: Zynith's shell pace relative to upstream, at the Smooth preset.
  inline constexpr float kShellBaseSpeed = 0.8F;

  [[nodiscard]] float presetFactor(MotionPreset preset) noexcept;

  // What MotionService should run at for this configuration.
  [[nodiscard]] float effectiveShellSpeed(const ShellConfig::AnimationConfig& animation) noexcept;

  // Body of ~/.config/niri/rice/animations.kdl.
  [[nodiscard]] std::string renderAnimations(const ShellConfig::AnimationConfig& animation);

  // niri blur passes/offset for a 0-100 glass blur strength. 50 reproduces passes 3 / offset 4.0.
  struct BlurParams {
    int passes = 3;
    float offset = 4.0F;
  };
  [[nodiscard]] BlurParams blurParams(int strength) noexcept;

  // Body of ~/.config/niri/rice/glass.kdl — niri's single, global `blur {}` node.
  [[nodiscard]] std::string renderGlass(const ShellConfig::GlassConfig& glass);

  // Shared number formatting, identical to the plugin's fmt(): "%.4f" with trailing zeros removed
  // but always at least one decimal ("1.0", "0.8", "1.5625").
  [[nodiscard]] std::string formatNumber(double value);

} // namespace niri_fragments
