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
// Composition: one focused item at the viewport centre, neighbours receding to
// either side (scale + opacity + z-order). Motion is the ScrollView's own model —
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
  // Centre-to-centre distance between items, as a fraction of the cell width.
  void setStrideRatio(float ratio);
  void setItemCursorShape(std::uint32_t shape);
  // Items kept bound on each side beyond the ones the viewport can show.
  void setPreloadCount(std::size_t count);

  void setFocusedIndex(std::size_t index, bool animated = true);
  [[nodiscard]] std::optional<std::size_t> focusedIndex() const noexcept { return m_focusedIndex; }
  void resetToStart();

  void setOnFocusChanged(std::function<void(std::optional<std::size_t>)> callback);
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
  void armSettle();
  void settleNow();
  [[nodiscard]] float offsetForIndex(std::size_t index) const noexcept;
  [[nodiscard]] std::optional<std::size_t> indexAt(float localX, float localY) const noexcept;
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

  float m_scale = 1.0F;
  float m_cellWidth = 320.0F;
  float m_cellHeight = 200.0F;
  float m_strideRatio = 0.62F;
  std::size_t m_preloadCount = 1;
  std::uint32_t m_itemCursorShape = 0;

  std::optional<std::size_t> m_focusedIndex;
  std::optional<std::size_t> m_hoveredIndex;
  std::optional<std::size_t> m_hoveredOverlayIndex;
  std::function<void(std::optional<std::size_t>)> m_onFocusChanged;
  std::function<void(std::size_t)> m_onActivate;

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
