#include "shell/lockscreen/lock_screen.h"

#include "auth/fingerprint_authenticator.h"
#include "capture/screencopy_util.h"
#include "compositors/compositor_detect.h"
#include "compositors/compositor_platform.h"
#include "compositors/niri/niri_runtime.h"
#include "config/config_service.h"
#include "config/config_types.h"
#include "core/deferred_call.h"
#include "core/input/key_chord.h"
#include "core/input/keybind_matcher.h"
#include "core/log.h"
#include "ext-session-lock-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "render/animation/motion_role.h"
#include "render/animation/motion_service.h"
#include "render/render_context.h"
#include "security/sensitive_string.h"
#include "shell/desktop/desktop_widget_layout.h"
#include "shell/keyboard_layout_label.h"
#include "shell/lockscreen/lock_surface.h"
#include "shell/veil/screen_veil.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <thread>

namespace {

  constexpr Logger kLog("lockscreen");

  Color resolveWallpaperFillColor(const WallpaperConfig& config) {
    // The lockscreen is an ext-session-lock surface: any transparency lets the
    // compositor's "client hasn't painted" fallback (e.g. niri's red) bleed
    // through. With no wallpaper image and no configured fill color, paint an
    // opaque black background so the lock surface is always fully opaque.
    if (!config.fillColor) {
      return rgba(0.0F, 0.0F, 0.0F, 1.0F);
    }
    return resolveColorSpec(*config.fillColor);
  }

  // An output can only carry a lock surface once it is complete and has real geometry.
  bool hasUsableOutput(const WaylandConnection& wayland) {
    return std::ranges::any_of(wayland.outputs(), [](const WaylandOutput& output) {
      return output.done && output.output != nullptr && output.hasUsableGeometry();
    });
  }

  const ext_session_lock_v1_listener kSessionLockListener = {
      .locked = &LockScreen::handleLocked,
      .finished = &LockScreen::handleFinished,
  };

} // namespace

LockScreen::LockScreen() = default;

LockScreen::~LockScreen() {
  invalidatePendingAuthentication();
  clearInstances();
  resetLockState();
}

bool LockScreen::initialize(
    WaylandConnection& wayland, RenderContext* renderContext, ConfigService* configService,
    SharedTextureCache* textureCache, SystemBus* systemBus, CompositorPlatform* compositorPlatform
) {
  m_wayland = &wayland;
  m_renderContext = renderContext;
  m_configService = configService;
  m_textureCache = textureCache;
  m_systemBus = systemBus;
  m_compositorPlatform = compositorPlatform;
  m_user = PamAuthenticator::currentUsername();

  if (m_systemBus != nullptr) {
    m_fingerprint = std::make_unique<FingerprintAuthenticator>(*m_systemBus);
    m_fingerprint->setAuthenticatedCallback([this]() {
      m_status = i18n::tr("lockscreen.unlocked");
      m_statusIsError = false;
      updatePromptOnSurfaces();
      beginUnlockTransition();
    });
    m_fingerprint->setStatusCallback([this](const std::string& message, bool isError) {
      handleFingerprintStatus(message, isError);
    });
  }
  return true;
}

void LockScreen::setSessionHooks(
    std::function<void()> onLocked, std::function<void()> onUnlocked, std::function<void()> onLockAborted
) {
  m_onSessionLocked = std::move(onLocked);
  m_onSessionUnlocked = std::move(onUnlocked);
  m_onLockAborted = std::move(onLockAborted);
}

void LockScreen::setLoginBoxServices(
    SessionActionRunner* sessionActions, MprisService* mpris, const WeatherService* weather, HttpClient* httpClient
) {
  m_sessionActions = sessionActions;
  m_mpris = mpris;
  m_weather = weather;
  m_httpClient = httpClient;
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      instance.surface->setLoginBoxServices(m_sessionActions, m_mpris, m_weather, m_httpClient);
    }
  }
}

bool LockScreen::lock() {
  // zynith: reserve once so typing never reallocates the password (a reallocation frees the old buffer unwiped).
  m_password.reserve(security::kPasswordBufferReserve);
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return false;
  }
  if (m_configService != nullptr && !m_configService->isLockScreenEnabled()) {
    kLog.debug("lock screen disabled");
    return false;
  }
  if (isActive()) {
    return true;
  }
  if (!m_wayland->hasSessionLockManager()) {
    kLog.warn("session lock protocol unavailable");
    return false;
  }
  if (!hasUsableOutput(*m_wayland)) {
    m_lockDeferred = true;
    kLog.warn("no outputs available for lock screen; lock deferred until an output is connected");
    // No output can ever show a lock surface, so run any pending post-lock action (e.g. suspend)
    // immediately instead of holding it until a monitor reconnects.
    dispatchPendingAfterLocked();
    return true;
  }

  if (m_desktopCapturesPrimed) {
    m_desktopCapturesPrimed = false;
  } else {
    m_desktopCaptures.clear();
    if (shouldUseBlurredDesktop()) {
      captureDesktopSnapshots();
    }
  }

  // lockfade: compositor freezes the current frame and crossfades into the lock surface.
  requestCompositorCrossfade(120);

  m_lock = ext_session_lock_manager_v1_lock(m_wayland->sessionLockManager());
  if (m_lock == nullptr) {
    kLog.warn("failed to create session lock object");
    return false;
  }
  if (ext_session_lock_v1_add_listener(m_lock, &kSessionLockListener, this) != 0) {
    ext_session_lock_v1_destroy(m_lock);
    m_lock = nullptr;
    kLog.warn("failed to register session lock listener");
    return false;
  }

  m_lockPending = true;
  m_locked = false;
  clearSensitiveString(m_password);
  m_status = i18n::tr("lockscreen.waiting");
  m_statusIsError = false;
  syncInstances();
  if (m_instances.empty()) {
    kLog.warn("no outputs available for lock screen");
    resetLockState();
    return false;
  }
  wl_display_flush(m_wayland->display());
  kLog.info("session lock requested");
  return true;
}

void LockScreen::unlock() {
  m_unlockTransitionTimer.stop();
  m_lockDeferred = false;
  if (!isActive()) {
    return;
  }

  m_pendingAfterLocked = {};
  m_suspendTimeoutTimer.stop();
  invalidatePendingAuthentication();
  stopFingerprint();

  const bool wasLockedInteractive = m_locked;

  if (m_lock != nullptr) {
    if (m_locked) {
      ext_session_lock_v1_unlock_and_destroy(m_lock);
      kLog.info("session unlock requested");
    } else {
      ext_session_lock_v1_destroy(m_lock);
      kLog.info("session lock request cancelled");
    }
    m_lock = nullptr;
  }

  m_lockPending = false;
  m_locked = false;
  clearSensitiveString(m_password);
  m_status.clear();
  m_statusIsError = false;
  m_wayland->stopKeyRepeat();
  m_desktopCaptures.clear();
  m_desktopCapturesPrimed = false;

  // Tear down widgets while lock surfaces still exist. Session hooks run only after
  // isActive() is false so LockscreenWidgetsController::applyVisibility() hides first.
  if (wasLockedInteractive && m_onSessionUnlocked) {
    m_onSessionUnlocked();
  }

  clearInstances();
  m_pointerSurface = nullptr;
  wl_display_flush(m_wayland->display());

  // lockfade: session is now unlocked; let the veil carry the eye into the live desktop.
  fadeOutUnlockVeils();
}

void LockScreen::onFontChanged() { requestLayout(); }

void LockScreen::requestLayout() {
  for (auto& inst : m_instances) {
    if (inst.surface != nullptr) {
      inst.surface->requestLayout();
    }
  }
}

void LockScreen::requestUpdate() {
  for (auto& inst : m_instances) {
    if (inst.surface != nullptr) {
      inst.surface->requestUpdate();
    }
  }
}

void LockScreen::forceRepaintAfterResume() {
  for (auto& inst : m_instances) {
    if (inst.surface != nullptr) {
      inst.surface->discardPendingFrameCallback();
      inst.surface->requestRedraw();
    }
  }
}

void LockScreen::onOutputChange() {
  if (m_lockDeferred) {
    if (m_wayland != nullptr && !m_wayland->outputs().empty()) {
      m_lockDeferred = false;
      (void)lock();
    }
    return;
  }
  if (!isActive()) {
    return;
  }
  syncInstances();
}

void LockScreen::onThemeChanged() {
  if (!isActive()) {
    return;
  }
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      if (m_configService != nullptr) {
        instance.surface->setWallpaperFillColor(resolveWallpaperFillColor(m_configService->config().wallpaper));
      }
      instance.surface->onThemeChanged();
    }
  }
}

void LockScreen::onGpuResourcesInvalidated() {
  if (!isActive()) {
    return;
  }
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      instance.surface->onGpuResourcesInvalidated();
    }
  }
}

void LockScreen::prepareForGraphicsReset() noexcept {
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      instance.surface->prepareForGraphicsReset();
    }
  }
}

void LockScreen::onConfigChanged() {
  if (m_configService == nullptr) {
    return;
  }
  if (!m_configService->isLockScreenEnabled()) {
    if (isActive()) {
      unlock();
    }
    return;
  }
  if (!isActive()) {
    return;
  }
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      applyLockscreenStyle(*instance.surface);
    }
  }
  applyOutputRestriction();
  applyWallpaperStyleToSurfaces();
  requestUpdate();
  requestLayout();
}

void LockScreen::onWallpaperChanged() {
  if (!isActive() || m_configService == nullptr) {
    return;
  }
  if (!m_configService->config().lockscreen.wallpaper.empty()) {
    return;
  }
  applyWallpaperStyleToSurfaces();
  requestLayout();
}

void LockScreen::onPointerEvent(const PointerEvent& event) {
  if (!isActive()) {
    return;
  }

  if (event.type == PointerEvent::Type::Enter && event.surface != nullptr) {
    m_pointerSurface = event.surface;
  } else if (event.type == PointerEvent::Type::Leave && event.surface == m_pointerSurface) {
    m_pointerSurface = nullptr;
  } else if (
      (event.type == PointerEvent::Type::Button || event.type == PointerEvent::Type::Axis) && event.surface != nullptr
  ) {
    m_pointerSurface = event.surface;
  }

  wl_surface* target = event.surface != nullptr ? event.surface : m_pointerSurface;
  if (target == nullptr) {
    return;
  }

  for (auto& instance : m_instances) {
    if (instance.surface->wlSurface() == target) {
      instance.surface->onPointerEvent(event);
      return;
    }
  }
}

void LockScreen::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isActive()) {
    return;
  }
  if (!m_locked) {
    return;
  }
  if (!event.pressed) {
    return;
  }

  // The password field always owns plain printable keys; Space is a Validate
  // chord but must type a space, not submit (passwords may contain spaces).
  if (!isPlainPrintableKey(event.utf32, event.modifiers, event.preedit)
      && KeybindMatcher::matches(KeybindAction::Validate, event.sym, event.modifiers)) {
    tryAuthenticate();
    return;
  }

  if (KeybindMatcher::matches(KeybindAction::Cancel, event.sym, event.modifiers)) {
    clearSensitiveString(m_password);
    m_status = i18n::tr("lockscreen.password-cleared");
    m_statusIsError = false;
    updatePromptOnSurfaces();
    return;
  }

  LockSurface* targetSurface = nullptr;
  if (m_pointerSurface != nullptr) {
    for (auto& instance : m_instances) {
      if (instance.surface != nullptr
          && !instance.surface->isBlackout()
          && instance.surface->wlSurface() == m_pointerSurface) {
        targetSurface = instance.surface.get();
        break;
      }
    }
  }
  if (targetSurface == nullptr) {
    for (auto& instance : m_instances) {
      if (instance.surface != nullptr && !instance.surface->isBlackout()) {
        targetSurface = instance.surface.get();
        break;
      }
    }
  }
  if (targetSurface != nullptr) {
    targetSurface->onKeyboardEvent(event);
  }
}

bool LockScreen::isActive() const noexcept { return m_lockPending || m_locked; }

bool LockScreen::isSessionLocked() const noexcept { return m_locked; }

bool LockScreen::tryFlushPendingAfterLocked() {
  if (m_locked && m_pendingAfterLocked && allSurfacesReady()) {
    auto pending = std::move(m_pendingAfterLocked);
    m_pendingAfterLocked = {};
    m_suspendTimeoutTimer.stop();
    DeferredCall::callLater(std::move(pending));
    return true;
  }
  return false;
}

void LockScreen::dispatchPendingAfterLocked() {
  if (m_pendingAfterLocked) {
    auto pending = std::move(m_pendingAfterLocked);
    m_pendingAfterLocked = {};
    m_suspendTimeoutTimer.stop();
    DeferredCall::callLater(std::move(pending));
  }
}

void LockScreen::runAfterSessionLocked(std::function<void()> fn) {
  if (fn == nullptr) {
    return;
  }
  m_pendingAfterLocked = std::move(fn);
  if (tryFlushPendingAfterLocked()) {
    return;
  }
  if (isActive()) {
    return;
  }
  if (!lock()) {
    m_pendingAfterLocked = {};
  }
}

void LockScreen::handleLocked(void* data, ext_session_lock_v1* /*lock*/) {
  auto* self = static_cast<LockScreen*>(data);
  // Ignore locked events after unlock()/handleFinished() tore down the lock object.
  // A late event would re-engage the locked state with no matching unlock hook.
  if (self->m_lock == nullptr || !self->m_lockPending) {
    return;
  }
  self->m_lockPending = false;
  self->m_locked = true;
  // Idle status is empty; the surface renders the password hint itself.
  self->m_status.clear();
  self->m_statusIsError = false;
  for (auto& instance : self->m_instances) {
    instance.surface->setLockedState(true);
    instance.surface->setOnLogin([self]() { self->tryAuthenticate(); });
  }

  // Start the fallback timer (3 seconds) to trigger suspend anyway if surfaces take too long to render
  self->m_suspendTimeoutTimer.start(std::chrono::seconds(3), [self]() {
    if (self->m_pendingAfterLocked) {
      kLog.warn("Lock screen surfaces took too long to render; suspending fallback triggered");
      auto pending = std::move(self->m_pendingAfterLocked);
      self->m_pendingAfterLocked = {};
      DeferredCall::callLater(std::move(pending));
    }
  });

  self->updatePromptOnSurfaces();
  self->updateIndicatorsOnSurfaces();
  self->startFingerprint();
  kLog.info("session is locked");
  if (self->m_onSessionLocked) {
    self->m_onSessionLocked();
  }
  self->tryFlushPendingAfterLocked();
}

void LockScreen::handleFinished(void* data, ext_session_lock_v1* /*lock*/) {
  auto* self = static_cast<LockScreen*>(data);
  kLog.info("session lock finished by compositor");
  const bool wasLockedInteractive = self->m_locked;
  self->m_pendingAfterLocked = {};
  self->invalidatePendingAuthentication();
  self->stopFingerprint();

  if (self->m_lock != nullptr) {
    if (self->m_locked) {
      ext_session_lock_v1_unlock_and_destroy(self->m_lock);
    } else {
      ext_session_lock_v1_destroy(self->m_lock);
    }
    self->m_lock = nullptr;
  }
  self->m_lockPending = false;
  self->m_locked = false;
  clearSensitiveString(self->m_password);
  self->m_status.clear();
  self->m_statusIsError = false;
  self->m_desktopCaptures.clear();
  self->m_desktopCapturesPrimed = false;
  if (wasLockedInteractive && self->m_onSessionUnlocked) {
    self->m_onSessionUnlocked();
  } else if (!wasLockedInteractive && self->m_onLockAborted) {
    self->m_onLockAborted();
  }
  self->clearInstances();
  self->m_pointerSurface = nullptr;
}

void LockScreen::syncInstances() {
  if (m_wayland == nullptr) {
    return;
  }

  const auto& outputs = m_wayland->outputs();

  std::erase_if(m_instances, [&](Instance& instance) {
    const auto it = std::ranges::find(outputs, instance.outputName, &WaylandOutput::name);
    const bool exists = it != outputs.end() && it->done && it->output != nullptr && it->hasUsableGeometry();
    if (!exists && instance.surface != nullptr && instance.surface->wlSurface() == m_pointerSurface) {
      m_pointerSurface = nullptr;
    }
    return !exists;
  });

  for (auto& instance : m_instances) {
    const auto it = std::ranges::find(outputs, instance.outputName, &WaylandOutput::name);
    if (it == outputs.end() || instance.surface == nullptr) {
      continue;
    }
    instance.surface->syncOutputScale(
        it->scale, it->configuredScaleNumerator > 0 ? static_cast<std::uint32_t>(it->configuredScaleNumerator) : 1U
    );
  }

  for (const auto& output : outputs) {
    if (!output.done || output.output == nullptr || !output.hasUsableGeometry()) {
      continue;
    }
    const bool exists = std::ranges::contains(m_instances, output.name, &Instance::outputName);
    if (!exists) {
      createInstance(output);
    }
  }

  applyOutputRestriction();
}

bool LockScreen::shouldUseBlurredDesktop() const {
  return m_configService != nullptr
      && m_configService->config().lockscreen.blurredDesktop
      && m_wayland != nullptr
      && m_wayland->hasScreencopy();
}

bool LockScreen::allSurfacesReady() const {
  for (const auto& instance : m_instances) {
    if (instance.surface != nullptr && !instance.surface->firstFrameRendered()) {
      return false;
    }
  }

  // With all outputs disconnected, no surface can ever render, so allow pending
  // actions to run instead of waiting for the fallback timeout.
  return true;
}

void LockScreen::primeDesktopCaptures() {
  if (m_configService != nullptr && !m_configService->isLockScreenEnabled()) {
    return;
  }
  if (isActive()) {
    return;
  }
  m_desktopCaptures.clear();
  m_desktopCapturesPrimed = false;
  if (!shouldUseBlurredDesktop()) {
    return;
  }
  captureDesktopSnapshots();
  m_desktopCapturesPrimed = true;
}

void LockScreen::clearPrimedDesktopCaptures() {
  if (!m_desktopCapturesPrimed) {
    return;
  }
  m_desktopCapturesPrimed = false;
  m_desktopCaptures.clear();
}

void LockScreen::captureDesktopSnapshots() {
  if (m_wayland == nullptr) {
    return;
  }

  ScreencopyCapture capture(*m_wayland);
  if (!capture.available()) {
    kLog.warn("blurred lockscreen requested but screencopy is unavailable");
    return;
  }

  for (const auto& output : m_wayland->outputs()) {
    if (!output.done || output.output == nullptr || !output.hasUsableGeometry() || !isInteractiveOutput(output)) {
      continue;
    }

    ScreencopyImage image;
    std::string error;
    if (!screencopy::captureOutputBlocking(capture, *m_wayland, output.output, image, error)) {
      kLog.warn("lockscreen desktop capture failed for {}: {}", output.connectorName, error);
      continue;
    }
    if (!screencopy::orientCaptureNative(image, *m_wayland, output.output)) {
      kLog.warn("lockscreen desktop capture orientation failed for {}", output.connectorName);
      continue;
    }
    m_desktopCaptures[output.output] = std::move(image);
  }
}

void LockScreen::applyLockscreenStyle(LockSurface& surface) const {
  if (m_configService == nullptr) {
    return;
  }
  const auto& lockscreen = m_configService->config().lockscreen;
  surface.setBackgroundStyle(lockscreen.blurIntensity, lockscreen.tintIntensity);
}

bool LockScreen::isInteractiveOutput(const WaylandOutput& output) const {
  if (m_configService == nullptr) {
    return true;
  }

  const auto& selectedMonitors = m_configService->config().lockscreen.monitors;
  if (selectedMonitors.empty()) {
    return true;
  }

  const bool anyConfiguredPresent =
      m_wayland != nullptr && std::ranges::any_of(m_wayland->outputs(), [&](const WaylandOutput& candidate) {
        return candidate.output != nullptr && std::ranges::any_of(selectedMonitors, [&](const std::string& match) {
                 return outputMatchesSelector(match, candidate);
               });
      });
  if (!anyConfiguredPresent) {
    return true;
  }

  return std::ranges::any_of(selectedMonitors, [&](const std::string& match) {
    return outputMatchesSelector(match, output);
  });
}

void LockScreen::applyOutputRestriction() {
  for (auto& instance : m_instances) {
    if (instance.surface == nullptr) {
      continue;
    }

    const WaylandOutput* output = nullptr;
    if (m_wayland != nullptr) {
      for (const auto& candidate : m_wayland->outputs()) {
        if (candidate.output == instance.output || candidate.connectorName == instance.connectorName) {
          output = &candidate;
          break;
        }
      }
    }

    const bool interactive = output != nullptr ? isInteractiveOutput(*output) : true;
    instance.surface->setBlackout(!interactive);
  }
  requestLayout();
}

std::string LockScreen::wallpaperPathForOutput(const std::string& connectorName) const {
  if (m_configService == nullptr) {
    return {};
  }
  const std::string& customWallpaper = m_configService->config().lockscreen.wallpaper;
  if (!customWallpaper.empty()) {
    return customWallpaper;
  }
  if (m_wallpaperPathFor) {
    return m_wallpaperPathFor(connectorName);
  }
  return m_configService->getWallpaperPath(connectorName);
}

void LockScreen::applyWallpaperStyleToSurfaces() {
  if (!isActive() || m_configService == nullptr) {
    return;
  }
  const auto& wallpaperConfig = m_configService->config().wallpaper;
  const WallpaperFillMode fillMode = wallpaperConfig.fillMode;
  const Color fillColor = resolveWallpaperFillColor(wallpaperConfig);
  for (auto& instance : m_instances) {
    if (instance.surface == nullptr || instance.surface->isBlackout() || instance.surface->hasDesktopCapture()) {
      continue;
    }
    instance.surface->setWallpaperPath(wallpaperPathForOutput(instance.connectorName));
    instance.surface->setWallpaperFillMode(fillMode);
    instance.surface->setWallpaperFillColor(fillColor);
  }
}

void LockScreen::createInstance(const WaylandOutput& output) {
  auto surface = std::make_unique<LockSurface>(*m_wayland, m_configService);
  surface->setRenderContext(m_renderContext);
  surface->setTextureCache(m_textureCache);
  surface->setLockedState(m_locked);
  applyLockscreenStyle(*surface);
  surface->setOutputKey(desktop_widgets::outputKey(output));
  if (m_configService != nullptr) {
    surface->setWallpaperPath(wallpaperPathForOutput(output.connectorName));
    surface->setWallpaperFillMode(m_configService->config().wallpaper.fillMode);
    surface->setWallpaperFillColor(resolveWallpaperFillColor(m_configService->config().wallpaper));
  }
  if (auto captureIt = m_desktopCaptures.find(output.output); captureIt != m_desktopCaptures.end()) {
    surface->setDesktopCapture(std::move(captureIt->second));
    m_desktopCaptures.erase(captureIt);
  }
  surface->setRenderCallback([this]() { tryFlushPendingAfterLocked(); });
  surface->setOnLogin([this]() { tryAuthenticate(); });
  surface->setOnCycleLayout([this]() { cycleKeyboardLayout(); });
  surface->setOnPasswordChanged([this](const std::string& value) { handlePasswordEdited(value); });
  surface->setLoginBoxServices(m_sessionActions, m_mpris, m_weather, m_httpClient);
  surface->setPromptState(m_user, m_password, m_status, m_statusIsError, m_authenticating);
  applyIndicatorsToSurface(*surface);

  surface->setBlackout(!isInteractiveOutput(output));

  if (!surface->initialize(m_lock, output.output, output.scale)) {
    kLog.warn("failed to create lock surface for output {}", output.name);
    return;
  }

  m_instances.push_back(
      Instance{
          .outputName = output.name,
          .output = output.output,
          .connectorName = output.connectorName,
          .surface = std::move(surface),
      }
  );
}

void LockScreen::resetLockState() {
  m_pendingAfterLocked = {};
  m_suspendTimeoutTimer.stop();
  m_lockDeferred = false;
  if (m_lock == nullptr) {
    m_lockPending = false;
    m_locked = false;
    return;
  }
  // unlock_and_destroy is required once the compositor may have entered the locked
  // state (including while m_lockPending is still true locally).
  ext_session_lock_v1_unlock_and_destroy(m_lock);
  m_lock = nullptr;
  m_lockPending = false;
  m_locked = false;
}

void LockScreen::clearInstances() { m_instances.clear(); }

void LockScreen::updatePromptOnSurfaces() {
  for (auto& instance : m_instances) {
    instance.surface->setPromptState(m_user, m_password, m_status, m_statusIsError, m_authenticating);
  }
}

void LockScreen::applyIndicatorsToSurface(LockSurface& surface) const {
  const bool capsLock = m_wayland != nullptr && m_wayland->keyboardLockKeysState().capsLock;
  bool hasMultipleLayouts = false;
  bool switchable = false;
  std::string layoutLabel;
  if (m_compositorPlatform != nullptr) {
    hasMultipleLayouts = m_compositorPlatform->keyboardLayoutNames().size() > 1;
    switchable = m_compositorPlatform->hasKeyboardLayoutBackend();
    const std::string layoutName = m_compositorPlatform->currentKeyboardLayoutName();
    layoutLabel = m_configService != nullptr
        ? resolveKeyboardLayoutLabel(
              layoutName, KeyboardLayoutDisplayMode::Short, m_configService->config().shell.keyboardLayout.customLabels
          )
        : formatKeyboardLayoutLabel(layoutName, KeyboardLayoutDisplayMode::Short);
  }
  surface.setKeyboardIndicators(capsLock, hasMultipleLayouts, switchable, std::move(layoutLabel));
}

void LockScreen::updateIndicatorsOnSurfaces() {
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      applyIndicatorsToSurface(*instance.surface);
    }
  }
}

void LockScreen::cycleKeyboardLayout() {
  if (m_compositorPlatform == nullptr || !m_compositorPlatform->cycleKeyboardLayout()) {
    return;
  }
  updateIndicatorsOnSurfaces();
}

void LockScreen::onLockKeysChanged() {
  if (!isActive()) {
    return;
  }
  updateIndicatorsOnSurfaces();
}

void LockScreen::onKeyboardLayoutChanged() {
  if (!isActive()) {
    return;
  }
  updateIndicatorsOnSurfaces();
}

void LockScreen::invalidatePendingAuthentication() {
  ++m_authGeneration;
  m_authenticating = false;
}

void LockScreen::handlePasswordEdited(const std::string& value) {
  if (m_authenticating) {
    m_password = value;
    updatePromptOnSurfaces();
    return;
  }
  if (m_password == value && m_status.empty() && !m_statusIsError) {
    return;
  }
  m_password = value;
  m_status.clear();
  m_statusIsError = false;
  updatePromptOnSurfaces();
}

void LockScreen::tryAuthenticate() {
  if (m_authenticating || !m_locked || m_unlockTransitionTimer.active()) {
    return;
  }
  if (m_password.empty()) {
    const bool allowEmptyPassword =
        m_configService != nullptr && m_configService->config().lockscreen.allowEmptyPassword;
    if (!allowEmptyPassword) {
      return;
    }
  }

  stopFingerprint();
  if (m_wayland != nullptr) {
    m_wayland->stopKeyRepeat();
  }

  std::string password = m_password;
  clearSensitiveString(m_password);

  const std::uint64_t generation = ++m_authGeneration;
  m_authenticating = true;
  m_status = i18n::tr("lockscreen.authenticating");
  m_statusIsError = false;
  updatePromptOnSurfaces();

  const PamAuthenticator authenticator = m_authenticator;
  // Authenticate against the "login" stack. If fingerprint is enabled, strip
  // pam_fprintd from it: zynith-shell drives the reader itself over D-Bus and the
  // two can't share the sensor. See docs/fingerprint.md.
  const std::string pamService = "login";
  const std::string pamLanguage(i18n::Service::instance().language());
  const std::string pamStartFailure = i18n::tr("auth.pam.start-failed");
  std::thread([this, generation, password = std::move(password), authenticator, pamService, pamLanguage,
               pamStartFailure]() mutable {
    const auto result = authenticator.authenticateCurrentUser(password, pamService, pamLanguage, pamStartFailure);
    clearSensitiveString(password);
    DeferredCall::callLater([this, generation, result]() { handleAuthResult(generation, result); });
  }).detach();
}

void LockScreen::handleAuthResult(std::uint64_t generation, PamAuthenticator::Result result) {
  if (generation != m_authGeneration || !m_locked) {
    return;
  }

  m_authenticating = false;

  if (result.success) {
    m_status = i18n::tr("lockscreen.unlocked");
    m_statusIsError = false;
    updatePromptOnSurfaces();
    beginUnlockTransition();
    return;
  }

  m_status = result.message.empty() ? i18n::tr("lockscreen.authentication-failed") : result.message;
  m_statusIsError = true;
  updatePromptOnSurfaces();
  startFingerprint();
}

void LockScreen::startFingerprint() {
  if (m_fingerprint == nullptr) {
    return;
  }
  if (m_configService != nullptr && !m_configService->config().lockscreen.fingerprint) {
    return;
  }
  m_fingerprint->start();
}

void LockScreen::stopFingerprint() {
  if (m_fingerprint != nullptr) {
    m_fingerprint->stop();
  }
}

// ── lockfade ────────────────────────────────────────────────────────────────
// Authentication has already succeeded when this runs. It only defers the unchanged unlock()
// by LockSurface::kExitDurationMs so the lock UI can fade out, then asks the compositor to
// crossfade from that frame (wallpaper only) back to the desktop.
void LockScreen::beginUnlockTransition() {
  if (m_unlockTransitionTimer.active()) {
    return;
  }
  // Wait exactly as long as the slowest surface's exit fades take on screen. The surfaces'
  // AnimationManager uses effective = base / [shell.animation].speed (MotionService clamps speed
  // to 0.05..4), and applies final values instantly when animations are disabled.
  float exitEndBaseMs = 0.0F;
  for (auto& instance : m_instances) {
    if (instance.surface != nullptr) {
      exitEndBaseMs = std::max(exitEndBaseMs, instance.surface->playExit());
    }
  }
  // Prepared now (invisible until unlock: the compositor shows only lock surfaces while locked).
  createUnlockVeils();
  const auto& motion = MotionService::instance();
  const float exitMs = motion.enabled() ? exitEndBaseMs / std::max(0.05F, motion.speed()) : 0.0F;
  kLog.info("unlock: authenticated; lock exit animation {:.0f} ms before the session unlocks", exitMs);
  m_unlockTransitionTimer.start(std::chrono::milliseconds(static_cast<int>(std::lround(exitMs))), [this]() {
    unlock();
  });
}

void LockScreen::createUnlockVeils() {
  m_unlockVeilSafetyTimer.stop();
  m_unlockVeils.clear();
  if (m_wayland == nullptr || m_renderContext == nullptr || m_configService == nullptr) {
    return;
  }
  const auto& config = m_configService->config();
  for (const auto& instance : m_instances) {
    if (instance.surface == nullptr || instance.output == nullptr) {
      continue;
    }
    // Draw exactly what the lock background draws: same source, blur, tint and fill.
    ScreenVeil::Style style{
        .nameSpace = "zynith-shell-unlock-veil",
        .layer = LayerShellLayer::Overlay,
        .blurIntensity = config.lockscreen.blurIntensity,
        .tintIntensity = config.lockscreen.tintIntensity,
        .fillMode = config.wallpaper.fillMode,
        .fillColor = resolveWallpaperFillColor(config.wallpaper),
    };
    auto veil = std::make_unique<ScreenVeil>(*m_wayland, m_renderContext, m_textureCache);
    bool ok = false;
    if (instance.surface->isBlackout()) {
      style.blurIntensity = 0.0F;
      style.tintIntensity = 0.0F;
      style.fillColor = rgba(0.0F, 0.0F, 0.0F, 1.0F);
      ok = veil->showWallpaper(instance.output, {}, style, 1.0F);
    } else if (const auto it = m_desktopCaptures.find(instance.output); it != m_desktopCaptures.end()) {
      ok = veil->showImage(instance.output, it->second, style, 1.0F); // blurred_desktop mode
    } else {
      ok = veil->showWallpaper(instance.output, wallpaperPathForOutput(instance.connectorName), style, 1.0F);
    }
    if (ok) {
      m_unlockVeils.push_back(std::move(veil));
    }
  }
}

void LockScreen::fadeOutUnlockVeils() {
  // A veil that never produced a frame would appear *after* the desktop and flash; drop it.
  std::erase_if(m_unlockVeils, [](const std::unique_ptr<ScreenVeil>& veil) { return !veil->ready(); });
  if (m_unlockVeils.empty()) {
    return;
  }
  // zynith: the veil is the lock background lifting off a desktop that was never torn down — the workspace and
  // its windows kept existing under the lock surface. It fades with the scene-reveal role (symmetric ease-in-out,
  // 420 ms base / [shell.animation] speed) and the fade starts on the veil's first presented frame, not here:
  // the old 210 ms ease-out, clocked from this call, was typically a third faded on the first visible frame and
  // two thirds by ~75 ms, which read as the desktop popping in. Input already goes to the desktop.
  kLog.info("unlock: veil reveal requested");
  auto clearVeils = [this]() {
    DeferredCall::callLater([this]() {
      kLog.info("unlock: veil reveal finished");
      m_unlockVeils.clear();
    });
  };
  for (auto& veil : m_unlockVeils) {
    veil->fadeOutOnPresent(motion::Role::SceneReveal, clearVeils);
  }
  // Belt and braces: never let a veil outlive the handoff, even if frames stop (e.g. DPMS off).
  m_unlockVeilSafetyTimer.start(std::chrono::milliseconds(2000), [this]() { m_unlockVeils.clear(); });
}

void LockScreen::requestCompositorCrossfade(std::uint16_t delayMs) const {
  // niri's native frozen-frame crossfade over its existing IPC connection; no-op elsewhere.
  if (m_compositorPlatform == nullptr || compositors::detect() != compositors::CompositorKind::Niri) {
    return;
  }
  (void)m_compositorPlatform->niriRuntime().requestAction(
      nlohmann::json{{"DoScreenTransition", nlohmann::json{{"delay_ms", delayMs}}}}, true
  );
}

void LockScreen::handleFingerprintStatus(const std::string& message, bool isError) {
  if (!isActive()) {
    return;
  }
  // Don't clobber a password the user is typing.
  if (!m_password.empty()) {
    return;
  }
  // Empty message means verification disarmed; fall back to the idle prompt (rendered by the surface).
  m_status = message.empty() ? std::string{} : message;
  m_statusIsError = isError;
  updatePromptOnSurfaces();
}

void LockScreen::clearSensitiveString(std::string& value) {
  // zynith: the whole capacity, not just size() (security/sensitive_string.h).
  security::wipeString(value);
}
