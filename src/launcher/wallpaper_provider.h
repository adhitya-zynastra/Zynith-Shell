#pragma once

#include "launcher/launcher_provider.h"

class ConfigService;
class WaylandConnection;

namespace zynith::theme {
  class ThemeService;
}

class WallpaperProvider : public LauncherProvider {
public:
  WallpaperProvider(
      ConfigService* config, WaylandConnection* wayland, zynith::theme::ThemeService* themeService = nullptr
  );

  [[nodiscard]] std::string_view defaultPrefix() const override { return "wall"; }
  [[nodiscard]] std::string_view id() const override { return "Wallpaper"; }
  [[nodiscard]] std::string displayName() const override;
  [[nodiscard]] std::string_view defaultGlyphName() const override { return "wallpaper-selector"; }
  [[nodiscard]] bool trackUsage() const override { return true; }

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;

private:
  ConfigService* m_config = nullptr;
  WaylandConnection* m_wayland = nullptr;
  zynith::theme::ThemeService* m_themeService = nullptr;
};
