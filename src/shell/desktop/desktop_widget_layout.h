#pragma once

#include "config/config_types.h"
#include "shell/desktop/widget_transform.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <string>
#include <variant>
#include <vector>

namespace desktop_widgets {

  inline float widgetContentScale(float baseUiScale) { return std::max(0.01F, baseUiScale); }

  inline void widgetNodeScale(const DesktopWidgetState& state, float& outScaleX, float& outScaleY) {
    outScaleX = state.flipX ? -1.0F : 1.0F;
    outScaleY = state.flipY ? -1.0F : 1.0F;
  }

  // zynith: responsive placement. A widget's position was stored against placementWidth x Height;
  // on a different output size, a "free" widget scales with the output (the historical behaviour),
  // while an anchored one keeps its distance to the anchored edge or corner — so a visualizer on the
  // right edge stays on the right edge of an ultrawide instead of drifting inward.
  inline void rescaleToOutput(DesktopWidgetState& widget, float width, float height) {
    std::string anchor = "free";
    if (const auto it = widget.settings.find("anchor"); it != widget.settings.end()) {
      if (const auto* value = std::get_if<std::string>(&it->second)) {
        anchor = *value;
      }
    }
    if (anchor == "free" || anchor.empty()) {
      widget.cx *= width / widget.placementWidth;
      widget.cy *= height / widget.placementHeight;
      return;
    }
    const float dw = width - widget.placementWidth;
    const float dh = height - widget.placementHeight;
    const bool right = anchor.ends_with("right");
    const bool left = anchor.ends_with("left");
    const bool top = anchor.starts_with("top");
    const bool bottom = anchor.starts_with("bottom");
    // Left/top keep their offset from 0; right/bottom from the far edge; the rest from the centre.
    widget.cx += right ? dw : (left ? 0.0F : dw * 0.5F);
    widget.cy += bottom ? dh : (top ? 0.0F : dh * 0.5F);
  }

  inline std::string outputKey(const WaylandOutput& output) {
    if (!output.connectorName.empty()) {
      return output.connectorName;
    }
    return std::to_string(output.name);
  }

  inline const WaylandOutput* findOutputByKey(const WaylandConnection& wayland, const std::string& key) {
    if (key.empty()) {
      return nullptr;
    }
    for (const auto& output : wayland.outputs()) {
      if (!output.done || output.output == nullptr || !output.hasUsableGeometry()) {
        continue;
      }
      if (outputKey(output) == key) {
        return &output;
      }
    }
    return nullptr;
  }

  inline const WaylandOutput*
  resolveEffectiveOutput(const WaylandConnection& wayland, const std::string& requestedOutput) {
    const auto& outputs = wayland.outputs();
    const WaylandOutput* primary = nullptr;
    for (const auto& output : outputs) {
      if (!output.done || output.output == nullptr || !output.hasUsableGeometry()) {
        continue;
      }
      if (primary == nullptr) {
        primary = &output;
      }
      if (!requestedOutput.empty() && outputKey(output) == requestedOutput) {
        return &output;
      }
    }
    if (!requestedOutput.empty()) {
      return nullptr;
    }
    return primary;
  }

  inline const WaylandOutput* resolveStateOutput(const WaylandConnection& wayland, const DesktopWidgetState& state) {
    if (state.outputName.empty()) {
      return resolveEffectiveOutput(wayland, state.outputName);
    }
    return findOutputByKey(wayland, state.outputName);
  }

  inline float outputLogicalWidth(const WaylandOutput& output) {
    return static_cast<float>(std::max(1, output.effectiveLogicalWidth()));
  }

  inline float outputLogicalHeight(const WaylandOutput& output) {
    return static_cast<float>(std::max(1, output.effectiveLogicalHeight()));
  }

  class PlacementMapper {
  public:
    [[nodiscard]] bool
    remapForOutputChange(const WaylandConnection& wayland, std::vector<DesktopWidgetState>& widgets) const {
      bool changed = false;
      for (auto& widget : widgets) {
        const WaylandOutput* output = resolveStateOutput(wayland, widget);
        if (output == nullptr) {
          continue;
        }

        const float width = outputLogicalWidth(*output);
        const float height = outputLogicalHeight(*output);
        if (widget.placementWidth <= 0.0F || widget.placementHeight <= 0.0F) {
          widget.placementWidth = width;
          widget.placementHeight = height;
          changed = true;
          continue;
        }

        if (widget.placementWidth == width && widget.placementHeight == height) {
          continue;
        }

        rescaleToOutput(widget, width, height);
        widget.placementWidth = width;
        widget.placementHeight = height;
        changed = true;
      }
      return changed;
    }

    void rebaseForCurrentOutputs(const WaylandConnection& wayland, std::vector<DesktopWidgetState>& widgets) const {
      for (auto& widget : widgets) {
        const WaylandOutput* output = resolveStateOutput(wayland, widget);
        if (output == nullptr) {
          continue;
        }
        widget.placementWidth = outputLogicalWidth(*output);
        widget.placementHeight = outputLogicalHeight(*output);
      }
    }
  };

  // Single source of truth for desktop widget coordinate clamping. Edit mode, default mode, and
  // snapshot normalization all route through here so the visibility rule stays identical. Resolves
  // the widget's effective output, then constrains state.cx/cy so that at least
  // kDesktopWidgetMinVisibleFraction of the widget's rotated AABB remains on screen. The caller
  // passes the widget's current box size as intrinsicWidth/intrinsicHeight, so no extra scale
  // multiplier is applied here.
  inline const WaylandOutput* clampStateToOutput(
      const WaylandConnection& wayland, DesktopWidgetState& state, float intrinsicWidth, float intrinsicHeight
  ) {
    const WaylandOutput* output = resolveStateOutput(wayland, state);
    if (output == nullptr) {
      return nullptr;
    }
    const WidgetTransformClampResult clamped = clampWidgetCenterToOutput(
        state.cx, state.cy, intrinsicWidth, intrinsicHeight, 1.0F, state.rotationRad, outputLogicalWidth(*output),
        outputLogicalHeight(*output), kDesktopWidgetMinVisibleFraction
    );
    state.cx = clamped.cx;
    state.cy = clamped.cy;
    return output;
  }

} // namespace desktop_widgets
