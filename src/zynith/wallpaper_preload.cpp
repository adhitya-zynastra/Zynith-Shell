#include "zynith/wallpaper_preload.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "render/core/image_file_loader.h"

#include <stb/stb_image_resize2.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <future>
#include <utility>

namespace zynith {

  namespace {
    constexpr Logger kLog("wallpaper-preload");

    // shrink to the smallest size that still covers bounds (never enlarge); the renderer scales from there
    void coverResize(LoadedImageFile& image, int boundsW, int boundsH) {
      if (boundsW <= 0 || boundsH <= 0 || image.width <= 0 || image.height <= 0) {
        return;
      }
      const double scale = std::max(static_cast<double>(boundsW) / image.width, static_cast<double>(boundsH) / image.height);
      if (scale >= 1.0) {
        return;
      }
      const int w = std::max(1, static_cast<int>(std::ceil(image.width * scale)));
      const int h = std::max(1, static_cast<int>(std::ceil(image.height * scale)));
      std::vector<std::uint8_t> out(static_cast<std::size_t>(w) * static_cast<std::size_t>(h) * 4U);
      if (stbir_resize_uint8_srgb(image.rgba.data(), image.width, image.height, 0, out.data(), w, h, 0, STBIR_RGBA)
          != nullptr) {
        image.rgba = std::move(out);
        image.width = w;
        image.height = h;
      }
    }
  } // namespace

  WallpaperPreload::WallpaperPreload(Done done) : m_done(std::move(done)), m_thread([this]() { run(); }) {}

  WallpaperPreload::~WallpaperPreload() {
    {
      std::scoped_lock lock(m_mutex);
      m_stop = true;
      m_pending.reset();
    }
    m_cv.notify_one();
    m_alive.reset();
    // a decode in progress finishes first (it cannot be interrupted); its result is discarded
    if (m_thread.joinable()) {
      m_thread.join();
    }
  }

  std::uint64_t WallpaperPreload::submit(Job job) {
    std::uint64_t generation = 0;
    {
      std::scoped_lock lock(m_mutex);
      generation = ++m_generation;
      m_pending = std::move(job);
    }
    m_cv.notify_one();
    return generation;
  }

  std::uint64_t WallpaperPreload::latest() const {
    std::scoped_lock lock(m_mutex);
    return m_generation;
  }

  void WallpaperPreload::run() {
    const std::weak_ptr<int> alive = m_alive;
    for (;;) {
      Job job;
      std::uint64_t generation = 0;
      {
        std::unique_lock lock(m_mutex);
        m_cv.wait(lock, [this]() { return m_stop || m_pending.has_value(); });
        if (m_stop) {
          return;
        }
        job = std::move(*m_pending);
        m_pending.reset();
        generation = m_generation;
      }

      const auto started = std::chrono::steady_clock::now();
      Result result;
      result.generation = generation;

      // the palette's decode (a 112x112 sample) runs beside the wallpaper's
      std::future<std::optional<noctalia::theme::ThemeService::PrimedWallpaperPalette>> palette;
      if (!job.palettePath.empty()) {
        palette = std::async(std::launch::async, [path = job.palettePath, scheme = job.paletteScheme]() {
          return noctalia::theme::ThemeService::computeWallpaperPalette(path, scheme);
        });
      }
      for (const auto& path : job.paths) {
        if (latest() != generation) {
          break; // a newer change is waiting: stop here, it decodes what it needs
        }
        auto loaded = loadImageFile(path, 0);
        if (!loaded) {
          kLog.warn("could not decode {}: {}", path, loaded.error());
          continue;
        }
        coverResize(*loaded, job.coverWidth, job.coverHeight);
        result.images.push_back(Image{
            .path = path, .rgba = std::move(loaded->rgba), .width = loaded->width, .height = loaded->height
        });
      }
      if (palette.valid()) {
        result.palette = palette.get();
      }
      result.decodeMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();

      if (latest() != generation) {
        continue; // superseded while decoding: nothing to deliver
      }
      DeferredCall::callLater([this, alive, result = std::move(result)]() mutable {
        if (alive.expired() || result.generation != latest()) {
          return;
        }
        m_done(std::move(result));
      });
    }
  }

} // namespace zynith
