#include "shell/desktop/widgets/desktop_session_actions_widget.h"

#include "core/log.h"
#include "i18n/i18n.h"
#include "render/scene/input_area.h"
#include "shell/session/session_action_meta.h"
#include "shell/session/session_action_runner.h"
#include "ui/builders.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <chrono>
#include <utility>

namespace {

  constexpr Logger kLog("session-actions-widget");
  // Long enough to read the hint and press again; short enough that an armed shutdown does not
  // linger on a lock screen someone walks away from.
  constexpr std::chrono::milliseconds kArmWindow{4000};
  constexpr float kButtonSize = 44.0F;

} // namespace

DesktopSessionActionsWidget::DesktopSessionActionsWidget(
    Options options, SessionActionRunner* runner, std::vector<SessionPanelActionConfig> actions
)
    : m_options(options), m_runner(runner), m_actions(std::move(actions)) {}

std::vector<SessionPanelActionConfig>
DesktopSessionActionsWidget::lockScreenActions(const std::vector<SessionPanelActionConfig>& configured) {
  std::vector<SessionPanelActionConfig> out;
  for (const auto& row : configured) {
    if (!row.enabled || !session_action::isKnown(row.action)) {
      continue;
    }
    // Already locked; and no shell strings from a lock screen, whatever the power menu allows.
    if (row.action == "lock" || row.action == "lock_and_suspend" || row.action == "command") {
      continue;
    }
    if (row.command.has_value() && !StringUtils::trim(*row.command).empty()) {
      continue;
    }
    out.push_back(row);
  }
  return out;
}

bool DesktopSessionActionsWidget::needsConfirmation(const SessionPanelActionConfig& action) noexcept {
  return action.action == "logout" || action.action == "reboot" || action.action == "shutdown"
      || action.variant == SessionActionButtonVariant::Destructive;
}

void DesktopSessionActionsWidget::create() {
  m_buttons.clear();
  auto column = ui::column({.out = &m_column, .align = FlexAlign::Center, .gap = Style::spaceSm});
  auto row = m_options.vertical ? ui::column({.out = &m_row, .align = FlexAlign::Center, .gap = Style::spaceSm})
                                : ui::row({.out = &m_row, .align = FlexAlign::Center, .gap = Style::spaceSm});
  for (std::size_t i = 0; i < m_actions.size(); ++i) {
    const auto& action = m_actions[i];
    Button* button = nullptr;
    const std::string glyph =
        action.glyph.has_value() && !action.glyph->empty() ? *action.glyph : session_action::defaultGlyph(action.action);
    const std::string label =
        action.label.has_value() && !action.label->empty() ? *action.label : i18n::tr(session_action::labelKey(action.action));
    row->addChild(ui::button({
        .out = &button,
        .text = m_options.showLabels ? label : std::string{},
        .glyph = glyph,
        .onClick = [this, i]() { onPressed(i); },
    }));
    if (m_animations != nullptr) {
      button->setAnimationManager(m_animations);
    }
    m_buttons.push_back(button);
  }
  column->addChild(std::move(row));
  // The hint line is always laid out (hidden until armed), so arming never moves the buttons.
  std::string reserve;
  for (const auto& action : m_actions) {
    if (needsConfirmation(action)) {
      reserve = i18n::tr("lockscreen.session.confirm", "action", i18n::tr(session_action::labelKey(action.action)));
      break;
    }
  }
  column->addChild(ui::label({
      .out = &m_hint,
      .text = reserve,
      .fontSize = Style::fontSizeCaption,
      .color = colorSpecFromRole(ColorRole::Error),
      .visible = false,
      .participatesInLayout = !reserve.empty(),
  }));
  setRoot(std::move(column));
  syncVisuals();
  if (m_editorPreview) {
    setEditorPreview(true);
  }
}

void DesktopSessionActionsWidget::setEditorPreview(bool enabled) noexcept {
  m_editorPreview = enabled;
  for (Button* button : m_buttons) {
    if (InputArea* area = button->inputArea()) {
      area->setHitTestVisible(!enabled);
    }
    button->setHoverSuppressed(enabled);
  }
}

bool DesktopSessionActionsWidget::applySetting(
    const std::string& key, const WidgetSettingValue& value,
    const std::unordered_map<std::string, WidgetSettingValue>& allSettings, Renderer& renderer
) {
  // Orientation and labels change the node tree; the host rebuilds the widget for those.
  if (key == "vertical" || key == "show_labels") {
    return false;
  }
  return DesktopWidget::applySetting(key, value, allSettings, renderer);
}

void DesktopSessionActionsWidget::onPressed(std::size_t index) {
  if (index >= m_actions.size() || m_runner == nullptr || m_editorPreview) {
    return;
  }
  const SessionPanelActionConfig& action = m_actions[index];
  if (needsConfirmation(action) && m_armed != index) {
    m_armed = index;
    m_armTimer.start(kArmWindow, [this]() { disarm(); });
    syncVisuals();
    return;
  }
  m_armTimer.stop();
  m_armed.reset();
  syncVisuals();
  kLog.info("lock screen: {} requested", action.action);
  m_runner->invoke(action);
}

void DesktopSessionActionsWidget::disarm() {
  if (!m_armed.has_value()) {
    return;
  }
  m_armed.reset();
  syncVisuals();
}

void DesktopSessionActionsWidget::syncVisuals() {
  // Quiet glass discs; an armed action turns into the error role and says what a second press does.
  for (std::size_t i = 0; i < m_buttons.size(); ++i) {
    const bool armed = m_armed == i;
    Button::ButtonPalette colors;
    colors.borderWidth = Style::borderWidth;
    const ColorSpec bg = armed ? colorSpecFromRole(ColorRole::Error) : colorSpecFromRole(ColorRole::Surface, 0.34F);
    const ColorSpec fg = armed ? colorSpecFromRole(ColorRole::OnError) : colorSpecFromRole(ColorRole::OnSurface);
    const ColorSpec edge = armed ? colorSpecFromRole(ColorRole::Error) : colorSpecFromRole(ColorRole::OnSurface, 0.12F);
    colors.normal = {.bg = bg, .border = edge, .label = fg};
    colors.hover = {
        .bg = armed ? bg : colorSpecFromRole(ColorRole::Surface, 0.55F),
        .border = armed ? edge : colorSpecFromRole(ColorRole::Primary, 0.45F),
        .label = fg,
    };
    colors.pressed = colors.hover;
    colors.disabled = colors.normal;
    m_buttons[i]->setCustomPalette(colors);
  }
  if (m_hint != nullptr) {
    const bool show = m_armed.has_value() && *m_armed < m_actions.size();
    if (show) {
      const auto& action = m_actions[*m_armed];
      const std::string label = action.label.has_value() && !action.label->empty()
          ? *action.label
          : i18n::tr(session_action::labelKey(action.action));
      m_hint->setText(i18n::tr("lockscreen.session.confirm", "action", label));
    }
    m_hint->setVisible(show);
  }
  requestLayout();
  requestRedraw();
}

void DesktopSessionActionsWidget::doLayout(Renderer& renderer) {
  if (root() == nullptr) {
    return;
  }
  const float scale = contentScale();
  for (Button* button : m_buttons) {
    button->setGlyphSize(Style::baseGlyphSize * scale);
    button->setFontSize(Style::fontSizeCaption * scale);
    button->setRadius(kButtonSize * 0.5F * scale);
    button->setMinWidth(kButtonSize * scale);
    button->setMinHeight(kButtonSize * scale);
    button->setPadding(Style::spaceXs * scale, (m_options.showLabels ? Style::spaceMd : Style::spaceXs) * scale);
  }
  if (m_row != nullptr) {
    m_row->setGap(Style::spaceSm * scale);
  }
  if (m_column != nullptr) {
    m_column->setGap(Style::spaceSm * scale);
  }
  if (m_hint != nullptr) {
    m_hint->setFontSize(Style::fontSizeCaption * scale);
  }
  root()->layout(renderer);
}
