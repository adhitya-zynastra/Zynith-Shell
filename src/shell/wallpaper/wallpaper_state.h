#pragma once

#include "ui/signal.h"

#include <cstdint>
#include <string>
#include <vector>

class ConfigService;
class LiveWallpaperController;
class Wallpaper;

// zynith: the one answer to "what wallpaper is this output showing". Desktop, overview backdrop, lock
// screen and palette all read it, so a live wallpaper is represented the same way everywhere: by its
// poster (the item's still preview) wherever its pixels cannot be shown — the renderer is another
// process, the lock hides every other surface, and niri offers no per-surface capture.
class WallpaperState {
public:
  enum class Mode : std::uint8_t { Static, Live };

  void initialize(ConfigService& config, Wallpaper& wallpaper, LiveWallpaperController& live);

  [[nodiscard]] Mode mode() const noexcept { return m_mode; }
  // A still image for this output: the live poster where a renderer covers it, else the static image.
  [[nodiscard]] std::string stillFor(const std::string& connector) const;
  // Where the palette comes from: the live poster, or empty for the static wallpaper (the config default).
  [[nodiscard]] const std::string& paletteSource() const noexcept { return m_poster; }

  // Fires when the mode, the poster or the live outputs changed.
  [[nodiscard]] Signal<>& changed() noexcept { return m_changed; }

  // Re-reads the sources; called on their change signals and on config reloads.
  void refresh();

private:
  ConfigService* m_config = nullptr;
  Wallpaper* m_wallpaper = nullptr;
  LiveWallpaperController* m_live = nullptr;

  Mode m_mode = Mode::Static;
  std::string m_poster;
  std::vector<std::string> m_liveOutputs;

  Signal<>::ScopedConnection m_liveConn;
  Signal<> m_changed;
};
