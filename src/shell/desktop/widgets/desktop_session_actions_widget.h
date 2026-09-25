#pragma once

#include "config/config_types.h"
#include "core/timer_manager.h"
#include "shell/desktop/desktop_widget.h"

#include <cstddef>
#include <optional>
#include <string>
#include <vector>

class Button;
class Flex;
class Label;
class SessionActionRunner;

// Zynith: power and session actions as a placeable widget — the lock screen's power controls.
//
// It runs the built-in suspend / logout / reboot / shutdown handlers of the shared
// SessionActionRunner (argv, never a shell string); rows that carry a custom command are refused.
// Logout, reboot and shutdown arm on the first press and run on a second press of the same button
// within kArmWindow. The arm lapses on a one-shot event-loop timer, so nothing ticks while it waits.
// Authentication and the session lock itself are untouched: this only asks logind to act.
class DesktopSessionActionsWidget : public DesktopWidget {
public:
  struct Options {
    bool vertical = false;
    bool showLabels = false;
  };

  DesktopSessionActionsWidget(
      Options options, SessionActionRunner* runner, std::vector<SessionPanelActionConfig> actions
  );

  void create() override;
  void setEditorPreview(bool enabled) noexcept override;
  bool applySetting(
      const std::string& key, const WidgetSettingValue& value,
      const std::unordered_map<std::string, WidgetSettingValue>& allSettings, Renderer& renderer
  ) override;

  // The actions this widget may run, from the configured session actions: enabled, built-in, and
  // meaningful on a locked session (no lock, no custom command).
  [[nodiscard]] static std::vector<SessionPanelActionConfig>
  lockScreenActions(const std::vector<SessionPanelActionConfig>& configured);

private:
  void doLayout(Renderer& renderer) override;
  void onPressed(std::size_t index);
  void disarm();
  void syncVisuals();
  [[nodiscard]] static bool needsConfirmation(const SessionPanelActionConfig& action) noexcept;

  Options m_options;
  SessionActionRunner* m_runner = nullptr;
  std::vector<SessionPanelActionConfig> m_actions;
  std::vector<Button*> m_buttons;
  Flex* m_column = nullptr;
  Flex* m_row = nullptr;
  Label* m_hint = nullptr;
  std::optional<std::size_t> m_armed;
  Timer m_armTimer;
  bool m_editorPreview = false;
};
