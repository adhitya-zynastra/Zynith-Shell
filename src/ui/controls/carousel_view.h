#pragma once

#include "core/timer_manager.h"
#include "ui/controls/flex.h"
#include "ui/controls/virtual_grid_view.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

class InputArea;
class ScrollView;

// zynith: a horizontal, single-row carousel over the same VirtualGridAdapter the
// grid uses, so a host can swap one for the other without touching its data model.
//
// Composition is one physical system, not per-card offsets. A single logical
// coordinate (signed distance from the focus, in items) becomes an angle on a
// shallow orbit; that one angle produces the 2D position, the depth, and from
// the depth the scale, the opacity and the paint order:
//
//   logical position u -> theta = u * kAngleStep
//                      -> x = cx + Rx * sin(theta)          (horizontal travel,
//                                                            compressing outward)
//                      -> depth = (1 - cos theta) / (1 - cos thetaMax)
//                      -> y = apex + sink * depth           (items sink away)
//                      -> scale / opacity / z from depth
//
// Rx is derived from the item stride so spacing near the focus matches the
// scroll axis exactly, which keeps one wheel detent equal to one item.
//
// Motion is the ScrollView's own model —
// wheel/trackpad/fling — so there is no second scroll engine and no frame clock
// beyond the AnimationManager animation that is already running. After motion
// stops, a one-shot event-loop timer settles the nearest item to the centre.
//
// Focus is *not* activation: moving the carousel only rebinds visuals and fires
// onFocusChanged. Items are activated by an explicit click or Enter in the host.
class CarouselView : public Flex {
public:
  CarouselView();

  [[nodiscard]] InputArea* focusArea() const noexcept { return m_inputArea; }

  // Adapter is non-owning and must outlive the view.
  void setAdapter(VirtualGridAdapter* adapter);
  void notifyDataChanged();

  void setScale(float scale);
  // Size of the focused item; neighbours are drawn from this by the depth curve.
  void setCellSize(float width, float height);
  // Centre-to-centre distance between items at the focus, as a fraction of the
  // cell width (< 1 lets neighbours overlap behind the focused item).
  void setStrideRatio(float ratio);
  void setItemCursorShape(std::uint32_t shape);
  // Items kept bound on each side beyond the ones the viewport can show.
  void setPreloadCount(std::size_t count);

  void setFocusedIndex(std::size_t index, bool animated = true);
  [[nodiscard]] std::optional<std::size_t> focusedIndex() const noexcept { return m_focusedIndex; }
  // Jump (no animation) so `index` is the focused item, e.g. the wallpaper that
  // is currently applied when the browser opens.
  void resetTo(std::size_t index);
  void resetToStart();

  void setOnFocusChanged(std::function<void(std::optional<std::size_t>)> callback);
  // Fired with true when the carousel starts moving and false once it has
  // settled. Hosts use it to hold off expensive per-item work (image decodes)
  // until the motion lands somewhere.
  void setOnMotionChanged(std::function<void(bool)> callback);
  [[nodiscard]] bool moving() const noexcept { return m_moving; }
  // Fired on an explicit click on the already-focused item (Enter is the host's).
  void setOnActivate(std::function<void(std::size_t)> callback);

  [[nodiscard]] ScrollView& scrollView() noexcept { return *m_scroll; }

protected:
  void doLayout(Renderer& renderer) override;
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doArrange(Renderer& renderer, const LayoutRect& rect) override;

private:
  class Canvas;

  void onScrollChanged(float offset);
  void onPointerMotion(float localX, float localY);
  void onPointerLeave();
  void onPointerPress(float localX, float localY);
  void onPointerRelease(float localX, float localY);
  // One point on the orbit. `u` is the signed distance from the focus in items.
  struct PathSample {
    float centreX = 0.0F; // viewport-relative
    float centreY = 0.0F;
    float scale = 1.0F;
    float opacity = 1.0F;
    float depth = 0.0F; // 0 at the focus, 1 at the far edge of the arc
  };
  [[nodiscard]] PathSample samplePath(float u) const noexcept;

  // Where a bound slot was drawn, in canvas coordinates. Hit-testing walks this
  // front-to-back, so overlapping cards resolve exactly as they are painted.
  struct SlotGeometry {
    std::size_t index = 0;
    float centreX = 0.0F;
    float centreY = 0.0F;
    float halfWidth = 0.0F;
    float halfHeight = 0.0F;
    float depth = 0.0F;
  };

  void armSettle();
  // Returns true when it started a settle animation (motion continues).
  bool settleNow();
  void setMoving(bool moving);
  [[nodiscard]] float offsetForIndex(std::size_t index) const noexcept;
  [[nodiscard]] std::optional<std::size_t> indexAt(float localX, float localY) const noexcept;
  // Drawn rect of a bound index, in canvas coordinates.
  [[nodiscard]] bool slotRectForIndex(std::size_t index, float& outX, float& outY, float& outW, float& outH) const noexcept;
  [[nodiscard]] std::size_t nearestIndexToCentre() const noexcept;
  void updateFocusFromOffset();

  ScrollView* m_scroll = nullptr;
  Canvas* m_canvas = nullptr;
  InputArea* m_inputArea = nullptr;

  VirtualGridAdapter* m_adapter = nullptr;
  std::vector<Node*> m_pool;
  std::vector<InputArea*> m_poolTooltipAreas;
  std::vector<std::optional<std::size_t>> m_slotBoundIndex;
  std::vector<bool> m_slotBoundSelected;
  std::vector<bool> m_slotBoundHovered;
  std::vector<bool> m_slotBoundOverlayHovered;

  Timer m_settleTimer;

  std::vector<SlotGeometry> m_slotGeometry;

  float m_scale = 1.0F;
  float m_cellWidth = 320.0F;
  float m_cellHeight = 200.0F;
  float m_strideRatio = 0.62F;
  // Resolved each layout from the orbit and the viewport (see doLayout).
  float m_orbitRadius = 0.0F;
  float m_sink = 0.0F;
  float m_apexCentreY = 0.0F;
  float m_cellWidthResolved = 0.0F;
  float m_cellHeightResolved = 0.0F;
  std::size_t m_visiblePerSide = 2;
  std::size_t m_preloadCount = 1;
  std::uint32_t m_itemCursorShape = 0;

  std::optional<std::size_t> m_focusedIndex;
  std::optional<std::size_t> m_hoveredIndex;
  std::optional<std::size_t> m_hoveredOverlayIndex;
  std::function<void(std::optional<std::size_t>)> m_onFocusChanged;
  std::function<void(std::size_t)> m_onActivate;
  std::function<void(bool)> m_onMotionChanged;
  bool m_moving = false;

  // Layout snapshot, used by hit-testing and the settle step without re-measuring.
  std::size_t m_itemCount = 0;
  float m_stride = 0.0F;
  float m_leadPadding = 0.0F;
  float m_virtualWidth = 0.0F;
  float m_viewportWidth = 0.0F;
  float m_viewportHeight = 0.0F;
  bool m_pendingFocusScroll = false;
  bool m_pendingFocusAnimated = true;
  std::size_t m_pendingFocusIndex = 0;
  bool m_settling = false;
};
