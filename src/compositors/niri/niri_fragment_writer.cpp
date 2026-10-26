#include "compositors/niri/niri_fragment_writer.h"

#include "config/atomic_file.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/process/process.h"

#include <fstream>
#include <optional>
#include <sstream>
#include <system_error>
#include <utility>

namespace {
  constexpr Logger kLog("niri-fragment");
  constexpr std::chrono::milliseconds kValidateTimeout{5000};
  constexpr std::size_t kValidateOutputLimit = 16 * 1024;

  std::optional<std::string> readFile(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
      return std::nullopt;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
  }

  std::string firstLine(std::string_view text) {
    const auto nl = text.find('\n');
    return std::string(text.substr(0, nl == std::string_view::npos ? text.size() : nl));
  }
} // namespace

struct NiriFragmentWriter::State : std::enable_shared_from_this<NiriFragmentWriter::State> {
  std::filesystem::path path;
  std::string label;
  std::string pending;
  // What is known to be installed right now. Seeded lazily from disk on the first flush.
  std::optional<std::string> installed;
  bool installedLoaded = false;
  // Content that failed validation; not retried until the configuration changes it.
  std::optional<std::string> lastRejected;
  std::uint64_t generation = 0;
  NiriFragmentWriter::Stats stats;

  void flush();
  void onFragmentValidated(std::uint64_t gen, std::filesystem::path tmp, std::string content, bool ok, std::string err);
  void onFullConfigValidated(std::uint64_t gen, std::optional<std::string> previous, bool ok, std::string err);
};

NiriFragmentWriter::NiriFragmentWriter(std::filesystem::path path, std::string label)
    : m_state(std::make_shared<State>()) {
  m_state->path = std::move(path);
  m_state->label = std::move(label);
}

NiriFragmentWriter::~NiriFragmentWriter() { m_debounce.stop(); }

const std::filesystem::path& NiriFragmentWriter::path() const noexcept { return m_state->path; }

NiriFragmentWriter::Stats NiriFragmentWriter::stats() const { return m_state->stats; }

void NiriFragmentWriter::submit(std::string content) {
  ++m_state->stats.submits;
  m_state->pending = std::move(content);
  std::weak_ptr<State> weak = m_state;
  m_debounce.start(kDebounce, [weak]() {
    if (auto state = weak.lock()) {
      state->flush();
    }
  });
}

void NiriFragmentWriter::State::flush() {
  if (!installedLoaded) {
    installed = readFile(path);
    installedLoaded = true;
  }
  if (installed.has_value() && *installed == pending) {
    ++stats.skippedUnchanged;
    return;
  }
  if (lastRejected.has_value() && *lastRejected == pending) {
    return;
  }
  if (!process::commandExists("niri")) {
    kLog.debug("{}: niri not on PATH, not generating {}", label, path.string());
    return;
  }

  const std::uint64_t gen = ++generation;
  std::error_code ec;
  std::filesystem::create_directories(path.parent_path(), ec);
  // Per-generation temp name: an older, still-validating candidate must never be overwritten by
  // a newer one under the same name.
  auto tmp = path;
  tmp += ".zynith-candidate-" + std::to_string(gen);
  if (!writeTextFileAtomic(tmp, pending)) {
    kLog.warn("{}: could not write candidate {}", label, tmp.string());
    return;
  }

  ++stats.validations;
  std::weak_ptr<State> weak = weak_from_this();
  std::string content = pending;
  const bool started = process::runAsync(
      std::vector<std::string>{"niri", "validate", "-c", tmp.string()},
      process::RunCallbacks{
          .stdOut = {},
          .stdErr = {},
          .onExit =
              [weak, gen, tmp, content = std::move(content)](process::RunResult result) mutable {
                const bool ok = static_cast<bool>(result);
                DeferredCall::callLater([weak, gen, tmp = std::move(tmp), content = std::move(content), ok,
                                         err = std::move(result.err)]() mutable {
                  if (auto state = weak.lock()) {
                    state->onFragmentValidated(gen, std::move(tmp), std::move(content), ok, std::move(err));
                  } else {
                    std::error_code ignored;
                    std::filesystem::remove(tmp, ignored);
                  }
                });
              },
      },
      process::RunOptions{.timeout = kValidateTimeout, .maxOutputBytes = kValidateOutputLimit}
  );
  if (!started) {
    kLog.warn("{}: could not start niri validate", label);
    std::filesystem::remove(tmp, ec);
  }
}

void NiriFragmentWriter::State::onFragmentValidated(
    std::uint64_t gen, std::filesystem::path tmp, std::string content, bool ok, std::string err
) {
  std::error_code ec;
  std::filesystem::remove(tmp, ec);
  if (gen != generation) {
    return; // superseded by a newer change; that one will install itself
  }
  if (!ok) {
    ++stats.rejected;
    lastRejected = content;
    kLog.warn("{}: generated fragment rejected by niri, keeping the installed one: {}", label, firstLine(err));
    return;
  }

  std::optional<std::string> previous = installed;
  if (!writeTextFileAtomic(path, content)) {
    kLog.warn("{}: could not install {}", label, path.string());
    return;
  }
  installed = content;
  lastRejected.reset();
  ++stats.installs;
  kLog.info("{}: installed {}", label, path.string());

  std::weak_ptr<State> weak = weak_from_this();
  const bool started = process::runAsync(
      std::vector<std::string>{"niri", "validate"},
      process::RunCallbacks{
          .stdOut = {},
          .stdErr = {},
          .onExit =
              [weak, gen, previous = std::move(previous)](process::RunResult result) mutable {
                const bool okFull = static_cast<bool>(result);
                DeferredCall::callLater([weak, gen, previous = std::move(previous), okFull,
                                         err = std::move(result.err)]() mutable {
                  if (auto state = weak.lock()) {
                    state->onFullConfigValidated(gen, std::move(previous), okFull, std::move(err));
                  }
                });
              },
      },
      process::RunOptions{.timeout = kValidateTimeout, .maxOutputBytes = kValidateOutputLimit}
  );
  if (!started) {
    kLog.warn("{}: could not start the full-config check", label);
  }
}

void NiriFragmentWriter::State::onFullConfigValidated(
    std::uint64_t gen, std::optional<std::string> previous, bool ok, std::string err
) {
  if (ok || gen != generation) {
    return;
  }
  // Valid alone, invalid in context. Put the previous fragment back so the next niri reload is of
  // a config that parses, and stop retrying this content.
  ++stats.rolledBack;
  lastRejected = installed;
  if (previous.has_value()) {
    if (writeTextFileAtomic(path, *previous)) {
      installed = previous;
    }
  } else {
    std::error_code ec;
    std::filesystem::remove(path, ec);
    installed.reset();
  }
  kLog.warn("{}: full niri config failed with the new fragment, rolled back: {}", label, firstLine(err));
}
