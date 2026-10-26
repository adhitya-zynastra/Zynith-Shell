#include "shell/lockscreen/lockscreen_widgets_host.h"

#include "config/config_service.h"
#include "core/log.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "scripting/plugin_registry.h"
#include "shell/desktop/desktop_widget_layout.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/lockscreen/lock_surface.h"
#include "shell/lockscreen/lockscreen_login_box.h"
#include "time/time_format.h"
#include "ui/builders.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <string>
#include <wayland-client-protocol.h>

namespace {

  constexpr Logger kLog("lockscreen");

  DesktopWidgetState* findStateById(LockscreenWidgetsSnapshot& snapshot, const std::string& id) {
    for (auto& widget : snapshot.widgets) {
      if (widget.id == id) {
        return &widget;
      }
    }
    return nullptr;
  }

} // namespace

void LockscreenWidgetsHost::initialize(const DesktopWidgetServices& services) {
  m_wayland = &services.wayland;
  m_config = services.config;
  m_renderContext = services.renderContext;
  m_factory = std::make_unique<DesktopWidgetFactory>(services.runtime);
}

void LockscreenWidgetsHost::show(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen) {
  m_snapshot = snapshot;
  m_visible = true;
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::hide() {
  for (auto& instance : m_instances) {
    if (instance->widget != nullptr) {
      instance->widget->setFrameTickRequestCallback(nullptr);
      instance->widget->setUpdateCallback(nullptr);
      instance->widget->setLayoutCallback(nullptr);
      instance->widget->setRedrawCallback(nullptr);
    }
    detachFromSurface(*instance);
  }
  m_visible = false;
  m_instances.clear();
}

void LockscreenWidgetsHost::rebuild(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen) {
  m_snapshot = snapshot;
  if (!m_visible) {
    return;
  }
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::reloadPluginWidgets(LockScreen& lockScreen) {
  if (!m_visible) {
    return;
  }
  const std::size_t removed = removeInstances([](const WidgetInstance& instance) {
    return scripting::isPluginEntryOfKind(instance.state.type, scripting::PluginEntryKind::DesktopWidget);
  });
  if (removed == 0) {
    return;
  }
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::onOutputChange(LockScreen& lockScreen) {
  if (!m_visible) {
    return;
  }
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::onSecondTick() {
  if (!m_visible) {
    return;
  }

  const bool minuteBoundary = formatLocalTime("{:%S}") == "00";
  for (auto& instance : m_instances) {
    if (instance->surface == nullptr || instance->widget == nullptr) {
      continue;
    }
    if (instance->widget->wantsSecondTicks()) {
      instance->surface->requestUpdateOnly();
    } else if (minuteBoundary) {
      instance->surface->requestUpdate();
    }
  }
}

LockscreenWidgetsHost::WidgetInstance* LockscreenWidgetsHost::findInstance(const std::string& id) {
  for (auto& instance : m_instances) {
    if (instance->state.id == id) {
      return instance.get();
    }
  }
  return nullptr;
}

LockSurface* LockscreenWidgetsHost::findSurfaceForOutput(LockScreen& lockScreen, const std::string& outputKey) const {
  LockSurface* found = nullptr;
  lockScreen.forEachSurface([&](LockSurface& surface) {
    if (found != nullptr || m_wayland == nullptr) {
      return;
    }
    const WaylandOutput* output = m_wayland->findOutputByWl(surface.output());
    if (output == nullptr) {
      return;
    }
    if (desktop_widgets::outputKey(*output) == outputKey) {
      found = &surface;
    }
  });
  return found;
}

void LockscreenWidgetsHost::syncSurfaces(LockScreen& lockScreen) {
  if (!m_visible || m_wayland == nullptr || m_renderContext == nullptr || m_factory == nullptr) {
    return;
  }

  removeInstances([this](const WidgetInstance& instance) {
    const DesktopWidgetState* state = findStateById(m_snapshot, instance.state.id);
    return state == nullptr || !state->enabled || instance.surface == nullptr;
  });

  for (const auto& state : m_snapshot.widgets) {
    if (!state.enabled || lockscreen_login_box::isLoginBoxWidget(state)) {
      continue;
    }

    const WaylandOutput* output = desktop_widgets::resolveStateOutput(*m_wayland, state);
    if (output == nullptr) {
      removeInstances([&state](const WidgetInstance& instance) { return instance.state.id == state.id; });
      continue;
    }

    const std::string outputKey = desktop_widgets::outputKey(*output);
    LockSurface* surface = findSurfaceForOutput(lockScreen, outputKey);
    if (surface == nullptr) {
      removeInstances([&state](const WidgetInstance& instance) { return instance.state.id == state.id; });
      continue;
    }

    WidgetInstance* existing = findInstance(state.id);
    if (existing == nullptr) {
      createInstance(state, *surface, *output);
      continue;
    }

    const bool widgetDefinitionChanged = existing->state.type != state.type
        || existing->state.settings != state.settings
        || existing->surface != surface;

    if (widgetDefinitionChanged) {
      // zynith fix: upstream detached EVERY instance here (the predicate detached before testing the id)
      // while std::erase_if was moving elements; the frame-tick re-sync inside detach then walked a
      // moved-from null entry and crashed the shell. A settings change to any lock widget while the
      // session was locked (a config reload) was enough, and it left the session locked with no UI.
      removeInstances([&state](const WidgetInstance& instance) { return instance.state.id == state.id; });
      createInstance(state, *surface, *output);
      continue;
    }

    if (!(existing->state == state)) {
      existing->state = state;
      if (existing->surface != nullptr) {
        existing->surface->requestLayout();
      }
    }
  }

  lockScreen.forEachSurface([&](LockSurface& surface) { surface.setWidgetsHost(this); });
}

void LockscreenWidgetsHost::createInstance(
    const DesktopWidgetState& state, LockSurface& surface, const WaylandOutput& output
) {
  if (m_factory == nullptr || m_renderContext == nullptr) {
    return;
  }

  const float baseUiScale = m_config != nullptr ? m_config->config().accessibility.uiScale : 1.0F;
  auto widget = m_factory->create(state.type, state.settings, desktop_widgets::widgetContentScale(baseUiScale));
  if (widget == nullptr) {
    return;
  }

  widget->create();
  widget->setBox(state.boxWidth, state.boxHeight);

  if (surface.renderTarget().isReady()) {
    m_renderContext->makeCurrent(surface.renderTarget());
    Renderer& renderer = surface.renderTarget().renderer();
    widget->update(renderer);
    widget->layout(renderer);
  }

  const float intrinsicWidth = std::max(1.0F, widget->intrinsicWidth());
  const float intrinsicHeight = std::max(1.0F, widget->intrinsicHeight());

  DesktopWidgetState clampedState = state;
  desktop_widgets::clampStateToOutput(*m_wayland, clampedState, intrinsicWidth, intrinsicHeight);

  auto instance = std::make_unique<WidgetInstance>();
  instance->state = clampedState;
  instance->surface = &surface;
  instance->widget = std::move(widget);
  instance->intrinsicWidth = intrinsicWidth;
  instance->intrinsicHeight = intrinsicHeight;

  auto* rawInstance = instance.get();
  instance->widget->setAnimationManager(&instance->animations);
  instance->widget->setUpdateCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestUpdateOnly();
    }
  });
  instance->widget->setLayoutCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestUpdate();
    }
  });
  instance->widget->setRedrawCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestRedraw();
    }
  });
  instance->widget->setFrameTickRequestCallback([this, rawInstance]() {
    if (rawInstance->surface != nullptr) {
      syncSurfaceFrameTick(rawInstance->surface);
      rawInstance->surface->requestFrameTick();
    }
  });

  attachToSurface(*instance);
  m_instances.push_back(std::move(instance));
  (void)output;
}

void LockscreenWidgetsHost::attachToSurface(WidgetInstance& instance) {
  if (instance.surface == nullptr || instance.widget == nullptr) {
    return;
  }

  Node* layer = instance.surface->widgetLayer();
  if (layer == nullptr) {
    return;
  }

  auto transformNode = ui::node({});
  transformNode->setAnimationManager(&instance.animations);
  instance.transformNode = layer->addChild(std::move(transformNode));
  instance.transformNode->addChild(instance.widget->releaseRoot());

  syncSurfaceFrameTick(instance.surface);
  instance.surface->requestLayout();
}

std::size_t LockscreenWidgetsHost::removeInstances(const std::function<bool(const WidgetInstance&)>& shouldRemove) {
  std::vector<const WidgetInstance*> doomed;
  for (const auto& instance : m_instances) {
    if (instance != nullptr && shouldRemove(*instance)) {
      doomed.push_back(instance.get());
    }
  }
  for (const auto& instance : m_instances) {
    if (std::ranges::contains(doomed, instance.get())) {
      detachFromSurface(*instance);
    }
  }
  return std::erase_if(m_instances, [&doomed](const std::unique_ptr<WidgetInstance>& instance) {
    return instance == nullptr || std::ranges::contains(doomed, instance.get());
  });
}

void LockscreenWidgetsHost::syncSurfaceFrameTick(LockSurface* surfacePtr) {
  if (surfacePtr == nullptr) {
    return;
  }

  const bool hasWidgets = std::ranges::any_of(m_instances, [&](const auto& instance) {
    return instance != nullptr && instance->surface == surfacePtr && instance->widget != nullptr;
  });
  if (!hasWidgets) {
    surfacePtr->setFrameTickCallback(nullptr);
    return;
  }

  auto* host = this;
  surfacePtr->setFrameTickCallback([host, surfacePtr](float deltaMs) {
    if (host->m_renderContext == nullptr) {
      return;
    }
    host->m_renderContext->makeCurrent(surfacePtr->renderTarget());
    Renderer& renderer = surfacePtr->renderTarget().renderer();

    bool needsRedraw = false;
    for (auto& instance : host->m_instances) {
      if (instance == nullptr || instance->surface != surfacePtr) {
        continue;
      }
      instance->animations.tick(deltaMs);
      needsRedraw = needsRedraw || instance->animations.hasActive();
    }

    bool needsContinuousRedraw = needsRedraw;
    for (auto& instance : host->m_instances) {
      if (instance == nullptr
          || instance->surface != surfacePtr
          || instance->widget == nullptr
          || !instance->widget->needsFrameTick()) {
        continue;
      }
      instance->widget->onFrameTick(deltaMs, renderer);
      needsContinuousRedraw = true;
    }

    if (needsContinuousRedraw) {
      surfacePtr->requestRedraw();
    }
  });
}

void LockscreenWidgetsHost::detachFromSurface(WidgetInstance& instance) {
  LockSurface* surface = instance.surface;

  if (instance.transformNode != nullptr && surface != nullptr) {
    if (Node* layer = surface->widgetLayer(); layer != nullptr) {
      (void)layer->removeChild(instance.transformNode);
    }
    instance.transformNode = nullptr;
  }
  instance.surface = nullptr;

  if (surface != nullptr) {
    syncSurfaceFrameTick(surface);
  }
}

void LockscreenWidgetsHost::prepareFrame(LockSurface& surface, bool needsUpdate, bool needsLayout) {
  if (!m_visible || m_renderContext == nullptr) {
    return;
  }

  m_renderContext->makeCurrent(surface.renderTarget());
  Renderer& renderer = surface.renderTarget().renderer();

  const float baseUiScale = m_config != nullptr ? m_config->config().accessibility.uiScale : 1.0F;
  const auto surfaceW = static_cast<float>(surface.width());
  const auto surfaceH = static_cast<float>(surface.height());

  Node* layer = surface.widgetLayer();
  if (layer != nullptr) {
    layer->setPosition(0.0F, 0.0F);
    layer->setSize(surfaceW, surfaceH);
  }

  for (auto& instance : m_instances) {
    if (instance->surface != &surface || instance->widget == nullptr) {
      continue;
    }

    instance->widget->setContentScale(desktop_widgets::widgetContentScale(baseUiScale));
    instance->widget->setBox(instance->state.boxWidth, instance->state.boxHeight);

    if (needsUpdate) {
      instance->widget->update(renderer);
    }
    if (needsLayout) {
      instance->widget->layout(renderer);
      instance->intrinsicWidth = std::max(1.0F, instance->widget->intrinsicWidth());
      instance->intrinsicHeight = std::max(1.0F, instance->widget->intrinsicHeight());
    }

    if (m_wayland != nullptr) {
      DesktopWidgetState currentState = instance->state;
      if (const DesktopWidgetState* origState = findStateById(m_snapshot, instance->state.id); origState != nullptr) {
        currentState = *origState;
      }
      desktop_widgets::clampStateToOutput(
          *m_wayland, currentState, instance->intrinsicWidth, instance->intrinsicHeight
      );
      instance->state = currentState;
    }

    if (instance->transformNode == nullptr) {
      continue;
    }

    instance->transformNode->setFrameSize(instance->intrinsicWidth, instance->intrinsicHeight);
    instance->transformNode->setPosition(
        instance->state.cx - instance->intrinsicWidth * 0.5F, instance->state.cy - instance->intrinsicHeight * 0.5F
    );
    instance->transformNode->setRotation(instance->state.rotationRad);
    float flipScaleX = 1.0F;
    float flipScaleY = 1.0F;
    desktop_widgets::widgetNodeScale(instance->state, flipScaleX, flipScaleY);
    instance->transformNode->setScale(flipScaleX, flipScaleY);
  }

  // Mirror the desktop host: widgets like sysmon drive updates from frame ticks.
  const bool needsFrameTick = std::ranges::any_of(m_instances, [&surface](const auto& instance) {
    return instance != nullptr
        && instance->surface == &surface
        && instance->widget != nullptr
        && instance->widget->needsFrameTick();
  });
  if (needsFrameTick) {
    surface.requestFrameTick();
  }
}
