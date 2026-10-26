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
#include "ui/semantic_color.h"
#include "ui/style.h"
#include "ui/tokens.h"
#include "ui/typography.h"
#include "util/string_utils.h"

#include <chrono>
#include <utility>

namespace {

  constexpr Logger kLog("session-actions-widget");
  // Long enough to read the hint and press again; short enough that an armed shutdown does not
  // linger on a lock screen someone walks away from.
  constexpr std::chrono::milliseconds kArmWindow{4000};

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
  return action.action == "logout"
      || action.action == "reboot"
      || action.action == "shutdown"
      || action.variant == SessionActionButtonVariant::Destructive;
}

void DesktopSessionActionsWidget::create() {
  m_buttons.clear();
  auto column = ui::column({.out = &m_column, .align = FlexAlign::Center, .gap = Style::spaceSm});
  // zynith: one glass capsule holding the actions (a single object in the corner), not a row of discs.
  auto row = m_options.vertical ? ui::column({.out = &m_row, .align = FlexAlign::Center})
                                : ui::row({.out = &m_row, .align = FlexAlign::Center});
  row->setFill(colorSpecFromRole(ColorRole::Surface, 0.30F));
  row->setBorder(ui::color::spec(ui::color::Semantic::Hairline), ui::tokens::kHairline);
  for (std::size_t i = 0; i < m_actions.size(); ++i) {
    const auto& action = m_actions[i];
    Button* button = nullptr;
    const std::string glyph = action.glyph.has_value() && !action.glyph->empty()
        ? *action.glyph
        : session_action::defaultGlyph(action.action);
    const std::string label = action.label.has_value() && !action.label->empty()
        ? *action.label
        : i18n::tr(session_action::labelKey(action.action));
    row->addChild(
        ui::button({
            .out = &button,
            .text = m_options.showLabels ? label : std::string{},
            .glyph = glyph,
            .onClick = [this, i]() { onPressed(i); },
        })
    );
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
  column->addChild(
      ui::label({
          .out = &m_hint,
          .text = reserve,
          .fontSize = Style::fontSizeCaption,
          .color = colorSpecFromRole(ColorRole::Error),
          .visible = false,
          .participatesInLayout = !reserve.empty(),
      })
  );
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
  // Clear actions inside the capsule; an armed action turns into the error role (the one solid fill in the
  // corner) and the hint below says what a second press does.
  for (std::size_t i = 0; i < m_buttons.size(); ++i) {
    const bool armed = m_armed == i;
    Button::ButtonPalette colors;
    colors.borderWidth = ui::tokens::kHairline;
    const ColorSpec bg = armed ? ui::color::spec(ui::color::Semantic::Error) : clearColorSpec();
    const ColorSpec fg =
        armed ? ui::color::spec(ui::color::Semantic::OnError) : ui::color::spec(ui::color::Semantic::Muted);
    const ColorSpec edge = armed ? ui::color::spec(ui::color::Semantic::Error) : clearColorSpec();
    colors.normal = {.bg = bg, .border = edge, .label = fg};
    colors.hover = {
        .bg = armed ? bg : colorSpecFromRole(ColorRole::OnSurface, 0.10F),
        .border = armed ? edge : clearColorSpec(),
        .label = armed ? fg : ui::color::spec(ui::color::Semantic::OnSurface),
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
  const float item = ui::tokens::controlHeight(ui::tokens::Size::Medium, scale);
  const float inset = ui::tokens::space(ui::tokens::Space::Inline, scale);
  for (Button* button : m_buttons) {
    button->setGlyphSize(ui::tokens::iconSize(ui::tokens::Size::Medium, scale));
    button->setFontSize(ui::type::size(ui::type::Role::Label, scale));
    button->setRadius(ui::tokens::pill(item));
    button->setMinWidth(item);
    button->setMinHeight(item);
    button->setPadding(0.0F, m_options.showLabels ? ui::tokens::space(ui::tokens::Space::Control, scale) : 0.0F);
  }
  if (m_row != nullptr) {
    // Concentric: the capsule's radius is the items' plus the inset, so the ends share one centre.
    m_row->setGap(inset * 0.5F);
    m_row->setPadding(inset);
    m_row->setRadius(ui::tokens::pill(item + inset * 2.0F));
    m_row->setBorder(ui::color::spec(ui::color::Semantic::Hairline), ui::tokens::kHairline * scale);
  }
  if (m_column != nullptr) {
    m_column->setGap(Style::spaceSm * scale);
  }
  if (m_hint != nullptr) {
    m_hint->setFontSize(Style::fontSizeCaption * scale);
  }
  root()->layout(renderer);
}
