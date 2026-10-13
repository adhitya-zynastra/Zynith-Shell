#pragma once

#include "config/config_types.h"
#include "shell/wallpaper/wallpaper_shuffle_state.h"
#include "ui/signal.h"

#include <chrono>
#include <optional>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

class ConfigService;
class IpcService;
class RenderContext;
class SharedTextureCache;
class WaylandConnection;
enum class ThemeMode : std::uint8_t;
enum class WallpaperTransitionDirection;
struct TextureHandle;
struct WallpaperInstance;
struct PointerEvent;
struct WaylandOutput;
struct wl_surface;

namespace noctalia::theme {
  class ThemeService;
}

struct WallpaperChange {
  std::string path;
  std::string connector;
};

class Wallpaper {
public:
  Wallpaper();
  ~Wallpaper();

  bool initialize(
      WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext, SharedTextureCache* textureCache,
      noctalia::theme::ThemeService* themeService = nullptr
  );
  void onOutputChange();
  // Mark an output as driven by an external wallpaper source (e.g. an mpvpaper plugin):
  // its Background surface is torn down so the external surface shows through. Runtime-only
  // (not persisted) — it clears on restart and is re-asserted by the owner.
  void setOutputExternallyManaged(const std::string& connector, bool managed);
  // zynith: runtime-only image shown instead of the configured wallpaper (never persisted, never touches
  // settings.toml). The live wallpaper controller uses it as a "poster frame" — the next live item's preview —
  // so a renderer switch never exposes the compositor's empty background. `instant` skips the startup
  // transition for surfaces created while it is set (the poster must be opaque on its first frame); surfaces
  // that already exist transition to it as to any wallpaper. An empty path restores the configured wallpaper.
  void setTransientImage(const std::string& path, bool instant);
  [[nodiscard]] const std::string& transientImage() const noexcept { return m_transientPath; }
  // True when every wallpaper surface shows its target (transient or configured) with no transition running.
  // Vacuously true with no surfaces. changed() fires whenever this may have become true.
  [[nodiscard]] bool settled() const;
  [[nodiscard]] bool hasInstances() const noexcept { return !m_instances.empty(); }
  // zynith: early background (Application::paintEarlyBackground): surfaces created while set show their image
  // immediately instead of running transition_on_startup, which cannot animate before the main loop runs.
  void setStartupTransitionSuppressed(bool suppressed) noexcept { m_startupTransitionSuppressed = suppressed; }
  [[nodiscard]] std::vector<WallpaperChange> onStateChange();
  void onSecondTick();
  void onGpuResourcesInvalidated();
  void registerIpc(IpcService& ipc);
  // Apply and persist a wallpaper image. nullopt connector targets all connected
  // outputs plus the default. Returns false if the path does not exist or the
  // connector is unknown. Shared by the wallpaper-set IPC handler and plugin scripts.
  bool applyWallpaperImage(const std::optional<std::string>& connector, const std::string& path);
  void setAutomationGate(std::function<bool()> gate);
  [[nodiscard]] bool ownsSurface(wl_surface* surface) const noexcept;
  bool onPointerEvent(const PointerEvent& event);

  // zynith: the images a state change is about to show (configured or transient, not yet current or on its
  // way), each once — what Application decodes off the main thread before running the change
  [[nodiscard]] std::vector<std::string> upcomingImagePaths() const;
  // zynith: the size a wallpaper needs to cover the largest output, in buffer pixels; {0, 0} when the fill mode
  // shows the image at its own size (center, repeat, span), so it must be decoded whole
  [[nodiscard]] std::pair<int, int> coverBounds() const;

  [[nodiscard]] TextureHandle currentTexture() const;
  [[nodiscard]] std::string currentPath() const;

  // Emits whenever the displayed wallpaper (path/texture) changes, including
  // automation rotation and transition completion. Lets consumers pre-warm
  // previews while their UI is closed.
  [[nodiscard]] Signal<>& changed() noexcept { return m_changed; }

private:
  enum class TransitionRedirect {
    Unrelated,
    AlreadyTargeting,
    Redirected,
  };

  enum class PickWallpaper {
    Random,
    Previous,
    Next,
  };

  enum class SwitchOutcome {
    Changed,     // at least one output was switched to a new wallpaper
    NoChange,    // wallpapers were found but there was nothing new to switch to
    Unavailable, // wallpaper disabled, target unknown, or no candidate images
  };

  [[nodiscard]] bool isConnectorKnown(std::string_view connector) const;
  // Persist a resolved image path to a single connector, or to every connected
  // output plus the default when no connector is given.
  void applyResolvedWallpaper(const std::optional<std::string>& connector, const std::string& resolvedPath);
  void reload();
  void syncInstances();
  void applyStartupAutomation(std::int64_t secondStamp);
  void resetAutomationState();
  void runAutomation(std::int64_t secondStamp);
  [[nodiscard]] bool automationAllowed() const noexcept;
  [[nodiscard]] SwitchOutcome
  switchWallpaperTo(PickWallpaper action, std::optional<std::string_view> connector = std::nullopt);
  [[nodiscard]] ThemeMode directoryThemeMode() const noexcept;
  [[nodiscard]] std::string pickRandomWallpaperPath(
      const std::vector<std::string>& candidates, const std::string& currentPath, std::string_view scope,
      std::string_view source
  );
  [[nodiscard]] std::string pickAutomationWallpaperPath(
      const WallpaperAutomationConfig& automation, std::vector<std::string> candidates, const std::string& currentPath,
      std::string_view scope, std::string_view source
  );
  void createInstance(const WaylandOutput& output);
  [[nodiscard]] TextureHandle acquireTexture(const std::string& path);
  void releaseTexture(TextureHandle& handle, const std::string& path);
  void loadWallpaper(WallpaperInstance& instance, const std::string& path);
  TransitionRedirect redirectActiveTransition(WallpaperInstance& instance, const std::string& path);
  void startTransition(WallpaperInstance& instance);
  // zynith: a newer wallpaper is waiting — finish the running transition quickly instead of playing it out
  void hurryTransition(WallpaperInstance& instance);
  void startTransitionAnimation(WallpaperInstance& instance, float fromTime, WallpaperTransitionDirection direction);
  void finishTransition(WallpaperInstance& instance);
  void promotePendingWallpaper(WallpaperInstance& instance);
  void discardPendingWallpaper(WallpaperInstance& instance);
  void runQueuedWallpaper(WallpaperInstance& instance);
  void updateRendererState(WallpaperInstance& instance);
  void releaseInstanceTextures(WallpaperInstance& inst);
  [[nodiscard]] std::string displayPathFor(const std::string& connector) const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  noctalia::theme::ThemeService* m_themeService = nullptr;
  bool m_wallpaperEnabled = false;
  WallpaperConfig m_lastWallpaperConfig{};
  std::int64_t m_lastAutomationSecondStamp = -1;
  std::int64_t m_lastAutomationSwitchSecond = -1;
  std::function<bool()> m_automationGate;
  wallpaper::ShuffleState m_shuffleState;
  Signal<>::ScopedConnection m_paletteConn;
  Signal<> m_changed;
  std::vector<std::unique_ptr<WallpaperInstance>> m_instances;
  std::unordered_set<std::string> m_externallyManagedOutputs;
  // zynith: the next transition on this connector grows from this point (wallpaper-reveal), once, if it starts soon
  struct RevealOrigin {
    std::string connector;
    float x = 0.5F;
    float y = 0.5F;
    std::chrono::steady_clock::time_point at;
  };
  std::optional<RevealOrigin> m_revealOrigin;
  std::string m_transientPath;
  bool m_transientInstant = false;
  bool m_startupTransitionSuppressed = false;
};
