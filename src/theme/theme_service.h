#pragma once

#include "config/config_types.h"
#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "theme/palette.h"
#include "ui/palette.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

class ConfigService;
class HttpClient;
class IpcService;

namespace zynith::theme {

  class ThemeService {
  public:
    using ChangeCallback = std::function<void()>;
    // Carries the resolved [theme].mode: the app-facing mode templates and the GTK color
    // scheme run in. Shell-facing consumers read resolvedShellMode()/isLightMode().
    using ResolvedCallback = std::function<void(const GeneratedPalette&, std::string_view)>;

    ThemeService(ConfigService& config, HttpClient& httpClient);

    // Snaps the palette to the resolved theme (no fade). Used at startup.
    void apply();

    // Resolves the target theme and cross-fades to it.
    void onConfigReload();
    void onWallpaperChange();
    void onAutoSchemeChanged();
    void setAutoCoordinates(std::optional<double> latitude, std::optional<double> longitude);
    void toggleLightDark();
    void cycleMode();
    [[nodiscard]] ThemeMode configuredMode() const noexcept;
    // Zynith's own resolved mode ([theme].shell_mode, or [theme].mode when it follows).
    [[nodiscard]] bool isLightMode() const noexcept;
    [[nodiscard]] std::string_view resolvedShellMode() const noexcept;
    // The resolved [theme].mode, which drives apps.
    [[nodiscard]] std::string_view resolvedMode() const noexcept;

    void setChangeCallback(ChangeCallback callback);
    void setResolvedCallback(ResolvedCallback callback);

    void registerIpc(IpcService& ipc);

    // zynith: a wallpaper palette computed off the main thread. wallpaperScheme() is read on the main thread when
    // the work is handed out; computeWallpaperPalette() is pure (decode, resize, generate) and safe on any thread;
    // primeWallpaperPalette() (main thread) stores its result where resolveWallpaperGenerated() looks first, so the
    // wallpaper change that follows resolves without decoding anything.
    struct PrimedWallpaperPalette {
      std::string path;
      std::string scheme;
      std::int64_t mtimeNs = 0;
      GeneratedPalette generated;
    };
    [[nodiscard]] std::string wallpaperScheme() const;
    [[nodiscard]] static std::optional<PrimedWallpaperPalette>
    computeWallpaperPalette(const std::string& path, const std::string& scheme);
    void primeWallpaperPalette(PrimedWallpaperPalette primed);

    // Writes the current wallpaper-generated palette to ~/.config/zynith-shell/palettes/
    // and switches palette source to custom.
    [[nodiscard]] bool saveWallpaperPaletteAsCustom(std::string* paletteNameOut, std::string* errorOut = nullptr);

  private:
    void resolveAndSet(bool animate);
    // Decodes + generates the wallpaper palette, memoized on (path, mtime, scheme)
    // so repeated resolves for an unchanged wallpaper skip the ~100ms image decode.
    std::optional<GeneratedPalette> resolveWallpaperGenerated(const ThemeConfig& cfg, const std::string& wallpaperPath);
    void queueResolvedCallback(const GeneratedPalette& generated, std::string_view mode);
    void flushResolvedCallback(bool defer);
    void startTransition(const Palette& target);
    void finishTransition(bool deferResolvedCallback);
    void tickTransition();
    void startCommunityDownload(const std::string& name);
    void rescheduleAutoTimer();
    [[nodiscard]] bool hasAutoMode() const noexcept;

    ConfigService& m_config;
    HttpClient& m_httpClient;
    std::string m_inflightCommunityName;

    // Memoized wallpaper palette (see resolveWallpaperGenerated). Keyed on the
    // wallpaper path, its mtime, and the active scheme; any mismatch re-decodes.
    std::optional<GeneratedPalette> m_wallpaperCacheGenerated;
    std::string m_wallpaperCachePath;
    std::string m_wallpaperCacheScheme;
    std::int64_t m_wallpaperCacheMtimeNs = 0;

    ChangeCallback m_changeCallback;
    ResolvedCallback m_resolvedCallback;
    // External template/hooks callbacks are delayed until the shell palette is
    // applied, and deferred callbacks must be able to drop stale resolves.
    std::optional<GeneratedPalette> m_pendingResolvedPalette;
    std::string m_pendingResolvedMode;
    std::uint64_t m_resolvedCallbackGeneration = 0;

    AnimationManager m_animations;
    Timer m_transitionTimer;
    Palette m_fromPalette{};
    Palette m_targetPalette{};
    AnimationManager::Id m_transitionAnimId = 0;
    bool m_transitionResolvedCallbackFlushed = false;
    bool m_isShellLightMode = false;
    bool m_isLightMode = false;
    std::optional<double> m_autoLatitude;
    std::optional<double> m_autoLongitude;
    Timer m_autoTimer;
  };

} // namespace zynith::theme
