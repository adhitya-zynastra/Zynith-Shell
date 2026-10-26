#include "shell/control_center/control_center_panel.h"

#include "compositors/compositor_platform.h"
#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/input/key_modifiers.h"
#include "dbus/mpris/mpris_service.h"
#include "i18n/i18n.h"
#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/control_center/tabs/screen_time_tab.h"
#include "shell/panel/panel_button_style.h"
#include "shell/panel/panel_manager.h"
#include "system/dependency_service.h"
#include "system/easyeffects_service.h"
#include "system/screen_time_service.h"
#include "ui/builders.h"
#include "ui/controls/roving_list_nav.h"
#include "ui/controls/scroll_view.h"
#include "ui/responsive.h"
#include "ui/scroll_into_view.h"
#include "ui/semantic_color.h"
#include "ui/split_pane_focus.h"
#include "ui/tokens.h"
#include "ui/typography.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <functional>
#include <memory>
#include <optional>
#include <string_view>
#include <wayland-client-protocol.h>
#include <xkbcommon/xkbcommon-keysyms.h>

using namespace control_center;

namespace {

  constexpr auto kMprisRefreshMinInterval = std::chrono::milliseconds(750);
  // Full-height cards need room for rounded-rect AA before the tab viewport clips them.
  constexpr float kTabViewportClipInset = 1.0F;

  float tabContentHeight(float viewportHeight) {
    return std::max(1.0F, std::floor(viewportHeight - kTabViewportClipInset));
  }

} // namespace

ControlCenterPanel::ControlCenterPanel(const ControlCenterServices& services) {
  m_hasPowerServices = services.upower != nullptr || services.powerProfiles != nullptr;
  WaylandConnection* wayland = services.platform != nullptr ? &services.platform->wayland() : nullptr;
  m_config = services.config;
  m_mpris = services.mpris;
  m_notificationManager = services.notifications;
  m_dependencies = services.dependencies;
  m_tabs[tabIndex(TabId::Home)] = std::make_unique<HomeTab>(services);
  m_tabs[tabIndex(TabId::Media)] = std::make_unique<MediaTab>(
      services.mpris, services.httpClient, services.spectrum, services.config, wayland,
      PanelManager::instance().renderContext()
  );
  m_tabs[tabIndex(TabId::Audio)] = std::make_unique<AudioTab>(
      services.audio, services.easyEffects, services.mpris, services.config, wayland,
      PanelManager::instance().renderContext()
  );
  m_tabs[tabIndex(TabId::Weather)] = std::make_unique<WeatherTab>(services.weather, services.config);
  m_tabs[tabIndex(TabId::Calendar)] = std::make_unique<CalendarTab>(services.config, services.calendar);
  m_tabs[tabIndex(TabId::Notifications)] =
      std::make_unique<NotificationsTab>(services.notifications, services.platform);
  m_tabs[tabIndex(TabId::Network)] =
      std::make_unique<NetworkTab>(services.network, services.networkSecrets, services.externalIp, services.modem);
  m_tabs[tabIndex(TabId::Bluetooth)] = std::make_unique<BluetoothTab>(services.bluetooth, services.bluetoothAgent);
  m_tabs[tabIndex(TabId::Monitor)] = std::make_unique<MonitorTab>(services.brightness, services.config);
  m_tabs[tabIndex(TabId::System)] = std::make_unique<SystemTab>(services.sysmon);
  m_tabs[tabIndex(TabId::ScreenTime)] = std::make_unique<ScreenTimeTab>(services.screenTime);
  m_tabs[tabIndex(TabId::Power)] = std::make_unique<PowerTab>(services.upower, services.powerProfiles);
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_tabHeaderActions.fill(nullptr);
}

float ControlCenterPanel::preferredWidth() const {
  const float fullSize = m_config != nullptr ? static_cast<float>(m_config->config().controlCenter.width)
                                             : static_cast<float>(ControlCenterConfig::kDefaultWidth);
  switch (sidebarModeForOpen(pendingOpenContext())) {
  case ControlCenterSidebarMode::Full:
    return fullSize * m_contentScale;
  case ControlCenterSidebarMode::None:
    return fullSize * 0.75F * m_contentScale;
  default:
  case ControlCenterSidebarMode::Compact:
    return fullSize * 0.85F * m_contentScale;
  }
}

PanelPlacement ControlCenterPanel::panelPlacement() const noexcept {
  return m_config == nullptr ? PanelPlacement::Attached : m_config->config().shell.panel.controlCenterPlacement;
}

bool ControlCenterPanel::dismissTransientUi() {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  return m_tabs[activeIdx] != nullptr && m_tabs[activeIdx]->dismissTransientUi();
}

void ControlCenterPanel::create() {
  const float scale = contentScale();
  // Frame rhythm: the gaps and padding that give the panel its breathing room scale with the
  // configured density. Each tab's internal spacing is its own and is not touched here.
  const float density = m_config != nullptr ? layoutDensityFactor(m_config->config().controlCenter.density) : 1.0F;
  const ControlCenterSidebarMode sidebarMode = sidebarModeForOpen(pendingOpenContext());
  const bool zynith = m_config == nullptr || m_config->config().controlCenter.style == ControlCenterStyle::Zynith;
  m_topNav = m_config != nullptr && m_config->config().controlCenter.topNav;
  // zynith top nav: icon-only buttons in a row above the content (no scroll rail needed).
  m_compact = m_topNav || sidebarMode == ControlCenterSidebarMode::Compact;
  m_showSidebar = sidebarMode != ControlCenterSidebarMode::None;
  // The command bar needs the top nav's placement; with the left rail the classic header stays.
  m_commandBar = zynith && m_topNav && m_showSidebar;
  // Sections build their plates and headings from this (tab.cpp); set before any tab creates.
  control_center::setZynithSurfaces(zynith);

  for (auto& tab : m_tabs) {
    tab->setContentScale(scale);
    tab->setPanelCardOpacity(panelCardOpacity());
  }

  const ui::FlexProps rootProps{
      .out = &m_rootLayout,
      .align = FlexAlign::Stretch,
      .gap = m_commandBar ? ui::responsive::space(ui::tokens::space(ui::tokens::Space::Control), density, scale)
                          : ui::responsive::space(Style::panelPadding, density, scale),
      .padding = 0.0F,
  };
  auto rootLayout = m_topNav ? ui::column(rootProps) : ui::row(rootProps);

  if (m_showSidebar) {
    const ui::FlexProps sidebarProps{
        .out = &m_sidebar,
        .align = m_topNav ? FlexAlign::Center : FlexAlign::Start,
        .justify = m_topNav ? FlexJustify::Center : FlexJustify::Start,
        .gap = 0.0F,
        .padding = ui::responsive::space(m_topNav ? Style::spaceXs : Style::spaceMd, density, scale),
        .fillWidth = m_topNav,
        .fillHeight = !m_topNav,
        .configure = [this, scale](Flex& flex) {
          if (m_commandBar) {
            // The command bar is not a tray: it sits directly on the panel's glass, and the rule
            // below it is the only line between navigation and content.
            flex.setPadding(0.0F);
            flex.setJustify(FlexJustify::SpaceBetween); // navigation left, the section's actions right
            return;
          }
          flex.setFill(colorSpecFromRole(ColorRole::SurfaceVariant, panelCardOpacity()));
          flex.setRadius(Style::scaledRadiusXl(scale));
        },
    };
    auto sidebar = m_topNav ? ui::row(sidebarProps) : ui::column(sidebarProps);

    auto sidebarScrollArea = ui::inputArea({});
    sidebarScrollArea->setParticipatesInLayout(false);
    sidebarScrollArea->setZIndex(-1);
    m_sidebarScrollArea = sidebarScrollArea.get();
    wireSidebarScroll(m_sidebarScrollArea);
    sidebar->addChild(std::move(sidebarScrollArea));

    const std::optional<float> sidebarScrollWidth =
        m_compact ? std::optional<float>{Style::controlHeightSm * scale} : std::nullopt;

    auto sidebarScroll = ui::scrollView({
        .out = &m_sidebarScrollView,
        .state = &m_sidebarScrollState,
        .contentScale = scale,
        .scrollbarVisible = true,
        .viewportPaddingH = 0.0F,
        .viewportPaddingV = 0.0F,
        .fillWidth = false,
        .fillHeight = true,
        .width = sidebarScrollWidth,
        .configure = [](ScrollView& scrollView) {
          scrollView.clearFill();
          scrollView.clearBorder();
        },
    });

    auto sidebarNav = std::make_unique<RovingListNavHost>(RovingListNavController::Options{
        .axis = m_topNav ? RovingListNavAxis::Horizontal : RovingListNavAxis::Vertical,
        .mode = RovingListNavMode::FollowFocus,
        .keepItemsInTabOrder = false,
        .wrap = true,
        .scrollIntoView = [this](const Node* node) { scrollSidebarNodeIntoView(node); },
        .syncIndexFromSelection = {},
    });
    sidebarNav->setTabFocusKey("control-center.sidebar");
    if (!m_compact) {
      sidebarNav->setAlign(FlexAlign::Stretch);
      sidebarNav->setFillWidth(true);
    } else {
      sidebarNav->setAlign(FlexAlign::Start);
    }
    sidebarNav->setGap(Style::spaceXs * scale);
    m_sidebarNav = sidebarNav.get();
    const float commandItemHeight = ui::tokens::controlHeight(ui::tokens::Size::Medium, scale);
    sidebarNav->addChild(
        ui::box({
            .out = &m_navIndicator,
            .fill = ui::color::spec(ui::color::Semantic::SelectionFill),
            .configure = [this, scale, commandItemHeight](Box& box) {
              box.setBorder(ui::color::spec(ui::color::Semantic::SelectionEdge), Style::borderWidth * scale);
              // In the command bar the indicator is a capsule: it has to read as one object whether it
              // wraps an icon (a circle) or an icon and its label (a pill).
              box.setRadius(m_commandBar ? ui::tokens::pill(commandItemHeight) : Style::scaledRadiusLg(scale));
              box.setParticipatesInLayout(false);
              box.setHitTestVisible(false);
              box.setZIndex(-1);
            },
        })
    );
    // A new panel instance places its indicator immediately (reset), then moves it by ElementMove.
    // Owner = the indicator node, so destroying the node cancels any glide in flight.
    m_indicatorMotion.reset();
    m_indicatorMotion.bind(m_animations, m_navIndicator, motion::Role::ElementMove, [this]() {
      applyNavIndicatorGeometry();
      if (m_commandBar) {
        applyCommandBarNavGeometry(); // the incoming label's ink follows the capsule
      }
      PanelManager::instance().requestRedraw();
    });

    for (auto& expand : m_navExpand) {
      expand.reset();
    }
    m_navInk.fill(0.0F);
    for (const auto& tab : kTabs) {
      const std::size_t idx = tabIndex(tab.id);
      const auto onClick = [this, id = tab.id]() {
        selectTab(id, true);
        PanelManager::instance().refresh();
      };
      if (m_commandBar) {
        const float glyphSize = ui::tokens::iconSize(ui::tokens::Size::Medium, scale);
        sidebarNav->addChild(
            ui::button({
                .out = &m_tabButtons[idx],
                .text = i18n::tr(tab.titleKey),
                .glyph = tab.glyph,
                .glyphSize = glyphSize,
                .contentAlign = ButtonContentAlign::Start,
                .variant = ButtonVariant::Tab,
                .tooltip = i18n::tr(tab.titleKey),
                .minHeight = commandItemHeight,
                .paddingV = 0.0F,
                // The glyph sits centred in the collapsed square and never moves: the label unfolds
                // to its right.
                .paddingH = (commandItemHeight - glyphSize) * 0.5F,
                .gap = ui::tokens::space(ui::tokens::Space::Related, scale),
                .radius = ui::tokens::pill(commandItemHeight),
                .onClick = onClick,
                .configure = [this, scale](Button& button) {
                  if (button.label() != nullptr) {
                    ui::type::apply(*button.label(), ui::type::Role::Label, scale);
                  }
                  button.setParticipatesInLayout(false);
                  button.setClipChildren(true);
                  wireSidebarScroll(button.inputArea());
                },
            })
        );
        m_navExpand[idx].bind(m_animations, m_tabButtons[idx], motion::Role::ElementMove, [this](float) {
          applyCommandBarNavGeometry();
          PanelManager::instance().requestRedraw();
        });
        sidebarNav->registerItem(m_tabButtons[idx], onClick);
        continue;
      }
      sidebarNav->addChild(
          ui::button({
              .out = &m_tabButtons[idx],
              .text = m_compact ? std::optional<std::string>{} : std::optional<std::string>{i18n::tr(tab.titleKey)},
              .glyph = tab.glyph,
              .glyphSize = 21.0F * scale,
              .contentAlign = m_compact ? ButtonContentAlign::Center : ButtonContentAlign::Start,
              .variant = ButtonVariant::Tab,
              .tooltip = m_compact ? i18n::tr(tab.titleKey) : std::string{},
              .minWidth = m_compact ? std::optional<float>{Style::controlHeightSm * scale} : std::optional<float>{},
              .minHeight = Style::controlHeightSm * scale,
              .paddingV = Style::spaceXs * scale,
              .paddingH = (m_compact ? Style::spaceXs : Style::spaceSm) * scale,
              .gap = Style::spaceSm * scale,
              .radius = Style::scaledRadiusLg(scale),
              .onClick = onClick,
              .configure = [this, scale](Button& button) {
                if (button.label() != nullptr) {
                  button.label()->setFontWeight(FontWeight::Bold);
                  button.label()->setFontSize(Style::fontSizeBody * scale);
                }
                wireSidebarScroll(button.inputArea());
              },
          })
      );
      sidebarNav->registerItem(m_tabButtons[idx], onClick);
    }

    if (m_topNav) {
      // No rail to scroll: the icon row fits the panel width, so skip the scroll view entirely.
      sidebarNav->setDirection(FlexDirection::Horizontal);
      sidebar->addChild(std::move(sidebarNav));
      sidebarScroll.reset();
      m_sidebarScrollView = nullptr; // destroyed above; keep no dangling pointer to it
    } else {
      if (sidebarScroll->content() != nullptr) {
        if (!m_compact) {
          sidebarScroll->content()->setAlign(FlexAlign::Stretch);
        }
        sidebarScroll->content()->addChild(std::move(sidebarNav));
      }
      sidebar->addChild(std::move(sidebarScroll));
    }
    rootLayout->addChild(std::move(sidebar));
    if (m_commandBar) {
      rootLayout->addChild(
          ui::box({
              .out = &m_commandRule,
              .fill = ui::color::spec(ui::color::Semantic::Hairline),
              .height = ui::tokens::kHairline * scale,
          })
      );
    }
  }

  auto content = ui::column({
      .out = &m_content,
      .align = FlexAlign::Stretch,
      .gap = ui::responsive::space(Style::spaceMd, density, scale),
      .clipChildren = true,
      .flexGrow = 4.0F,
  });

  auto dismissArea = ui::inputArea({});
  dismissArea->setParticipatesInLayout(false);
  dismissArea->setZIndex(-1);
  dismissArea->setFocusable(false);
  dismissArea->setTabStop(false);
  dismissArea->setOnPress([this](const InputArea::PointerData&) {
    const std::size_t activeIdx = tabIndex(m_activeTab);
    if (m_tabs[activeIdx] != nullptr && m_tabs[activeIdx]->dismissTransientUi()) {
      PanelManager::instance().refresh();
    }
  });
  m_contentDismissArea = static_cast<InputArea*>(content->addChild(std::move(dismissArea)));

  // The command bar has no title row: the unfolded navigation item names the section.
  std::unique_ptr<Flex> header;
  if (!m_commandBar) {
    header = ui::row({
        .out = &m_contentHeader,
        .align = FlexAlign::Center,
        .justify = FlexJustify::SpaceBetween,
        .gap = Style::spaceSm * scale,
    });

    // zynith: the section title is set in the display face, lighter and in the surface colour; accent
    // colour is reserved for the navigation indicator and active states, so there is one focal accent.
    const std::string displayFont = m_config != nullptr ? m_config->config().shell.displayFontFamily : std::string{};
    header->addChild(
        ui::label({
            .out = &m_contentTitle,
            .text = i18n::tr("control-center.tabs.home"),
            .fontSize = (zynith ? Style::fontSizeHeader : Style::fontSizeTitle) * scale,
            .fontWeight = zynith ? FontWeight::Medium : FontWeight::Bold,
            .fontFamily =
                zynith && !displayFont.empty() ? std::optional<std::string>{displayFont} : std::optional<std::string>{},
            .color = colorSpecFromRole(zynith ? ColorRole::OnSurface : ColorRole::Primary),
            .flexGrow = 1.0F,
        })
    );
  }

  auto headerActions = ui::row({
      .out = &m_contentHeaderActions,
      .align = FlexAlign::Center,
      .gap = Style::spaceSm * scale,
  });

  for (std::size_t i = 0; i < kTabCount; ++i) {
    auto actions = m_tabs[i]->createHeaderActions();
    m_tabHeaderActions[i] = actions.get();
    if (actions != nullptr) {
      actions->setVisible(false);
      m_contentHeaderActions->addChild(std::move(actions));
    }
  }

  m_contentHeaderActions->addChild(
      ui::button({
          .out = &m_closeButton,
          .glyph = "close",
          .onClick = []() { PanelManager::instance().close(); },
          .configure =
              [zynith, scale](Button& button) {
                panel_button_style::configureHeaderIconButton(button, scale);
                if (zynith) {
                  button.setVariant(ButtonVariant::Ghost);
                }
              },
      })
  );
  if (zynith) {
    // Same geometry as the navigation: every action becomes a capsule. Only the shape changes — a
    // section's actions keep their own variants and selected states (a DND toggle, a destructive clear).
    const float actionRadius = ui::tokens::pill(Style::controlHeightSm * scale);
    std::function<void(Node&)> capsule = [&capsule, actionRadius](Node& node) {
      for (const auto& child : node.children()) {
        if (auto* button = dynamic_cast<Button*>(child.get())) {
          button->setRadius(actionRadius);
        } else {
          capsule(*child);
        }
      }
    };
    capsule(*headerActions);
  }
  if (m_commandBar && m_sidebar != nullptr) {
    m_sidebar->addChild(std::move(headerActions));
  } else {
    header->addChild(std::move(headerActions));
    content->addChild(std::move(header));
  }

  auto bodies = ui::column({
      .out = &m_tabBodies,
      .align = FlexAlign::Stretch,
      .gap = 0.0F,
      .clipChildren = true,
      .flexGrow = 1.0F,
  });

  for (std::size_t i = 0; i < kTabCount; ++i) {
    auto container = m_tabs[i]->create();
    container->setFlexGrow(1.0F);
    container->setParticipatesInLayout(false);
    container->setVisible(false);
    m_tabContainers[i] = container.get();
    m_tabBodies->addChild(std::move(container));
  }

  content->addChild(std::move(bodies));
  rootLayout->addChild(std::move(content));
  setRoot(std::move(rootLayout));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  syncTabVisibility();
  m_firstOpenAfterCreate = true;
  selectTab(m_activeTab);
}

void ControlCenterPanel::onPanelCardOpacityChanged(float opacity) {
  for (auto& tab : m_tabs) {
    if (tab != nullptr) {
      tab->setPanelCardOpacity(opacity);
    }
  }
  if (m_sidebar != nullptr) {
    m_sidebar->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, opacity));
  }
}

void ControlCenterPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_content == nullptr || m_tabBodies == nullptr) {
    return;
  }

  if (!m_compact && m_showSidebar) {
    layoutFullSidebarWidth(renderer);
  }
  if (m_commandBar) {
    layoutCommandBarNav(renderer, width);
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  if (m_commandBar) {
    // The flex pass skips the hand-placed items; lay each out at its unfolded size once, then the
    // expansion only changes the visible width (the item clips its label).
    for (const auto& meta : kTabs) {
      Button* button = m_tabButtons[tabIndex(meta.id)];
      if (button == nullptr || !button->visible()) {
        continue;
      }
      const std::size_t idx = tabIndex(meta.id);
      button->arrange(
          renderer, LayoutRect{.x = 0.0F, .y = 0.0F, .width = m_navExpandedWidth[idx], .height = m_navItemHeight}
      );
    }
    applyCommandBarNavGeometry();
    if (m_commandRule != nullptr) {
      m_commandRule->setSize(width, m_commandRule->height());
    }
  }

  const float contentInnerWidth =
      std::max(0.0F, m_content->width() - (m_content->paddingLeft() + m_content->paddingRight()));
  const float bodyWidth = m_tabBodies->width();
  const float bodyHeight = m_tabBodies->height();
  const float bodyContentHeight = tabContentHeight(bodyHeight);

  if (m_sidebarScrollArea != nullptr && m_sidebar != nullptr) {
    m_sidebarScrollArea->setPosition(0.0F, 0.0F);
    m_sidebarScrollArea->setSize(m_sidebar->width(), m_sidebar->height());
  }

  if (m_contentDismissArea != nullptr) {
    m_contentDismissArea->setPosition(0.0F, 0.0F);
    m_contentDismissArea->setFrameSize(m_content->width(), m_content->height());
  }

  if (m_contentHeader != nullptr) {
    m_contentHeader->setSize(contentInnerWidth, 0.0F);
  }

  if (m_contentTitle != nullptr) {
    const float actionsWidth = m_contentHeaderActions != nullptr ? m_contentHeaderActions->width() : 0.0F;
    const float headerGap = m_contentHeader != nullptr ? m_contentHeader->gap() : 0.0F;
    const float titleWidth = std::max(0.0F, contentInnerWidth - actionsWidth - headerGap);
    m_contentTitle->setMaxWidth(titleWidth);
  }

  for (auto* container : m_tabContainers) {
    if (container != nullptr && container->visible()) {
      container->setSize(bodyWidth, bodyContentHeight);
    }
  }

  layoutTabContainers(bodyWidth, bodyHeight);

  const auto layoutTab = [this, bodyWidth, bodyContentHeight, &renderer](TabId tabId) {
    const std::size_t idx = tabIndex(tabId);
    if (m_tabs[idx] == nullptr || m_tabContainers[idx] == nullptr || !m_tabContainers[idx]->visible()) {
      return;
    }
    m_tabs[idx]->layout(renderer, bodyWidth, bodyContentHeight);
  };

  if (m_tabMorph.active()) {
    layoutTab(m_tabTransitionOutgoing);
  }
  layoutTab(m_activeTab);
}

void ControlCenterPanel::doUpdate(Renderer& renderer) {
  if (!isTabFeatureAvailable(m_activeTab) || (!m_activeTabForced && !isTabVisible(m_activeTab))) {
    selectTab(firstVisibleTab());
  } else {
    syncTabVisibility();
  }
  const std::size_t activeIdx = tabIndex(m_activeTab);
  if (m_tabs[activeIdx] != nullptr) {
    m_tabs[activeIdx]->update(renderer);
  }
}

void ControlCenterPanel::onFrameTick(float deltaMs) {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  if (m_tabs[activeIdx] != nullptr) {
    m_tabs[activeIdx]->onFrameTick(deltaMs);
  }
}

void ControlCenterPanel::onOpen(std::string_view context) {
  if (m_dependencies != nullptr) {
    m_dependencies->rescan();
  }
  const bool animateTabSwitch = !m_firstOpenAfterCreate;
  m_firstOpenAfterCreate = false;
  selectTab(tabFromContext(context), animateTabSwitch);
}

bool ControlCenterPanel::retargetOpen(std::string_view context) {
  // The shell stays exactly where it is; only the content region transitions.
  selectTab(tabFromContext(context), /*animated=*/true);
  return true;
}

bool ControlCenterPanel::isContextActive(std::string_view context) const {
  return m_activeTab == tabFromContext(context);
}

bool ControlCenterPanel::handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) {
  // Section cycling, browser-tab style: Ctrl+Tab / Ctrl+Shift+Tab and Ctrl+PageDown / Ctrl+PageUp.
  // Plain Tab stays with focus traversal below. Goes through the same path as a wheel over the
  // navigation, so a held chord retargets the section morph rather than queueing transitions.
  if (pressed && !preedit && (modifiers & KeyMod::Ctrl) != 0 && (modifiers & (KeyMod::Alt | KeyMod::Super)) == 0) {
    int direction = 0;
    if (sym == XKB_KEY_Tab) {
      direction = (modifiers & KeyMod::Shift) != 0 ? -1 : 1;
    } else if (sym == XKB_KEY_ISO_Left_Tab || sym == XKB_KEY_Prior) {
      direction = -1;
    } else if (sym == XKB_KEY_Next) {
      direction = 1;
    }
    if (direction != 0) {
      selectAdjacentVisibleTab(direction);
      return true;
    }
  }

  // The top nav has no scroll rail (and in the command bar the section's actions share the row), so
  // the navigation strip itself is the "sidebar" pane there.
  const Node* sidebarRoot = m_sidebarScrollView != nullptr ? static_cast<const Node*>(m_sidebarScrollView)
                                                           : static_cast<const Node*>(m_sidebarNav);
  if (!m_showSidebar || m_sidebarNav == nullptr || sidebarRoot == nullptr || m_content == nullptr) {
    return false;
  }

  const SplitPaneFocusConfig panes{
      .sidebarFocus = m_sidebarNav->focusArea(),
      .sidebarRoot = sidebarRoot,
      .contentRoot = m_content,
      .headerFocus = nullptr,
  };
  auto& dispatcher = PanelManager::instance().inputDispatcher();
  const SplitPaneFocusResult splitResult =
      handleSplitPaneFocusNavigation(dispatcher, panes, sym, modifiers, pressed, preedit);
  return splitResult == SplitPaneFocusResult::Consumed;
}

void ControlCenterPanel::onClose() {
  // Closing mid-transition drops the leg; the primitive's cancel is idempotent and safe
  // to call whether or not one is running.
  m_tabMorph.cancel();
  m_activeTab = TabId::Home;
  for (auto& tab : m_tabs) {
    tab->setActive(false);
    tab->onClose();
  }
  m_rootLayout = nullptr;
  m_sidebar = nullptr;
  m_sidebarScrollView = nullptr;
  m_sidebarScrollState = {};
  m_sidebarNav = nullptr;
  m_indicatorMotion.reset();
  m_navIndicator = nullptr;
  for (auto& expand : m_navExpand) {
    expand.reset();
  }
  m_commandRule = nullptr;
  m_navItemHeight = 0.0F;
  m_sidebarScrollArea = nullptr;
  m_content = nullptr;
  m_contentDismissArea = nullptr;
  m_contentHeader = nullptr;
  m_contentHeaderActions = nullptr;
  m_contentTitle = nullptr;
  m_closeButton = nullptr;
  m_tabBodies = nullptr;
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_tabHeaderActions.fill(nullptr);
  clearReleasedRoot();
}

bool ControlCenterPanel::deferExternalRefresh() const {
  if (m_activeTab != TabId::Audio) {
    return false;
  }
  const auto* audioTab = dynamic_cast<const AudioTab*>(m_tabs[tabIndex(TabId::Audio)].get());
  return audioTab != nullptr && audioTab->dragging();
}

bool ControlCenterPanel::deferPointerRelayout() const { return deferExternalRefresh(); }

bool ControlCenterPanel::isTabFeatureAvailable(TabId tab) const {
  if (m_config == nullptr) {
    switch (tab) {
    case TabId::ScreenTime:
      return false;
    case TabId::Power:
      return m_hasPowerServices;
    default:
      return true;
    }
  }
  const auto& cfg = m_config->config();
  switch (tab) {
  case TabId::Weather:
    return cfg.weather.enabled;
  case TabId::ScreenTime:
    return cfg.shell.screenTimeEnabled;
  case TabId::System:
    return cfg.system.monitor.enabled;
  case TabId::Power:
    return m_hasPowerServices;
  default:
    return true;
  }
}

bool ControlCenterPanel::isTabVisible(TabId tab) const {
  if (!isTabFeatureAvailable(tab)) {
    return false;
  }
  // Home is always shown so the panel never opens to an empty surface.
  if (tab == TabId::Home || m_config == nullptr) {
    return true;
  }
  const auto& hidden = m_config->config().controlCenter.hiddenTabs;
  return !std::ranges::contains(hidden, tabKey(tab));
}

bool ControlCenterPanel::isTabShown(TabId tab) const {
  if (tab == m_activeTab && m_activeTabForced) {
    return isTabFeatureAvailable(tab);
  }
  return isTabVisible(tab);
}

std::vector<ControlCenterPanel::TabCatalogEntry> ControlCenterPanel::hideableTabCatalog() {
  std::vector<TabCatalogEntry> out;
  out.reserve(kTabCount - 1);
  for (const auto& meta : kTabs) {
    if (meta.id == TabId::Home) {
      continue;
    }
    out.push_back({.key = meta.key, .titleKey = meta.titleKey});
  }
  return out;
}

std::string_view ControlCenterPanel::tabKey(TabId tab) {
  for (const auto& meta : kTabs) {
    if (meta.id == tab) {
      return meta.key;
    }
  }
  return {};
}

ControlCenterPanel::TabId ControlCenterPanel::firstVisibleTab() const {
  for (const auto& meta : kTabs) {
    if (isTabVisible(meta.id)) {
      return meta.id;
    }
  }
  return TabId::Home;
}

void ControlCenterPanel::syncTabVisibility() {
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    const bool visible = isTabShown(meta.id);
    if (m_tabButtons[idx] != nullptr) {
      m_tabButtons[idx]->setVisible(visible);
    }
    if (!visible) {
      if (m_tabContainers[idx] != nullptr) {
        m_tabContainers[idx]->setVisible(false);
      }
      if (m_tabHeaderActions[idx] != nullptr) {
        m_tabHeaderActions[idx]->setVisible(false);
      }
    }
  }
}

void ControlCenterPanel::updateTabChrome(TabId tab) {
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    const bool tabEnabled = isTabShown(meta.id);
    if (m_tabs[idx] != nullptr) {
      m_tabs[idx]->setActive(tabEnabled && meta.id == tab);
    }
    if (m_tabButtons[idx] != nullptr) {
      m_tabButtons[idx]->setVisible(tabEnabled);
      styleNavButton(m_tabButtons[idx], meta.id == tab);
    }
    if (meta.id == tab && m_contentTitle != nullptr) {
      m_contentTitle->setText(i18n::tr(meta.titleKey));
    }
    if (m_tabHeaderActions[idx] != nullptr) {
      m_tabHeaderActions[idx]->setVisible(tabEnabled && meta.id == tab);
    }
  }

  if (m_contentTitle != nullptr) {
    m_contentTitle->setVisible(true);
  }
  if (m_contentHeaderActions != nullptr) {
    m_contentHeaderActions->setVisible(true);
  }
  if (m_sidebarNav != nullptr) {
    m_sidebarNav->notifyExternalSelectionChanged();
  }
}

void ControlCenterPanel::applyTabContainerVisibility(TabId activeTab) {
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    const bool tabEnabled = isTabShown(meta.id);
    if (m_tabContainers[idx] != nullptr) {
      m_tabContainers[idx]->setVisible(tabEnabled && meta.id == activeTab);
    }
  }
}

void ControlCenterPanel::layoutTabContainers(float bodyWidth, float bodyHeight) {
  // zynith morph. Content never travels: the outgoing section settles slightly inward as it
  // dissolves and the incoming one resolves from a slight overscale onto the same frame, both about
  // the top centre so the header line stays put. Continuity is carried by what does not change — the
  // frame, the header — and by the one element that transforms between the two states, the nav
  // indicator (layoutNavIndicator). The carry is the leaving section's reveal when a switch is
  // interrupted, so reversals continue from what is on screen.
  constexpr float kMorphScale = 0.03F;
  const float contentHeight = tabContentHeight(bodyHeight);
  for (std::size_t i = 0; i < kTabCount; ++i) {
    auto* container = m_tabContainers[i];
    if (container == nullptr || !container->visible()) {
      continue;
    }

    container->setSize(bodyWidth, contentHeight);

    float scale = 1.0F;
    float opacity = 1.0F;
    const auto tabId = static_cast<TabId>(i);
    if (m_tabMorph.active() && bodyHeight > 0.0F) {
      const float progress = m_tabMorph.progress();
      if (tabId == m_tabTransitionOutgoing) {
        const float reveal = std::clamp(m_tabMorph.carry(), 0.0F, 1.0F) * (1.0F - progress);
        opacity = reveal;
        scale = 1.0F - kMorphScale * (1.0F - reveal);
      } else if (tabId == m_activeTab) {
        opacity = progress;
        scale = 1.0F + kMorphScale * (1.0F - progress);
      }
    }

    container->setPosition(0.0F, 0.0F);
    container->setTransformOrigin(bodyWidth * 0.5F, 0.0F);
    container->setScale(scale);
    container->setOpacity(opacity);
    if (m_tabMorph.active()) {
      container->setZIndex(tabId == m_activeTab ? 1 : 0);
    } else {
      container->setZIndex(0);
    }
  }
  layoutNavIndicator();
}

void ControlCenterPanel::resetTabContainerTransforms() {
  for (auto* container : m_tabContainers) {
    if (container == nullptr) {
      continue;
    }
    container->setPosition(0.0F, 0.0F);
    container->setScale(1.0F);
    container->setOpacity(1.0F);
    container->setZIndex(0);
  }
  layoutNavIndicator();
}

void ControlCenterPanel::styleNavButton(Button* button, bool active) const {
  if (button == nullptr) {
    return;
  }
  // The indicator carries the selection fill; buttons stay clear so it can move between them.
  Button::ButtonPalette colors;
  const ColorSpec label = colorSpecFromRole(active ? ColorRole::Primary : ColorRole::OnSurfaceVariant);
  colors.normal = {.bg = clearColorSpec(), .border = clearColorSpec(), .label = label};
  colors.hover = {
      .bg = active ? clearColorSpec() : colorSpecFromRole(ColorRole::OnSurface, 0.06F),
      .border = clearColorSpec(),
      .label = active ? label : colorSpecFromRole(ColorRole::OnSurface),
  };
  colors.pressed = colors.hover;
  colors.disabled = colors.normal;
  button->setCustomPalette(colors);
}

void ControlCenterPanel::layoutNavIndicator() {
  if (m_navIndicator == nullptr) {
    return;
  }
  Button* target = m_tabButtons[tabIndex(m_activeTab)];
  const bool measured = m_commandBar ? m_navItemHeight > 0.0F : target != nullptr && target->width() > 0.0F;
  if (target == nullptr || !target->visible() || !measured) {
    m_navIndicator->setVisible(false);
    return;
  }
  // In the command bar the destination is where the item WILL be once the labels have folded and
  // unfolded, not where it is mid-reconfiguration: the indicator makes one journey there, and the
  // items converge on it.
  const MotionRectValue to = m_commandBar
      ? commandBarNavRest(m_activeTab)
      : MotionRectValue{.x = target->x(), .y = target->y(), .width = target->width(), .height = target->height()};
  if (!m_indicatorMotion.hasValue()) {
    m_indicatorTab = m_activeTab;
    m_indicatorMotion.setImmediate(to);
  } else if (m_activeTab != m_indicatorTab || m_indicatorMotion.animating()) {
    // A section switch travels, and so does any correction while a glide is in flight — from where
    // the indicator is drawn now, with its current velocity (retarget), never from the old button.
    m_indicatorTab = m_activeTab;
    m_indicatorMotion.setTarget(to);
  } else {
    m_indicatorMotion.setImmediate(to); // same section, layout changed: follow it exactly
  }
  applyNavIndicatorGeometry();
}

void ControlCenterPanel::applyNavIndicatorGeometry() {
  if (m_navIndicator == nullptr || !m_indicatorMotion.hasValue()) {
    return;
  }
  const auto r = m_indicatorMotion.value();
  m_navIndicator->setVisible(true);
  m_navIndicator->setPosition(r.x, r.y);
  m_navIndicator->setSize(r.width, r.height);
}

void ControlCenterPanel::layoutCommandBarNav(Renderer& renderer, float barWidth) {
  if (m_sidebarNav == nullptr || m_sidebar == nullptr) {
    return;
  }
  const float scale = contentScale();
  m_navGap = ui::tokens::space(ui::tokens::Space::Inline, scale);

  // Sized against the widest section's actions, not the active one's: otherwise the whole strip would
  // resize at the moment of a switch (Home has three actions, most sections one) — the frame must not move.
  float widestSectionActions = 0.0F;
  for (Flex* actions : m_tabHeaderActions) {
    if (actions != nullptr) {
      widestSectionActions = std::max(widestSectionActions, actions->measure(renderer, LayoutConstraints{}).width);
    }
  }
  float actionsWidth = m_closeButton != nullptr ? m_closeButton->measure(renderer, LayoutConstraints{}).width : 0.0F;
  if (widestSectionActions > 0.0F && m_contentHeaderActions != nullptr) {
    actionsWidth += widestSectionActions + m_contentHeaderActions->gap();
  }
  const float available = std::max(0.0F, barWidth - actionsWidth - ui::tokens::space(ui::tokens::Space::Group, scale));

  int visibleItems = 0;
  for (const auto& meta : kTabs) {
    const Button* button = m_tabButtons[tabIndex(meta.id)];
    visibleItems += button != nullptr && button->visible() ? 1 : 0;
  }
  // Responsive, labels first. An item's unfold (gap + label) does not depend on its height, so the items
  // shrink — from the medium control height down to 30 px — to make room for the widest label beside the
  // actions. Only when even that fails does the strip go icon-only, and then it may shrink to 28 px before
  // anything overlaps (a section opened directly is 0.75 of the panel width).
  const float gaps = m_navGap * static_cast<float>(std::max(0, visibleItems - 1));
  const float labelGap = ui::tokens::space(ui::tokens::Space::Related, scale);
  const auto& labelSpec = ui::type::spec(ui::type::Role::Label);
  float widestText = 0.0F;
  for (const auto& meta : kTabs) {
    const Button* button = m_tabButtons[tabIndex(meta.id)];
    if (button == nullptr || !button->visible()) {
      continue;
    }
    widestText = std::max(
        widestText,
        renderer
            .measureText(
                i18n::tr(meta.titleKey), ui::type::size(ui::type::Role::Label, scale), labelSpec.weight, 0.0F, 0,
                TextAlign::Start, ui::type::familyFor(ui::type::Role::Label)
            )
            .width
    );
  }
  const float maxItem = ui::tokens::controlHeight(ui::tokens::Size::Medium, scale);
  const float items = static_cast<float>(std::max(1, visibleItems));
  // 1 px margin: the unfolded widths are ceiled, which must not flip the labels off at fractional scales.
  const float withLabels = std::floor((available - gaps - labelGap - std::ceil(widestText) - 1.0F) / items);
  if (withLabels >= 30.0F * scale) {
    m_navItemHeight = std::min(maxItem, withLabels);
  } else {
    m_navItemHeight = std::clamp(std::floor((available - gaps) / items), 28.0F * scale, maxItem);
  }
  const float glyphSize = std::min(ui::tokens::iconSize(ui::tokens::Size::Medium, scale), m_navItemHeight * 0.55F);

  float collapsedRun = 0.0F;
  float widestUnfold = 0.0F;
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    Button* button = m_tabButtons[idx];
    if (button == nullptr || !button->visible()) {
      continue;
    }
    button->setGlyphSize(glyphSize);
    button->setPadding(0.0F, (m_navItemHeight - glyphSize) * 0.5F);
    button->setRadius(ui::tokens::pill(m_navItemHeight));
    // Unfolded = the collapsed square (glyph centred, equal padding) + gap + label. Measured from the
    // text rather than the button: the button's frame is pinned by the expansion between layouts.
    m_navCollapsedWidth[idx] = m_navItemHeight;
    const float textWidth =
        renderer
            .measureText(
                i18n::tr(meta.titleKey), ui::type::size(ui::type::Role::Label, scale), labelSpec.weight, 0.0F, 0,
                TextAlign::Start, ui::type::familyFor(ui::type::Role::Label)
            )
            .width;
    m_navExpandedWidth[idx] = std::ceil(m_navItemHeight + labelGap + textWidth);
    widestUnfold = std::max(widestUnfold, m_navExpandedWidth[idx] - m_navCollapsedWidth[idx]);
    collapsedRun += m_navCollapsedWidth[idx];
  }
  collapsedRun += gaps;

  // Labels only when the widest one fits beside the section's actions; the strip is then sized for the
  // widest unfolded state, so nothing else in the bar moves while the items reconfigure.
  if (m_navIndicator != nullptr) {
    m_navIndicator->setRadius(ui::tokens::pill(m_navItemHeight));
  }
  const bool labelsFit = collapsedRun + widestUnfold <= available;
  const bool fitChanged = labelsFit != m_navLabelsFit;
  m_navLabelsFit = labelsFit;

  const float stripWidth = std::ceil(collapsedRun + (labelsFit ? widestUnfold : 0.0F));
  m_sidebarNav->setMinWidth(stripWidth);
  m_sidebarNav->setMaxWidth(stripWidth);
  m_sidebarNav->setMinHeight(m_navItemHeight);
  if (fitChanged) {
    syncCommandBarNavTargets(false);
  }
}

void ControlCenterPanel::syncCommandBarNavTargets(bool animate) {
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    if (m_tabButtons[idx] == nullptr) {
      continue;
    }
    const float target = m_navLabelsFit && meta.id == m_activeTab ? 1.0F : 0.0F;
    if (animate) {
      m_navExpand[idx].setTarget(target);
    } else {
      m_navExpand[idx].setImmediate(target);
    }
  }
}

MotionRectValue ControlCenterPanel::commandBarNavRest(TabId tab) const {
  float x = 0.0F;
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    const Button* button = m_tabButtons[idx];
    if (button == nullptr || !button->visible()) {
      continue;
    }
    const bool unfolded = m_navLabelsFit && meta.id == tab;
    const float w = unfolded ? m_navExpandedWidth[idx] : m_navCollapsedWidth[idx];
    if (meta.id == tab) {
      return MotionRectValue{.x = x, .y = 0.0F, .width = w, .height = m_navItemHeight};
    }
    x += w + m_navGap;
  }
  return MotionRectValue{.x = 0.0F, .y = 0.0F, .width = m_navItemHeight, .height = m_navItemHeight};
}

void ControlCenterPanel::applyCommandBarNavGeometry() {
  if (!m_commandBar || m_navItemHeight <= 0.0F) {
    return;
  }
  float x = 0.0F;
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    Button* button = m_tabButtons[idx];
    if (button == nullptr || !button->visible()) {
      continue;
    }
    const float unfold = m_navExpand[idx].hasValue() ? std::clamp(m_navExpand[idx].value(), 0.0F, 1.0F) : 0.0F;
    const float collapsed = m_navCollapsedWidth[idx];
    const float w = collapsed + unfold * std::max(0.0F, m_navExpandedWidth[idx] - collapsed);
    // Frame size, not setSize: a frame change repaints without asking for a layout pass, so an
    // unfold costs a redraw per frame, not a panel relayout.
    button->setPosition(x, 0.0F);
    button->setFrameSize(w, m_navItemHeight);
    button->updateInputArea();
    if (Label* label = button->label()) {
      // The clip reveals the label; its ink arrives over the second half of the unfold so a
      // half-open item never shows a squeezed word.
      float ink = std::clamp((unfold - 0.4F) / 0.6F, 0.0F, 1.0F);
      // The incoming label also waits for the capsule: items and capsule converge on the same end state
      // by different paths, and mid-flight the unfolding word would otherwise show beside the capsule
      // instead of inside it. It appears as the capsule settles around it (within 12 px of rest).
      if (meta.id == m_activeTab) {
        if (m_indicatorMotion.hasValue()) {
          const MotionRectValue pill = m_indicatorMotion.value();
          const MotionRectValue rest = commandBarNavRest(m_activeTab);
          const float offRest = std::abs(pill.x - rest.x) + std::abs(pill.width - rest.width);
          ink = std::min(ink, std::clamp(1.0F - offRest / (12.0F * contentScale()), 0.0F, 1.0F));
        }
      } else {
        // An item the capsule has left may only lose ink: in a burst of switches, an item passed through
        // on the way (half unfolded, never reached) must not flash its label as it folds again.
        ink = std::min(ink, m_navInk[idx]);
      }
      m_navInk[idx] = ink;
      label->setOpacity(ink);
    }
    x += w + m_navGap;
  }
}

int ControlCenterPanel::visibleTabOrdinal(TabId tab) const {
  int ordinal = 0;
  for (const auto& meta : kTabs) {
    if (!isTabShown(meta.id)) {
      continue;
    }
    if (meta.id == tab) {
      return ordinal;
    }
    ++ordinal;
  }
  return 0;
}

void ControlCenterPanel::applyTabTransitionLayout() {
  if (m_tabBodies == nullptr) {
    return;
  }
  layoutTabContainers(m_tabBodies->width(), m_tabBodies->height());
}

void ControlCenterPanel::startTabTransition(TabId from, TabId to, float carry) {
  if (m_animations == nullptr || m_tabBodies == nullptr) {
    applyTabContainerVisibility(to);
    resetTabContainerTransforms();
    return;
  }

  m_tabTransitionOutgoing = from;
  // The indicator is not driven from here: layoutNavIndicator() retargets its MotionRect when the
  // active section changes, so a burst of switches stays one continuous motion with its velocity kept.

  const int fromOrdinal = visibleTabOrdinal(from);
  const int toOrdinal = visibleTabOrdinal(to);
  const int direction = toOrdinal >= fromOrdinal ? 1 : -1;

  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    if (m_tabContainers[idx] == nullptr || !isTabVisible(meta.id)) {
      continue;
    }
    const bool show = meta.id == from || meta.id == to;
    m_tabContainers[idx]->setVisible(show);
  }

  // start() must precede the first layout pass: layoutTabContainers reads progress and
  // direction off the morph, so the pre-animation frame has to see the new leg's state.
  m_tabMorph.bind(m_animations, m_tabBodies);
  m_tabMorph.start(
      direction, carry, motion::Role::Morph,
      [this](float) {
        applyTabTransitionLayout();
        PanelManager::instance().requestRedraw();
      },
      [this]() {
        finishTabTransition();
        PanelManager::instance().requestLayout();
        PanelManager::instance().requestRedraw();
      }
  );

  applyTabTransitionLayout();
  PanelManager::instance().requestLayout();
  PanelManager::instance().requestRedraw();
  PanelManager::instance().requestFrameTick();
}

void ControlCenterPanel::finishTabTransition() {
  resetTabContainerTransforms();
  applyTabContainerVisibility(m_activeTab);
}

void ControlCenterPanel::wireSidebarScroll(InputArea* area) {
  if (area == nullptr) {
    return;
  }
  area->setOnAxis([this](const InputArea::PointerData& data) {
    if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL) {
      return;
    }
    const float steps = data.scrollSteps();
    if (steps == 0.0F) {
      return;
    }
    selectAdjacentVisibleTab(steps > 0.0F ? 1 : -1);
  });
}

void ControlCenterPanel::selectAdjacentVisibleTab(int direction) {
  if (direction == 0) {
    return;
  }

  const int activeOrdinal = visibleTabOrdinal(m_activeTab);
  const int targetOrdinal = activeOrdinal + direction;

  int ordinal = 0;
  for (const auto& meta : kTabs) {
    if (!isTabShown(meta.id)) {
      continue;
    }
    if (ordinal == targetOrdinal) {
      if (meta.id != m_activeTab) {
        selectTab(meta.id, true);
        PanelManager::instance().refresh();
      }
      return;
    }
    ++ordinal;
  }
}

void ControlCenterPanel::selectTab(TabId tab, bool animated) {
  if (!isTabFeatureAvailable(tab)) {
    tab = firstVisibleTab();
  }
  m_activeTabForced = !isTabVisible(tab);

  const TabId previousTab = m_activeTab;
  const bool tabChanged = tab != previousTab;

  // Interrupting a switch: remember where the content that is now leaving
  // actually sits, so the next transition continues from there.
  float interruptedOffset = 0.0F;
  bool interrupted = false;
  if (m_tabMorph.active()) {
    // Read the live offset BEFORE cancelling: this is the visual state the next leg
    // carries in, and it is the whole reason a reversal does not snap back.
    const std::size_t incomingIdx = tabIndex(m_activeTab);
    if (m_tabContainers[incomingIdx] != nullptr) {
      interruptedOffset = m_tabContainers[incomingIdx]->opacity(); // its reveal, 0..1
      interrupted = true;
    }
    m_tabMorph.cancel();
    applyTabContainerVisibility(m_activeTab);
  }

  m_activeTab = tab;
  if (tab == TabId::Notifications && m_notificationManager != nullptr) {
    m_notificationManager->markNotificationHistorySeen();
  }

  updateTabChrome(tab);
  if (m_commandBar) {
    syncCommandBarNavTargets(animated);
  }

  if (tabChanged && animated && m_animations != nullptr && m_tabBodies != nullptr) {
    startTabTransition(previousTab, tab, interrupted ? interruptedOffset : 1.0F);
  } else {
    m_tabMorph.cancel();
    applyTabContainerVisibility(tab);
    resetTabContainerTransforms();
  }

  scheduleMprisRefreshFor(tab);
}

void ControlCenterPanel::scheduleMprisRefreshFor(TabId tab) {
  if (m_mpris == nullptr || m_mprisRefreshScheduled || (tab != TabId::Home && tab != TabId::Media)) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (m_lastMprisRefreshAt.time_since_epoch().count() != 0 && now - m_lastMprisRefreshAt < kMprisRefreshMinInterval) {
    return;
  }

  m_lastMprisRefreshAt = now;
  m_mprisRefreshScheduled = true;
  DeferredCall::callLater([this]() {
    m_mprisRefreshScheduled = false;
    if (m_mpris == nullptr || !PanelManager::instance().isOpenPanel("control-center")) {
      return;
    }
    m_mpris->refreshPlayers();
    PanelManager::instance().requestUpdateOnly();
    PanelManager::instance().requestRedraw();
  });
}

bool ControlCenterPanel::isDirectSectionOpenContext(std::string_view context) const {
  if (context.empty() || context == "home") {
    return false;
  }
  for (const auto& tab : kTabs) {
    if (tab.id != TabId::Home && context == tab.key) {
      return true;
    }
  }
  return false;
}

ControlCenterSidebarMode ControlCenterPanel::sidebarModeForOpen(std::string_view context) const {
  if (m_config == nullptr) {
    return ControlCenterSidebarMode::Compact;
  }
  const auto& cc = m_config->config().controlCenter;
  return isDirectSectionOpenContext(context) ? cc.sidebarSectionMode : cc.sidebarMode;
}

ControlCenterPanel::TabId ControlCenterPanel::tabFromContext(std::string_view context) const {
  for (const auto& tab : kTabs) {
    if (context == tab.key) {
      return tab.id;
    }
  }
  return TabId::Home;
}

std::size_t ControlCenterPanel::tabIndex(TabId id) { return static_cast<std::size_t>(id); }

void ControlCenterPanel::layoutFullSidebarWidth(Renderer& renderer) {
  if (m_sidebarScrollView == nullptr || m_sidebarNav == nullptr) {
    return;
  }

  const float scale = contentScale();
  const float fontSize = Style::fontSizeBody * scale;
  const float paddingH = Style::spaceSm * scale * 2.0F;
  const float gap = Style::spaceSm * scale;
  const float glyphW = 21.0F * scale;

  float maxTabWidth = 0.0F;
  for (const auto& meta : kTabs) {
    if (!isTabVisible(meta.id)) {
      continue;
    }
    const TextMetrics text = renderer.measureText(i18n::tr(meta.titleKey), fontSize, FontWeight::Bold);
    maxTabWidth = std::max(maxTabWidth, paddingH + glyphW + gap + text.width);
  }

  const float minWidth = Style::controlHeightSm * scale;
  const float contentWidth = std::max(minWidth, std::ceil(maxTabWidth));

  // Scrollbar gutter lives inside the scroll viewport; reserve it only when the nav overflows.
  float targetWidth = contentWidth;
  const float scrollHeight = m_sidebarScrollView->height();
  if (scrollHeight > 0.0F) {
    LayoutConstraints navConstraints;
    navConstraints.setExactWidth(contentWidth);
    const float navHeight = m_sidebarNav->measure(renderer, navConstraints).height;
    if (navHeight > scrollHeight + 0.5F) {
      targetWidth = contentWidth + m_sidebarScrollView->scrollbarGutter();
    }
  }

  if (std::abs(m_sidebarScrollView->width() - targetWidth) > 0.5F) {
    m_sidebarScrollView->setSize(targetWidth, m_sidebarScrollView->height());
  }
}

void ControlCenterPanel::scrollSidebarNodeIntoView(const Node* node) {
  if (node == nullptr || m_sidebarScrollView == nullptr) {
    return;
  }
  scrollNodeIntoScrollView(*m_sidebarScrollView, &m_sidebarScrollState, *node, Style::spaceXs * contentScale());
  PanelManager::instance().requestLayout();
}

void ControlCenterPanel::scrollFocusedInputIntoView(InputArea* area) {
  if (area == nullptr) {
    return;
  }

  if (m_sidebarScrollView != nullptr && m_sidebarScrollView->content() != nullptr) {
    for (const Node* node = area; node != nullptr; node = node->parent()) {
      if (node == m_sidebarScrollView->content()) {
        scrollNodeIntoScrollView(*m_sidebarScrollView, &m_sidebarScrollState, *area, Style::spaceXs * contentScale());
        PanelManager::instance().requestLayout();
        return;
      }
    }
  }

  if (ScrollView* scrollView = findEnclosingScrollView(area)) {
    scrollNodeIntoScrollView(*scrollView, nullptr, *area, Style::spaceMd * contentScale());
    PanelManager::instance().requestLayout();
  }
}
