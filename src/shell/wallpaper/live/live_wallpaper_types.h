#pragma once

// zynith: Live wallpapers — shared types.
//
// A live wallpaper is rendered by an external program (linux-wallpaperengine for the Wallpaper Engine
// provider). Zynith is only the selector and supervisor: it never copies, moves or rewrites the
// provider's content. What Zynith stores is a *reference* — provider id + stable item id (for Wallpaper
// Engine, the Steam Workshop id) — and the provider resolves that to the canonical on-disk location every
// time it is needed. A copied or cached path would go stale the moment Steam updates, relocates (library
// moved to another drive) or removes the item; the id stays valid for as long as the item exists at all.

#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace live {

  enum class ItemKind : std::uint8_t {
    Scene,
    Video,
    Web,
    // A Workshop "preset": a property set layered over another item (project.json "dependency"). Its own
    // files are referenced relative to its folder while linux-wallpaperengine only mounts the base item, so
    // it cannot be rendered faithfully — listed as unsupported rather than rendered wrong.
    Preset,
    // Anything else (e.g. Wallpaper Engine "application" wallpapers, which are Windows executables).
    Unsupported,
  };

  [[nodiscard]] constexpr bool isRenderable(ItemKind kind) noexcept {
    return kind == ItemKind::Scene || kind == ItemKind::Video || kind == ItemKind::Web;
  }

  [[nodiscard]] constexpr std::string_view kindName(ItemKind kind) noexcept {
    switch (kind) {
    case ItemKind::Scene:
      return "scene";
    case ItemKind::Video:
      return "video";
    case ItemKind::Web:
      return "web";
    case ItemKind::Preset:
      return "preset";
    case ItemKind::Unsupported:
      break;
    }
    return "unsupported";
  }

  // One discovered item. All paths point into the provider's canonical location (for Wallpaper Engine, the
  // Steam library); none of them is ever a Zynith-owned copy.
  struct Item {
    std::string id; // stable provider id (Workshop id)
    std::string title;
    ItemKind kind = ItemKind::Unsupported;
    std::filesystem::path directory; // canonical content folder
    std::filesystem::path preview;   // author-supplied still/animated preview, may be empty
    std::string dependency;          // presets: the base item's id
    std::int64_t updatedNs = 0;      // project.json mtime: "newest" ordering and palette/thumbnail freshness
  };

  // How to start the renderer for one item. Built by the provider so that the controller and UI never
  // know the renderer's command line, working directory or environment quirks.
  struct LaunchSpec {
    std::vector<std::string> argv; // argv[0] is an absolute path to the executable
    std::filesystem::path workingDir;
    std::vector<std::pair<std::string, std::string>> env; // additions/overrides for the child only
    // Private scratch directory handed to the child as TMPDIR and emptied after it exits (see
    // LiveRendererProcess): linux-wallpaperengine's embedded CEF leaves a profile directory in $TMPDIR
    // on every run.
    std::filesystem::path scratchDir;
  };

} // namespace live
