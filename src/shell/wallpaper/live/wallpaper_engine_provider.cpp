#include "shell/wallpaper/live/wallpaper_engine_provider.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "util/file_utils.h"
#include "util/string_utils.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <system_error>
#include <unistd.h>
#include <unordered_set>

namespace {

  namespace fs = std::filesystem;
  namespace we = live::wallpaper_engine;

  constexpr Logger kLog("live-we");
  constexpr std::string_view kDefaultRenderer = "linux-wallpaperengine";

  [[nodiscard]] fs::path homeDir() {
    const char* home = std::getenv("HOME");
    return home != nullptr ? fs::path(home) : fs::path();
  }

  // Resolves the renderer: an explicit path (with ~ expanded) or a bare name looked up on PATH.
  [[nodiscard]] std::optional<fs::path> resolveExecutable(const std::string& configured) {
    const std::string name = configured.empty() ? std::string(kDefaultRenderer) : configured;
    if (name.find('/') != std::string::npos || name.starts_with("~")) {
      fs::path path = FileUtils::expandUserPath(name);
      if (::access(path.c_str(), X_OK) == 0) {
        std::error_code ec;
        const fs::path canonical = fs::canonical(path, ec);
        return ec ? path : canonical;
      }
      return std::nullopt;
    }
    const char* envPath = std::getenv("PATH");
    std::string_view rest = envPath != nullptr ? envPath : "/usr/local/bin:/usr/bin";
    while (!rest.empty()) {
      const std::size_t colon = rest.find(':');
      const std::string_view dir = rest.substr(0, colon);
      rest = colon == std::string_view::npos ? std::string_view{} : rest.substr(colon + 1);
      if (dir.empty()) {
        continue;
      }
      const fs::path candidate = fs::path(dir) / name;
      if (::access(candidate.c_str(), X_OK) == 0) {
        return candidate;
      }
    }
    return std::nullopt;
  }

  [[nodiscard]] std::string_view scalingName(LiveWallpaperScaling scaling) {
    switch (scaling) {
    case LiveWallpaperScaling::Fit:
      return "fit";
    case LiveWallpaperScaling::Stretch:
      return "stretch";
    case LiveWallpaperScaling::Default:
      return "default";
    case LiveWallpaperScaling::Fill:
      break;
    }
    return "fill";
  }

  [[nodiscard]] std::vector<std::pair<fs::path, fs::file_time_type>> stampsFor(const std::vector<fs::path>& dirs) {
    std::vector<std::pair<fs::path, fs::file_time_type>> stamps;
    for (const fs::path& dir : dirs) {
      std::error_code ec;
      const auto mtime = fs::last_write_time(dir, ec);
      stamps.emplace_back(dir, ec ? fs::file_time_type{} : mtime);
    }
    return stamps;
  }

} // namespace

WallpaperEngineProvider::WallpaperEngineProvider(ConfigService* config) : m_config(config) {}

WallpaperEngineProvider::~WallpaperEngineProvider() {
  m_alive->store(false);
  if (m_worker.joinable()) {
    m_worker.join();
  }
}

std::string WallpaperEngineProvider::displayName() const { return "Wallpaper Engine"; }

fs::path WallpaperEngineProvider::scratchRoot() {
  if (const char* runtime = std::getenv("XDG_RUNTIME_DIR"); runtime != nullptr && runtime[0] != '\0') {
    return fs::path(runtime) / "zynith" / "live-wallpaper";
  }
  return fs::temp_directory_path() / ("zynith-" + std::to_string(::getuid())) / "zynith" / "live-wallpaper";
}

std::vector<fs::path> WallpaperEngineProvider::steamRoots() const {
  std::string configured;
  if (m_config != nullptr) {
    configured = m_config->config().wallpaper.live.steamRoot;
    if (!configured.empty()) {
      configured = FileUtils::expandUserPath(configured).string();
    }
  }
  return we::steamRootCandidates(configured, homeDir());
}

const live::Item* WallpaperEngineProvider::find(std::string_view id) const {
  const auto it = m_index.find(std::string(id));
  return it == m_index.end() ? nullptr : &m_items[it->second];
}

bool WallpaperEngineProvider::catalogIsFresh() const {
  if (!m_discovered || !m_layout.has_value()) {
    return false;
  }
  // One stat per Workshop content folder: Steam adds or removes an item's folder there, which bumps it.
  return stampsFor(m_layout->workshopDirs) == m_stamps;
}

void WallpaperEngineProvider::refresh(bool force) {
  if (m_discovering) {
    m_refreshQueued = m_refreshQueued || force;
    return;
  }
  if (!force && catalogIsFresh()) {
    return;
  }
  if (m_worker.joinable()) {
    m_worker.join(); // the previous scan has already delivered its result
  }
  m_discovering = true;
  notifyChanged();

  const std::vector<fs::path> roots = steamRoots();
  std::weak_ptr<std::atomic<bool>> alive = m_alive;
  m_worker = std::thread([this, roots, alive]() {
    const auto begin = std::chrono::steady_clock::now();
    ScanResult result;
    result.layout = we::resolveLayout(roots);
    std::unordered_set<std::string> seen;
    for (const fs::path& workshop : result.layout.workshopDirs) {
      std::error_code ec;
      for (fs::directory_iterator it(workshop, fs::directory_options::skip_permission_denied, ec), end;
           !ec && it != end; it.increment(ec)) {
        const std::string id = it->path().filename().string();
        if (!we::isWorkshopId(id) || !seen.insert(id).second) {
          continue;
        }
        std::error_code dirEc;
        if (!it->is_directory(dirEc)) {
          continue;
        }
        if (auto item = we::loadItem(it->path(), id); item.has_value()) {
          result.items.push_back(std::move(*item));
        }
      }
    }
    std::ranges::sort(result.items, [](const live::Item& a, const live::Item& b) {
      const int order = StringUtils::naturalCaseInsensitiveCompare(a.title, b.title);
      return order != 0 ? order < 0 : a.id < b.id;
    });
    result.stamps = stampsFor(result.layout.workshopDirs);
    result.elapsedMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - begin).count();

    // Hand the result to the main thread; the provider may have been destroyed meanwhile.
    auto shared = std::make_shared<ScanResult>(std::move(result));
    DeferredCall::callLater([this, alive, shared]() {
      if (const auto token = alive.lock(); token != nullptr && token->load()) {
        applyScan(std::move(*shared));
      }
    });
  });
}

void WallpaperEngineProvider::applyScan(ScanResult result) {
  m_layout = std::move(result.layout);
  m_stamps = std::move(result.stamps);
  m_items = std::move(result.items);
  m_index.clear();
  std::size_t unsupported = 0;
  for (std::size_t i = 0; i < m_items.size(); ++i) {
    m_index.emplace(m_items[i].id, i);
    if (!live::isRenderable(m_items[i].kind)) {
      ++unsupported;
    }
  }
  m_problem = layoutProblem(*m_layout);
  m_discovering = false;
  m_discovered = true;
  kLog.info(
      "discovered {} Workshop items ({} not renderable) in {} library folder(s), {:.1f} ms", m_items.size(),
      unsupported, m_layout->libraries.size(), result.elapsedMs
  );
  if (m_refreshQueued) {
    m_refreshQueued = false;
    refresh(true);
    return;
  }
  notifyChanged();
}

std::string WallpaperEngineProvider::layoutProblem(const we::Layout& layout) {
  if (layout.libraries.empty()) {
    return "No Steam library found";
  }
  if (layout.workshopDirs.empty()) {
    return "No Wallpaper Engine Workshop content in any Steam library";
  }
  if (!layout.assetsDir.has_value()) {
    return "Wallpaper Engine is not installed (its assets folder is missing)";
  }
  return {};
}

const we::Layout& WallpaperEngineProvider::layout() {
  if (!m_layout.has_value()) {
    m_layout = we::resolveLayout(steamRoots());
    m_problem = layoutProblem(*m_layout);
  }
  return *m_layout;
}

std::expected<live::Item, std::string> WallpaperEngineProvider::resolve(std::string_view id) {
  if (!we::isWorkshopId(id)) {
    return std::unexpected("not a Workshop id: \"" + std::string(id) + "\"");
  }
  const auto directory = we::findItemDirectory(layout(), id);
  if (!directory.has_value()) {
    if (!m_problem.empty()) {
      return std::unexpected(m_problem);
    }
    return std::unexpected("Workshop item " + std::string(id) + " is not installed (unsubscribed or deleted?)");
  }
  auto item = we::loadItem(*directory, id);
  if (!item.has_value()) {
    return std::unexpected("Workshop item " + std::string(id) + " has no readable project.json");
  }
  return std::move(*item);
}

std::expected<live::LaunchSpec, std::string> WallpaperEngineProvider::launchSpec(
    const live::Item& item, const std::vector<std::string>& outputs, const WallpaperLiveConfig& config
) {
  if (item.kind == live::ItemKind::Preset) {
    return std::unexpected(
        "\""
        + item.title
        + "\" is a Wallpaper Engine preset (built on item "
        + item.dependency
        + "), which linux-wallpaperengine cannot render"
    );
  }
  if (!live::isRenderable(item.kind)) {
    return std::unexpected("\"" + item.title + "\" is a wallpaper type linux-wallpaperengine does not support");
  }
  if (outputs.empty()) {
    return std::unexpected("no output to render on");
  }
  // Re-validate against disk: the catalog may predate an unsubscribe, or the library's drive may be gone.
  const auto resolved = resolve(item.id);
  if (!resolved.has_value()) {
    return std::unexpected(resolved.error());
  }
  const we::Layout& current = layout();
  if (!current.assetsDir.has_value()) {
    return std::unexpected(layoutProblem(current));
  }
  const auto renderer = resolveExecutable(config.renderer);
  if (!renderer.has_value()) {
    return std::unexpected(
        "linux-wallpaperengine not found (set [wallpaper.live] renderer, currently \""
        + (config.renderer.empty() ? std::string(kDefaultRenderer) : config.renderer)
        + "\")"
    );
  }

  live::LaunchSpec spec;
  spec.argv.push_back(renderer->string());
  spec.argv.push_back("--fps");
  spec.argv.push_back(std::to_string(std::clamp(config.fps, 1, 144)));
  if (config.volume <= 0) {
    spec.argv.push_back("--silent");
  } else {
    spec.argv.push_back("--volume");
    spec.argv.push_back(std::to_string(std::clamp(config.volume, 1, 100)));
  }
  // Same layer as Zynith's own wallpaper surface (noctalia-wallpaper). On niri a background-layer surface
  // without a place-within-backdrop rule behaves exactly like the static wallpaper does today, including in
  // the overview. Zynith keeps niri's backdrop for its own blurred noctalia-backdrop surface.
  spec.argv.push_back("--layer");
  spec.argv.push_back("background");
  if (!config.mouse) {
    spec.argv.push_back("--disable-mouse");
  }
  if (!config.fullscreenPause) {
    spec.argv.push_back("--no-fullscreen-pause");
  }
  // Explicit, not left to the renderer's own search: that search only knows four home-relative Steam roots
  // and would miss Wallpaper Engine installed in another library folder.
  spec.argv.push_back("--assets-dir");
  spec.argv.push_back(current.assetsDir->string());
  // One process covers every output. --bg gets the canonical item folder (not the bare id) for the same
  // reason: the renderer's id lookup does not follow libraryfolders.vdf.
  for (const std::string& output : outputs) {
    spec.argv.push_back("--screen-root");
    spec.argv.push_back(output);
    spec.argv.push_back("--bg");
    spec.argv.push_back(resolved->directory.string());
    spec.argv.push_back("--scaling");
    spec.argv.push_back(std::string(scalingName(config.scaling)));
  }

  // linux-wallpaperengine mounts its working directory into its virtual filesystem as a fallback root.
  // Its own directory is the neutral choice (it holds the bundled CEF resources anyway) rather than
  // wherever the shell happened to be started from.
  spec.workingDir = renderer->parent_path();
  spec.scratchDir =
      scratchRoot() / ("renderer-" + std::to_string(::getpid()) + "-" + std::to_string(++m_scratchCounter));
  spec.env.emplace_back("TMPDIR", spec.scratchDir.string());
  return spec;
}
