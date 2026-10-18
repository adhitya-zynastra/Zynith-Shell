#pragma once

// zynith: Wallpaper Engine provider (Steam Workshop app 431960, rendered by linux-wallpaperengine).
//
// Discovery reads each installed item's project.json on a worker thread (never on the UI thread) and keeps
// the catalog in memory for the shell's lifetime; a later refresh(false) only re-walks when a Workshop
// content folder's mtime changed (subscribing/unsubscribing adds/removes a folder there). Measured on the
// owner's 560-item library: see docs 03_Performance/benchmarks/live-wallpaper.md.
//
// Previews are the author's own preview image inside the Workshop folder (preview.jpg/.gif/.png — present
// for all 560 items on a test machine). They are handed to the shell's ThumbnailService as-is, which
// decodes them on its workers and persists a small WebP per size in ~/.cache/noctalia/thumbnails, keyed by
// path + size + mtime: so nothing is re-decoded until Steam actually updates the item, and no live renderer
// is ever launched just to produce a thumbnail.

#include "shell/wallpaper/live/live_wallpaper_provider.h"
#include "shell/wallpaper/live/wallpaper_engine_catalog.h"

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <utility>

class ConfigService;

class WallpaperEngineProvider final : public LiveWallpaperProvider {
public:
  explicit WallpaperEngineProvider(ConfigService* config);
  ~WallpaperEngineProvider() override;

  WallpaperEngineProvider(const WallpaperEngineProvider&) = delete;
  WallpaperEngineProvider& operator=(const WallpaperEngineProvider&) = delete;

  [[nodiscard]] std::string_view id() const override { return live::wallpaper_engine::kProviderId; }
  [[nodiscard]] std::string displayName() const override;

  void refresh(bool force) override;
  [[nodiscard]] bool discovering() const override { return m_discovering; }
  [[nodiscard]] bool discovered() const override { return m_discovered; }
  [[nodiscard]] const std::vector<live::Item>& items() const override { return m_items; }
  [[nodiscard]] const live::Item* find(std::string_view id) const override;
  [[nodiscard]] const std::string& problem() const override { return m_problem; }

  [[nodiscard]] std::expected<live::Item, std::string> resolve(std::string_view id) override;
  [[nodiscard]] std::expected<live::LaunchSpec, std::string> launchSpec(
      const live::Item& item, const std::vector<std::string>& outputs, const WallpaperLiveConfig& config
  ) override;

  // Where renderer scratch directories (the child's TMPDIR) are created. Stale ones left by a crashed shell
  // are removed by the controller at startup.
  [[nodiscard]] static std::filesystem::path scratchRoot();

private:
  struct ScanResult {
    live::wallpaper_engine::Layout layout;
    std::vector<live::Item> items;
    std::vector<std::pair<std::filesystem::path, std::filesystem::file_time_type>> stamps;
    double elapsedMs = 0.0;
  };

  [[nodiscard]] std::vector<std::filesystem::path> steamRoots() const;
  [[nodiscard]] bool catalogIsFresh() const;
  void applyScan(ScanResult result);
  // Layout for synchronous callers: the discovered one, else resolved on the spot (a handful of stats).
  [[nodiscard]] const live::wallpaper_engine::Layout& layout();
  [[nodiscard]] static std::string layoutProblem(const live::wallpaper_engine::Layout& layout);

  ConfigService* m_config = nullptr;
  std::vector<live::Item> m_items;
  std::unordered_map<std::string, std::size_t> m_index;
  std::optional<live::wallpaper_engine::Layout> m_layout;
  std::vector<std::pair<std::filesystem::path, std::filesystem::file_time_type>> m_stamps;
  std::string m_problem;
  bool m_discovering = false;
  bool m_discovered = false;
  bool m_refreshQueued = false;
  std::thread m_worker;
  // Guards the worker's result hand-off against provider destruction: the posted main-thread callback
  // checks it before touching `this`.
  std::shared_ptr<std::atomic<bool>> m_alive = std::make_shared<std::atomic<bool>>(true);
  std::uint64_t m_scratchCounter = 0;
};
