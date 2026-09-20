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
  // ── The orbit ─────────────────────────────────────────────────────────────
  // Angular spacing between neighbouring items. Wide enough that the outer
  // cards visibly turn away, shallow enough to avoid a fairground wheel.
  constexpr float kAngleStepRad = 0.3665F; // 21 degrees
  // The arc is normalised over this many items per side, so the depth curve
  // (and therefore scale/opacity/sink) is stable whatever the viewport shows.
  constexpr float kArcHalfSpanItems = 3.0F;
  // Far-edge appearance.
  constexpr float kMinItemScale = 0.52F;
  // < 1 makes the first neighbour recede decisively instead of shadowing the focus.
  constexpr float kScaleFalloffExp = 0.6F;
  constexpr float kSinkFalloffExp = 0.55F;
  constexpr float kMinItemOpacity = 0.26F;
  // How far the far edge of the arc sinks, as a fraction of the focused height.
  constexpr float kSinkRatio = 0.38F;
  // Below this drawn scale a card is noise rather than a preview: the arc ends.
  constexpr float kLegibleScale = 0.42F;
  // Hard ceiling on the working set, whatever the geometry asks for.
  constexpr std::size_t kMaxPerSide = 3;
  constexpr std::size_t kMaxPoolSize = 16;
  // Paint order: cards span 0..kFocusZIndex by depth, the hit-test overlay sits above.
  constexpr std::int32_t kFocusZIndex = 1000;
  constexpr std::int32_t kOverlayZIndex = 5000;

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
  // Above every card: cards carry a depth-derived z-index (up to kFocusZIndex) so
  // the arc paints back-to-front, and an InputArea sitting under them would never
  // see a press — WallpaperTile is itself an InputArea and would swallow it.
  inputArea->setZIndex(kOverlayZIndex);
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

void CarouselView::setOnMotionChanged(std::function<void(bool)> callback) { m_onMotionChanged = std::move(callback); }

void CarouselView::setMoving(bool moving) {
  if (m_moving == moving) {
    return;
  }
  m_moving = moving;
  if (m_onMotionChanged) {
    m_onMotionChanged(moving);
  }
}

CarouselView::PathSample CarouselView::samplePath(float u) const noexcept {
  const float theta = u * kAngleStepRad;
  const float thetaMax = kArcHalfSpanItems * kAngleStepRad;
  const float depthSpan = 1.0F - std::cos(thetaMax);
  const float depth = depthSpan <= 0.0F ? 0.0F : std::clamp((1.0F - std::cos(theta)) / depthSpan, 0.0F, 1.0F);

  PathSample sample;
  sample.depth = depth;
  sample.centreX = m_viewportWidth * 0.5F + m_orbitRadius * std::sin(theta);
  // The sink follows a gentler exponent than scale, so the arc is legible right
  // next to the focus instead of only at the far edge.
  sample.centreY = m_apexCentreY + m_sink * std::pow(depth, kSinkFalloffExp);
  // Near neighbours stay close to full size; the fall-off accelerates outward.
  sample.scale = 1.0F - (1.0F - kMinItemScale) * std::pow(depth, kScaleFalloffExp);
  sample.opacity = 1.0F - (1.0F - kMinItemOpacity) * depth;
  return sample;
}

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

void CarouselView::resetTo(std::size_t index) {
  m_settleTimer.stop();
  setMoving(false);
  m_focusedIndex.reset();
  const std::size_t count = m_adapter == nullptr ? 0U : m_adapter->itemCount();
  if (m_scroll != nullptr) {
    m_scroll->setScrollOffset(count == 0 ? 0.0F : offsetForIndex(std::min(index, count - 1)));
  }
  notifyDataChanged();
  // Land focus straight away so Enter has a target. Focus is still only focus:
  // nothing is applied until the item is explicitly activated.
  if (count > 0) {
    setFocusedIndex(std::min(index, count - 1), /*animated=*/false);
  } else if (m_onFocusChanged) {
    m_onFocusChanged(std::nullopt);
  }
}

void CarouselView::resetToStart() { resetTo(0); }

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
  m_settleTimer.start(kSettleDelay, [this]() {
    if (!settleNow()) {
      return;
    }
    // A settle animation is running: check again when it has stopped emitting.
    armSettle();
  });
}

bool CarouselView::settleNow() {
  if (m_scroll == nullptr || m_itemCount == 0 || m_stride <= 0.0F) {
    setMoving(false);
    return false;
  }
  const float target = offsetForIndex(nearestIndexToCentre());
  const float delta = target - m_scroll->scrollOffset();
  if (std::abs(delta) < 1.0F) {
    // Nothing left to travel: the carousel has landed.
    setMoving(false);
    return false;
  }
  // ScrollView's own eased scroll: decelerating, no overshoot, and the frame
  // clock stops with it.
  m_settling = true;
  m_scroll->scrollBy(delta);
  m_settling = false;
  return true;
}

void CarouselView::onScrollChanged(float /*offset*/) {
  setMoving(true);
  updateFocusFromOffset();
  if (!m_settling) {
    armSettle();
  }
  markLayoutDirty();
}

std::optional<std::size_t> CarouselView::indexAt(float localX, float localY) const noexcept {
  // Front-to-back over what was actually drawn: overlapping cards resolve the
  // way they are painted, so the focused card always wins its own area.
  const SlotGeometry* best = nullptr;
  for (const SlotGeometry& slot : m_slotGeometry) {
    if (std::abs(localX - slot.centreX) > slot.halfWidth || std::abs(localY - slot.centreY) > slot.halfHeight) {
      continue;
    }
    if (best == nullptr || slot.depth < best->depth) {
      best = &slot;
    }
  }
  return best == nullptr ? std::nullopt : std::optional<std::size_t>{best->index};
}

bool CarouselView::slotRectForIndex(std::size_t index, float& outX, float& outY, float& outW, float& outH)
    const noexcept {
  for (const SlotGeometry& slot : m_slotGeometry) {
    if (slot.index != index) {
      continue;
    }
    outW = slot.halfWidth * 2.0F;
    outH = slot.halfHeight * 2.0F;
    outX = slot.centreX - slot.halfWidth;
    outY = slot.centreY - slot.halfHeight;
    return true;
  }
  return false;
}

void CarouselView::onPointerMotion(float localX, float localY) {
  const auto idx = indexAt(localX, localY);
  std::optional<std::size_t> overlayIdx;
  if (idx.has_value() && m_adapter != nullptr && m_focusedIndex.has_value() && *idx == *m_focusedIndex) {
    float x = 0.0F;
    float y = 0.0F;
    float w = 0.0F;
    float h = 0.0F;
    if (slotRectForIndex(*idx, x, y, w, h)
        && m_adapter->overlayHitTest(*idx, (localX - x) / std::max(0.01F, w) * m_cellWidthResolved,
                                     (localY - y) / std::max(0.01F, h) * m_cellHeightResolved,
                                     m_cellWidthResolved, m_cellHeightResolved)) {
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

  float x = 0.0F;
  float y = 0.0F;
  float w = 0.0F;
  float h = 0.0F;
  const bool haveRect = slotRectForIndex(*idx, x, y, w, h);
  const bool overlayTook = haveRect
      && m_adapter->onPointerPress(*idx, (localX - x) / std::max(0.01F, w) * m_cellWidthResolved,
                                   (localY - y) / std::max(0.01F, h) * m_cellHeightResolved, m_cellWidthResolved,
                                   m_cellHeightResolved);
  if (overlayTook) {
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

  // ── Fit the focused card into the body ───────────────────────────────────
  // The sunk far edge never reaches below the focused card's own bottom with
  // the current curve, so the body only has to hold the focused card itself.
  // Fitting keeps the aspect: whichever axis binds first shrinks both.
  const float maxCellW = std::max(1.0F, m_viewportWidth * 0.86F);
  const float maxCellH = std::max(1.0F, m_viewportHeight * 0.96F);
  const float fit = std::min({1.0F, maxCellW / m_cellWidth, maxCellH / m_cellHeight});
  const float cellW = std::max(1.0F, m_cellWidth * fit);
  const float cellH = std::max(1.0F, m_cellHeight * fit);
  m_cellWidthResolved = cellW;
  m_cellHeightResolved = cellH;

  // ── Resolve the orbit ────────────────────────────────────────────────────
  // Rx is chosen so travel near the focus matches the scroll axis: d(x)/d(u) at
  // u = 0 is Rx * kAngleStepRad, which must equal one stride.
  m_stride = std::max(1.0F, cellW * m_strideRatio);
  m_orbitRadius = m_stride / kAngleStepRad;
  m_sink = cellH * kSinkRatio;
  m_apexCentreY = (m_viewportHeight - cellH) * 0.5F + cellH * 0.5F - m_sink * 0.5F;

  // How much of the arc this viewport can actually carry: walk outward until a
  // card is either illegible or completely outside the viewport. Resource cost
  // and composition therefore follow the geometry instead of a magic number.
  std::size_t perSide = 0;
  for (std::size_t n = 1; n <= kMaxPerSide; ++n) {
    const PathSample sample = samplePath(static_cast<float>(n));
    if (sample.scale < kLegibleScale) {
      break;
    }
    if (sample.centreX - cellW * sample.scale * 0.5F >= m_viewportWidth) {
      break;
    }
    perSide = n;
  }
  m_visiblePerSide = perSide;

  m_scroll->setScrollWheelStep(m_stride);

  // The scroll axis stays linear — logical position x stride — and the curve is
  // applied when drawing. One detent is still exactly one item.
  const float lead = std::max(0.0F, (m_viewportWidth - cellW) * 0.5F);
  m_leadPadding = lead;
  m_virtualWidth = m_itemCount == 0
      ? m_viewportWidth
      : (2.0F * lead + cellW + static_cast<float>(m_itemCount - 1) * m_stride);
  m_canvas->setVirtualSize(m_virtualWidth, m_viewportHeight);

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

  const float offset = m_scroll->scrollOffset();
  const float focusPosition = m_stride <= 0.0F ? 0.0F : offset / m_stride;
  const auto centre = static_cast<long>(std::lround(focusPosition));
  const auto reach = static_cast<long>(m_visiblePerSide + m_preloadCount);
  const long firstIdx = std::max<long>(0, centre - reach);
  const long lastIdx =
      m_itemCount == 0 ? -1 : std::min<long>(centre + reach, static_cast<long>(m_itemCount) - 1);
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
  m_slotGeometry.clear();
  m_slotGeometry.reserve(poolSize);

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

      // One logical coordinate drives everything below.
      const float u = static_cast<float>(index) - focusPosition;
      const PathSample sample = samplePath(u);
      const bool onArc = std::abs(u) <= static_cast<float>(m_visiblePerSide) + 0.5F;

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

      // Canvas coordinates: the scroll view translates the canvas by -offset,
      // so the viewport-relative sample is shifted back by the offset here.
      const float centreX = offset + sample.centreX;
      tile->setPosition(centreX - cellW * 0.5F, sample.centreY - cellH * 0.5F);
      tile->setScale(sample.scale);
      tile->setOpacity(sample.opacity);
      tile->setZIndex(static_cast<std::int32_t>(std::lround((1.0F - sample.depth) * static_cast<float>(kFocusZIndex))));
      tile->setVisible(onArc);
      tile->layout(renderer);

      InputArea* tooltipArea = m_poolTooltipAreas[slot];
      const float halfW = cellW * sample.scale * 0.5F;
      const float halfH = cellH * sample.scale * 0.5F;
      if (tooltipArea != nullptr) {
        tooltipArea->setPosition(centreX - halfW, sample.centreY - halfH);
        tooltipArea->setFrameSize(halfW * 2.0F, halfH * 2.0F);
        tooltipArea->setVisible(onArc);
      }
      if (onArc) {
        m_slotGeometry.push_back(
            SlotGeometry{
                .index = index,
                .centreX = centreX,
                .centreY = sample.centreY,
                .halfWidth = halfW,
                .halfHeight = halfH,
                .depth = sample.depth,
            }
        );
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
