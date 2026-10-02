#include "shell/wallpaper/live/live_wallpaper_controller.h"

#include "cli/schema_msg.h"
#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/random.h"
#include "ipc/ipc_service.h"
#include "shell/wallpaper/live/wallpaper_engine_catalog.h"
#include "shell/wallpaper/live/wallpaper_engine_provider.h"
#include "shell/wallpaper/wallpaper.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <nlohmann/json.hpp>
#include <charconv>
#include <format>
#include <random>
#include <system_error>

namespace {

  constexpr Logger kLog("live-wallpaper");
  constexpr std::string_view kStateOwner = "wallpaper_live";
  // A renderer that ran at least this long before crashing is restarted once (at most every
  // kAutoRestartWindow); one that dies sooner is treated as broken and the static wallpaper stays.
  constexpr auto kAutoRestartMinUptime = std::chrono::seconds(30);
  constexpr auto kAutoRestartWindow = std::chrono::minutes(5);
  constexpr auto kAutoRestartDelay = std::chrono::seconds(2);

  namespace we = live::wallpaper_engine;

  [[nodiscard]] std::string_view categoryKey(LiveWallpaperController::Category category) {
    switch (category) {
    case LiveWallpaperController::Category::Collection:
      return "collection";
    case LiveWallpaperController::Category::Favorites:
      return "favorites";
    case LiveWallpaperController::Category::Recent:
      return "recent";
    case LiveWallpaperController::Category::Installed:
      break;
    }
    return "installed";
  }

  [[nodiscard]] std::string jsonEscape(std::string_view text) {
    std::string out;
    out.reserve(text.size() + 2);
    for (const char c : text) {
      switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          out += std::format("\\u{:04x}", static_cast<unsigned>(c));
        } else {
          out.push_back(c);
        }
      }
    }
    return out;
  }

  [[nodiscard]] std::string lastLine(std::string_view text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == ' ')) {
      text.remove_suffix(1);
    }
    const std::size_t newline = text.rfind('\n');
    return std::string(newline == std::string_view::npos ? text : text.substr(newline + 1));
  }

  [[nodiscard]] std::string_view stateName(LiveRendererProcess::State state) {
    switch (state) {
    case LiveRendererProcess::State::Starting:
      return "starting";
    case LiveRendererProcess::State::Running:
      return "running";
    case LiveRendererProcess::State::Stopping:
      return "stopping";
    case LiveRendererProcess::State::Idle:
      break;
    }
    return "idle";
  }

  // Removes renderer scratch dirs a previous shell left behind. The shell is single-instance and every
  // renderer dies with the shell that spawned it (PR_SET_PDEATHSIG), so none of these is in use.
  void removeStaleScratchDirs() {
    namespace fs = std::filesystem;
    const fs::path root = WallpaperEngineProvider::scratchRoot();
    std::error_code ec;
    for (fs::directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec)) {
      if (it->path().filename().string().starts_with("renderer-")) {
        std::error_code rmEc;
        fs::remove_all(it->path(), rmEc);
      }
    }
  }

} // namespace

LiveWallpaperController::LiveWallpaperController() = default;

LiveWallpaperController::~LiveWallpaperController() { shutdown(); }

void LiveWallpaperController::initialize(WaylandConnection& wayland, ConfigService& config, Wallpaper& wallpaper) {
  m_wayland = &wayland;
  m_config = &config;
  m_wallpaper = &wallpaper;
  m_provider = std::make_unique<WallpaperEngineProvider>(&config);
  m_provider->setOnChanged([this]() { notify(); });
  m_process.setOnStarted([this]() { onRendererStarted(); });
  m_process.setOnExit([this](const LiveRendererProcess::Exit& exit) { onRendererExited(exit); });
  m_staticChangedConn = m_wallpaper->changed().connect([this]() { onStaticChanged(); });
  removeStaleScratchDirs();
  loadState();
}

void LiveWallpaperController::shutdown() {
  if (m_shuttingDown) {
    return;
  }
  m_shuttingDown = true;
  m_carouselTimer.stop();
  m_restartTimer.stop();
  m_handoverTimer.stop();
  m_staticChangedConn.disconnect();
  m_pending.reset();
  m_process.terminateNow();
}

// ── Persistence ─────────────────────────────────────────────────────────────

void LiveWallpaperController::loadState() {
  const auto str = [this](std::string_view key) { return m_config->stateString(kStateOwner, key).value_or(""); };
  // Only the Wallpaper Engine provider exists today; a state written by a future provider is ignored.
  const std::string provider = str("provider");
  const bool providerMatches = provider.empty() || provider == m_provider->id();
  m_currentId = providerMatches && we::isWorkshopId(str("current")) ? str("current") : std::string();
  m_favorites = we::decodeIdList(str("favorites"));
  m_collection = we::decodeIdList(str("collection"));
  m_recent = we::decodeIdList(str("recent"));
  const std::string category = str("category");
  for (const Category c : {Category::Collection, Category::Favorites, Category::Recent, Category::Installed}) {
    if (category == categoryKey(c)) {
      m_category = c;
    }
  }
  if (category.empty() && !m_collection.empty()) {
    m_category = Category::Collection;
  }
  m_carouselEnabled = m_config->stateBool(kStateOwner, "carousel").value_or(false);
  std::int32_t interval = 0;
  const std::string intervalText = str("carousel_interval");
  if (std::from_chars(intervalText.data(), intervalText.data() + intervalText.size(), interval).ec == std::errc{}) {
    m_carouselInterval = std::max(interval, kMinCarouselInterval);
  }
  m_carouselOrder = str("carousel_order") == "shuffle" ? CarouselOrder::Shuffle : CarouselOrder::Sequential;
  kLog.info(
      "state: mode={} current={} favorites={} collection={} carousel={}", str("mode").empty() ? "static" : str("mode"),
      m_currentId.empty() ? "-" : m_currentId, m_favorites.size(), m_collection.size(), m_carouselEnabled
  );
}

void LiveWallpaperController::saveList(const char* key, const std::vector<std::string>& ids) {
  (void)m_config->setStateString(kStateOwner, key, we::encodeIdList(ids));
}

// ── Outputs ─────────────────────────────────────────────────────────────────

std::vector<std::string> LiveWallpaperController::currentOutputs() const {
  std::vector<std::string> outputs;
  if (m_wayland == nullptr) {
    return outputs;
  }
  for (const auto& output : m_wayland->outputs()) {
    if (output.done && !output.connectorName.empty() && output.hasUsableGeometry()) {
      outputs.push_back(output.connectorName);
    }
  }
  std::ranges::sort(outputs);
  return outputs;
}

void LiveWallpaperController::onOutputChange() {
  if (m_config == nullptr || m_shuttingDown) {
    return;
  }
  const std::vector<std::string> outputs = currentOutputs();
  if (!m_resumed) {
    if (outputs.empty()) {
      return; // resume once outputs exist
    }
    m_resumed = true;
    const bool wantLive = m_config->stateString(kStateOwner, "mode").value_or("") == "live";
    if (wantLive && !m_currentId.empty()) {
      // Deferred off the startup path; until the renderer is verified the static wallpaper stays up.
      DeferredCall::callLater([this]() {
        std::string error;
        if (!m_shuttingDown && !activate(m_currentId, &error, false, false)) {
          setError("Could not resume live wallpaper: " + error);
          notify();
        }
      });
    }
    return;
  }
  if (!m_activeItem.has_value() || outputs == m_renderOutputs) {
    return;
  }
  // Output set changed under a running live wallpaper: give removed outputs back to the static backend
  // and restart the one renderer on the new set.
  for (const std::string& connector : m_managedOutputs) {
    if (!std::ranges::contains(outputs, connector)) {
      m_wallpaper->setOutputExternallyManaged(connector, false);
    }
  }
  std::erase_if(m_managedOutputs, [&](const std::string& c) { return !std::ranges::contains(outputs, c); });
  kLog.info("outputs changed; restarting live wallpaper on {}", StringUtils::join(outputs, ", "));
  std::string error;
  if (outputs.empty() || !activate(m_activeItem->id, &error, false, true)) {
    if (!outputs.empty()) {
      setError(error);
    }
  }
}

// ── Selection and lifecycle ─────────────────────────────────────────────────

std::optional<live::Item> LiveWallpaperController::lookup(const std::string& id, std::string* error) {
  if (const live::Item* item = m_provider->find(id); item != nullptr) {
    return *item;
  }
  auto resolved = m_provider->resolve(id);
  if (!resolved.has_value()) {
    if (error != nullptr) {
      *error = resolved.error();
    }
    return std::nullopt;
  }
  return std::move(*resolved);
}

bool LiveWallpaperController::select(const std::string& id, std::string* error) {
  std::string reason;
  if (!activate(id, &reason, false, false)) {
    setError(reason);
    notify();
    if (error != nullptr) {
      *error = reason;
    }
    return false;
  }
  return true;
}

bool LiveWallpaperController::activate(const std::string& id, std::string* error, bool isFallback, bool isRestart) {
  if (m_config == nullptr || m_shuttingDown) {
    return false;
  }
  auto item = lookup(id, error);
  if (!item.has_value()) {
    return false;
  }
  std::vector<std::string> outputs = currentOutputs();
  auto spec = m_provider->launchSpec(*item, outputs, m_config->config().wallpaper.live);
  if (!spec.has_value()) {
    if (error != nullptr) {
      *error = spec.error();
    }
    return false;
  }

  m_restartTimer.stop();
  m_carouselTimer.stop();
  m_pending = Pending{
      .item = std::move(*item),
      .spec = std::move(*spec),
      .outputs = std::move(outputs),
      .isFallback = isFallback,
      .isRestart = isRestart,
  };
  kLog.info("switching live wallpaper to {} \"{}\"", m_pending->item.id, m_pending->item.title);
  m_waitingStatic = false;
  const std::string poster = m_pending->item.preview.string();
  // Exactly one renderer: if one is alive, it is stopped and the pending one starts from its exit callback.
  if (m_process.active()) {
    if (m_process.state() != LiveRendererProcess::State::Stopping && !m_managedOutputs.empty() && !poster.empty()) {
      // Poster frame: bring the shell's own wallpaper surface back above the old renderer showing the new
      // item's preview — opaque on its first frame — and stop the old renderer only once it is on screen.
      // The compositor's empty background is never exposed; the new renderer later draws over the poster.
      m_wallpaper->setTransientImage(poster, /*instant=*/true);
      for (const std::string& connector : m_managedOutputs) {
        m_wallpaper->setOutputExternallyManaged(connector, false);
      }
      m_managedOutputs.clear();
      m_waitingPoster = true;
      kLog.info("transition: poster requested");
      m_handoverTimer.start(std::chrono::milliseconds(600), [this]() { stopAfterPoster(); });
      onStaticChanged(); // already settled if the static backend has no surfaces
    } else {
      if (!poster.empty() && m_managedOutputs.empty()) {
        m_wallpaper->setTransientImage(poster, /*instant=*/false); // poster or static surface already up
      }
      m_waitingPoster = false;
      m_process.stop();
    }
  } else {
    // Static -> Live: the static wallpaper transitions to the poster while the renderer starts underneath it.
    if (!poster.empty()) {
      m_wallpaper->setTransientImage(poster, /*instant=*/false);
    }
    startPending();
  }
  notify();
  return true;
}

void LiveWallpaperController::startPending() {
  if (!m_pending.has_value() || m_shuttingDown) {
    return;
  }
  std::string error;
  if (!m_process.start(m_pending->spec, error)) {
    const Pending failed = std::move(*m_pending);
    m_pending.reset();
    setError("\"" + failed.item.title + "\" could not be started: " + error);
    restoreStatic();
    m_activeItem.reset();
    m_mode = Mode::Static;
    notify();
    return;
  }
  // m_pending now describes the starting renderer until onRendererStarted() promotes it.
}

void LiveWallpaperController::onRendererStarted() {
  if (!m_pending.has_value()) {
    return;
  }
  Pending started = std::move(*m_pending);
  m_pending.reset();

  m_activeItem = started.item;
  m_renderOutputs = started.outputs;
  m_mode = Mode::Live;
  m_currentId = started.item.id;
  m_lastGoodId = started.item.id;
  if (!started.isFallback) {
    m_lastError.clear();
  }

  // Persist the reference only now that the renderer is verified: a selection that never started does
  // not overwrite the last working one.
  (void)m_config->setStateString(kStateOwner, "mode", "live");
  (void)m_config->setStateString(kStateOwner, "provider", std::string(m_provider->id()));
  (void)m_config->setStateString(kStateOwner, "current", m_currentId);
  pushRecent(m_currentId);

  handOverToLive(started.outputs);
  // The palette follows the poster through WallpaperState (one owner for every view of the wallpaper).
  armCarousel();
  notify();
}

void LiveWallpaperController::onRendererExited(const LiveRendererProcess::Exit& exit) {
  if (m_shuttingDown) {
    return;
  }

  // A switch is waiting for this exit (or the renderer died while one was queued behind it).
  // Note: while starting, m_pending *is* the starting renderer; it is only "queued" if the exit was
  // requested by activate(), which replaced it with the new selection.
  if (m_pending.has_value() && exit.requested) {
    startPending();
    notify();
    return;
  }

  if (exit.requested) {
    m_activeItem.reset(); // Live -> Static: static surfaces were restored before the stop
    notify();
    return;
  }

  // Unexpected exit.
  const std::string detail = lastLine(exit.outputTail);
  if (exit.duringStartup && m_pending.has_value()) {
    const Pending failed = std::move(*m_pending);
    m_pending.reset();
    setError(
        "\"" + failed.item.title + "\" failed to start"
        + (detail.empty() ? std::string() : std::string(": ") + detail)
    );
    restoreStatic();
    m_activeItem.reset();
    m_mode = Mode::Static;
    // Fall back to the last wallpaper that did run, once.
    if (!failed.isFallback && !m_lastGoodId.empty() && m_lastGoodId != failed.item.id) {
      std::string error;
      if (activate(m_lastGoodId, &error, true, false)) {
        kLog.info("falling back to last working live wallpaper {}", m_lastGoodId);
      }
    }
    notify();
    return;
  }

  // Crashed while running.
  const std::optional<live::Item> crashed = m_activeItem;
  restoreStatic();
  m_activeItem.reset();
  m_mode = Mode::Static;
  const auto now = std::chrono::steady_clock::now();
  const bool mayRestart = crashed.has_value()
      && exit.uptime >= kAutoRestartMinUptime
      && (m_lastAutoRestart == std::chrono::steady_clock::time_point{} || now - m_lastAutoRestart >= kAutoRestartWindow);
  if (mayRestart) {
    m_lastAutoRestart = now;
    setError("Live wallpaper renderer crashed; restarting it");
    const std::string id = crashed->id;
    m_restartTimer.start(kAutoRestartDelay, [this, id]() {
      std::string error;
      if (!activate(id, &error, false, true)) {
        setError("Live wallpaper could not be restarted: " + error);
        notify();
      }
    });
  } else {
    setError(
        "Live wallpaper renderer stopped unexpectedly"
        + (detail.empty() ? std::string() : std::string(": ") + detail) + " — showing the static wallpaper"
    );
  }
  notify();
}

void LiveWallpaperController::handOverToLive(const std::vector<std::string>& outputs) {
  for (const std::string& connector : m_managedOutputs) {
    if (!std::ranges::contains(outputs, connector)) {
      m_wallpaper->setOutputExternallyManaged(connector, false);
    }
  }
  for (const std::string& connector : outputs) {
    m_wallpaper->setOutputExternallyManaged(connector, true);
  }
  m_managedOutputs = outputs;
  // The surfaces are gone, so dropping the poster costs nothing and never shows on screen.
  m_wallpaper->setTransientImage({}, false);
  kLog.info("transition: static surfaces released to the renderer on {}", StringUtils::join(outputs, ", "));
}

void LiveWallpaperController::restoreStatic() {
  m_carouselTimer.stop();
  m_waitingPoster = false;
  m_handoverTimer.stop();
  m_wallpaper->setTransientImage({}, false);
  for (const std::string& connector : m_managedOutputs) {
    m_wallpaper->setOutputExternallyManaged(connector, false);
  }
  const bool hadManaged = !m_managedOutputs.empty();
  m_managedOutputs.clear();
  if (hadManaged) {
    kLog.info("transition: static surfaces restored");
  }
}

void LiveWallpaperController::switchToStatic() {
  if (m_config == nullptr) {
    return;
  }
  m_pending.reset();
  m_restartTimer.stop();
  m_mode = Mode::Static;
  m_lastError.clear();
  (void)m_config->setStateString(kStateOwner, "mode", "static");
  // Static first, then stop — and only once the static wallpaper has finished its transition in: a fresh
  // static surface starts transparent (transition_on_startup), so stopping the renderer earlier exposed the
  // compositor's grey background through it (measured: a 20-30 ms grey flash, 3 of 5 samples).
  restoreStatic();
  if (m_process.active()) {
    if (m_process.state() != LiveRendererProcess::State::Stopping) {
      m_waitingStatic = true;
      m_handoverTimer.start(std::chrono::milliseconds(3000), [this]() { stopAfterStaticSettled(); });
      onStaticChanged();
    }
  } else {
    m_activeItem.reset();
  }
  notify();
}

void LiveWallpaperController::onStaticChanged() {
  if (m_shuttingDown || m_wallpaper == nullptr || !m_wallpaper->settled()) {
    return;
  }
  if (m_waitingPoster) {
    kLog.info("transition: poster on screen");
    stopAfterPoster();
  } else if (m_waitingStatic) {
    kLog.info("transition: static wallpaper settled");
    stopAfterStaticSettled();
  }
}

void LiveWallpaperController::stopAfterPoster() {
  if (!m_waitingPoster) {
    return;
  }
  m_waitingPoster = false;
  m_handoverTimer.stop();
  m_process.stop(); // its exit callback starts the pending renderer
}

void LiveWallpaperController::stopAfterStaticSettled() {
  if (!m_waitingStatic) {
    return;
  }
  m_waitingStatic = false;
  m_handoverTimer.stop();
  if (m_mode == Mode::Static && !m_pending.has_value()) {
    m_process.stop();
  }
}

// ── Library views ───────────────────────────────────────────────────────────

std::vector<const live::Item*> LiveWallpaperController::itemsFor(Category category) const {
  std::vector<const live::Item*> out;
  if (m_provider == nullptr) {
    return out;
  }
  const auto fromIds = [&](const std::vector<std::string>& ids) {
    for (const std::string& id : ids) {
      if (const live::Item* item = m_provider->find(id); item != nullptr && live::isRenderable(item->kind)) {
        out.push_back(item);
      }
    }
  };
  switch (category) {
  case Category::Collection:
    fromIds(m_collection);
    break;
  case Category::Favorites:
    fromIds(m_favorites);
    break;
  case Category::Recent:
    fromIds(m_recent);
    break;
  case Category::Installed:
    for (const live::Item& item : m_provider->items()) {
      if (live::isRenderable(item.kind)) {
        out.push_back(&item);
      }
    }
    break;
  }
  return out;
}

std::size_t LiveWallpaperController::unsupportedCount() const {
  if (m_provider == nullptr) {
    return 0;
  }
  return static_cast<std::size_t>(std::ranges::count_if(m_provider->items(), [](const live::Item& item) {
    return !live::isRenderable(item.kind);
  }));
}

bool LiveWallpaperController::isFavorite(const std::string& id) const { return std::ranges::contains(m_favorites, id); }

bool LiveWallpaperController::isInCollection(const std::string& id) const {
  return std::ranges::contains(m_collection, id);
}

void LiveWallpaperController::toggleFavorite(const std::string& id) {
  if (!we::isWorkshopId(id)) {
    return;
  }
  if (std::erase(m_favorites, id) == 0) {
    m_favorites.insert(m_favorites.begin(), id);
  }
  saveList("favorites", m_favorites);
  notify();
}

void LiveWallpaperController::toggleCollection(const std::string& id) {
  if (!we::isWorkshopId(id)) {
    return;
  }
  if (std::erase(m_collection, id) == 0) {
    m_collection.push_back(id);
  }
  saveList("collection", m_collection);
  armCarousel(); // the collection may have grown to, or shrunk below, two items
  notify();
}

void LiveWallpaperController::setCategory(Category category) {
  if (m_category == category) {
    return;
  }
  m_category = category;
  (void)m_config->setStateString(kStateOwner, "category", std::string(categoryKey(category)));
}

void LiveWallpaperController::pushRecent(const std::string& id) {
  std::erase(m_recent, id);
  m_recent.insert(m_recent.begin(), id);
  if (m_recent.size() > kRecentLimit) {
    m_recent.resize(kRecentLimit);
  }
  saveList("recent", m_recent);
}

// ── Carousel ────────────────────────────────────────────────────────────────
// Cycles through the user's collection only — never the whole Workshop library — and never renders two
// wallpapers at once: a rotation is an ordinary activate(), i.e. stop the current renderer, start the next.

std::vector<std::string> LiveWallpaperController::carouselCandidates() const {
  std::vector<std::string> ids;
  for (const std::string& id : m_collection) {
    const live::Item* item = m_provider->find(id);
    // Before discovery ran, keep the id: activate() validates it against disk anyway.
    if (item == nullptr ? !m_provider->discovered() : live::isRenderable(item->kind)) {
      ids.push_back(id);
    }
  }
  return ids;
}

void LiveWallpaperController::armCarousel() {
  m_carouselTimer.stop();
  if (!m_carouselEnabled || m_mode != Mode::Live || m_process.state() != LiveRendererProcess::State::Running) {
    return;
  }
  if (carouselCandidates().size() < 2) {
    return;
  }
  m_carouselTimer.start(std::chrono::seconds(m_carouselInterval), [this]() { onCarouselTimer(); });
}

void LiveWallpaperController::onCarouselTimer() {
  if (m_automationGate && !m_automationGate()) {
    armCarousel(); // locked: try again next interval
    return;
  }
  std::string error;
  if (!advanceCarousel(&error)) {
    kLog.warn("carousel: {}", error);
  }
}

bool LiveWallpaperController::advanceCarousel(std::string* error) {
  const std::vector<std::string> candidates = carouselCandidates();
  if (candidates.empty()) {
    if (error != nullptr) {
      *error = "the live collection is empty";
    }
    return false;
  }
  std::vector<std::string> order;
  if (m_carouselOrder == CarouselOrder::Shuffle) {
    for (const std::string& id : candidates) {
      if (id != m_currentId || candidates.size() == 1) {
        order.push_back(id);
      }
    }
    std::ranges::shuffle(order, Random::rng());
  } else {
    const auto it = std::ranges::find(candidates, m_currentId);
    const std::size_t start = it == candidates.end() ? 0 : static_cast<std::size_t>(it - candidates.begin()) + 1;
    for (std::size_t i = 0; i < candidates.size(); ++i) {
      const std::string& id = candidates[(start + i) % candidates.size()];
      if (id != m_currentId || candidates.size() == 1) {
        order.push_back(id);
      }
    }
  }
  if (m_mode == Mode::Live && candidates.size() == 1 && candidates.front() == m_currentId) {
    if (error != nullptr) {
      *error = "the live collection has only the current wallpaper";
    }
    return false;
  }
  // Skip items that can no longer be launched (unsubscribed since they were added).
  std::string lastError;
  for (const std::string& id : order) {
    std::string reason;
    if (activate(id, &reason, false, false)) {
      kLog.info("carousel: advancing to {}", id);
      return true;
    }
    kLog.warn("carousel: skipping {}: {}", id, reason);
    lastError = reason;
  }
  if (error != nullptr) {
    *error = lastError.empty() ? "no launchable wallpaper in the collection" : lastError;
  }
  return false;
}

void LiveWallpaperController::setCarouselEnabled(bool enabled) {
  if (m_carouselEnabled == enabled) {
    return;
  }
  m_carouselEnabled = enabled;
  (void)m_config->setStateBool(kStateOwner, "carousel", enabled);
  if (enabled && m_mode == Mode::Static && !m_process.active()) {
    // Enabling the carousel means "cycle my collection": start it rather than wait on a static desktop.
    std::string error;
    if (!advanceCarousel(&error)) {
      setError(error);
    }
  }
  armCarousel();
  notify();
}

void LiveWallpaperController::setCarouselInterval(std::int32_t seconds) {
  seconds = std::max(seconds, kMinCarouselInterval);
  if (m_carouselInterval == seconds) {
    return;
  }
  m_carouselInterval = seconds;
  (void)m_config->setStateString(kStateOwner, "carousel_interval", std::to_string(seconds));
  armCarousel();
  notify();
}

void LiveWallpaperController::setCarouselOrder(CarouselOrder order) {
  if (m_carouselOrder == order) {
    return;
  }
  m_carouselOrder = order;
  (void)m_config->setStateString(
      kStateOwner, "carousel_order", order == CarouselOrder::Shuffle ? "shuffle" : "sequential"
  );
  notify();
}

// ── Status ──────────────────────────────────────────────────────────────────

void LiveWallpaperController::setError(std::string message) {
  if (!message.empty()) {
    kLog.warn("{}", message);
  }
  m_lastError = std::move(message);
}

void LiveWallpaperController::notify() { m_changed.emit(); }

std::string LiveWallpaperController::statusLine() const {
  if (m_pending.has_value()) {
    return "Starting \"" + m_pending->item.title + "\"…";
  }
  if (!m_lastError.empty()) {
    return m_lastError;
  }
  if (m_mode == Mode::Live && m_activeItem.has_value()) {
    std::string line = "Live: " + m_activeItem->title + " · " + std::string(live::kindName(m_activeItem->kind));
    if (m_carouselEnabled) {
      line += " · carousel";
    }
    return line;
  }
  return "Static wallpaper";
}

std::string LiveWallpaperController::statusJson() const {
  std::string outputs;
  for (const std::string& output : m_renderOutputs) {
    outputs += (outputs.empty() ? "\"" : ", \"") + jsonEscape(output) + "\"";
  }
  const std::string title = m_activeItem.has_value() ? m_activeItem->title : std::string();
  const std::string kind = m_activeItem.has_value() ? std::string(live::kindName(m_activeItem->kind)) : std::string();
  return std::format(
      "{{\n  \"mode\": \"{}\",\n  \"provider\": \"{}\",\n  \"current\": \"{}\",\n  \"title\": \"{}\",\n"
      "  \"kind\": \"{}\",\n  \"renderer\": {{\"state\": \"{}\", \"pid\": {}, \"uptime_ms\": {}}},\n"
      "  \"outputs\": [{}],\n  \"managed_outputs\": {},\n  \"pending\": \"{}\",\n"
      "  \"carousel\": {{\"enabled\": {}, \"interval\": {}, \"order\": \"{}\", \"collection\": {}}},\n"
      "  \"favorites\": {},\n  \"catalog\": {{\"discovered\": {}, \"items\": {}, \"unsupported\": {}}},\n"
      "  \"palette_source\": \"{}\",\n  \"error\": \"{}\"\n}}\n",
      m_mode == Mode::Live ? "live" : "static", m_provider != nullptr ? m_provider->id() : "",
      jsonEscape(m_currentId), jsonEscape(title), kind, stateName(m_process.state()), m_process.pid(),
      m_process.uptime().count(), outputs, m_managedOutputs.size(),
      m_pending.has_value() ? jsonEscape(m_pending->item.id) : std::string(), m_carouselEnabled ? "true" : "false",
      m_carouselInterval, m_carouselOrder == CarouselOrder::Shuffle ? "shuffle" : "sequential", m_collection.size(),
      m_favorites.size(), m_provider != nullptr && m_provider->discovered() ? "true" : "false",
      m_provider != nullptr ? m_provider->items().size() : 0, unsupportedCount(),
      m_config != nullptr ? jsonEscape(m_config->paletteSourceOverride()) : std::string(), jsonEscape(m_lastError)
  );
}

// ── IPC ─────────────────────────────────────────────────────────────────────

void LiveWallpaperController::registerIpc(IpcService& ipc) {
  namespace msg = noctalia::cli::msg;
  const auto firstToken = [](const std::string& args) {
    const auto tokens = StringUtils::splitWhitespace(StringUtils::trim(args));
    return tokens.empty() ? std::string() : std::string(tokens.front());
  };

  ipc.bind(msg::wallpaperLiveSet, [this, firstToken](const std::string& args) -> std::string {
    const std::string id = firstToken(args);
    if (id.empty()) {
      return "error: workshop id required (wallpaper-live-set <id>)\n";
    }
    std::string error;
    if (!select(id, &error)) {
      return "error: " + error + "\n";
    }
    return "ok\n";
  });

  ipc.bind(msg::wallpaperLiveStop, [this](const std::string&) -> std::string {
    switchToStatic();
    return "ok\n";
  });

  ipc.bind(msg::wallpaperLiveStatus, [this](const std::string&) -> std::string { return statusJson(); });

  // zynith: ids resolve one by one (a small project.json read each), so this works before discovery has run
  ipc.bind(msg::wallpaperLiveList, [this](const std::string& args) -> std::string {
    const std::string source = args.empty() ? std::string("collection") : args;
    const std::vector<std::string>* ids = source == "favorites" ? &m_favorites
                                          : source == "recent"  ? &m_recent
                                                                : &m_collection;
    nlohmann::json out = nlohmann::json::array();
    for (const std::string& id : *ids) {
      const live::Item* known = m_provider->find(id);
      std::optional<live::Item> resolved;
      if (known == nullptr) {
        if (auto item = m_provider->resolve(id); item.has_value()) {
          resolved = std::move(*item);
          known = &*resolved;
        }
      }
      if (known == nullptr) {
        continue; // unsubscribed or removed from the library
      }
      out.push_back({
          {"id", known->id},
          {"title", known->title},
          {"kind", std::string(live::kindName(known->kind))},
          {"preview", known->preview.string()},
          {"favorite", std::ranges::find(m_favorites, known->id) != m_favorites.end()},
          {"current", m_activeItem.has_value() && m_activeItem->id == known->id},
      });
    }
    return out.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace) + "\n";
  });

  ipc.bind(msg::wallpaperLiveNext, [this](const std::string&) -> std::string {
    std::string error;
    if (!advanceCarousel(&error)) {
      return "error: " + error + "\n";
    }
    return "ok\n";
  });

  ipc.bind(msg::wallpaperLiveCarousel, [this](const std::string& args) -> std::string {
    const auto tokens = StringUtils::splitWhitespace(StringUtils::trim(args));
    if (tokens.empty()) {
      return "error: usage: wallpaper-live-carousel <on|off> [seconds] [sequential|shuffle]\n";
    }
    for (std::size_t i = 1; i < tokens.size(); ++i) {
      const std::string_view token = tokens[i];
      std::int32_t seconds = 0;
      if (std::from_chars(token.data(), token.data() + token.size(), seconds).ec == std::errc{}) {
        if (seconds < kMinCarouselInterval) {
          return std::format("error: interval must be at least {} seconds\n", kMinCarouselInterval);
        }
        setCarouselInterval(seconds);
      } else if (token == "shuffle" || token == "sequential") {
        setCarouselOrder(token == "shuffle" ? CarouselOrder::Shuffle : CarouselOrder::Sequential);
      } else {
        return "error: unknown argument \"" + std::string(token) + "\"\n";
      }
    }
    if (tokens.front() == "on" || tokens.front() == "off") {
      setCarouselEnabled(tokens.front() == "on");
      return m_lastError.empty() || tokens.front() == "off" ? "ok\n" : "error: " + m_lastError + "\n";
    }
    return "error: first argument must be on or off\n";
  });

  const auto listHandler = [this](bool favorites) {
    return [this, favorites](const std::string& args) -> std::string {
      const auto tokens = StringUtils::splitWhitespace(StringUtils::trim(args));
      if (tokens.size() != 2 || (tokens[0] != "add" && tokens[0] != "remove") || !we::isWorkshopId(tokens[1])) {
        return "error: usage: <add|remove> <workshop id>\n";
      }
      const std::string id(tokens[1]);
      const bool present = favorites ? isFavorite(id) : isInCollection(id);
      if (present != (tokens[0] == "add")) {
        if (favorites) {
          toggleFavorite(id);
        } else {
          toggleCollection(id);
        }
      }
      return "ok\n";
    };
  };
  ipc.bind(msg::wallpaperLiveCollection, listHandler(false));
  ipc.bind(msg::wallpaperLiveFavorite, listHandler(true));
}
