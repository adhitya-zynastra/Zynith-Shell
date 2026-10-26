#pragma once

#include "theme/theme_service.h"

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace zynith {

  // Decodes the wallpaper a change is about to show off the main thread, so the change itself (renderer, backdrop,
  // lock screen, theme) finds everything ready and costs the main loop only an upload.
  //
  // One worker and one slot: a job that has not started is replaced by a newer one, and a finished job whose
  // generation is no longer the latest is dropped where it lands. Flicking through wallpapers decodes at most the
  // one in progress plus the last one asked for, never every image passed over, and memory stays at one decode.
  class WallpaperPreload {
  public:
    struct Job {
      std::vector<std::string> paths;
      // the size each image must cover (buffer pixels); 0 x 0 keeps the file's own size
      int coverWidth = 0;
      int coverHeight = 0;
      // the wallpaper the palette comes from, and its scheme ("" when the palette does not follow the wallpaper)
      std::string palettePath;
      std::string paletteScheme;
    };
    struct Image {
      std::string path;
      std::vector<std::uint8_t> rgba;
      int width = 0;
      int height = 0;
    };
    struct Result {
      std::uint64_t generation = 0;
      std::vector<Image> images;
      std::optional<zynith::theme::ThemeService::PrimedWallpaperPalette> palette;
      double decodeMs = 0;
    };
    // called on the main thread, for the latest job only
    using Done = std::function<void(Result)>;

    explicit WallpaperPreload(Done done);
    ~WallpaperPreload();

    WallpaperPreload(const WallpaperPreload&) = delete;
    WallpaperPreload& operator=(const WallpaperPreload&) = delete;

    std::uint64_t submit(Job job);
    [[nodiscard]] std::uint64_t latest() const;

  private:
    void run();

    Done m_done;
    mutable std::mutex m_mutex;
    std::condition_variable m_cv;
    std::optional<Job> m_pending;
    std::uint64_t m_generation = 0;
    bool m_stop = false;
    // dropped on destruction: a result still on its way to the main loop is then discarded
    std::shared_ptr<int> m_alive = std::make_shared<int>(0);
    std::thread m_thread;
  };

} // namespace zynith
