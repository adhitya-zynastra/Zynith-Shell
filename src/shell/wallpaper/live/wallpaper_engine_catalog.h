#pragma once

// zynith: Wallpaper Engine / Steam discovery — pure functions, no shell state, unit-tested
// (tests/wallpaper_engine_catalog_test.cpp).
//
// How the canonical location is resolved
// --------------------------------------
// linux-wallpaperengine itself only looks in four hard-coded places under $HOME
// (~/.local/share/Steam, ~/.steam/steam, the Flatpak and Snap Steam roots). Steam, however, can keep the
// Workshop content of an app in any *library folder* — e.g. a second drive — and lists those in
// <steam root>/steamapps/libraryfolders.vdf. Zynith therefore resolves the location itself:
//
//   Steam roots (configured, else the four standard roots; symlinks such as ~/.steam/steam collapse)
//     -> library folders (each root + every "path" in its libraryfolders.vdf)
//        -> <library>/steamapps/workshop/content/431960/<workshop id>   (the wallpapers)
//        -> <library>/steamapps/common/wallpaper_engine/assets          (the shared engine assets)
//
// and hands linux-wallpaperengine the resolved absolute item folder plus an explicit --assets-dir. The
// renderer reads the files in place; nothing is ever copied (45+ GB on a test machine).

#include "shell/wallpaper/live/live_wallpaper_types.h"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace live::wallpaper_engine {

  // Steam app id of Wallpaper Engine; its Workshop content lives under workshop/content/<this>.
  inline constexpr std::string_view kWorkshopAppId = "431960";
  inline constexpr std::string_view kProviderId = "wallpaper-engine";

  // Workshop ids are decimal numbers (currently up to 10 digits). Anything else — a path, "..", a name —
  // is rejected before it can reach the filesystem or a command line.
  [[nodiscard]] bool isWorkshopId(std::string_view id) noexcept;

  // Every "path" value in a libraryfolders.vdf (Valve KeyValues text). Tolerates the old flat format
  // ("1" "/path") and the current nested one ("0" { "path" "/path" ... }). Unescapes \\ and \".
  [[nodiscard]] std::vector<std::string> parseLibraryFolderPaths(std::string_view vdfText);

  // Parses one project.json (UTF-8, optional BOM). `id` is the item's folder name — the Workshop id —
  // which is authoritative (253 of 560 items on a test machine carry no "workshopid" field at all).
  // Returns nullopt only for unreadable JSON; unknown types come back as ItemKind::Unsupported.
  [[nodiscard]] std::optional<Item>
  parseProject(std::string_view jsonText, std::string_view id, const std::filesystem::path& directory);

  struct Layout {
    std::vector<std::filesystem::path> libraries;       // canonical, de-duplicated
    std::vector<std::filesystem::path> workshopDirs;    // existing <lib>/steamapps/workshop/content/431960
    std::optional<std::filesystem::path> assetsDir;     // first existing wallpaper_engine/assets
  };

  // Resolves the layout from `steamRoots` (already expanded; missing entries are skipped). Touches the
  // filesystem — call it off the UI thread.
  [[nodiscard]] Layout resolveLayout(const std::vector<std::filesystem::path>& steamRoots);

  // The roots to try: `configured` alone when non-empty, else the standard native/Flatpak/Snap roots.
  [[nodiscard]] std::vector<std::filesystem::path>
  steamRootCandidates(const std::string& configured, const std::filesystem::path& home);

  // Canonical folder of one item, or nullopt when no Workshop dir holds it (unsubscribed, deleted, or the
  // library's drive is not mounted). Touches the filesystem.
  [[nodiscard]] std::optional<std::filesystem::path> findItemDirectory(const Layout& layout, std::string_view id);

  // Reads and parses one item from its folder. Touches the filesystem.
  [[nodiscard]] std::optional<Item> loadItem(const std::filesystem::path& directory, std::string_view id);

  // Comma-separated id lists as persisted in state.toml ("123,456"). Invalid ids and duplicates are dropped
  // while preserving order.
  [[nodiscard]] std::vector<std::string> decodeIdList(std::string_view text);
  [[nodiscard]] std::string encodeIdList(const std::vector<std::string>& ids);

} // namespace live::wallpaper_engine
