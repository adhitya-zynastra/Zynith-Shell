#pragma once

// zynith: a source of live wallpapers. Wallpaper Engine is the first provider; the controller and UI only
// see this interface, so a second source (e.g. mpvpaper over a video folder) plugs in without touching
// either. A provider owns everything source-specific: discovery, metadata, preview images, where the
// content lives, and how its renderer must be invoked.

#include "shell/wallpaper/live/live_wallpaper_types.h"

#include <expected>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

struct WallpaperLiveConfig;

class LiveWallpaperProvider {
public:
  virtual ~LiveWallpaperProvider() = default;

  [[nodiscard]] virtual std::string_view id() const = 0;
  [[nodiscard]] virtual std::string displayName() const = 0;

  // Asynchronous discovery. Never blocks the caller; the change callback fires on the main thread when
  // results land. force = false keeps a fresh catalog (nothing changed on disk) instead of rescanning.
  virtual void refresh(bool force) = 0;
  [[nodiscard]] virtual bool discovering() const = 0;
  [[nodiscard]] virtual bool discovered() const = 0;

  // Main-thread snapshot of the catalog, ordered by title. Includes unsupported items so the UI can say
  // why they cannot be used; callers filter with live::isRenderable().
  [[nodiscard]] virtual const std::vector<live::Item>& items() const = 0;
  [[nodiscard]] virtual const live::Item* find(std::string_view id) const = 0;
  // Empty when usable; otherwise a human-readable reason (no Steam library, no Wallpaper Engine assets…).
  [[nodiscard]] virtual const std::string& problem() const = 0;

  // Resolves one item directly from disk (one small metadata read), for use before discovery has run
  // (resuming Live mode at startup, IPC). Also re-validates that the item still exists.
  [[nodiscard]] virtual std::expected<live::Item, std::string> resolve(std::string_view id) = 0;

  // Builds the renderer invocation for `item` on `outputs` (connector names). Re-validates the item on
  // disk, so a wallpaper unsubscribed since discovery fails here with a clear message.
  [[nodiscard]] virtual std::expected<live::LaunchSpec, std::string>
  launchSpec(const live::Item& item, const std::vector<std::string>& outputs, const WallpaperLiveConfig& config) = 0;

  void setOnChanged(std::function<void()> callback) { m_onChanged = std::move(callback); }

protected:
  void notifyChanged() {
    if (m_onChanged) {
      m_onChanged();
    }
  }

private:
  std::function<void()> m_onChanged;
};
