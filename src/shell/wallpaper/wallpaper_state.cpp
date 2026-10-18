#include "shell/wallpaper/wallpaper_state.h"

#include "config/config_service.h"
#include "core/log.h"
#include "shell/wallpaper/live/live_wallpaper_controller.h"
#include "shell/wallpaper/wallpaper.h"

#include <algorithm>

namespace {
  constexpr Logger kLog("wallpaper_state");
}

void WallpaperState::initialize(ConfigService& config, Wallpaper& wallpaper, LiveWallpaperController& live) {
  m_config = &config;
  m_wallpaper = &wallpaper;
  m_live = &live;
  // Static changes already reach every view through the config's wallpaper-change callback; so does a
  // palette-source change, which refresh() makes after updating the state the views read.
  m_liveConn = live.changed().connect([this]() { refresh(); });
  refresh();
}

std::string WallpaperState::stillFor(const std::string& connector) const {
  if (m_mode == Mode::Live && !m_poster.empty() && std::ranges::contains(m_liveOutputs, connector)) {
    return m_poster;
  }
  return m_config != nullptr ? m_config->getWallpaperPath(connector) : std::string();
}

void WallpaperState::refresh() {
  if (m_live == nullptr) {
    return;
  }
  const std::string poster = m_live->activePoster();
  const Mode mode = poster.empty() ? Mode::Static : Mode::Live;
  const std::vector<std::string>& outputs = m_live->renderOutputs();
  if (mode == m_mode && poster == m_poster && outputs == m_liveOutputs) {
    return;
  }
  m_mode = mode;
  m_poster = poster;
  m_liveOutputs = outputs;
  kLog.info("{}{}", mode == Mode::Live ? "live, poster " : "static", mode == Mode::Live ? poster : std::string());
  // the palette follows the same still the lock and overview show
  m_config->setPaletteSourceOverride(m_poster);
  m_changed.emit();
}
