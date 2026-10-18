#include "shell/wallpaper/live/wallpaper_engine_catalog.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <fstream>
#include <iterator>
#include <sstream>
#include <system_error>
#include <unordered_set>

namespace live::wallpaper_engine {

  namespace {

    namespace fs = std::filesystem;

    [[nodiscard]] std::string toLowerAscii(std::string_view text) {
      std::string out(text);
      std::ranges::transform(out, out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
      return out;
    }

    // Quoted-string tokens of a KeyValues document, in order. Braces and comments are skipped: the
    // "path" key is unique enough that the structure does not have to be modelled.
    [[nodiscard]] std::vector<std::string> quotedTokens(std::string_view text) {
      std::vector<std::string> tokens;
      std::size_t i = 0;
      while (i < text.size()) {
        const char c = text[i];
        if (c == '/' && i + 1 < text.size() && text[i + 1] == '/') {
          while (i < text.size() && text[i] != '\n') {
            ++i;
          }
          continue;
        }
        if (c != '"') {
          ++i;
          continue;
        }
        std::string token;
        ++i;
        while (i < text.size() && text[i] != '"') {
          if (text[i] == '\\' && i + 1 < text.size()) {
            const char next = text[i + 1];
            if (next == '\\' || next == '"') {
              token.push_back(next);
              i += 2;
              continue;
            }
          }
          token.push_back(text[i]);
          ++i;
        }
        ++i; // closing quote
        tokens.push_back(std::move(token));
      }
      return tokens;
    }

    [[nodiscard]] fs::path canonicalOrNormal(const fs::path& path) {
      std::error_code ec;
      auto canonical = fs::canonical(path, ec);
      return ec ? path.lexically_normal() : canonical;
    }

    [[nodiscard]] bool isDirectory(const fs::path& path) {
      std::error_code ec;
      return fs::is_directory(path, ec);
    }

    [[nodiscard]] std::optional<std::string> readText(const fs::path& path) {
      std::ifstream in(path, std::ios::binary);
      if (!in) {
        return std::nullopt;
      }
      std::ostringstream buffer;
      buffer << in.rdbuf();
      return std::move(buffer).str();
    }

    // Only a plain file name inside the item folder is accepted as a preview: project.json is third-party
    // content and must not be able to point the thumbnailer at arbitrary files.
    [[nodiscard]] fs::path safeChildFile(const fs::path& directory, const std::string& name) {
      if (name.empty()) {
        return {};
      }
      const fs::path relative(name);
      if (relative.is_absolute() || relative.has_parent_path() || name == "." || name == "..") {
        return {};
      }
      return directory / relative;
    }

    [[nodiscard]] ItemKind kindFromType(std::string_view type, std::string_view file) {
      if (type == "scene") {
        return ItemKind::Scene;
      }
      if (type == "video") {
        return ItemKind::Video;
      }
      if (type == "web") {
        return ItemKind::Web;
      }
      if (!type.empty()) {
        return ItemKind::Unsupported; // "application" and anything newer
      }
      // Older items omit "type"; the entry file still says what they are.
      const std::string lowered = toLowerAscii(file);
      if (lowered.ends_with(".json")) {
        return ItemKind::Scene;
      }
      if (lowered.ends_with(".mp4") || lowered.ends_with(".webm") || lowered.ends_with(".mkv")) {
        return ItemKind::Video;
      }
      if (lowered.ends_with(".html") || lowered.ends_with(".htm")) {
        return ItemKind::Web;
      }
      return ItemKind::Unsupported;
    }

    [[nodiscard]] std::string stringField(const nlohmann::json& json, const char* key) {
      const auto it = json.find(key);
      if (it == json.end()) {
        return {};
      }
      if (it->is_string()) {
        return it->get<std::string>();
      }
      if (it->is_number_unsigned() || it->is_number_integer()) {
        return std::to_string(it->get<std::int64_t>());
      }
      return {};
    }

  } // namespace

  bool isWorkshopId(std::string_view id) noexcept {
    if (id.empty() || id.size() > 20) {
      return false;
    }
    return std::ranges::all_of(id, [](char c) { return c >= '0' && c <= '9'; });
  }

  std::vector<std::string> parseLibraryFolderPaths(std::string_view vdfText) {
    std::vector<std::string> paths;
    const auto tokens = quotedTokens(vdfText);
    for (std::size_t i = 0; i + 1 < tokens.size(); ++i) {
      const std::string& key = tokens[i];
      const std::string& value = tokens[i + 1];
      // Current format: "path" "/x". Legacy flat format: "1" "/x" directly under "LibraryFolders".
      const bool legacyIndex = !key.empty() && isWorkshopId(key) && !value.empty() && value.front() == '/';
      if (toLowerAscii(key) == "path" || legacyIndex) {
        if (!value.empty() && std::ranges::find(paths, value) == paths.end()) {
          paths.push_back(value);
        }
        ++i;
      }
    }
    return paths;
  }

  std::optional<Item> parseProject(std::string_view jsonText, std::string_view id, const fs::path& directory) {
    if (jsonText.starts_with("\xEF\xBB\xBF")) {
      jsonText.remove_prefix(3);
    }
    const nlohmann::json json = nlohmann::json::parse(jsonText, nullptr, /*allow_exceptions=*/false);
    if (json.is_discarded() || !json.is_object()) {
      return std::nullopt;
    }

    Item item;
    item.id = std::string(id);
    item.directory = directory;
    item.title = stringField(json, "title");
    if (item.title.empty()) {
      item.title = item.id;
    }
    item.preview = safeChildFile(directory, stringField(json, "preview"));
    item.dependency = stringField(json, "dependency");
    if (!item.dependency.empty() && isWorkshopId(item.dependency)) {
      item.kind = ItemKind::Preset;
    } else {
      item.dependency.clear();
      item.kind = kindFromType(toLowerAscii(stringField(json, "type")), stringField(json, "file"));
    }
    return item;
  }

  std::vector<fs::path> steamRootCandidates(const std::string& configured, const fs::path& home) {
    if (!configured.empty()) {
      return {fs::path(configured)};
    }
    return {
        home / ".local/share/Steam",
        home / ".steam/steam",
        home / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
        home / "snap/steam/common/.local/share/Steam",
    };
  }

  Layout resolveLayout(const std::vector<fs::path>& steamRoots) {
    Layout layout;
    std::unordered_set<std::string> seen;
    const auto addLibrary = [&](const fs::path& candidate) {
      if (!isDirectory(candidate)) {
        return;
      }
      const fs::path canonical = canonicalOrNormal(candidate);
      if (seen.insert(canonical.string()).second) {
        layout.libraries.push_back(canonical);
      }
    };

    for (const fs::path& root : steamRoots) {
      if (!isDirectory(root)) {
        continue;
      }
      addLibrary(root);
      // Steam has kept this file in both places over the years.
      for (const char* relative : {"steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"}) {
        if (const auto text = readText(root / relative); text.has_value()) {
          for (const std::string& path : parseLibraryFolderPaths(*text)) {
            addLibrary(fs::path(path));
          }
        }
      }
    }

    for (const fs::path& library : layout.libraries) {
      const fs::path workshop = library / "steamapps/workshop/content" / std::string(kWorkshopAppId);
      if (isDirectory(workshop)) {
        layout.workshopDirs.push_back(workshop);
      }
      const fs::path assets = library / "steamapps/common/wallpaper_engine/assets";
      if (!layout.assetsDir.has_value() && isDirectory(assets)) {
        layout.assetsDir = assets;
      }
    }
    return layout;
  }

  std::optional<fs::path> findItemDirectory(const Layout& layout, std::string_view id) {
    if (!isWorkshopId(id)) {
      return std::nullopt;
    }
    for (const fs::path& workshop : layout.workshopDirs) {
      const fs::path candidate = workshop / std::string(id);
      if (isDirectory(candidate)) {
        return candidate;
      }
    }
    return std::nullopt;
  }

  std::optional<Item> loadItem(const fs::path& directory, std::string_view id) {
    const fs::path projectPath = directory / "project.json";
    const auto text = readText(projectPath);
    if (!text.has_value()) {
      return std::nullopt;
    }
    auto item = parseProject(*text, id, directory);
    if (item.has_value()) {
      std::error_code ec;
      const auto mtime = fs::last_write_time(projectPath, ec);
      item->updatedNs = ec ? 0 : static_cast<std::int64_t>(mtime.time_since_epoch().count());
      if (!item->preview.empty() && !fs::is_regular_file(item->preview, ec)) {
        item->preview.clear();
      }
    }
    return item;
  }

  std::vector<std::string> decodeIdList(std::string_view text) {
    std::vector<std::string> ids;
    std::unordered_set<std::string> seen;
    std::size_t start = 0;
    while (start <= text.size()) {
      const std::size_t end = std::min(text.find(',', start), text.size());
      std::string_view token = text.substr(start, end - start);
      while (!token.empty() && std::isspace(static_cast<unsigned char>(token.front())) != 0) {
        token.remove_prefix(1);
      }
      while (!token.empty() && std::isspace(static_cast<unsigned char>(token.back())) != 0) {
        token.remove_suffix(1);
      }
      if (isWorkshopId(token) && seen.insert(std::string(token)).second) {
        ids.emplace_back(token);
      }
      start = end + 1;
    }
    return ids;
  }

  std::string encodeIdList(const std::vector<std::string>& ids) {
    std::string out;
    for (const std::string& id : ids) {
      if (!isWorkshopId(id)) {
        continue;
      }
      if (!out.empty()) {
        out.push_back(',');
      }
      out += id;
    }
    return out;
  }

} // namespace live::wallpaper_engine
