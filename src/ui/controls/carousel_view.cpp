#include "ui/controls/carousel_view.h"

#include "render/scene/input_area.h"
#include "ui/controls/scroll_view.h"
#include "ui/style.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <linux/input-event-codes.h>
#include <memory>
#include <utility>

namespace {

  // How long the carousel waits after the last scroll change before settling the
  // nearest item. One shot on the shared event-loop timer: nothing runs while the
  // carousel is idle.
  constexpr std::chrono::milliseconds kSettleDelay{90};
  // Depth curve for neighbours.
  constexpr float kMinItemScale = 0.74F;
  constexpr float kMinItemOpacity = 0.42F;
  constexpr float kOpacityFalloff = 1.35F;
  constexpr float kSinkRatio = 0.05F;
  constexpr std::size_t kMaxPoolSize = 16;

  float smoothstep(float t) noexcept {
    const float c = std::clamp(t, 0.0F, 1.0F);
    return c * c * (3.0F - 2.0F * c);
  }

} // namespace

// Reports an externally set virtual size and never moves its children:
// CarouselView positions the pool explicitly (same contract as VirtualGridView).
class CarouselView::Canvas : public Node {
public:
  Canvas() = default;

  void setVirtualSize(float width, float height) {
    m_virtualWidth = std::max(0.0F, width);
    m_virtualHeight = std::max(0.0F, height);
    setSize(m_virtualWidth, m_virtualHeight);
  }

protected:
  LayoutSize doMeasure(Renderer& /*renderer*/, const LayoutConstraints& constraints) override {
    return constraints.constrain(LayoutSize{.width = m_virtualWidth, .height = m_virtualHeight});
  }

  void doLayout(Renderer& /*renderer*/) override {}

  void doArrange(Renderer& /*renderer*/, const LayoutRect& rect) override {
    setPosition(rect.x, rect.y);
    setSize(m_virtualWidth, m_virtualHeight);
  }

private:
  float m_virtualWidth = 0.0F;
  float m_virtualHeight = 0.0F;
};

CarouselView::CarouselView() {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);
  setGap(0.0F);
  setPadding(0.0F);
  setFillWidth(true);
  setFillHeight(true);

  auto scroll = std::make_unique<ScrollView>();
  scroll->setOrientation(ScrollOrientation::Horizontal);
  scroll->setFlexGrow(1.0F);
  scroll->setViewportPaddingH(0.0F);
  scroll->setViewportPaddingV(0.0F);
  scroll->setScrollbarVisible(false);
  // A mouse wheel emits a vertical axis even over a horizontal strip.
  scroll->setCrossAxisWheel(true);
  scroll->setOnScrollChanged([this](float offset) { onScrollChanged(offset); });
  m_scroll = static_cast<ScrollView*>(addChild(std::move(scroll)));

  auto canvas = std::make_unique<Canvas>();
  m_canvas = static_cast<Canvas*>(m_scroll->content()->addChild(std::move(canvas)));

  auto inputArea = std::make_unique<InputArea>();
  inputArea->setZIndex(50);
  inputArea->setFocusable(true);
  inputArea->setAcceptedButtons(InputArea::buttonMask({BTN_LEFT}));
  inputArea->setOnEnter([this](const InputArea::PointerData& data) { onPointerMotion(data.localX, data.localY); });
  inputArea->setOnMotion([this](const InputArea::PointerData& data) { onPointerMotion(data.localX, data.localY); });
  inputArea->setOnLeave([this]() { onPointerLeave(); });
  inputArea->setOnPress([this](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT) {
      return;
    }
    if (data.pressed) {
      onPointerPress(data.localX, data.localY);
    } else {
      onPointerRelease(data.localX, data.localY);
    }
  });
  m_inputArea = static_cast<InputArea*>(m_canvas->addChild(std::move(inputArea)));
}

void CarouselView::setAdapter(VirtualGridAdapter* adapter) {
  if (m_adapter == adapter) {
    return;
  }
  m_adapter = adapter;
  for (Node* tile : m_pool) {
    if (tile != nullptr) {
      m_canvas->removeChild(tile);
    }
  }
  for (InputArea* area : m_poolTooltipAreas) {
    if (area != nullptr) {
      m_inputArea->removeChild(area);
    }
  }
  m_poolTooltipAreas.clear();
  m_pool.clear();
  m_slotBoundIndex.clear();
  m_slotBoundSelected.clear();
  m_slotBoundHovered.clear();
  m_slotBoundOverlayHovered.clear();
  m_focusedIndex.reset();
  m_hoveredIndex.reset();
  m_hoveredOverlayIndex.reset();
  m_settleTimer.stop();
  markLayoutDirty();
}

void CarouselView::notifyDataChanged() {
  std::ranges::fill(m_slotBoundIndex, std::nullopt);
  markLayoutDirty();
}

void CarouselView::setScale(float scale) {
  m_scale = std::max(0.1F, scale);
  if (m_scroll != nullptr) {
    m_scroll->setContentScale(m_scale);
  }
}

void CarouselView::setCellSize(float width, float height) {
  const float w = std::max(1.0F, width);
  const float h = std::max(1.0F, height);
  if (std::abs(w - m_cellWidth) < 0.5F && std::abs(h - m_cellHeight) < 0.5F) {
    return;
  }
  m_cellWidth = w;
  m_cellHeight = h;
  notifyDataChanged();
}

void CarouselView::setStrideRatio(float ratio) {
  m_strideRatio = std::clamp(ratio, 0.3F, 1.5F);
  markLayoutDirty();
}

void CarouselView::setItemCursorShape(std::uint32_t shape) {
  if (m_itemCursorShape == shape) {
    return;
  }
  m_itemCursorShape = shape;
  for (InputArea* area : m_poolTooltipAreas) {
    if (area != nullptr) {
      area->setCursorShape(shape);
    }
  }
}

void CarouselView::setPreloadCount(std::size_t count) {
  m_preloadCount = std::min<std::size_t>(count, 4);
  markLayoutDirty();
}

void CarouselView::setOnFocusChanged(std::function<void(std::optional<std::size_t>)> callback) {
  m_onFocusChanged = std::move(callback);
}

void CarouselView::setOnActivate(std::function<void(std::size_t)> callback) { m_onActivate = std::move(callback); }

float CarouselView::offsetForIndex(std::size_t index) const noexcept {
  return static_cast<float>(index) * m_stride;
}

void CarouselView::setFocusedIndex(std::size_t index, bool animated) {
  const std::size_t count = m_adapter == nullptr ? 0U : m_adapter->itemCount();
  if (count == 0 || index >= count) {
    return;
  }
  const bool changed = !m_focusedIndex.has_value() || *m_focusedIndex != index;
  m_focusedIndex = index;
  m_pendingFocusScroll = true;
  m_pendingFocusAnimated = animated;
  m_pendingFocusIndex = index;
  markLayoutDirty();
  if (changed && m_onFocusChanged) {
    m_onFocusChanged(m_focusedIndex);
  }
}

void CarouselView::resetToStart() {
  m_settleTimer.stop();
  m_focusedIndex.reset();
  if (m_scroll != nullptr) {
    m_scroll->setScrollOffset(0.0F);
  }
  notifyDataChanged();
  // Land focus on the first item so Enter has a target straight away. Focus is
  // still only focus: nothing is applied until the item is explicitly activated.
  if (m_adapter != nullptr && m_adapter->itemCount() > 0) {
    setFocusedIndex(0, /*animated=*/false);
  } else if (m_onFocusChanged) {
    m_onFocusChanged(std::nullopt);
  }
}

std::size_t CarouselView::nearestIndexToCentre() const noexcept {
  if (m_itemCount == 0 || m_stride <= 0.0F || m_scroll == nullptr) {
    return 0;
  }
  const float raw = m_scroll->scrollOffset() / m_stride;
  const auto index = static_cast<long>(std::lround(raw));
  return static_cast<std::size_t>(std::clamp<long>(index, 0, static_cast<long>(m_itemCount) - 1));
}

void CarouselView::updateFocusFromOffset() {
  if (m_itemCount == 0) {
    if (m_focusedIndex.has_value()) {
      m_focusedIndex.reset();
      if (m_onFocusChanged) {
        m_onFocusChanged(m_focusedIndex);
      }
    }
    return;
  }
  const std::size_t index = nearestIndexToCentre();
  if (m_focusedIndex.has_value() && *m_focusedIndex == index) {
    return;
  }
  m_focusedIndex = index;
  if (m_onFocusChanged) {
    m_onFocusChanged(m_focusedIndex);
  }
}

void CarouselView::armSettle() {
  m_settleTimer.start(kSettleDelay, [this]() { settleNow(); });
}

void CarouselView::settleNow() {
  if (m_scroll == nullptr || m_itemCount == 0 || m_stride <= 0.0F) {
    return;
  }
  const float target = offsetForIndex(nearestIndexToCentre());
  const float delta = target - m_scroll->scrollOffset();
  if (std::abs(delta) < 1.0F) {
    return;
  }
  // ScrollView's own eased scroll: decelerating, no overshoot, and the frame
  // clock stops with it.
  m_settling = true;
  m_scroll->scrollBy(delta);
  m_settling = false;
}

void CarouselView::onScrollChanged(float /*offset*/) {
  updateFocusFromOffset();
  if (!m_settling) {
    armSettle();
  }
  markLayoutDirty();
}

std::optional<std::size_t> CarouselView::indexAt(float localX, float localY) const noexcept {
  if (m_itemCount == 0 || m_stride <= 0.0F) {
    return std::nullopt;
  }
  const float bandTop = (m_viewportHeight - m_cellHeight) * 0.5F;
  if (localY < bandTop - m_cellHeight * 0.1F || localY > bandTop + m_cellHeight * 1.1F) {
    return std::nullopt;
  }
  const float centreX = localX - m_leadPadding - m_cellWidth * 0.5F;
  const auto raw = static_cast<long>(std::lround(centreX / m_stride));
  if (raw < 0 || raw >= static_cast<long>(m_itemCount)) {
    return std::nullopt;
  }
  return static_cast<std::size_t>(raw);
}

void CarouselView::onPointerMotion(float localX, float localY) {
  const auto idx = indexAt(localX, localY);
  std::optional<std::size_t> overlayIdx;
  if (idx.has_value() && m_adapter != nullptr && m_focusedIndex.has_value() && *idx == *m_focusedIndex) {
    const float cellX = m_leadPadding + static_cast<float>(*idx) * m_stride;
    const float cellY = (m_viewportHeight - m_cellHeight) * 0.5F;
    if (m_adapter->overlayHitTest(*idx, localX - cellX, localY - cellY, m_cellWidth, m_cellHeight)) {
      overlayIdx = idx;
    }
  }
  if (idx == m_hoveredIndex && overlayIdx == m_hoveredOverlayIndex) {
    return;
  }
  m_hoveredIndex = idx;
  m_hoveredOverlayIndex = overlayIdx;
  markLayoutDirty();
}

void CarouselView::onPointerLeave() {
  if (!m_hoveredIndex.has_value() && !m_hoveredOverlayIndex.has_value()) {
    return;
  }
  m_hoveredIndex.reset();
  m_hoveredOverlayIndex.reset();
  markLayoutDirty();
}

void CarouselView::onPointerPress(float localX, float localY) {
  const auto idx = indexAt(localX, localY);
  if (!idx.has_value() || m_adapter == nullptr) {
    return;
  }

  // Clicking a neighbour only brings it to the centre — focus is never an apply.
  if (!m_focusedIndex.has_value() || *m_focusedIndex != *idx) {
    setFocusedIndex(*idx, true);
    return;
  }

  const float cellX = m_leadPadding + static_cast<float>(*idx) * m_stride;
  const float cellY = (m_viewportHeight - m_cellHeight) * 0.5F;
  if (m_adapter->onPointerPress(*idx, localX - cellX, localY - cellY, m_cellWidth, m_cellHeight)) {
    notifyDataChanged();
    return;
  }

  if (m_onActivate) {
    m_onActivate(*idx);
  } else {
    m_adapter->onActivate(*idx);
  }
}

void CarouselView::onPointerRelease(float /*localX*/, float /*localY*/) {}

void CarouselView::doLayout(Renderer& renderer) {
  if (m_adapter == nullptr || m_scroll == nullptr || m_canvas == nullptr || m_inputArea == nullptr) {
    Flex::doLayout(renderer);
    return;
  }

  m_itemCount = m_adapter->itemCount();
  m_viewportWidth = std::max(0.0F, width());
  m_viewportHeight = std::max(0.0F, height());

  // Fit the requested cell into the viewport without distorting it: whichever axis
  // binds first shrinks both, so the focused item is as large as the body allows.
  const float maxCellW = std::max(1.0F, m_viewportWidth * 0.86F);
  const float maxCellH = std::max(1.0F, m_viewportHeight * 0.96F);
  const float fit = std::min({1.0F, maxCellW / m_cellWidth, maxCellH / m_cellHeight});
  const float cellW = std::max(1.0F, m_cellWidth * fit);
  const float cellH = std::max(1.0F, m_cellHeight * fit);
  m_stride = std::max(1.0F, cellW * m_strideRatio);
  m_leadPadding = std::max(0.0F, (m_viewportWidth - cellW) * 0.5F);
  m_virtualWidth = m_itemCount == 0
      ? m_viewportWidth
      : (2.0F * m_leadPadding + cellW + static_cast<float>(m_itemCount - 1) * m_stride);

  m_canvas->setVirtualSize(m_virtualWidth, m_viewportHeight);
  // One wheel detent travels one item: the step is animated, not a jump, so the
  // motion still reads as scrolling rather than snapping.
  m_scroll->setScrollWheelStep(m_stride);

  if (m_pendingFocusScroll) {
    m_pendingFocusScroll = false;
    if (m_pendingFocusIndex < m_itemCount) {
      const float target = offsetForIndex(m_pendingFocusIndex);
      if (m_pendingFocusAnimated) {
        const float delta = target - m_scroll->scrollOffset();
        if (std::abs(delta) >= 1.0F) {
          m_settling = true;
          m_scroll->scrollBy(delta);
          m_settling = false;
        }
      } else {
        m_scroll->requestScrollToOffset(target);
      }
    }
  }

  // Visible window: what the viewport can show around the centre, plus preload.
  const float offset = m_scroll->scrollOffset();
  const auto span = static_cast<long>(std::ceil((m_viewportWidth * 0.5F) / m_stride))
      + static_cast<long>(m_preloadCount) + 1;
  const auto centre = static_cast<long>(std::lround(offset / m_stride));
  const long firstIdx = std::max<long>(0, centre - span);
  const long lastIdx = m_itemCount == 0
      ? -1
      : std::min<long>(centre + span, static_cast<long>(m_itemCount) - 1);
  const std::size_t desiredPoolSize = lastIdx < firstIdx
      ? 0U
      : std::min<std::size_t>(kMaxPoolSize, static_cast<std::size_t>(lastIdx - firstIdx + 1));

  while (m_pool.size() < desiredPoolSize) {
    const std::size_t slot = m_pool.size();
    auto tile = m_adapter->createTile();
    if (tile == nullptr) {
      break;
    }
    tile->setVisible(false);
    tile->setParticipatesInLayout(false);
    Node* raw = m_canvas->addChild(std::move(tile));
    m_pool.push_back(raw);
    m_slotBoundIndex.emplace_back();
    m_slotBoundSelected.push_back(false);
    m_slotBoundHovered.push_back(false);
    m_slotBoundOverlayHovered.push_back(false);

    auto tooltipArea = std::make_unique<InputArea>();
    tooltipArea->setVisible(false);
    tooltipArea->setAcceptedButtons(0);
    tooltipArea->setCursorShape(m_itemCursorShape);
    tooltipArea->setTooltipProvider([this, slot]() -> TooltipContent {
      if (m_adapter == nullptr || slot >= m_slotBoundIndex.size() || !m_slotBoundIndex[slot].has_value()) {
        return {};
      }
      std::string tooltip = m_adapter->itemTooltip(*m_slotBoundIndex[slot]);
      return tooltip.empty() ? TooltipContent{} : TooltipContent{std::move(tooltip)};
    });
    m_poolTooltipAreas.push_back(static_cast<InputArea*>(m_inputArea->addChild(std::move(tooltipArea))));
  }

  const std::size_t poolSize = m_pool.size();
  std::vector<bool> slotActive(poolSize, false);
  const float cellY = (m_viewportHeight - cellH) * 0.5F;

  if (poolSize > 0 && lastIdx >= firstIdx) {
    for (long i = firstIdx; i <= lastIdx; ++i) {
      const auto index = static_cast<std::size_t>(i);
      const std::size_t slot = index % poolSize;
      if (slotActive[slot]) {
        continue; // More items than slots: the far edge simply stays unbound.
      }
      Node* tile = m_pool[slot];
      if (tile == nullptr) {
        continue;
      }
      slotActive[slot] = true;

      const float x = m_leadPadding + static_cast<float>(index) * m_stride;
      tile->setPosition(x, cellY);
      tile->setSize(cellW, cellH);

      const bool focused = m_focusedIndex.has_value() && *m_focusedIndex == index;
      const bool hovered = m_hoveredIndex.has_value() && *m_hoveredIndex == index;
      const bool overlayHovered = m_hoveredOverlayIndex.has_value() && *m_hoveredOverlayIndex == index;
      const bool dirty = !m_slotBoundIndex[slot].has_value()
          || *m_slotBoundIndex[slot] != index
          || m_slotBoundSelected[slot] != focused
          || m_slotBoundHovered[slot] != hovered;
      if (dirty) {
        m_adapter->bindTile(*tile, index, focused, hovered);
        m_slotBoundIndex[slot] = index;
        m_slotBoundSelected[slot] = focused;
        m_slotBoundHovered[slot] = hovered;
      }
      if (m_slotBoundOverlayHovered[slot] != overlayHovered) {
        m_adapter->applyOverlayHover(*tile, overlayHovered);
        m_slotBoundOverlayHovered[slot] = overlayHovered;
      }

      // Depth: distance from the viewport centre in stride units drives scale,
      // opacity, a small sink and paint order. Recomputed only when the offset
      // changes, never on a clock of its own.
      const float distance = std::abs(static_cast<float>(index) * m_stride - offset) / m_stride;
      const float t = smoothstep(std::min(1.0F, distance));
      const float itemScale = 1.0F - (1.0F - kMinItemScale) * t;
      const float itemOpacity =
          1.0F - (1.0F - kMinItemOpacity) * std::clamp(distance / kOpacityFalloff, 0.0F, 1.0F);
      tile->setScale(itemScale);
      tile->setOpacity(itemOpacity);
      tile->setPosition(x, cellY + cellH * kSinkRatio * t);
      tile->setZIndex(static_cast<std::int32_t>(100.0F - std::min(90.0F, distance * 10.0F)));
      tile->setVisible(true);
      tile->layout(renderer);

      InputArea* tooltipArea = m_poolTooltipAreas[slot];
      if (tooltipArea != nullptr) {
        const float visibleW = cellW * itemScale;
        const float visibleH = cellH * itemScale;
        tooltipArea->setPosition(x + (cellW - visibleW) * 0.5F, cellY + (cellH - visibleH) * 0.5F);
        tooltipArea->setFrameSize(visibleW, visibleH);
        tooltipArea->setVisible(true);
      }
    }
  }

  for (std::size_t slot = 0; slot < poolSize; ++slot) {
    if (!slotActive[slot] && m_pool[slot] != nullptr) {
      m_pool[slot]->setVisible(false);
      m_slotBoundIndex[slot].reset();
      m_slotBoundOverlayHovered[slot] = false;
      if (slot < m_poolTooltipAreas.size() && m_poolTooltipAreas[slot] != nullptr) {
        m_poolTooltipAreas[slot]->setVisible(false);
      }
    }
  }

  m_inputArea->setPosition(0.0F, 0.0F);
  m_inputArea->setFrameSize(m_virtualWidth, m_viewportHeight);

  Flex::doLayout(renderer);
}

LayoutSize CarouselView::doMeasure(Renderer& /*renderer*/, const LayoutConstraints& constraints) {
  const float w = constraints.hasExactWidth() ? constraints.maxWidth
      : constraints.hasMaxWidth               ? constraints.maxWidth
                                              : 0.0F;
  const float h = constraints.hasExactHeight() ? constraints.maxHeight
      : constraints.hasMaxHeight               ? constraints.maxHeight
                                               : 0.0F;
  return LayoutSize{.width = w, .height = h};
}

void CarouselView::doArrange(Renderer& renderer, const LayoutRect& rect) { arrangeByLayout(renderer, rect); }
