#pragma once

#include "render/animation/animation_manager.h"
#include "render/animation/morph_transition.h"
#include "render/animation/motion_value.h"
#include "shell/control_center/control_center_services.h"
#include "shell/control_center/tab.h"
#include "shell/control_center/tabs/audio_tab.h"
#include "shell/control_center/tabs/bluetooth_tab.h"
#include "shell/control_center/tabs/calendar_tab.h"
#include "shell/control_center/tabs/home_tab.h"
#include "shell/control_center/tabs/media_tab.h"
#include "shell/control_center/tabs/monitor_tab.h"
#include "shell/control_center/tabs/network_tab.h"
#include "shell/control_center/tabs/notifications_tab.h"
#include "shell/control_center/tabs/power_tab.h"
#include "shell/control_center/tabs/system_tab.h"
#include "shell/control_center/tabs/weather_tab.h"
#include "shell/panel/panel.h"
#include "ui/controls/scroll_view.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <memory>
#include <string_view>
#include <vector>

class BluetoothAgent;
class BluetoothService;
class BrightnessService;
class Box;
class Button;
class CompositorPlatform;
class ConfigService;
class DependencyService;
class EasyEffectsService;
class Flex;
class HttpClient;
class IdleInhibitor;
class IpcService;
class InputArea;
class Label;
class MprisService;
class Node;
class RovingListNavHost;
class NetworkSecretAgent;
class INetworkService;
class GammaService;
class NotificationManager;
class PipeWireService;
class PipeWireSpectrum;
class PowerProfilesService;
class ScreenTimeService;
class SystemMonitorService;
class CalendarService;
class UPowerService;
class Wallpaper;
class WeatherService;
class ClipboardService;

namespace noctalia::theme {
  class ThemeService;
}
namespace scripting {
  class ScriptApiContext;
}

class AccountsService;
class ThumbnailService;

class ControlCenterPanel : public Panel {
public:
  explicit ControlCenterPanel(const ControlCenterServices& services);

  // Tabs the user may hide from the Settings GUI (every tab except Home).
  // Keys match the [control_center] hidden_tabs entries.
  struct TabCatalogEntry {
    std::string_view key;
    std::string_view titleKey;
  };
  [[nodiscard]] static std::vector<TabCatalogEntry> hideableTabCatalog();

  void create() override;
  void onFrameTick(float deltaMs) override;
  void onOpen(std::string_view context) override;
  [[nodiscard]] bool retargetOpen(std::string_view context) override;
  void onClose() override;
  [[nodiscard]] bool dismissTransientUi() override;
  [[nodiscard]] bool isContextActive(std::string_view context) const override;
  [[nodiscard]] bool handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) override;
  [[nodiscard]] bool deferExternalRefresh() const override;
  [[nodiscard]] bool deferPointerRelayout() const override;
  [[nodiscard]] float preferredWidth() const override;
  [[nodiscard]] float preferredHeight() const override { return scaled(520.0F); }
  [[nodiscard]] PanelPlacement panelPlacement() const noexcept override;
  [[nodiscard]] bool showsSidebar() const noexcept { return m_showSidebar; }

private:
  void onPanelCardOpacityChanged(float opacity) override;
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;

  enum class TabId : std::uint8_t {
    Home,
    Media,
    Audio,
    Monitor,
    System,
    Network,
    Bluetooth,
    Weather,
    Calendar,
    Notifications,
    ScreenTime,
    Power,
    Count,
  };

  struct TabMeta {
    TabId id;
    const char* key;
    const char* titleKey;
    const char* glyph;
  };

  static constexpr std::size_t kTabCount = static_cast<std::size_t>(TabId::Count);
  static constexpr std::array<TabMeta, kTabCount> kTabs{{
      {TabId::Home, "home", "control-center.tabs.home", "home"},
      {TabId::Media, "media", "control-center.tabs.media", "disc-filled"},
      {TabId::Audio, "audio", "control-center.tabs.audio", "volume"},
      {TabId::Monitor, "monitor", "control-center.tabs.monitor", "device-desktop"},
      {TabId::System, "system", "control-center.tabs.system", "activity-heartbeat"},
      {TabId::Power, "power", "control-center.tabs.power", "battery-charging-2"},
      {TabId::Network, "network", "control-center.tabs.network", "wifi"},
      {TabId::Bluetooth, "bluetooth", "control-center.tabs.bluetooth", "bluetooth"},
      {TabId::Weather, "weather", "control-center.tabs.weather", "weather-cloud-sun"},
      {TabId::Calendar, "calendar", "control-center.tabs.calendar", "calendar-event"},
      {TabId::Notifications, "notifications", "control-center.tabs.notifications", "bell"},
      {TabId::ScreenTime, "screen-time", "control-center.tabs.screen-time", "hourglass"},
  }};

  void selectTab(TabId tab, bool animated = false);
  void selectAdjacentVisibleTab(int direction);
  void wireSidebarScroll(InputArea* area);
  void scrollFocusedInputIntoView(InputArea* area) override;
  void scrollSidebarNodeIntoView(const Node* node);
  void scheduleMprisRefreshFor(TabId tab);
  void updateTabChrome(TabId tab);
  void applyTabContainerVisibility(TabId activeTab);
  void layoutTabContainers(float bodyWidth, float bodyHeight);
  void layoutNavIndicator();
  void applyNavIndicatorGeometry();
  // zynith command bar (see m_commandBar): measures the nav items, then places them by hand.
  void layoutCommandBarNav(Renderer& renderer, float barWidth);
  void applyCommandBarNavGeometry();
  void syncCommandBarNavTargets(bool animate);
  // Where `tab`'s item sits once every expansion has settled (the indicator's destination).
  [[nodiscard]] MotionRectValue commandBarNavRest(TabId tab) const;
  void styleNavButton(Button* button, bool active) const;
  void layoutFullSidebarWidth(Renderer& renderer);
  void resetTabContainerTransforms();
  // `carry` is the outgoing content's live offset when a switch interrupts another,
  // so the new leg continues from where the content actually is. 0 for a fresh switch.
  void startTabTransition(TabId from, TabId to, float carry);
  void finishTabTransition();
  void applyTabTransitionLayout();
  [[nodiscard]] int visibleTabOrdinal(TabId tab) const;
  void syncTabVisibility();
  [[nodiscard]] bool isTabFeatureAvailable(TabId tab) const;
  [[nodiscard]] bool isTabVisible(TabId tab) const;
  [[nodiscard]] bool isTabShown(TabId tab) const;
  [[nodiscard]] static std::string_view tabKey(TabId tab);
  [[nodiscard]] TabId firstVisibleTab() const;
  [[nodiscard]] TabId tabFromContext(std::string_view context) const;
  [[nodiscard]] bool isDirectSectionOpenContext(std::string_view context) const;
  [[nodiscard]] ControlCenterSidebarMode sidebarModeForOpen(std::string_view context) const;
  [[nodiscard]] static std::size_t tabIndex(TabId id);

  // Tab instances (long-lived, survive panel open/close cycles)
  std::array<std::unique_ptr<Tab>, kTabCount> m_tabs;

  // Panel UI structure (rebuilt each create(), nulled in onClose())
  Flex* m_rootLayout = nullptr;
  bool m_topNav = false; // zynith: sections along the top instead of the left rail
  Flex* m_sidebar = nullptr;
  ScrollView* m_sidebarScrollView = nullptr;
  ScrollViewState m_sidebarScrollState{};
  RovingListNavHost* m_sidebarNav = nullptr;
  InputArea* m_sidebarScrollArea = nullptr;
  Flex* m_content = nullptr;
  InputArea* m_contentDismissArea = nullptr;
  Flex* m_contentHeader = nullptr;
  Flex* m_contentHeaderActions = nullptr;
  Label* m_contentTitle = nullptr;
  Button* m_closeButton = nullptr;
  Flex* m_tabBodies = nullptr;
  std::array<Button*, kTabCount> m_tabButtons{};
  // zynith morph: one selection indicator shared by every section. It is the element that survives a
  // section switch — it moves and resizes from the old tab's button to the new one — so the switch
  // reads as this panel reconfiguring, not as one page replacing another.
  Box* m_navIndicator = nullptr;
  // Its geometry is a MotionRect on the ElementMove role: a critically damped spring per edge, so a
  // burst of switches bends the one motion toward each new tab with its velocity kept instead of
  // restarting a curve. Only a change of section animates; layout corrections for the same section
  // snap (or bend an in-flight glide).
  MotionRect m_indicatorMotion;
  TabId m_indicatorTab = TabId::Home;
  // zynith command bar: style = "zynith" with top_nav. The section navigation, the section's own actions
  // and close share one bar; there is no title row, because the active item names the section. Items are
  // positioned by hand, not by the flex pass: each has an expansion (0 = icon, 1 = icon + label) moved by
  // a spring, so when the section changes the old label folds away, the new one unfolds, and every item
  // between them slides — one continuous reconfiguration with the indicator travelling through it.
  bool m_commandBar = false;
  Box* m_commandRule = nullptr;
  std::array<MotionValue, kTabCount> m_navExpand;
  std::array<float, kTabCount> m_navCollapsedWidth{};
  std::array<float, kTabCount> m_navExpandedWidth{};
  std::array<float, kTabCount> m_navInk{}; // label opacity last drawn, per item
  float m_navItemHeight = 0.0F;
  float m_navGap = 0.0F;
  // False when the bar is too narrow for any label: the strip stays icon-only (tooltips name them).
  bool m_navLabelsFit = true;
  std::array<Flex*, kTabCount> m_tabContainers{};
  std::array<Flex*, kTabCount> m_tabHeaderActions{};
  TabId m_activeTab = TabId::Home;
  bool m_activeTabForced = false;
  ConfigService* m_config = nullptr;
  MprisService* m_mpris = nullptr;
  NotificationManager* m_notificationManager = nullptr;
  DependencyService* m_dependencies = nullptr;
  bool m_compact = false;
  bool m_showSidebar = true;
  bool m_hasPowerServices = false;
  bool m_mprisRefreshScheduled = false;
  std::chrono::steady_clock::time_point m_lastMprisRefreshAt;
  // Section navigation runs on the shared morph primitive rather than bespoke bookkeeping;
  // the visual behaviour (travel, direction, interruption carry-over) is unchanged and lives
  // in layoutTabContainers. Only the outgoing tab id is extra state the primitive does not
  // carry, because it is about what is being morphed rather than about the morph.
  MorphTransition m_tabMorph;
  TabId m_tabTransitionOutgoing = TabId::Home;
  bool m_firstOpenAfterCreate = false;
};
