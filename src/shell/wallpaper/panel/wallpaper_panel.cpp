#include "shell/wallpaper/panel/wallpaper_panel.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/input/keybind_matcher.h"
#include "core/log.h"
#include "core/random.h"
#include "core/ui_phase.h"
#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/core/thumbnail_service.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "shell/tooltip/tooltip_manager.h"
#include "shell/wallpaper/live/live_wallpaper_controller.h"
#include "shell/wallpaper/panel/wallpaper_tile.h"
#include "shell/wallpaper/wallpaper_paths.h"
#include "theme/builtin_palettes.h"
#include "theme/community_palettes.h"
#include "theme/custom_palettes.h"
#include "theme/theme_service.h"
#include "ui/builders.h"
#include "ui/controls/carousel_view.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/palette.h"
#include "ui/responsive.h"
#include "ui/style.h"
#include "ui/tokens.h"
#include "util/file_utils.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <random>
#include <string_view>
#include <system_error>
#include <unordered_set>
#include <utility>

namespace {

  [[nodiscard]] bool isDescendantOf(const Node* node, const Node* ancestor) {
    if (node == nullptr || ancestor == nullptr)
      return false;
    for (const Node* p = node->parent(); p != nullptr; p = p->parent()) {
      if (p == ancestor)
        return true;
    }
    return false;
  }

  constexpr Logger kLog("wp-panel");
  constexpr auto kFilterDebounceInterval = std::chrono::milliseconds(120);
  constexpr float kMinTileWidth = 180.0F;
  constexpr float kMonitorSelectMinWidth = 136.0F;
  constexpr float kFavoriteSelectMinWidth = 168.0F;
  constexpr float kFavoritesMetaRowGap = Style::spaceSm;
  constexpr float kTileAspect = 0.78F; // height / width, leaves room for label under widescreen thumb
  // Carousel: focused item width as a fraction of the panel, and centre-to-centre spacing
  // as a fraction of that width (< 1 makes neighbours overlap behind the focused item).
  // Width of the compact control card in carousel mode: the panel's own width
  // before the carousel existed, so the menu keeps exactly its old footprint.
  // Browsing session idle budget. Sized so a sweep back and forth across the
  // visible neighbourhood re-uses textures instead of re-decoding: ~1.4 MB per
  // 762 px preview, so this holds roughly 45 of them. Released on close.
  // Session working set. The whole browsable collection is made resident at a
  // cheap browse resolution so fast scrolling never waits for a decode; only the
  // focused card is promoted to a sharp one. ~370 KB per browse thumbnail, so
  // this ceiling holds roughly 350 of them, and a larger library simply keeps
  // the most recently prefetched ones.
  constexpr int kBrowseThumbnailPx = 384;
  constexpr int kFocusedThumbnailPx = 768;
  constexpr std::size_t kBrowseSessionIdleBytes = 128U * 1024U * 1024U;
  constexpr std::size_t kBrowseSessionIdleEntries = 512;
  // Upper bound on how many entries one session prefetches, whatever the library
  // size. Ordered outward from the focused item so the useful ones land first.
  constexpr std::size_t kMaxPrefetchEntries = 360;
  // zynith: Live tab. A Wallpaper Engine library easily holds hundreds of items, so the live browser keeps
  // only the neighbourhood of the focused card resident (~24 MB at the browse size) instead of the whole
  // collection; everything further away decodes on arrival from the persistent WebP thumbnail cache.
  constexpr std::size_t kMaxLivePrefetchEntries = 64;
  // Cards within the promotion window hold the display-quality texture: every card the arc
  // shows (a preview is visibly soft at the 475-760 px they draw at), plus this many past the
  // leading edge, so the next card is already sharp when it arrives. The arc widens with the
  // output (carousel_geometry.h), so the window is derived per update, not fixed.
  constexpr long kPromotionLead = 1;
  // Before the carousel has laid out once.
  constexpr long kPromotionFallbackSide = 2;
  // A second activation of the same wallpaper inside this window is treated as
  // one gesture (double-click), not two applies.
  constexpr auto kReapplyGuard = std::chrono::milliseconds(600);
  constexpr float kMenuCardWidth = 1000.0F;
  // Focused-card sizing. The preference comes from [wallpaper].carousel_card_width; these bound it.
  // kCarouselMaxBandFraction is the pre-responsive 40 % of the band: on anything up to the laptop's
  // width the card is capped there, which keeps the old composition (outer pair showing), and the
  // 760 px default sits just under it at 1920 px. Only wider bands leave the card at its preference.
  constexpr float kCarouselMinCardWidth = 320.0F;
  constexpr float kCarouselMaxCardWidth = 1400.0F;
  constexpr float kCarouselMaxBandFraction = 0.40F;
  constexpr float kCarouselStrideRatio = 0.66F;

  [[nodiscard]] std::size_t themeModeSegmentIndex(ThemeMode mode) {
    switch (mode) {
    case ThemeMode::Dark:
      return 0;
    case ThemeMode::Light:
      return 1;
    case ThemeMode::Auto:
    default:
      return 2;
    }
  }

  [[nodiscard]] ThemeMode themeModeFromSegmentIndex(std::size_t index) {
    switch (index) {
    case 0:
      return ThemeMode::Dark;
    case 1:
      return ThemeMode::Light;
    default:
      return ThemeMode::Auto;
    }
  }

  [[nodiscard]] std::vector<std::string> wallpaperSchemeOptions() {
    return {
        i18n::tr("theme.scheme.m3-content"),     i18n::tr("theme.scheme.m3-tonal-spot"),
        i18n::tr("theme.scheme.m3-fruit-salad"), i18n::tr("theme.scheme.m3-rainbow"),
        i18n::tr("theme.scheme.m3-monochrome"),  i18n::tr("theme.scheme.vibrant"),
        i18n::tr("theme.scheme.faithful"),       i18n::tr("theme.scheme.soft"),
        i18n::tr("theme.scheme.dysfunctional"),  i18n::tr("theme.scheme.muted"),
    };
  }

  [[nodiscard]] std::vector<std::string> wallpaperSchemeValues() {
    return {
        "m3-content", "m3-tonal-spot", "m3-fruit-salad", "m3-rainbow",    "m3-monochrome",
        "vibrant",    "faithful",      "soft",           "dysfunctional", "muted",
    };
  }

  [[nodiscard]] std::optional<ThemeMode> favoriteThemeBadge(const WallpaperFavorite* favorite) {
    if (favorite == nullptr) {
      return std::nullopt;
    }
    if (favorite->themeMode == ThemeMode::Light || favorite->themeMode == ThemeMode::Dark) {
      return favorite->themeMode;
    }
    return std::nullopt;
  }

  bool parseColorWallpaperPath(std::string_view path, Color& out) {
    constexpr std::string_view kPrefix = "color:";
    if (!path.starts_with(kPrefix)) {
      return false;
    }
    return tryParseHexColor(path.substr(kPrefix.size()), out);
  }

  std::string colorWallpaperPath(const Color& color) { return "color:" + formatRgbHex(color); }

  bool wallpaperEntryIsCurrent(const WallpaperEntry& entry, std::string_view currentWallpaperPath) {
    if (entry.isDir) {
      return false;
    }
    return FileUtils::normalizeWallpaperPath(entry.absPath.string())
        == FileUtils::normalizeWallpaperPath(currentWallpaperPath);
  }

  [[nodiscard]] WallpaperFavorite wallpaperFavoriteFromTheme(const ThemeConfig& theme) {
    WallpaperFavorite favorite;
    favorite.themeMode = theme.mode;
    favorite.paletteSource = theme.source;
    favorite.builtinPalette = theme.builtinPalette;
    favorite.communityPalette = theme.communityPalette;
    favorite.customPalette = theme.customPalette;
    favorite.wallpaperScheme = theme.wallpaperScheme;
    return favorite;
  }

  [[nodiscard]] std::string paletteSelectionValue(const WallpaperFavorite& theme) {
    switch (theme.paletteSource.value_or(PaletteSource::Builtin)) {
    case PaletteSource::Builtin:
      return theme.builtinPalette;
    case PaletteSource::Wallpaper:
      return theme.wallpaperScheme;
    case PaletteSource::Community:
      return theme.communityPalette;
    case PaletteSource::Custom:
      return theme.customPalette;
    }
    return {};
  }

  [[nodiscard]] std::filesystem::path canonicalWallpaperDirectory(const std::filesystem::path& dir) {
    if (dir.empty()) {
      return {};
    }
    std::error_code ec;
    const auto canonical = std::filesystem::weakly_canonical(dir, ec);
    return ec ? dir.lexically_normal() : canonical;
  }

  [[nodiscard]] bool wallpaperDirectoriesEquivalent(const std::filesystem::path& a, const std::filesystem::path& b) {
    if (a.empty() || b.empty()) {
      return a.empty() && b.empty();
    }
    std::error_code ec;
    if (std::filesystem::equivalent(a, b, ec)) {
      return true;
    }
    return canonicalWallpaperDirectory(a) == canonicalWallpaperDirectory(b);
  }

  [[nodiscard]] bool
  wallpaperPathInsideDirectory(const std::filesystem::path& file, const std::filesystem::path& directory) {
    const std::filesystem::path dir = canonicalWallpaperDirectory(directory);
    if (dir.empty()) {
      return false;
    }
    std::error_code ec;
    const auto filePath = std::filesystem::weakly_canonical(file, ec);
    if (ec) {
      return false;
    }
    const auto rel = std::filesystem::relative(filePath.parent_path(), dir, ec);
    if (ec || rel.empty()) {
      return wallpaperDirectoriesEquivalent(filePath.parent_path(), dir);
    }
    const std::string relText = rel.generic_string();
    return !relText.starts_with("..");
  }

  [[nodiscard]] int caseInsensitiveNameOrder(std::string_view a, std::string_view b) {
    return StringUtils::naturalCaseInsensitiveCompare(a, b);
  }

  [[nodiscard]] std::optional<std::filesystem::file_time_type> entryModifiedTime(const WallpaperEntry& entry) {
    if (entry.isDir || entry.absPath.string().starts_with("color:")) {
      return std::nullopt;
    }
    // Scanned entries carry the mtime captured during the directory walk, so the
    // sort comparator never stats. Pinned favorites lack it and stat once here.
    if (entry.hasMtime) {
      return entry.mtime;
    }
    std::error_code ec;
    const auto mtime = std::filesystem::last_write_time(entry.absPath, ec);
    if (ec) {
      return std::nullopt;
    }
    return mtime;
  }

  // Ordering key for SortMode::Random. Hashing the path against a seed keeps the
  // shuffled order fixed until the seed changes, so filtering or starring a tile
  // rebuilds the visible entries without reordering the grid.
  [[nodiscard]] std::uint64_t randomOrderKey(const WallpaperEntry& entry, std::uint64_t seed) {
    std::uint64_t hash = std::filesystem::hash_value(entry.absPath) ^ seed;
    hash ^= hash >> 30U;
    hash *= 0xBF58476D1CE4E5B9ULL;
    hash ^= hash >> 27U;
    hash *= 0x94D049BB133111EBULL;
    return hash ^ (hash >> 31U);
  }

  [[nodiscard]] bool favoriteVisibleInBrowseContext(
      std::string_view favoritePath, const std::filesystem::path& activeDir, const std::filesystem::path& rootDir,
      bool flatten
  ) {
    if (favoritePath.starts_with("color:")) {
      return wallpaperDirectoriesEquivalent(activeDir, rootDir);
    }

    const std::filesystem::path favoriteFile = std::filesystem::path(FileUtils::normalizeWallpaperPath(favoritePath));
    if (wallpaperDirectoriesEquivalent(activeDir, rootDir)) {
      return true;
    }
    if (!flatten) {
      return wallpaperDirectoriesEquivalent(favoriteFile.parent_path(), activeDir);
    }
    return wallpaperPathInsideDirectory(favoriteFile, activeDir);
  }

} // namespace

class WallpaperGridAdapter : public VirtualGridAdapter {
public:
  using ActivateCallback = std::function<void(const WallpaperEntry&)>;
  using StarCallback = std::function<void(const WallpaperEntry&)>;

  explicit WallpaperGridAdapter(float scale) : m_scale(scale) {}

  void setEntries(const std::vector<WallpaperEntry>* entries) { m_entries = entries; }
  void setRenderer(Renderer* renderer) { m_renderer = renderer; }
  void setConfig(ConfigService* config) { m_config = config; }
  void setCurrentWallpaperPath(std::string path) { m_currentWallpaperPath = std::move(path); }
  // zynith: live entries (entry.liveId set) take their star and "current" marks from the live controller.
  void setCurrentLiveId(std::string id) { m_currentLiveId = std::move(id); }
  void setLiveFavoriteQuery(std::function<bool(const std::string&)> query) { m_liveFavorite = std::move(query); }
  void setThumbnailService(ThumbnailService* service) {
    m_thumbnails = service;
    for (WallpaperTile* tile : m_pool) {
      if (tile != nullptr) {
        tile->setThumbnailService(service);
      }
    }
  }
  void setOnActivate(ActivateCallback callback) { m_onActivate = std::move(callback); }
  void setOnStarToggle(StarCallback callback) { m_onStarToggle = std::move(callback); }

  void refreshVisibleThumbnails(Renderer& renderer) {
    for (WallpaperTile* tile : m_pool) {
      if (tile != nullptr && tile->visible()) {
        tile->refreshThumbnail(renderer);
      }
    }
  }

  [[nodiscard]] std::size_t itemCount() const override { return m_entries == nullptr ? 0U : m_entries->size(); }

  // Indices that should hold the display-quality texture (inclusive).
  void setPromotedRange(long lo, long hi) {
    m_promotedLo = lo;
    m_promotedHi = hi;
  }

  void setBrowseThumbnailSizes(int browsePx, int promotedPx) {
    m_browsePx = browsePx;
    m_promotedPx = promotedPx;
    for (WallpaperTile* tile : m_pool) {
      if (tile != nullptr) {
        tile->setBrowseThumbnailPx(browsePx);
        tile->setPromotedThumbnailPx(promotedPx);
      }
    }
  }

  [[nodiscard]] std::unique_ptr<Node> createTile() override {
    auto tile = std::make_unique<WallpaperTile>(0.0F, 0.0F, m_scale);
    tile->setThumbnailService(m_thumbnails);
    tile->setBrowseThumbnailPx(m_browsePx);
    tile->setPromotedThumbnailPx(m_promotedPx);
    tile->setOnStarClick([this](const WallpaperEntry& entry) {
      if (m_onStarToggle) {
        m_onStarToggle(entry);
      }
    });
    m_pool.push_back(tile.get());
    return tile;
  }

  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override {
    auto* wt = static_cast<WallpaperTile*>(&tile);
    wt->setCellSize(wt->width(), wt->height());
    if (m_renderer != nullptr && m_entries != nullptr && index < m_entries->size()) {
      const auto& entry = (*m_entries)[index];
      wt->setEntry(entry, *m_renderer);
      if (!entry.liveId.empty()) {
        wt->setFavoriteState(m_liveFavorite && m_liveFavorite(entry.liveId), std::nullopt);
      } else if (m_config != nullptr && !entry.isDir) {
        const std::string path = entry.absPath.string();
        wt->setFavoriteState(
            m_config->isWallpaperFavorite(path), favoriteThemeBadge(m_config->wallpaperFavorite(path))
        );
      } else {
        wt->setFavoriteState(false, std::nullopt);
      }
    }
    const auto signedIndex = static_cast<long>(index);
    wt->setPromoted(m_promotedPx > 0 && signedIndex >= m_promotedLo && signedIndex <= m_promotedHi);
    wt->setSelected(selected);
    wt->setCurrent(
        m_entries != nullptr
        && index < m_entries->size()
        && ((*m_entries)[index].liveId.empty() ? wallpaperEntryIsCurrent((*m_entries)[index], m_currentWallpaperPath)
                                               : (*m_entries)[index].liveId == m_currentLiveId)
    );
    wt->setHoveredVisual(hovered && !selected);
  }

  // Grid overlay owns clicks; star toggles dispatch here.
  bool
  onPointerPress(std::size_t index, float cellLocalX, float cellLocalY, float cellWidth, float cellHeight) override {
    if (m_entries == nullptr || index >= m_entries->size()) {
      return false;
    }
    const auto& entry = (*m_entries)[index];
    if (entry.isDir) {
      return false;
    }
    if (!WallpaperTile::hitTestStarRegion(cellWidth, cellHeight, m_scale, cellLocalX, cellLocalY)) {
      return false;
    }
    if (m_onStarToggle) {
      m_onStarToggle(entry);
    }
    return true;
  }

  [[nodiscard]] bool overlayHitTest(
      std::size_t index, float cellLocalX, float cellLocalY, float cellWidth, float cellHeight
  ) const override {
    if (m_entries == nullptr || index >= m_entries->size()) {
      return false;
    }
    if ((*m_entries)[index].isDir) {
      return false;
    }
    return WallpaperTile::hitTestStarRegion(cellWidth, cellHeight, m_scale, cellLocalX, cellLocalY);
  }

  void applyOverlayHover(Node& tile, bool hovered) override {
    static_cast<WallpaperTile&>(tile).setStarHovered(hovered);
  }

  void onActivate(std::size_t index) override {
    if (!m_onActivate || m_entries == nullptr || index >= m_entries->size()) {
      return;
    }
    m_onActivate((*m_entries)[index]);
  }

private:
  float m_scale;
  const std::vector<WallpaperEntry>* m_entries = nullptr;
  std::string m_currentWallpaperPath;
  std::string m_currentLiveId;
  std::function<bool(const std::string&)> m_liveFavorite;
  Renderer* m_renderer = nullptr;
  ThumbnailService* m_thumbnails = nullptr;
  ConfigService* m_config = nullptr;

  std::vector<WallpaperTile*> m_pool;
  int m_browsePx = 0;
  int m_promotedPx = 0;
  long m_promotedLo = 0;
  long m_promotedHi = -1;
  ActivateCallback m_onActivate;
  StarCallback m_onStarToggle;
};

WallpaperPanel::WallpaperPanel(
    WaylandConnection* wayland, ConfigService* config, ThumbnailService* thumbnails, WallpaperScanner* scanner,
    zynith::theme::ThemeService* themeService, LiveWallpaperController* live
)
    : m_wayland(wayland), m_config(config), m_thumbnails(thumbnails), m_scanner(scanner), m_themeService(themeService),
      m_live(live) {
  if (m_config != nullptr) {
    m_flatten = m_config->stateBool("wallpaper_panel", "flatten").value_or(false);
    if (const std::optional<std::string> sort = m_config->stateString("wallpaper_panel", "sort")) {
      m_sortMode = sortModeFromState(*sort);
    }
  }
  if (m_scanner != nullptr) {
    m_scanner->setOnComplete([this]() { onScanComplete(); });
  }
}

WallpaperPanel::~WallpaperPanel() {
  if (m_scanner != nullptr) {
    m_scanner->setOnComplete(nullptr);
  }
}

PanelPlacement WallpaperPanel::panelPlacement() const noexcept {
  // The carousel band spans the output, which only floating surfaces can do
  // (an attached panel is sized to its bar anchor).
  if (carouselMode()) {
    return PanelPlacement::Floating;
  }
  return m_config == nullptr ? PanelPlacement::Attached : m_config->config().shell.panel.wallpaperPlacement;
}

void WallpaperPanel::create() {
  const float scale = contentScale();

  auto root = ui::column({
      .out = &m_rootLayout,
      .align = FlexAlign::Stretch,
      // Carousel mode deliberately separates the control card from the content
      // band; grid mode keeps the tight panel spacing it always had.
      .gap = (carouselMode() ? Style::spaceLg * 2.0F : Style::spaceSm) * scale,
  });

  auto toolbar = ui::row({
      .out = &m_toolbar,
      .align = FlexAlign::Center,
      .gap = Style::spaceSm * scale,
      .fillWidth = true,
  });

  toolbar->addChild(
      ui::label({
          .out = &m_title,
          .text = i18n::tr("wallpaper.panel.title"),
          .fontSize = Style::fontSizeTitle * scale,
          .fontWeight = FontWeight::Bold,
          .color = colorSpecFromRole(ColorRole::Primary),
      })
  );

  // zynith: Static / Live. Switching the tab only changes what is browsed; the desktop changes when a
  // wallpaper is actually selected.
  if (m_live != nullptr) {
    toolbar->addChild(
        ui::segmented({
            .out = &m_modeSegmented,
            .options =
                std::vector<ui::SegmentedOption>{
                    {.label = i18n::tr("wallpaper.panel.mode-static")},
                    {.label = i18n::tr("wallpaper.panel.mode-live")},
                },
            .selectedIndex = static_cast<std::size_t>(m_liveTab ? 1 : 0),
            .scale = scale,
            .compact = true,
            .surfaceOpacity = panelCardOpacity(),
            .onChange = [this](std::size_t index) {
              if (!m_syncingLiveControls) {
                setLiveTab(index == 1);
              }
            },
        })
    );
  }

  toolbar->addChild(
      ui::input({
          .out = &m_filterInput,
          .placeholder = i18n::tr("wallpaper.panel.filter-placeholder"),
          .fontSize = Style::fontSizeBody * scale,
          .controlHeight = Style::controlHeightSm * scale,
          .horizontalPadding = Style::spaceMd * scale,
          .surfaceOpacity = panelCardOpacity(),
          .width = 210.0F * scale,
          .height = 0.0F,
          .onChange =
              [this](const std::string& text) {
                if (text == m_pendingFilterQuery) {
                  return;
                }
                m_pendingFilterQuery = text;
                m_filterDebounceTimer.start(kFilterDebounceInterval, [this]() {
                  if (m_pendingFilterQuery == m_filterQuery) {
                    return;
                  }
                  m_filterQuery = m_pendingFilterQuery;
                  applyFilter();
                  resetSelection();
                  rebindGrid();
                  syncBrowseChrome();
                  m_dirty = true;
                  PanelManager::instance().refresh();
                });
              },
          .onKeyEvent = [this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); },
      })
  );

  toolbar->addChild(
      ui::button({
          .out = &m_backButton,
          .glyph = "arrow-big-up",
          .glyphSize = Style::fontSizeBody * scale,
          .variant = ButtonVariant::Secondary,
          .tooltip = i18n::tr("wallpaper.panel.navigate-up"),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = [this]() { navigateUp(); },
      })
  );

  toolbar->addChild(ui::spacer());

  toolbar->addChild(
      ui::label({
          .out = &m_flattenLabel,
          .text = i18n::tr("wallpaper.panel.flatten"),
          .fontSize = Style::fontSizeBody * scale,
          .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
      })
  );

  toolbar->addChild(
      ui::toggle({
          .out = &m_flattenToggle,
          .checked = m_flatten,
          .onChange = [this](bool checked) {
            m_flatten = checked;
            if (m_config != nullptr) {
              (void)m_config->setStateBool("wallpaper_panel", "flatten", checked);
            }
            refreshVisibleEntries();
            resetSelection();
            rebindGrid();
            syncBrowseChrome();
            m_dirty = true;
            PanelManager::instance().refresh();
          },
      })
  );

  toolbar->addChild(
      ui::select({
          .out = &m_monitorSelect,
          .fontSize = Style::fontSizeBody * scale,
          .controlHeight = Style::controlHeightSm * scale,
          .surfaceOpacity = panelCardOpacity(),
          .onSelectionChanged =
              [this](std::size_t idx, std::string_view) {
                m_selectedMonitorIndex = idx;
                m_navStack.clear();
                refreshVisibleEntries();
                resetSelection();
                rebindGrid();
                syncBackButton();
                syncBrowseChrome();
                m_dirty = true;
                PanelManager::instance().refresh();
              },
          .configure = [scale](Select& select) { select.setMinWidth(kMonitorSelectMinWidth * scale); },
      })
  );

  toolbar->addChild(
      ui::button({
          .out = &m_colorButton,
          .glyph = "color-picker",
          .glyphSize = Style::fontSizeBody * scale,
          .variant = ButtonVariant::Default,
          .tooltip = i18n::tr("wallpaper.panel.choose-color"),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = [this]() { applyColorWallpaper(); },
      })
  );

  toolbar->addChild(
      ui::button({
          .out = &m_sortButton,
          .glyph = std::string(sortModeGlyph(m_sortMode)),
          .glyphSize = Style::fontSizeBody * scale,
          .variant = ButtonVariant::Default,
          .tooltip = i18n::tr(sortModeTooltipKey(m_sortMode)),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = [this]() { cycleSortMode(); },
      })
  );

  toolbar->addChild(
      ui::button({
          .out = &m_refreshButton,
          .glyph = "refresh",
          .glyphSize = Style::fontSizeBody * scale,
          .variant = ButtonVariant::Default,
          .tooltip = i18n::tr("wallpaper.panel.refresh"),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = [this]() {
            if (liveTab()) {
              m_live->provider().refresh(/*force=*/true);
            } else if (m_scanner != nullptr) {
              m_scanner->invalidate();
            }
            refreshVisibleEntries();
            resetSelection();
            rebindGrid();
            syncBrowseChrome();
            m_dirty = true;
            PanelManager::instance().refresh();
          },
      })
  );

  toolbar->addChild(
      ui::button({
          .out = &m_closeButton,
          .glyph = "close",
          .glyphSize = Style::fontSizeBody * scale,
          .tooltip = i18n::tr("wallpaper.panel.close"),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = []() { PanelManager::instance().close(); },
      })
  );

  // Carousel mode splits the browser into two surfaces: this compact control
  // card (the menu the panel always had, at its original width) and, below it,
  // the full-width carousel. The card is drawn here because the panel surface
  // itself is undecorated in this mode.
  Flex* menuHost = m_rootLayout;
  if (carouselMode()) {
    auto menuRow = ui::row({
        .align = FlexAlign::Start,
        .justify = FlexJustify::Center,
        .fillWidth = true,
    });
    auto menuCard = ui::column({
        .out = &m_menuCard,
        .align = FlexAlign::Stretch,
        .gap = Style::spaceSm * scale,
        .padding = Style::spaceMd * scale,
        .radius = ui::tokens::radius(ui::tokens::Radius::Surface, scale),
        .width = kMenuCardWidth * scale,
    });
    menuCard->setCardStyle(scale, panelCardOpacity(), true);
    menuHost = static_cast<Flex*>(menuRow->addChild(std::move(menuCard)));
    m_rootLayout->addChild(std::move(menuRow));
  }

  menuHost->addChild(std::move(toolbar));

  const float favoritesControlHeight = Style::controlHeightSm * scale;
  const float favoritesLabelFontSize = Style::fontSizeCaption * scale;

  auto favoritesOptions = ui::row({
      .out = &m_favoritesOptionsColumn,
      .align = FlexAlign::Center,
      .gap = kFavoritesMetaRowGap * scale,
      .fillWidth = true,
  });

  // Only offer palette sources that actually have palettes; Community/Custom are empty
  // when nothing is fetched/installed, and selecting them would do nothing.
  m_paletteSourceOrder.clear();
  std::vector<ui::SegmentedOption> paletteSourceOptions;
  const auto addPaletteSource = [&](PaletteSource source, const char* labelKey) {
    m_paletteSourceOrder.push_back(source);
    paletteSourceOptions.push_back({.label = i18n::tr(labelKey)});
  };
  addPaletteSource(PaletteSource::Builtin, "settings.options.theme.source.built-in");
  addPaletteSource(PaletteSource::Wallpaper, "settings.options.theme.source.wallpaper");
  if (!zynith::theme::availableCommunityPalettes().empty()) {
    addPaletteSource(PaletteSource::Community, "settings.options.theme.source.community");
  }
  if (!zynith::theme::availableCustomPalettes().empty()) {
    addPaletteSource(PaletteSource::Custom, "settings.options.theme.source.custom");
  }

  favoritesOptions->addChild(
      ui::segmented({
          .out = &m_favoritePaletteSourceSegmented,
          .options = std::move(paletteSourceOptions),
          .selectedIndex = static_cast<std::size_t>(0),
          .scale = scale,
          .compact = true,
          .surfaceOpacity = panelCardOpacity(),
          .onChange = [this](std::size_t index) {
            if (m_syncingFavoriteControls || m_config == nullptr) {
              return;
            }
            const std::optional<PaletteSource> source = paletteSourceForSegment(index);
            if (!source.has_value()) {
              return;
            }
            // Repopulate the palette picker for the newly chosen source, then apply.
            WallpaperFavorite seed = activeThemeSettings();
            seed.paletteSource = source;
            if (m_favoriteThemeSegmented != nullptr) {
              seed.themeMode = themeModeFromSegmentIndex(m_favoriteThemeSegmented->selectedIndex());
            }
            m_syncingFavoriteControls = true;
            rebuildFavoritePaletteDetailSelect(&seed);
            m_syncingFavoriteControls = false;

            applyThemeFromControls();
            m_dirty = true;
            PanelManager::instance().refresh();
          },
      })
  );

  favoritesOptions->addChild(
      ui::select({
          .out = &m_favoritePaletteDetailSelect,
          .fontSize = favoritesLabelFontSize,
          .controlHeight = favoritesControlHeight,
          .horizontalPadding = Style::spaceSm * scale,
          .glyphSize = Style::fontSizeCaption * scale,
          .surfaceOpacity = panelCardOpacity(),
          .visible = false,
          .onSelectionChanged =
              [this](std::size_t index, std::string_view) {
                if (m_syncingFavoriteControls || m_config == nullptr || index >= m_favoritePaletteDetailValues.size()) {
                  return;
                }
                applyThemeFromControls();
                m_dirty = true;
                PanelManager::instance().refresh();
              },
          .configure = [scale](Select& select) { select.setMinWidth(kFavoriteSelectMinWidth * scale); },
      })
  );

  favoritesOptions->addChild(
      ui::button({
          .out = &m_favoriteCurrentButton,
          .glyph = "star",
          .glyphSize = Style::fontSizeBody * scale,
          .variant = ButtonVariant::Default,
          .tooltip = i18n::tr("wallpaper.panel.favorite-current"),
          .minWidth = Style::controlHeightSm * scale,
          .minHeight = Style::controlHeightSm * scale,
          .padding = Style::spaceXs * scale,
          .radius = Style::scaledRadiusMd(scale),
          .onClick = [this]() { toggleFavoriteForPath(currentWallpaperPathForSelection()); },
      })
  );

  favoritesOptions->addChild(ui::spacer());

  favoritesOptions->addChild(
      ui::segmented({
          .out = &m_favoriteThemeSegmented,
          .options =
              std::vector<ui::SegmentedOption>{
                  {.label = i18n::tr("settings.options.theme.mode.dark")},
                  {.label = i18n::tr("settings.options.theme.mode.light")},
                  {.label = i18n::tr("common.states.auto")},
              },
          .selectedIndex = static_cast<std::size_t>(0),
          .scale = scale,
          .compact = true,
          .surfaceOpacity = panelCardOpacity(),
          .onChange = [this](std::size_t) {
            if (m_syncingFavoriteControls || m_config == nullptr) {
              return;
            }
            applyThemeFromControls();
            rebindGrid();
            m_dirty = true;
            PanelManager::instance().refresh();
          },
      })
  );

  menuHost->addChild(std::move(favoritesOptions));

  if (m_live != nullptr) {
    auto liveRow = ui::row({
        .out = &m_liveOptionsRow,
        .align = FlexAlign::Center,
        .gap = kFavoritesMetaRowGap * scale,
        .fillWidth = true,
        .visible = false,
    });
    liveRow->addChild(
        ui::select({
            .out = &m_liveSourceSelect,
            .fontSize = favoritesLabelFontSize,
            .controlHeight = favoritesControlHeight,
            .horizontalPadding = Style::spaceSm * scale,
            .glyphSize = Style::fontSizeCaption * scale,
            .surfaceOpacity = panelCardOpacity(),
            .configure = [this, scale](Select& select) {
              // One provider today; the source picker is where a second one appears.
              select.setOptions({m_live->provider().displayName()});
              select.setSelectedIndexSilently(0);
              select.setMinWidth(kFavoriteSelectMinWidth * scale);
            },
        })
    );
    liveRow->addChild(
        ui::segmented({
            .out = &m_liveCategorySegmented,
            .options =
                std::vector<ui::SegmentedOption>{
                    {.label = i18n::tr("wallpaper.panel.live-collection")},
                    {.label = i18n::tr("wallpaper.panel.live-favorites")},
                    {.label = i18n::tr("wallpaper.panel.live-recent")},
                    {.label = i18n::tr("wallpaper.panel.live-installed")},
                },
            .selectedIndex = static_cast<std::size_t>(m_live->category()),
            .scale = scale,
            .compact = true,
            .surfaceOpacity = panelCardOpacity(),
            .onChange = [this](std::size_t index) {
              if (m_syncingLiveControls || index > 3) {
                return;
              }
              m_live->setCategory(static_cast<LiveWallpaperController::Category>(index));
              m_pendingInitialFocus = true;
              rebuildLiveEntries();
              syncLoadingState();
              resetSelection();
              rebindGrid(true);
              syncBrowseChrome();
              m_dirty = true;
              PanelManager::instance().refresh();
            },
        })
    );
    liveRow->addChild(
        ui::button({
            .out = &m_liveCollectionButton,
            .glyph = "playlist-add",
            .glyphSize = Style::fontSizeBody * scale,
            .variant = ButtonVariant::Default,
            .tooltip = i18n::tr("wallpaper.panel.live-collection-add"),
            .minWidth = Style::controlHeightSm * scale,
            .minHeight = Style::controlHeightSm * scale,
            .padding = Style::spaceXs * scale,
            .radius = Style::scaledRadiusMd(scale),
            .onClick = [this]() {
              if (const std::string id = focusedLiveId(); !id.empty()) {
                m_live->toggleCollection(id);
              }
            },
        })
    );
    liveRow->addChild(ui::spacer());
    liveRow->addChild(
        ui::label({
            .out = &m_liveCarouselLabel,
            .text = i18n::tr("wallpaper.panel.live-carousel"),
            .fontSize = favoritesLabelFontSize,
            .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
        })
    );
    liveRow->addChild(
        ui::toggle({
            .out = &m_liveCarouselToggle,
            .checked = m_live->carouselEnabled(),
            .onChange = [this](bool checked) {
              if (!m_syncingLiveControls) {
                m_live->setCarouselEnabled(checked);
              }
            },
        })
    );
    liveRow->addChild(
        ui::select({
            .out = &m_liveIntervalSelect,
            .fontSize = favoritesLabelFontSize,
            .controlHeight = favoritesControlHeight,
            .horizontalPadding = Style::spaceSm * scale,
            .glyphSize = Style::fontSizeCaption * scale,
            .surfaceOpacity = panelCardOpacity(),
            .onSelectionChanged =
                [this](std::size_t index, std::string_view) {
                  if (!m_syncingLiveControls && index < LiveWallpaperController::kCarouselIntervalPresets.size()) {
                    m_live->setCarouselInterval(LiveWallpaperController::kCarouselIntervalPresets[index]);
                  }
                },
            .configure =
                [](Select& select) {
                  std::vector<std::string> labels;
                  for (const std::int32_t seconds : LiveWallpaperController::kCarouselIntervalPresets) {
                    labels.push_back(
                        seconds < 3600 ? i18n::trp("wallpaper.panel.live-interval-minutes", seconds / 60)
                                       : i18n::trp("wallpaper.panel.live-interval-hours", seconds / 3600)
                    );
                  }
                  select.setOptions(std::move(labels));
                },
        })
    );
    liveRow->addChild(
        ui::button({
            .out = &m_liveOrderButton,
            .glyph = "repeat",
            .glyphSize = Style::fontSizeBody * scale,
            .variant = ButtonVariant::Default,
            .tooltip = i18n::tr("wallpaper.panel.live-order-sequential"),
            .minWidth = Style::controlHeightSm * scale,
            .minHeight = Style::controlHeightSm * scale,
            .padding = Style::spaceXs * scale,
            .radius = Style::scaledRadiusMd(scale),
            .onClick = [this]() {
              m_live->setCarouselOrder(
                  m_live->carouselOrder() == LiveWallpaperController::CarouselOrder::Shuffle
                      ? LiveWallpaperController::CarouselOrder::Sequential
                      : LiveWallpaperController::CarouselOrder::Shuffle
              );
            },
        })
    );
    liveRow->addChild(
        ui::button({
            .out = &m_liveStopButton,
            .glyph = "player-stop",
            .glyphSize = Style::fontSizeBody * scale,
            .variant = ButtonVariant::Default,
            .tooltip = i18n::tr("wallpaper.panel.live-stop"),
            .minWidth = Style::controlHeightSm * scale,
            .minHeight = Style::controlHeightSm * scale,
            .padding = Style::spaceXs * scale,
            .radius = Style::scaledRadiusMd(scale),
            .onClick = [this]() { m_live->switchToStatic(); },
        })
    );
    menuHost->addChild(std::move(liveRow));
    menuHost->addChild(
        ui::label({
            .out = &m_liveStatusLabel,
            .text = "",
            .fontSize = favoritesLabelFontSize,
            .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
            .visible = false,
        })
    );
  }

  // ── Body: virtualized scrolling grid ──────────────────────────────────
  m_adapter = std::make_unique<WallpaperGridAdapter>(scale);
  m_adapter->setThumbnailService(m_thumbnails);
  m_adapter->setConfig(m_config);
  m_adapter->setEntries(&m_visibleEntries);
  m_adapter->setOnActivate([this](const WallpaperEntry& entry) {
    if (entry.isDir) {
      navigateInto(entry.absPath);
    } else {
      applyWallpaperFromEntry(entry);
    }
  });
  m_adapter->setOnStarToggle([this](const WallpaperEntry& entry) {
    if (!entry.liveId.empty()) {
      if (m_live != nullptr) {
        m_live->toggleFavorite(std::string(entry.liveId)); // copy: the refresh may rebuild the entries
      }
    } else if (!entry.isDir) {
      toggleFavoriteForPath(entry.absPath.string());
    }
  });
  if (m_live != nullptr) {
    m_adapter->setLiveFavoriteQuery([this](const std::string& id) { return m_live->isFavorite(id); });
  }

  m_carouselMode = carouselMode();

  if (m_carouselMode) {
    // Cinematic browse surface: one dominant wallpaper at the centre, neighbours
    // receding to either side. Same adapter, same tiles, same thumbnail cache.
    auto carousel = std::make_unique<CarouselView>();
    carousel->setScale(scale);
    carousel->setStrideRatio(kCarouselStrideRatio);
    carousel->setPreloadCount(1);
    carousel->setItemCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    carousel->setFlexGrow(1.0F);
    carousel->setFillWidth(true);
    carousel->setAdapter(m_adapter.get());
    carousel->setOnFocusChanged([this](std::optional<std::size_t> idx) {
      if (m_syncingGridSelectionVisual) {
        return;
      }
      // Focus only: the wallpaper is applied on an explicit click or Enter.
      m_selectedVisibleIndex = (idx.has_value() && *idx < m_visibleEntries.size()) ? *idx : kNoVisibleSelection;
      updatePromotionWindow();
      syncThemeControls();
      if (liveTab()) {
        syncLiveChrome();
      }
      m_dirty = true;
      PanelManager::instance().refresh();
    });
    // While the carousel is in motion, hold thumbnail decodes: a fling then
    // costs the handful of images it lands on instead of every one it passed.
    carousel->setOnMotionChanged([this](bool moving) {
      if (m_thumbnails == nullptr || m_decodeGateHeld == moving) {
        return;
      }
      m_decodeGateHeld = moving;
      if (moving) {
        m_thumbnails->pauseDecodes();
      } else {
        m_thumbnails->resumeDecodes();
      }
    });
    m_adapter->setBrowseThumbnailSizes(kBrowseThumbnailPx, kFocusedThumbnailPx);
    // No promoted range until the initial focus resolves (see updatePromotionWindow): seeding one,
    // or deriving it from the provisional focus, decoded display-tier textures for the first few
    // entries on every open, whether or not they were on screen.
    m_carousel = static_cast<CarouselView*>(root->addChild(std::move(carousel)));
  } else {
    root->addChild(
        ui::virtualGridView({
            .out = &m_grid,
            .contentScale = scale,
            .minCellWidth = kMinTileWidth * scale,
            .squareCells = false,
            .columnGap = Style::spaceMd * scale,
            .rowGap = Style::spaceMd * scale,
            .overscanRows = 2,
            .itemCursorShape = WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER,
            .adapter = m_adapter.get(),
            .flexGrow = 1.0F,
            .onSelectionChanged =
                [this](std::optional<std::size_t> idx) {
                  if (m_syncingGridSelectionVisual) {
                    return;
                  }
                  if (idx.has_value() && *idx < m_visibleEntries.size()) {
                    m_selectedVisibleIndex = *idx;
                  } else {
                    m_selectedVisibleIndex = kNoVisibleSelection;
                  }
                  syncThemeControls();
                  if (liveTab()) {
                    syncLiveChrome();
                  }
                },
            .configure = [](VirtualGridView& grid) { grid.setFillWidth(true); },
        })
    );
  }

  if (InputArea* browseFocus = browseFocusArea(); browseFocus != nullptr) {
    browseFocus->setOnFocusGain([this]() {
      m_gridKeyboardActive = true;
      if (m_grid != nullptr && hasVisibleSelection()) {
        m_syncingGridSelectionVisual = true;
        m_grid->setSelectedIndex(m_selectedVisibleIndex);
        m_syncingGridSelectionVisual = false;
      }
    });
    browseFocus->setOnFocusLoss([this]() {
      m_gridKeyboardActive = false;
      if (m_grid != nullptr) {
        m_syncingGridSelectionVisual = true;
        m_grid->setSelectedIndex(std::nullopt);
        m_syncingGridSelectionVisual = false;
      }
    });
  }

  // Loading state shown while the directory scan runs on the worker thread.
  // Occupies the body in place of the grid (only one is visible at a time).
  root->addChild(
      ui::column(
          {
              .out = &m_loadingBox,
              .align = FlexAlign::Center,
              .justify = FlexJustify::Center,
              .gap = Style::spaceMd * scale,
              .fillWidth = true,
              .flexGrow = 1.0F,
              .visible = false,
          },
          ui::spinner({
              .out = &m_spinner,
              .spinnerSize = Style::fontSizeTitle * scale * 1.6F,
              .spinning = false,
          }),
          ui::label({
              .text = i18n::tr("wallpaper.panel.loading"),
              .fontSize = Style::fontSizeBody * scale,
              .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
          })
      )
  );

  setRoot(std::move(root));
  if (m_animations != nullptr) {
    this->root()->setAnimationManager(m_animations);
  }

  if (m_thumbnails != nullptr) {
    m_thumbnailPendingSub = m_thumbnails->subscribePendingUpload([this]() {
      if (m_rootLayout == nullptr) {
        return;
      }
      m_thumbnailRefreshPending = true;
      PanelManager::instance().requestUpdateOnly();
    });
  }
}

void WallpaperPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_lastWidth = width;
  m_lastHeight = height;

  if (m_thumbnails != nullptr) {
    (void)m_thumbnails->uploadPending(renderer.textureManager());
    m_thumbnailRefreshPending = false;
  }

  if (m_adapter != nullptr) {
    m_adapter->setRenderer(&renderer);
  }

  // Drive cell height from current tile width via VirtualGridView's resolved
  // geometry: configure the cell height to follow the chosen tile aspect.
  if (m_grid != nullptr) {
    m_grid->setCellHeight(kMinTileWidth * contentScale() * kTileAspect);
  }

  // The focused card is sized from a preference, not as a fraction of the band: the band only
  // bounds it. So a wider output keeps the card the same size and the carousel resolves more
  // visible neighbours (ui/controls/carousel_geometry.h), while a narrow one shrinks the card
  // rather than the arc. Resolved here, on layout, never per frame.
  if (m_carousel != nullptr) {
    const float preferred =
        m_config != nullptr ? static_cast<float>(m_config->config().wallpaper.carouselCardWidth) : 760.0F;
    const float cellW = ui::responsive::resolve(
        {.min = kCarouselMinCardWidth, .preferred = preferred, .max = kCarouselMaxCardWidth}, width, contentScale(),
        kCarouselMaxBandFraction
    );
    // The view shrinks this to fit its own body height, keeping the aspect.
    m_carousel->setCellSize(cellW, cellW * kTileAspect);
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
  m_dirty = false;

  // The arc is resolved by the layout above. If it widened or narrowed (first layout on a wide
  // output, output change, card-size setting), re-derive the display-tier window now rather than
  // at the next navigation. Compared first, so steady-state layouts do nothing here.
  if (m_carousel != nullptr && m_carousel->visiblePerSide() != m_promotionSide) {
    m_promotionSide = m_carousel->visiblePerSide();
    updatePromotionWindow();
  }
}

void WallpaperPanel::doUpdate(Renderer& renderer) {
  if (m_rootLayout == nullptr) {
    return;
  }

  if (m_thumbnailRefreshPending && m_thumbnails != nullptr) {
    const bool changed = m_thumbnails->uploadPending(renderer.textureManager());
    m_thumbnailRefreshPending = false;
    if (changed && m_adapter != nullptr) {
      m_adapter->setRenderer(&renderer);
      m_adapter->refreshVisibleThumbnails(renderer);
    }
  }
}

void WallpaperPanel::onPanelCardOpacityChanged(float opacity) {
  if (m_menuCard != nullptr) {
    m_menuCard->setCardStyle(contentScale(), opacity, true);
  }
  if (m_filterInput != nullptr) {
    m_filterInput->setSurfaceOpacity(opacity);
  }
  if (m_monitorSelect != nullptr) {
    m_monitorSelect->setSurfaceOpacity(opacity);
  }
  if (m_favoriteThemeSegmented != nullptr) {
    m_favoriteThemeSegmented->setSurfaceOpacity(opacity);
  }
  if (m_favoritePaletteSourceSegmented != nullptr) {
    m_favoritePaletteSourceSegmented->setSurfaceOpacity(opacity);
  }
  if (m_favoritePaletteDetailSelect != nullptr) {
    m_favoritePaletteDetailSelect->setSurfaceOpacity(opacity);
  }
  for (Segmented* segmented : {m_modeSegmented, m_liveCategorySegmented}) {
    if (segmented != nullptr) {
      segmented->setSurfaceOpacity(opacity);
    }
  }
  for (Select* select : {m_liveSourceSelect, m_liveIntervalSelect}) {
    if (select != nullptr) {
      select->setSurfaceOpacity(opacity);
    }
  }
}

void WallpaperPanel::onOpen(std::string_view /*context*/) {
  m_filterQuery.clear();
  m_pendingFilterQuery.clear();
  m_filterDebounceTimer.stop();
  if (m_filterInput != nullptr) {
    m_filterInput->setValue("");
  }
  if (m_flattenToggle != nullptr) {
    m_flattenToggle->setCheckedImmediate(m_flatten);
  }
  m_navStack.clear();
  m_pendingInitialFocus = true;
  // Browsing session: the carousel can cross 20+ wallpapers a second, so while
  // it is open the shared thumbnail cache keeps a larger (still bounded) idle
  // set. Everything this session parked is dropped again in onClose().
  if (m_thumbnails != nullptr && m_thumbnailSession == 0) {
    m_thumbnails->resetStats();
    m_thumbnailSession = m_thumbnails->beginSession(kBrowseSessionIdleBytes, kBrowseSessionIdleEntries);
  }
  if (m_live != nullptr) {
    // Open on Live while a live wallpaper is up; otherwise on the tab used last.
    m_liveTab = m_live->mode() == LiveWallpaperController::Mode::Live
        || m_live->process().active()
        || (m_config != nullptr && m_config->stateString("wallpaper_panel", "tab").value_or("") == "live");
    m_liveChangedConn = m_live->changed().connect([this]() { scheduleLiveRefresh(); });
    if (m_liveTab) {
      m_live->provider().refresh(/*force=*/false); // no-op while the catalog is fresh
    }
  }
  populateMonitorChoices();
  syncSortButtonGlyph();
  reseedRandomSort();
  refreshVisibleEntries();
  resetSelection();
  rebindGrid();
  syncBrowseChrome();
  syncBackButton();
  m_dirty = true;
}

void WallpaperPanel::onClose() {
  m_filterDebounceTimer.stop();
  m_pendingFilterQuery.clear();
  m_filterQuery.clear();

  m_visibleEntries.clear();

  // Detach adapter from grid before either is destroyed; the pool tiles were
  // minted by the adapter.
  if (m_grid != nullptr) {
    m_grid->setAdapter(nullptr);
  }
  if (m_carousel != nullptr) {
    m_carousel->setAdapter(nullptr);
  }
  m_adapter.reset();
  // Never leave the shared decode gate closed behind us.
  if (m_decodeGateHeld && m_thumbnails != nullptr) {
    m_thumbnails->resumeDecodes();
  }
  m_decodeGateHeld = false;
  // Tiles have released their thumbnails by now, so closing the session drops
  // exactly what browsing parked — not what other surfaces (control center,
  // file dialogs) left in the shared cache, and never the desktop wallpaper,
  // which lives in SharedTextureCache rather than here.
  if (m_thumbnails != nullptr && m_thumbnailSession != 0) {
    const auto& stats = m_thumbnails->stats();
    kLog.debug(
        "browse session: {} decodes, {} cache hits, {} evictions, peak idle {:.1f} MB", stats.decodes, stats.idleHits,
        stats.evictions, static_cast<double>(stats.peakIdleBytes) / (1024.0 * 1024.0)
    );
    m_thumbnails->endSession(m_thumbnailSession);
    m_thumbnailSession = 0;
  }
  m_thumbnailPendingSub.disconnect();
  m_liveChangedConn.disconnect();
  m_liveRefreshQueued = false;
  m_modeSegmented = nullptr;
  m_liveOptionsRow = nullptr;
  m_liveSourceSelect = nullptr;
  m_liveCategorySegmented = nullptr;
  m_liveCollectionButton = nullptr;
  m_liveCarouselLabel = nullptr;
  m_liveCarouselToggle = nullptr;
  m_liveIntervalSelect = nullptr;
  m_liveOrderButton = nullptr;
  m_liveStopButton = nullptr;
  m_liveStatusLabel = nullptr;

  m_rootLayout = nullptr;
  m_toolbar = nullptr;
  m_menuCard = nullptr;
  m_favoritesOptionsColumn = nullptr;
  m_title = nullptr;
  m_backButton = nullptr;
  m_monitorSelect = nullptr;
  m_favoriteCurrentButton = nullptr;
  m_filterInput = nullptr;
  m_flattenToggle = nullptr;
  m_flattenLabel = nullptr;
  m_sortButton = nullptr;
  m_refreshButton = nullptr;
  m_colorButton = nullptr;
  m_closeButton = nullptr;
  m_favoriteThemeSegmented = nullptr;
  m_favoritePaletteSourceSegmented = nullptr;
  m_favoritePaletteDetailSelect = nullptr;
  m_grid = nullptr;
  m_carousel = nullptr;
  m_loadingBox = nullptr;
  m_spinner = nullptr;
  m_scanPending = false;
  m_pendingInitialFocus = false;

  clearReleasedRoot();
  m_lastWidth = 0.0F;
  m_lastHeight = 0.0F;
  m_thumbnailRefreshPending = false;
}

bool WallpaperPanel::carouselMode() const { return m_config != nullptr && m_config->config().wallpaper.carousel; }

std::size_t WallpaperPanel::indexOfCurrentWallpaper() const {
  if (liveTab()) {
    const std::string& id = m_live->currentId();
    for (std::size_t i = 0; !id.empty() && i < m_visibleEntries.size(); ++i) {
      if (m_visibleEntries[i].liveId == id) {
        return i;
      }
    }
    return kNoVisibleSelection;
  }
  const std::string current = currentWallpaperPathForSelection();
  if (current.empty()) {
    return kNoVisibleSelection;
  }
  for (std::size_t i = 0; i < m_visibleEntries.size(); ++i) {
    const WallpaperEntry& entry = m_visibleEntries[i];
    if (!entry.isDir && entry.absPath.string() == current) {
      return i;
    }
  }
  return kNoVisibleSelection;
}

InputArea* WallpaperPanel::browseFocusArea() const {
  if (m_carousel != nullptr) {
    return m_carousel->focusArea();
  }
  return m_grid != nullptr ? m_grid->focusArea() : nullptr;
}

bool WallpaperPanel::browseOwnsFocus(const InputArea* area) const {
  return isDescendantOf(
      area, m_carousel != nullptr ? static_cast<const Node*>(m_carousel) : static_cast<const Node*>(m_grid)
  );
}

bool WallpaperPanel::handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) {
  if (!pressed || preedit) {
    return false;
  }

  auto& dispatcher = PanelManager::instance().inputDispatcher();
  InputArea* focused = dispatcher.focusedArea();

  if (m_favoriteThemeSegmented != nullptr && focused == m_favoriteThemeSegmented->focusArea()) {
    const bool moveIntoGrid = KeybindMatcher::matches(KeybindAction::Down, sym, modifiers)
        || KeybindMatcher::matches(KeybindAction::TabNext, sym, modifiers);
    if (moveIntoGrid && browseFocusArea() != nullptr) {
      dispatcher.setFocus(browseFocusArea());
      if (!hasVisibleSelection() && !m_visibleEntries.empty()) {
        selectVisibleIndex(0);
      }
      return true;
    }
  }

  if (m_favoritePaletteSourceSegmented != nullptr && focused == m_favoritePaletteSourceSegmented->focusArea()) {
    const bool moveIntoGrid = KeybindMatcher::matches(KeybindAction::Down, sym, modifiers);
    if (moveIntoGrid && browseFocusArea() != nullptr) {
      dispatcher.setFocus(browseFocusArea());
      if (!hasVisibleSelection() && !m_visibleEntries.empty()) {
        selectVisibleIndex(0);
      }
      return true;
    }
  }

  if (m_filterInput != nullptr
      && focused == m_filterInput->inputArea()
      && KeybindMatcher::matches(KeybindAction::Down, sym, modifiers)
      && browseFocusArea() != nullptr) {
    dispatcher.setFocus(browseFocusArea());
    if (!hasVisibleSelection() && !m_visibleEntries.empty()) {
      selectVisibleIndex(0);
    }
    return true;
  }

  if (focused != nullptr && !browseOwnsFocus(focused)) {
    return false;
  }

  return handleKeyEvent(sym, modifiers);
}

InputArea* WallpaperPanel::initialFocusArea() const {
  return m_filterInput != nullptr ? m_filterInput->inputArea() : nullptr;
}

void WallpaperPanel::populateMonitorChoices() {
  m_monitorChoices.clear();
  m_monitorChoices.push_back({"", i18n::tr("wallpaper.panel.all-monitors")});
  if (m_wayland != nullptr) {
    for (const auto& out : m_wayland->outputs()) {
      if (out.connectorName.empty()) {
        continue;
      }
      m_monitorChoices.push_back({out.connectorName, out.connectorName});
    }
  }

  if (m_selectedMonitorIndex >= m_monitorChoices.size()) {
    m_selectedMonitorIndex = 0;
  }

  if (m_monitorSelect != nullptr) {
    std::vector<std::string> labels;
    labels.reserve(m_monitorChoices.size());
    for (const auto& c : m_monitorChoices) {
      labels.push_back(c.label);
    }
    m_monitorSelect->setOptions(std::move(labels));
    m_monitorSelect->setSelectedIndex(m_selectedMonitorIndex);
  }
}

std::filesystem::path WallpaperPanel::rootDirectoryForSelection() const {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return {};
  }
  const auto& wp = m_config->config().wallpaper;
  const ThemeMode configured = shellThemeMode(m_config->config().theme);
  const bool isLight = m_themeService != nullptr ? m_themeService->isLightMode() : configured == ThemeMode::Light;
  const ThemeMode mode = wallpaper::effectiveThemeMode(configured, isLight);

  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  if (choice.connector.empty() || !wp.perMonitorDirectories) {
    return std::filesystem::path(wallpaper::resolveGlobalWallpaperDirectory(wp, mode));
  }

  if (m_wayland != nullptr) {
    for (const auto& out : m_wayland->outputs()) {
      if (out.connectorName == choice.connector) {
        return std::filesystem::path(wallpaper::resolveWallpaperDirectory(wp, out, mode));
      }
    }
  }
  return std::filesystem::path(wallpaper::resolveGlobalWallpaperDirectory(wp, mode));
}

std::filesystem::path WallpaperPanel::activeDirectoryForSelection() const {
  if (!m_navStack.empty()) {
    return m_navStack.back();
  }
  return rootDirectoryForSelection();
}

std::string WallpaperPanel::currentWallpaperPathForSelection() const {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return {};
  }

  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  return choice.connector.empty() ? m_config->getDefaultWallpaperPath() : m_config->getWallpaperPath(choice.connector);
}

std::optional<Color> WallpaperPanel::selectedFillColor() const {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return std::nullopt;
  }

  const auto& wp = m_config->config().wallpaper;
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  Color sourceColor;
  const std::string currentPath =
      choice.connector.empty() ? m_config->getDefaultWallpaperPath() : m_config->getWallpaperPath(choice.connector);
  if (parseColorWallpaperPath(currentPath, sourceColor)) {
    return sourceColor;
  }

  if (!choice.connector.empty()) {
    for (const auto& ovr : wp.monitorOverrides) {
      if (ovr.match == choice.connector && ovr.fillColor.has_value()) {
        return resolveColorSpec(*ovr.fillColor);
      }
    }
  }

  if (wp.fillColor.has_value()) {
    return resolveColorSpec(*wp.fillColor);
  }
  return std::nullopt;
}

std::vector<std::string> WallpaperPanel::allMonitorConnectors() const {
  std::vector<std::string> connectors;
  if (m_wayland == nullptr) {
    return connectors;
  }
  for (const auto& out : m_wayland->outputs()) {
    if (!out.connectorName.empty()) {
      connectors.push_back(out.connectorName);
    }
  }
  return connectors;
}

std::string WallpaperPanel::displayNameForWallpaperPath(std::string_view path) {
  if (path.starts_with("color:")) {
    return std::string(path.substr(std::string_view("color:").size()));
  }
  const std::filesystem::path filePath(path);
  if (!filePath.filename().empty()) {
    return filePath.filename().string();
  }
  return std::string(path);
}

void WallpaperPanel::syncBrowseChrome() {
  if (m_backButton != nullptr) {
    m_backButton->setVisible(!m_navStack.empty() && !liveTab());
  }
  syncLiveChrome();
  if (m_favoriteCurrentButton != nullptr && m_config != nullptr) {
    const std::string current = currentWallpaperPathForSelection();
    const bool favorite = !current.empty() && m_config->isWallpaperFavorite(current);
    m_favoriteCurrentButton->setEnabled(!current.empty());
    m_favoriteCurrentButton->setGlyph(favorite ? "star-filled" : "star");
    m_favoriteCurrentButton->setTooltip(
        i18n::tr(favorite ? "wallpaper.panel.unfavorite-current" : "wallpaper.panel.favorite-current")
    );
  }
  syncThemeControls();
}

std::string WallpaperPanel::selectedWallpaperPath() const {
  if (m_visibleEntries.empty() || m_selectedVisibleIndex >= m_visibleEntries.size()) {
    return {};
  }
  const auto& entry = m_visibleEntries[m_selectedVisibleIndex];
  if (entry.isDir) {
    return {};
  }
  return entry.absPath.string();
}

void WallpaperPanel::appendFilteredFavoriteEntries(
    std::vector<WallpaperEntry>& out, std::unordered_set<std::string>& favoritePaths,
    const std::filesystem::path& activeDir, const std::filesystem::path& rootDir
) const {
  if (m_config == nullptr) {
    return;
  }

  const std::string filterNeedle = StringUtils::toLower(m_filterQuery);
  for (const auto& favorite : m_config->wallpaperFavorites()) {
    if (!favoriteVisibleInBrowseContext(favorite.path, activeDir, rootDir, m_flatten)) {
      continue;
    }

    const std::string displayName = displayNameForWallpaperPath(favorite.path);
    if (!filterNeedle.empty() && !StringUtils::toLower(displayName).contains(filterNeedle)) {
      continue;
    }

    const std::string normalized = FileUtils::normalizeWallpaperPath(favorite.path);
    if (!favoritePaths.insert(normalized).second) {
      continue;
    }

    WallpaperEntry entry;
    entry.absPath = std::filesystem::path(favorite.path);
    entry.name = displayName;
    entry.isDir = false;
    out.push_back(std::move(entry));
  }
}

void WallpaperPanel::rebuildFavoritePaletteDetailSelect(const WallpaperFavorite* favorite) {
  if (m_favoritePaletteDetailSelect == nullptr) {
    return;
  }

  m_favoritePaletteDetailValues.clear();
  std::vector<std::string> labels;
  std::size_t selectedIndex = 0;
  std::string selectedValue;

  if (favorite != nullptr) {
    const PaletteSource source = favorite->paletteSource.value_or(PaletteSource::Builtin);
    switch (source) {
    case PaletteSource::Builtin:
      for (const auto& builtin : zynith::theme::builtinPalettes()) {
        m_favoritePaletteDetailValues.emplace_back(builtin.name);
        labels.emplace_back(builtin.name);
      }
      selectedValue = favorite->builtinPalette;
      break;
    case PaletteSource::Wallpaper:
      m_favoritePaletteDetailValues = wallpaperSchemeValues();
      labels = wallpaperSchemeOptions();
      selectedValue = favorite->wallpaperScheme;
      break;
    case PaletteSource::Community:
      for (const auto& community : zynith::theme::availableCommunityPalettes()) {
        m_favoritePaletteDetailValues.push_back(community.name);
        labels.push_back(community.name);
      }
      selectedValue = favorite->communityPalette;
      break;
    case PaletteSource::Custom:
      for (const auto& custom : zynith::theme::availableCustomPalettes()) {
        m_favoritePaletteDetailValues.push_back(custom.name);
        labels.push_back(custom.name);
      }
      selectedValue = favorite->customPalette;
      break;
    }
  }

  const bool visible = !labels.empty();
  m_favoritePaletteDetailSelect->setVisible(visible);
  if (!visible) {
    m_favoritePaletteDetailSelect->setOptions({});
    m_favoritePaletteDetailSelect->clearSelection();
    return;
  }

  m_favoritePaletteDetailSelect->setOptions(std::move(labels));
  if (!selectedValue.empty()) {
    for (std::size_t i = 0; i < m_favoritePaletteDetailValues.size(); ++i) {
      if (m_favoritePaletteDetailValues[i] == selectedValue) {
        selectedIndex = i;
        break;
      }
    }
  }
  m_favoritePaletteDetailSelect->setSelectedIndex(selectedIndex);
}

std::optional<PaletteSource> WallpaperPanel::paletteSourceForSegment(std::size_t index) const {
  if (index >= m_paletteSourceOrder.size()) {
    return std::nullopt;
  }
  return m_paletteSourceOrder[index];
}

std::size_t WallpaperPanel::segmentForPaletteSource(PaletteSource source) const {
  for (std::size_t i = 0; i < m_paletteSourceOrder.size(); ++i) {
    if (m_paletteSourceOrder[i] == source) {
      return i;
    }
  }
  return 0;
}

WallpaperFavorite WallpaperPanel::activeThemeSettings() const {
  // A selected favorite wallpaper's saved preset is the source of truth; otherwise the live global theme is.
  WallpaperFavorite theme =
      (m_config != nullptr) ? wallpaperFavoriteFromTheme(m_config->config().theme) : WallpaperFavorite{};
  if (m_config != nullptr) {
    if (const std::string path = selectedWallpaperPath(); !path.empty()) {
      if (const WallpaperFavorite* favorite = m_config->wallpaperFavorite(path); favorite != nullptr) {
        theme = *favorite;
      }
    }
  }
  return theme;
}

void WallpaperPanel::applyThemeFromControls() {
  if (m_config == nullptr) {
    return;
  }
  const WallpaperFavorite theme = themeFromControls();
  const std::string path = selectedWallpaperPath();

  if (!path.empty() && m_config->isWallpaperFavorite(path)) {
    // Edit the selected wallpaper's favorite preset and apply it live (also re-asserts the wallpaper).
    m_config->setWallpaperFavoriteThemeMode(path, theme.themeMode);
    m_config->setWallpaperFavoritePaletteSource(path, theme.paletteSource);
    m_config->setWallpaperFavoritePaletteSelection(path, paletteSelectionValue(theme));
    applyWallpaperPath(path, &theme);
    return;
  }

  // No favorite target, so behave like the Settings window and change the global theme only.
  m_config->setThemeMode(theme.themeMode);
  if (theme.paletteSource.has_value()) {
    (void)m_config->setThemeColorScheme(*theme.paletteSource, paletteSelectionValue(theme));
  }
}

void WallpaperPanel::syncThemeControls() {
  if (liveTab()) {
    return; // the palette controls belong to static wallpapers; the Live tab hides them
  }
  if (m_favoriteThemeSegmented == nullptr || m_config == nullptr) {
    return;
  }

  const WallpaperFavorite themeSettings = activeThemeSettings();

  m_syncingFavoriteControls = true;

  m_favoriteThemeSegmented->setSelectedIndex(themeModeSegmentIndex(themeSettings.themeMode));

  if (m_favoritePaletteSourceSegmented != nullptr) {
    const std::size_t sourceIndex =
        themeSettings.paletteSource.has_value() ? segmentForPaletteSource(*themeSettings.paletteSource) : 0;
    m_favoritePaletteSourceSegmented->setSelectedIndex(sourceIndex);
  }

  rebuildFavoritePaletteDetailSelect(&themeSettings);
  m_syncingFavoriteControls = false;
}

void WallpaperPanel::refreshScan() {
  const auto dir = activeDirectoryForSelection();
  if (dir.empty() || m_scanner == nullptr) {
    m_scanPending = false;
    return;
  }
  // requestScan() returns false when a worker scan was queued; the entries
  // arrive later via onScanComplete(). A cached/fresh dir returns true.
  m_scanPending = !m_scanner->requestScan(dir, m_flatten);
}

void WallpaperPanel::refreshVisibleEntries() {
  if (liveTab()) {
    rebuildLiveEntries();
    syncLoadingState();
    return;
  }
  refreshScan();
  applyFilter();
  syncLoadingState();
}

void WallpaperPanel::onScanComplete() {
  // The scanner outlives the panel's UI; ignore late results after teardown.
  if (m_rootLayout == nullptr || liveTab()) {
    return;
  }
  const auto dir = activeDirectoryForSelection();
  m_scanPending = !dir.empty() && m_scanner != nullptr && m_scanner->scanning(dir, m_flatten);

  applyFilter();
  rebindGrid();
  syncBrowseChrome();
  syncLoadingState();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::syncLoadingState() {
  const bool loading = m_scanPending;
  if (m_loadingBox != nullptr) {
    m_loadingBox->setVisible(loading);
  }
  if (m_grid != nullptr) {
    m_grid->setVisible(!loading);
  }
  if (m_carousel != nullptr) {
    m_carousel->setVisible(!loading);
  }
  if (m_spinner != nullptr) {
    if (loading) {
      m_spinner->start();
    } else {
      m_spinner->stop();
    }
  }
}

void WallpaperPanel::applyFilter() {
  if (liveTab()) {
    rebuildLiveEntries();
    return;
  }
  m_visibleEntries.clear();
  std::unordered_set<std::string> favoritePaths;
  const auto dir = activeDirectoryForSelection();
  const auto rootDir = rootDirectoryForSelection();
  appendFilteredFavoriteEntries(m_visibleEntries, favoritePaths, dir, rootDir);
  m_pinnedFavoriteCount = m_visibleEntries.size();

  const WallpaperScanResult* result =
      (dir.empty() || m_scanner == nullptr) ? nullptr : m_scanner->cached(dir, m_flatten);
  if (result != nullptr) {
    const std::string needle = StringUtils::toLower(m_filterQuery);
    const bool filterActive = !needle.empty();
    m_visibleEntries.reserve(m_visibleEntries.size() + result->entries.size());
    for (const auto& entry : result->entries) {
      if (!entry.isDir) {
        const std::string normalized = FileUtils::normalizeWallpaperPath(entry.absPath.string());
        if (favoritePaths.contains(normalized)) {
          continue;
        }
      }
      if (filterActive && !StringUtils::toLower(entry.name).contains(needle)) {
        continue;
      }
      m_visibleEntries.push_back(entry);
    }
  }

  sortVisibleEntries();
  if (m_selectedVisibleIndex >= m_visibleEntries.size()) {
    resetSelection();
  }
}

void WallpaperPanel::updatePromotionWindow() {
  // While the initial focus is pending, the carousel reports a provisional focus (index 0) as the
  // entries arrive; rebindGrid derives the window once the real one (the wallpaper in use) lands.
  if (m_adapter == nullptr
      || m_thumbnails == nullptr
      || !m_carouselMode
      || m_visibleEntries.empty()
      || !hasVisibleSelection()
      || m_pendingInitialFocus) {
    return;
  }
  const auto focus = static_cast<long>(m_selectedVisibleIndex);

  // Which way is the user travelling? The window leans that way so the next
  // cards are already display-quality when they arrive at the centre, and the
  // ones left behind give their textures back.
  if (focus != m_lastPromotionFocus) {
    if (m_lastPromotionFocus >= 0) {
      m_promotionDirection = focus >= m_lastPromotionFocus ? 1 : -1;
    }
    m_lastPromotionFocus = focus;
  }

  const std::size_t perSide = m_carousel != nullptr ? m_carousel->visiblePerSide() : 0;
  const long behind = perSide > 0 ? static_cast<long>(perSide) : kPromotionFallbackSide;
  const long ahead = behind + kPromotionLead;
  const long lo = focus - (m_promotionDirection >= 0 ? behind : ahead);
  const long hi = focus + (m_promotionDirection >= 0 ? ahead : behind);
  const bool windowMoved = lo != m_promotionLo || hi != m_promotionHi;
  m_promotionLo = lo;
  m_promotionHi = hi;
  m_adapter->setPromotedRange(lo, hi);
  if (windowMoved && m_carousel != nullptr) {
    // Bound tiles cache their promotion state, so the window change has to reach
    // them: rebinding is just a thumbnail re-evaluation for the few live tiles.
    m_carousel->notifyDataChanged();
  }

  // Predictive: queue the display-quality decode for the window before those
  // cards reach the centre. Anything outside is simply not requested; its
  // texture ages out of the session's idle set.
  const auto count = static_cast<long>(m_visibleEntries.size());
  for (long i = lo; i <= hi; ++i) {
    if (i < 0 || i >= count) {
      continue;
    }
    const WallpaperEntry& entry = m_visibleEntries[static_cast<std::size_t>(i)];
    if (!entry.isDir) {
      m_thumbnails->prefetch(entry.absPath.string(), kFocusedThumbnailPx);
    }
  }
}

void WallpaperPanel::prefetchSessionThumbnails() {
  if (m_thumbnails == nullptr || m_visibleEntries.empty() || !m_carouselMode) {
    return;
  }
  // Walk outward from the focused item so the neighbourhood is ready first and a
  // fast flick in either direction stays instant.
  const std::size_t count = m_visibleEntries.size();
  const std::size_t centre = hasVisibleSelection() ? m_selectedVisibleIndex : 0;
  std::size_t queued = 0;
  const std::size_t cap = liveTab() ? kMaxLivePrefetchEntries : kMaxPrefetchEntries;
  for (std::size_t step = 0; step < count && queued < cap; ++step) {
    for (const long dir : {1L, -1L}) {
      if (step == 0 && dir < 0) {
        continue; // centre once
      }
      const long idx = static_cast<long>(centre) + dir * static_cast<long>(step);
      if (idx < 0 || idx >= static_cast<long>(count)) {
        continue;
      }
      const WallpaperEntry& entry = m_visibleEntries[static_cast<std::size_t>(idx)];
      if (entry.isDir) {
        continue;
      }
      m_thumbnails->prefetch(entry.absPath.string(), kBrowseThumbnailPx);
      if (++queued >= cap) {
        break;
      }
    }
  }
  kLog.debug("browse session: prefetching {} of {} entries at {} px", queued, count, kBrowseThumbnailPx);
}

void WallpaperPanel::rebindGrid(bool resetScroll) {
  if (m_adapter != nullptr) {
    m_adapter->setCurrentWallpaperPath(liveTab() ? std::string() : currentWallpaperPathForSelection());
    m_adapter->setCurrentLiveId(
        m_live != nullptr && m_live->mode() == LiveWallpaperController::Mode::Live ? m_live->currentId() : std::string()
    );
  }
  if (m_carousel != nullptr) {
    m_carousel->notifyDataChanged();
    const bool initialFocus = m_pendingInitialFocus && !m_visibleEntries.empty();
    if (initialFocus || resetScroll || m_visibleEntries.empty() || !hasVisibleSelection()) {
      // Open on the wallpaper that is actually in use, so the browser says
      // "this is what you are running" before the user touches anything. The
      // scan is async, so the first rebind usually has nothing to focus yet —
      // hence the one-shot flag rather than a plain "on open" reset.
      const std::size_t current = indexOfCurrentWallpaper();
      m_carousel->resetTo(current == kNoVisibleSelection ? 0U : current);
      if (initialFocus) {
        m_pendingInitialFocus = false;
        updatePromotionWindow();
        prefetchSessionThumbnails();
      }
    } else if (hasVisibleSelection()) {
      m_carousel->setFocusedIndex(m_selectedVisibleIndex, /*animated=*/false);
    }
    return;
  }
  if (m_grid == nullptr) {
    return;
  }
  m_grid->notifyDataChanged();
  if (resetScroll || m_visibleEntries.empty()) {
    m_grid->scrollView().setScrollOffset(0.0F);
  }
  if (m_visibleEntries.empty() || !hasVisibleSelection() || !m_gridKeyboardActive) {
    m_grid->setSelectedIndex(std::nullopt);
  } else {
    m_grid->setSelectedIndex(m_selectedVisibleIndex);
  }
}

void WallpaperPanel::resetSelection() { m_selectedVisibleIndex = kNoVisibleSelection; }

bool WallpaperPanel::hasVisibleSelection() const { return m_selectedVisibleIndex < m_visibleEntries.size(); }

void WallpaperPanel::toggleFavoriteForPath(const std::string& path) {
  if (m_config == nullptr || path.empty()) {
    return;
  }

  if (m_config->isWallpaperFavorite(path)) {
    m_config->removeWallpaperFavorite(path);
  } else {
    std::optional<WallpaperFavorite> preset;
    const std::string currentPath = currentWallpaperPathForSelection();
    if (!currentPath.empty()
        && FileUtils::normalizeWallpaperPath(path) == FileUtils::normalizeWallpaperPath(currentPath)) {
      preset = wallpaperFavoriteFromTheme(m_config->config().theme);
    }
    m_config->addWallpaperFavorite(path, preset);
  }

  refreshVisibleEntries();
  rebindGrid();
  syncBrowseChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::applyWallpaperPath(const std::string& path, const WallpaperFavorite* applyTheme) {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return;
  }

  // Choosing a static wallpaper ends Live mode: the static surfaces come back first, then the renderer
  // stops (LiveWallpaperController::switchToStatic), and the new image transitions in as usual.
  if (m_live != nullptr && (m_live->mode() == LiveWallpaperController::Mode::Live || m_live->process().active())) {
    m_live->switchToStatic();
  }
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  const std::optional<std::string> connector =
      choice.connector.empty() ? std::optional<std::string>{} : std::optional<std::string>{choice.connector};
  m_config->applyWallpaperSelection(connector, path, applyTheme, allMonitorConnectors());
  rebindGrid();
  syncBrowseChrome();
}

const WallpaperFavorite* WallpaperPanel::favoriteThemeToApply(std::string_view path) const {
  if (m_config == nullptr || !m_config->isWallpaperFavorite(path)) {
    return nullptr;
  }
  return m_config->wallpaperFavorite(path);
}

WallpaperFavorite WallpaperPanel::themeFromControls() const {
  WallpaperFavorite theme;
  if (m_favoriteThemeSegmented != nullptr) {
    theme.themeMode = themeModeFromSegmentIndex(m_favoriteThemeSegmented->selectedIndex());
  }
  if (m_favoritePaletteSourceSegmented != nullptr) {
    theme.paletteSource = paletteSourceForSegment(m_favoritePaletteSourceSegmented->selectedIndex());
  }
  if (m_favoritePaletteDetailSelect != nullptr && !m_favoritePaletteDetailValues.empty()) {
    const std::size_t index = m_favoritePaletteDetailSelect->selectedIndex();
    if (index < m_favoritePaletteDetailValues.size()) {
      const std::string& value = m_favoritePaletteDetailValues[index];
      switch (theme.paletteSource.value_or(PaletteSource::Builtin)) {
      case PaletteSource::Builtin:
        theme.builtinPalette = value;
        break;
      case PaletteSource::Wallpaper:
        theme.wallpaperScheme = value;
        break;
      case PaletteSource::Community:
        theme.communityPalette = value;
        break;
      case PaletteSource::Custom:
        theme.customPalette = value;
        break;
      }
    }
  }
  return theme;
}

void WallpaperPanel::selectVisibleIndex(std::size_t index) {
  if (m_visibleEntries.empty() || index >= m_visibleEntries.size()) {
    return;
  }

  m_selectedVisibleIndex = index;
  if (m_carousel != nullptr) {
    m_carousel->setFocusedIndex(index, /*animated=*/true);
  } else if (m_grid != nullptr) {
    m_grid->setSelectedIndex(index);
    m_grid->scrollToIndex(index);
  }
  syncThemeControls();

  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::activateSelectedEntry() {
  if (!hasVisibleSelection()) {
    return;
  }

  const auto& entry = m_visibleEntries[m_selectedVisibleIndex];
  if (entry.isDir) {
    navigateInto(entry.absPath);
  } else {
    applyWallpaperFromEntry(entry);
  }
}

bool WallpaperPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_visibleEntries.empty()) {
    return false;
  }

  // Approximate column count from current grid layout. VirtualGridView does
  // not expose its column count directly, so we recompute from viewport width.
  // The carousel is a single row: Up/Down step one item, like Left/Right.
  std::size_t columns = 1;
  if (m_grid != nullptr) {
    const float viewportW = m_grid->scrollView().contentViewportWidth();
    const float cellW = kMinTileWidth * contentScale();
    const float gap = Style::spaceMd * contentScale();
    if (cellW > 0.0F) {
      columns = std::max<std::size_t>(1, static_cast<std::size_t>((viewportW + gap) / (cellW + gap)));
    }
  }

  if (KeybindMatcher::matches(KeybindAction::Left, sym, modifiers)) {
    if (!hasVisibleSelection()) {
      return true;
    }
    if (m_selectedVisibleIndex > 0) {
      selectVisibleIndex(m_selectedVisibleIndex - 1);
    }
    return true;
  }

  if (KeybindMatcher::matches(KeybindAction::Right, sym, modifiers)) {
    if (!hasVisibleSelection()) {
      selectVisibleIndex(0);
    } else if (m_selectedVisibleIndex + 1 < m_visibleEntries.size()) {
      selectVisibleIndex(m_selectedVisibleIndex + 1);
    }
    return true;
  }

  if (KeybindMatcher::matches(KeybindAction::Up, sym, modifiers)) {
    if (!hasVisibleSelection()) {
      selectVisibleIndex(0);
    } else if (m_selectedVisibleIndex >= columns) {
      selectVisibleIndex(m_selectedVisibleIndex - columns);
    }
    return true;
  }

  if (KeybindMatcher::matches(KeybindAction::Down, sym, modifiers)) {
    if (!hasVisibleSelection()) {
      selectVisibleIndex(0);
    } else {
      const std::size_t nextIndex = m_selectedVisibleIndex + columns;
      if (nextIndex < m_visibleEntries.size()) {
        selectVisibleIndex(nextIndex);
      }
    }
    return true;
  }

  if (KeybindMatcher::matches(KeybindAction::Validate, sym, modifiers)) {
    activateSelectedEntry();
    return true;
  }

  return false;
}

void WallpaperPanel::syncBackButton() {
  uiAssertNotRendering("WallpaperPanel::syncBackButton");
  if (m_backButton == nullptr) {
    return;
  }
  const bool canNavigateUp = !m_navStack.empty();
  m_backButton->setEnabled(canNavigateUp);
  m_backButton->setVisible(canNavigateUp);
}

void WallpaperPanel::navigateInto(const std::filesystem::path& dir) {
  m_navStack.push_back(dir);
  refreshVisibleEntries();
  resetSelection();
  rebindGrid(true);
  syncBackButton();
  syncBrowseChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::navigateUp() {
  if (m_navStack.empty()) {
    return;
  }
  m_navStack.pop_back();
  refreshVisibleEntries();
  resetSelection();
  rebindGrid(true);
  syncBackButton();
  syncBrowseChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

WallpaperPanel::SortMode WallpaperPanel::sortModeFromState(std::string_view value) {
  if (value == "name_desc") {
    return SortMode::NameDesc;
  }
  if (value == "date_asc") {
    return SortMode::DateAsc;
  }
  if (value == "date_desc") {
    return SortMode::DateDesc;
  }
  if (value == "random") {
    return SortMode::Random;
  }
  return SortMode::NameAsc;
}

std::string_view WallpaperPanel::sortModeStateValue(SortMode mode) {
  switch (mode) {
  case SortMode::NameDesc:
    return "name_desc";
  case SortMode::DateAsc:
    return "date_asc";
  case SortMode::DateDesc:
    return "date_desc";
  case SortMode::Random:
    return "random";
  case SortMode::NameAsc:
  default:
    return "name_asc";
  }
}

std::string_view WallpaperPanel::sortModeGlyph(SortMode mode) {
  switch (mode) {
  case SortMode::NameDesc:
    return "sort-z-a";
  case SortMode::DateAsc:
    return "sort-ascending-2";
  case SortMode::DateDesc:
    return "sort-descending-2";
  case SortMode::Random:
    return "arrows-random";
  case SortMode::NameAsc:
  default:
    return "sort-a-z";
  }
}

const char* WallpaperPanel::sortModeTooltipKey(SortMode mode) {
  switch (mode) {
  case SortMode::NameDesc:
    return "wallpaper.panel.sort-name-desc";
  case SortMode::DateAsc:
    return "wallpaper.panel.sort-date-asc";
  case SortMode::DateDesc:
    return "wallpaper.panel.sort-date-desc";
  case SortMode::Random:
    return "wallpaper.panel.sort-random";
  case SortMode::NameAsc:
  default:
    return "wallpaper.panel.sort-name-asc";
  }
}

void WallpaperPanel::syncSortButtonGlyph() {
  if (m_sortButton == nullptr) {
    return;
  }
  m_sortButton->setGlyph(sortModeGlyph(m_sortMode));
  m_sortButton->setTooltip(i18n::tr(sortModeTooltipKey(m_sortMode)));

  if (!m_sortButton->hovered()) {
    return;
  }
  InputArea* area = m_sortButton->inputArea();
  if (area == nullptr || !area->hasTooltip()) {
    return;
  }
  const auto parentCtx = PanelManager::instance().fallbackPopupParentContext();
  if (!parentCtx.has_value() || parentCtx->layerSurface == nullptr || parentCtx->output == nullptr) {
    return;
  }
  TooltipManager::instance().onHoverChange(area, parentCtx->layerSurface, parentCtx->output);
}

void WallpaperPanel::cycleSortMode() {
  SortMode next = SortMode::NameAsc;
  switch (m_sortMode) {
  case SortMode::NameAsc:
    next = SortMode::NameDesc;
    break;
  case SortMode::NameDesc:
    next = SortMode::DateAsc;
    break;
  case SortMode::DateAsc:
    next = SortMode::DateDesc;
    break;
  case SortMode::DateDesc:
    next = SortMode::Random;
    break;
  case SortMode::Random:
    next = SortMode::NameAsc;
    break;
  }
  setSortMode(next);
}

void WallpaperPanel::setSortMode(SortMode mode) {
  if (m_sortMode == mode) {
    return;
  }
  m_sortMode = mode;
  if (mode == SortMode::Random) {
    reseedRandomSort();
  }
  if (m_config != nullptr) {
    (void)m_config->setStateString("wallpaper_panel", "sort", std::string(sortModeStateValue(mode)));
  }
  syncSortButtonGlyph();
  sortVisibleEntries();
  rebindGrid();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::reseedRandomSort() {
  m_randomSeed = std::uniform_int_distribution<std::uint64_t>{}(Random::rng());
}

void WallpaperPanel::sortVisibleEntries() {
  if (m_visibleEntries.empty() || liveTab()) { // live lists keep their own order (collection, recency, title)
    return;
  }

  const auto compareEntries = [this](const WallpaperEntry& a, const WallpaperEntry& b) {
    switch (m_sortMode) {
    case SortMode::NameDesc: {
      const int order = caseInsensitiveNameOrder(a.name, b.name);
      return order > 0;
    }
    case SortMode::DateAsc: {
      const auto aTime = entryModifiedTime(a);
      const auto bTime = entryModifiedTime(b);
      if (aTime.has_value() && bTime.has_value()) {
        if (*aTime != *bTime) {
          return *aTime < *bTime;
        }
      } else if (aTime.has_value() != bTime.has_value()) {
        return !aTime.has_value();
      }
      return caseInsensitiveNameOrder(a.name, b.name) < 0;
    }
    case SortMode::DateDesc: {
      const auto aTime = entryModifiedTime(a);
      const auto bTime = entryModifiedTime(b);
      if (aTime.has_value() && bTime.has_value()) {
        if (*aTime != *bTime) {
          return *aTime > *bTime;
        }
      } else if (aTime.has_value() != bTime.has_value()) {
        return aTime.has_value();
      }
      return caseInsensitiveNameOrder(a.name, b.name) < 0;
    }
    case SortMode::Random: {
      const std::uint64_t aKey = randomOrderKey(a, m_randomSeed);
      const std::uint64_t bKey = randomOrderKey(b, m_randomSeed);
      if (aKey != bKey) {
        return aKey < bKey;
      }
      return caseInsensitiveNameOrder(a.name, b.name) < 0;
    }
    case SortMode::NameAsc:
    default: {
      const int order = caseInsensitiveNameOrder(a.name, b.name);
      return order < 0;
    }
    }
  };

  const auto sortRange = [&](const std::size_t beginIndex, const std::size_t endIndex, const bool foldersFirst) {
    if (beginIndex >= endIndex || beginIndex >= m_visibleEntries.size()) {
      return;
    }
    const std::size_t end = std::min(endIndex, m_visibleEntries.size());
    const auto begin = m_visibleEntries.begin() + static_cast<std::ptrdiff_t>(beginIndex);
    const auto endIt = m_visibleEntries.begin() + static_cast<std::ptrdiff_t>(end);
    if (foldersFirst) {
      const auto folderEnd = std::partition(begin, endIt, [](const WallpaperEntry& entry) { return entry.isDir; });
      std::sort(begin, folderEnd, compareEntries);
      std::sort(folderEnd, endIt, compareEntries);
    } else {
      std::sort(begin, endIt, compareEntries);
    }
  };

  sortRange(0, m_pinnedFavoriteCount, false);
  sortRange(m_pinnedFavoriteCount, m_visibleEntries.size(), !m_flatten);
}

void WallpaperPanel::applyWallpaperFromEntry(const WallpaperEntry& entry) {
  if (entry.isDir) {
    return;
  }
  if (!entry.liveId.empty()) {
    applyLiveEntry(entry);
    return;
  }

  const std::string path = entry.absPath.string();

  // An accidental double-click would otherwise run palette extraction and a
  // wallpaper transition twice for the same image, stacking two transitions.
  // Deliberate re-application still works — the guard only spans one gesture.
  const auto now = std::chrono::steady_clock::now();
  if (path == m_lastAppliedPath && now - m_lastAppliedAt < kReapplyGuard) {
    kLog.debug("ignoring repeat apply of {} within the double-click guard", path);
    return;
  }
  m_lastAppliedPath = path;
  m_lastAppliedAt = now;
  applyWallpaperPath(path, favoriteThemeToApply(path));
  kLog.info(
      "applied wallpaper {} to {}", path,
      m_selectedMonitorIndex == 0 ? "ALL" : m_monitorChoices[m_selectedMonitorIndex].connector
  );
}

void WallpaperPanel::applyColorWallpaper() {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return;
  }

  ColorPickerDialogOptions options;
  options.title = i18n::tr("wallpaper.panel.color-title");
  if (auto color = selectedFillColor()) {
    options.initialColor = *color;
  } else if (auto last = ColorPickerDialog::lastResult()) {
    options.initialColor = *last;
  }

  (void)ColorPickerDialog::open(std::move(options), [this](std::optional<Color> result) {
    if (!result.has_value() || m_config == nullptr) {
      return;
    }

    Color rgb = *result;
    rgb.a = 1.0F;
    applyWallpaperPath(colorWallpaperPath(rgb), nullptr);
    syncBrowseChrome();
    kLog.info("applied color wallpaper {}", colorWallpaperPath(rgb));
  });
}

// ── zynith: Live tab ────────────────────────────────────────────────────────

void WallpaperPanel::setLiveTab(bool live) {
  if (m_live == nullptr || m_liveTab == live) {
    return;
  }
  m_liveTab = live;
  if (m_config != nullptr) {
    (void)m_config->setStateString("wallpaper_panel", "tab", live ? "live" : "static");
  }
  if (live) {
    m_live->provider().refresh(/*force=*/false);
  }
  m_navStack.clear();
  m_pendingInitialFocus = true;
  m_lastPromotionFocus = -1;
  refreshVisibleEntries();
  resetSelection();
  rebindGrid(true);
  syncBackButton();
  syncBrowseChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

std::string WallpaperPanel::focusedLiveId() const {
  if (!hasVisibleSelection()) {
    return {};
  }
  return m_visibleEntries[m_selectedVisibleIndex].liveId;
}

void WallpaperPanel::rebuildLiveEntries() {
  const std::string keepId = focusedLiveId();
  m_visibleEntries.clear();
  m_pinnedFavoriteCount = 0;
  if (m_live == nullptr) {
    return;
  }
  const LiveWallpaperProvider& provider = m_live->provider();
  m_scanPending = provider.discovering() && provider.items().empty();

  const std::string needle = StringUtils::toLower(m_filterQuery);
  const auto items = m_live->itemsFor(m_live->category());
  m_visibleEntries.reserve(items.size());
  for (const live::Item* item : items) {
    if (!needle.empty() && !StringUtils::toLower(item->title).contains(needle) && item->id != needle) {
      continue;
    }
    WallpaperEntry entry;
    entry.name = item->title;
    // The author's preview inside the Steam Workshop folder is the thumbnail source. An item without one
    // uses its folder: unique per item, and it simply fails to decode into the tile's placeholder.
    entry.absPath = item->preview.empty() ? item->directory : item->preview;
    entry.liveId = item->id;
    m_visibleEntries.push_back(std::move(entry));
  }

  resetSelection();
  if (!keepId.empty()) {
    for (std::size_t i = 0; i < m_visibleEntries.size(); ++i) {
      if (m_visibleEntries[i].liveId == keepId) {
        m_selectedVisibleIndex = i;
        break;
      }
    }
  }
}

void WallpaperPanel::applyLiveEntry(const WallpaperEntry& entry) {
  if (m_live == nullptr) {
    return;
  }
  // Copy first: selecting emits changes that rebuild m_visibleEntries (deferred, but be safe).
  const std::string id = entry.liveId;
  const std::string guardKey = "live:" + id;
  const auto now = std::chrono::steady_clock::now();
  if (guardKey == m_lastAppliedPath && now - m_lastAppliedAt < kReapplyGuard) {
    return;
  }
  m_lastAppliedPath = guardKey;
  m_lastAppliedAt = now;
  if (id == m_live->currentId() && m_live->mode() == LiveWallpaperController::Mode::Live) {
    return; // already showing it
  }
  std::string error;
  if (!m_live->select(id, &error)) {
    kLog.warn("live wallpaper {} not applied: {}", id, error);
  }
  syncLiveChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::scheduleLiveRefresh() {
  // Controller changes arrive from renderer callbacks, IPC and from inside our own click handlers
  // (select() emits synchronously while the adapter is still dispatching the activation). Coalesce them
  // and apply at the top of the next loop iteration, never mid-dispatch.
  if (m_liveRefreshQueued) {
    return;
  }
  m_liveRefreshQueued = true;
  DeferredCall::callLater([this]() { onLiveChanged(); });
}

void WallpaperPanel::onLiveChanged() {
  if (!m_liveRefreshQueued) {
    return; // panel closed in the meantime
  }
  m_liveRefreshQueued = false;
  if (m_rootLayout == nullptr) {
    return;
  }
  if (liveTab()) {
    rebuildLiveEntries();
    syncLoadingState();
    rebindGrid();
    if (m_pendingInitialFocus == false && m_carouselMode) {
      updatePromotionWindow();
    }
  } else {
    rebindGrid();
  }
  syncBrowseChrome();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::syncLiveChrome() {
  const bool live = liveTab();
  // Static-only chrome.
  for (Node* node : std::initializer_list<Node*>{
           m_flattenLabel, m_flattenToggle, m_monitorSelect, m_colorButton, m_sortButton, m_favoritesOptionsColumn
       }) {
    if (node != nullptr) {
      node->setVisible(!live);
    }
  }
  if (m_liveOptionsRow != nullptr) {
    m_liveOptionsRow->setVisible(live);
  }
  if (m_liveStatusLabel != nullptr) {
    m_liveStatusLabel->setVisible(live);
  }
  if (m_live == nullptr) {
    return;
  }

  m_syncingLiveControls = true;
  if (m_modeSegmented != nullptr) {
    m_modeSegmented->setSelectedIndex(live ? 1 : 0);
  }
  if (m_liveCategorySegmented != nullptr) {
    m_liveCategorySegmented->setSelectedIndex(static_cast<std::size_t>(m_live->category()));
  }
  if (m_liveCarouselToggle != nullptr) {
    m_liveCarouselToggle->setCheckedImmediate(m_live->carouselEnabled());
  }
  if (m_liveIntervalSelect != nullptr) {
    const auto& presets = LiveWallpaperController::kCarouselIntervalPresets;
    std::size_t nearest = 0;
    for (std::size_t i = 0; i < presets.size(); ++i) {
      if (std::abs(presets[i] - m_live->carouselInterval()) < std::abs(presets[nearest] - m_live->carouselInterval())) {
        nearest = i;
      }
    }
    m_liveIntervalSelect->setSelectedIndexSilently(nearest);
  }
  m_syncingLiveControls = false;

  if (m_liveOrderButton != nullptr) {
    const bool shuffle = m_live->carouselOrder() == LiveWallpaperController::CarouselOrder::Shuffle;
    m_liveOrderButton->setGlyph(shuffle ? "arrows-random" : "repeat");
    m_liveOrderButton->setTooltip(
        i18n::tr(shuffle ? "wallpaper.panel.live-order-shuffle" : "wallpaper.panel.live-order-sequential")
    );
  }
  if (m_liveCollectionButton != nullptr) {
    const std::string id = focusedLiveId();
    const bool inCollection = !id.empty() && m_live->isInCollection(id);
    m_liveCollectionButton->setEnabled(!id.empty());
    m_liveCollectionButton->setGlyph(inCollection ? "playlist-x" : "playlist-add");
    m_liveCollectionButton->setTooltip(
        i18n::tr(inCollection ? "wallpaper.panel.live-collection-remove" : "wallpaper.panel.live-collection-add")
    );
  }
  if (m_liveStopButton != nullptr) {
    m_liveStopButton->setEnabled(m_live->mode() == LiveWallpaperController::Mode::Live || m_live->process().active());
  }
  if (m_liveStatusLabel != nullptr && live) {
    const LiveWallpaperProvider& provider = m_live->provider();
    std::string text;
    if (!provider.problem().empty() && provider.discovered()) {
      text = provider.problem();
    } else if (provider.discovering() && provider.items().empty()) {
      text = i18n::tr("wallpaper.panel.live-discovering");
    } else {
      text = m_live->statusLine();
      if (m_visibleEntries.empty() && m_filterQuery.empty()) {
        switch (m_live->category()) {
        case LiveWallpaperController::Category::Collection:
          text += "  ·  " + i18n::tr("wallpaper.panel.live-empty-collection");
          break;
        case LiveWallpaperController::Category::Favorites:
          text += "  ·  " + i18n::tr("wallpaper.panel.live-empty-favorites");
          break;
        case LiveWallpaperController::Category::Recent:
          text += "  ·  " + i18n::tr("wallpaper.panel.live-empty-recent");
          break;
        case LiveWallpaperController::Category::Installed:
          break;
        }
      } else {
        text += "  ·  " + i18n::trp("wallpaper.panel.live-count", static_cast<long>(m_visibleEntries.size()));
        if (m_live->category() == LiveWallpaperController::Category::Installed && m_live->unsupportedCount() > 0) {
          text +=
              "  ·  " + i18n::tr("wallpaper.panel.live-hidden", "count", static_cast<long>(m_live->unsupportedCount()));
        }
      }
    }
    m_liveStatusLabel->setText(text);
  }
}
