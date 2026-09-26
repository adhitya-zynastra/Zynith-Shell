#pragma once

// zynith: Live wallpaper controller — the one place that decides what the desktop background is.
//
//   Wallpaper panel (UI) ──► LiveWallpaperController ──► LiveWallpaperProvider (WallpaperEngineProvider)
//                                   │                          discovery · metadata · previews · launch spec
//                                   ├──► LiveRendererProcess   the one external renderer
//                                   ├──► Wallpaper             static backend (hand-over of the outputs)
//                                   └──► ConfigService         state.toml persistence · palette source
//
// Ownership model. Static mode: Zynith's own wallpaper surfaces (noctalia-wallpaper) own every output.
// Live mode: the renderer owns them and the static surfaces are torn down through
// Wallpaper::setOutputExternallyManaged() — the hook upstream built for external wallpaper sources — so two
// surfaces never fight over the background layer and the static textures are freed while hidden.
//
// Hand-over order is chosen so the desktop is never left bare:
//   Static -> Live   start renderer; only once it has survived its startup grace are the static surfaces
//                    released (until then the static wallpaper stays on screen underneath).
//   Live -> Static   static surfaces come back first, then the renderer is stopped.
//   Live -> Live     old renderer stopped, new one started after the old has exited — never two at once.
//   Failure          static surfaces come back immediately; a failed switch falls back to the last
//                    wallpaper that ran; a renderer that crashes after running a while is restarted once.
//
// Persistence: stable identifiers only (provider id + Workshop id), in state.toml under [wallpaper_live].
// Never a path into Steam and never a copy of Workshop content.

#include "core/timer_manager.h"
#include "shell/wallpaper/live/live_renderer_process.h"
#include "shell/wallpaper/live/live_wallpaper_provider.h"
#include "ui/signal.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class ConfigService;
class IpcService;
class Wallpaper;
class WaylandConnection;

class LiveWallpaperController {
public:
  enum class Mode : std::uint8_t { Static, Live };
  enum class Category : std::uint8_t { Collection, Favorites, Recent, Installed };
  enum class CarouselOrder : std::uint8_t { Sequential, Shuffle };

  // Interval presets offered by the panel; IPC accepts any value >= kMinCarouselInterval.
  static constexpr std::array<std::int32_t, 5> kCarouselIntervalPresets{60, 300, 900, 1800, 3600};
  static constexpr std::int32_t kMinCarouselInterval = 10;
  static constexpr std::size_t kRecentLimit = 16;

  LiveWallpaperController();
  ~LiveWallpaperController();

  LiveWallpaperController(const LiveWallpaperController&) = delete;
  LiveWallpaperController& operator=(const LiveWallpaperController&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService& config, Wallpaper& wallpaper);
  // Called from Application::reconcileOutputSurfaces() after the static wallpaper reconciled. The first
  // call resumes a persisted Live selection.
  void onOutputChange();
  void registerIpc(IpcService& ipc);
  // Carousel rotation is suspended while this returns false (lock screen), like static automation.
  void setAutomationGate(std::function<bool()> gate) { m_automationGate = std::move(gate); }
  void shutdown();

  [[nodiscard]] LiveRendererProcess& process() noexcept { return m_process; }
  [[nodiscard]] LiveWallpaperProvider& provider() noexcept { return *m_provider; }

  // ── Selection ───────────────────────────────────────────────────────────
  [[nodiscard]] Mode mode() const noexcept { return m_mode; }
  // What Live mode shows (or will show): the persisted Workshop id.
  [[nodiscard]] const std::string& currentId() const noexcept { return m_currentId; }
  // Switches to Live mode with this item. Returns false with a reason when it cannot even be launched
  // (invalid id, not installed, unsupported type, renderer missing). Startup failures are reported
  // asynchronously through lastError()/changed().
  bool select(const std::string& id, std::string* error = nullptr);
  void switchToStatic();

  // ── Library views (UI) ──────────────────────────────────────────────────
  [[nodiscard]] std::vector<const live::Item*> itemsFor(Category category) const;
  [[nodiscard]] std::size_t unsupportedCount() const;
  [[nodiscard]] bool isFavorite(const std::string& id) const;
  [[nodiscard]] bool isInCollection(const std::string& id) const;
  void toggleFavorite(const std::string& id);
  void toggleCollection(const std::string& id);
  [[nodiscard]] Category category() const noexcept { return m_category; }
  void setCategory(Category category);

  // ── Carousel ────────────────────────────────────────────────────────────
  [[nodiscard]] bool carouselEnabled() const noexcept { return m_carouselEnabled; }
  [[nodiscard]] std::int32_t carouselInterval() const noexcept { return m_carouselInterval; }
  [[nodiscard]] CarouselOrder carouselOrder() const noexcept { return m_carouselOrder; }
  void setCarouselEnabled(bool enabled);
  void setCarouselInterval(std::int32_t seconds);
  void setCarouselOrder(CarouselOrder order);
  // Moves to the next collection item now. False when there is nothing to move to.
  bool advanceCarousel(std::string* error = nullptr);

  // ── Status ──────────────────────────────────────────────────────────────
  [[nodiscard]] const std::string& lastError() const noexcept { return m_lastError; }
  [[nodiscard]] std::string statusLine() const;
  [[nodiscard]] std::string statusJson() const;
  // Emits on any change the UI shows: mode, current item, favourites/collection, renderer state, catalog.
  [[nodiscard]] Signal<>& changed() noexcept { return m_changed; }

private:
  struct Pending {
    live::Item item;
    live::LaunchSpec spec;
    std::vector<std::string> outputs;
    bool isFallback = false;
    bool isRestart = false;
  };

  void loadState();
  void saveList(const char* key, const std::vector<std::string>& ids);
  [[nodiscard]] std::vector<std::string> currentOutputs() const;
  [[nodiscard]] std::optional<live::Item> lookup(const std::string& id, std::string* error);
  bool activate(const std::string& id, std::string* error, bool isFallback, bool isRestart);
  void startPending();
  void onRendererStarted();
  void onRendererExited(const LiveRendererProcess::Exit& exit);
  void handOverToLive(const std::vector<std::string>& outputs);
  void restoreStatic();
  void armCarousel();
  void onCarouselTimer();
  [[nodiscard]] std::vector<std::string> carouselCandidates() const;
  void pushRecent(const std::string& id);
  void setError(std::string message);
  void notify();

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  Wallpaper* m_wallpaper = nullptr;
  std::unique_ptr<LiveWallpaperProvider> m_provider;
  LiveRendererProcess m_process;

  Mode m_mode = Mode::Static;
  std::string m_currentId;
  // The item the running renderer shows, and the last one that ran successfully (failure fallback).
  std::optional<live::Item> m_activeItem;
  std::string m_lastGoodId;
  std::optional<Pending> m_pending;
  std::vector<std::string> m_renderOutputs;
  // Outputs whose static surface is currently released to the renderer.
  std::vector<std::string> m_managedOutputs;
  bool m_resumed = false;
  bool m_shuttingDown = false;
  std::chrono::steady_clock::time_point m_lastAutoRestart{};

  std::vector<std::string> m_favorites;
  std::vector<std::string> m_collection;
  std::vector<std::string> m_recent;
  Category m_category = Category::Installed;
  bool m_carouselEnabled = false;
  std::int32_t m_carouselInterval = 300;
  CarouselOrder m_carouselOrder = CarouselOrder::Sequential;
  Timer m_carouselTimer;
  Timer m_restartTimer;
  std::function<bool()> m_automationGate;

  std::string m_lastError;
  Signal<> m_changed;
};
