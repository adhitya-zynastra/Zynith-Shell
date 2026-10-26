#include "scripting/plugin_capabilities.h"

#include "core/log.h"
#include "core/toml.h"

#include <array>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <system_error>
#include <unistd.h>

namespace scripting {

  namespace {

    constexpr Logger kLog("plugin-caps");

    constexpr std::array<std::pair<std::string_view, Capability>, 7> kNames{{
        {"exec", Capability::Exec},
        {"shell", Capability::Shell},
        {"network", Capability::Network},
        {"files", Capability::Files},
        {"notifications", Capability::Notifications},
        {"clipboard", Capability::Clipboard},
        {"env", Capability::Env},
    }};

    std::filesystem::path home() {
      const char* h = std::getenv("HOME");
      return (h != nullptr && *h != '\0') ? std::filesystem::path(h) : std::filesystem::path("/nonexistent");
    }

    std::filesystem::path xdg(const char* var, const char* fallback) {
      const char* v = std::getenv(var);
      return (v != nullptr && *v == '/') ? std::filesystem::path(v) : home() / fallback;
    }

    // weakly_canonical resolves symlinks and "..": a link inside the plugin directory that points at
    // ~/.ssh is judged by where it lands
    std::filesystem::path resolvedPath(const std::filesystem::path& path) {
      std::error_code ec;
      auto out = std::filesystem::weakly_canonical(path, ec);
      return ec ? path.lexically_normal() : out;
    }

    bool within(const std::filesystem::path& path, const std::filesystem::path& base) {
      if (base.empty()) {
        return false;
      }
      const auto rel = path.lexically_relative(base);
      return !rel.empty() && *rel.begin() != "..";
    }

    bool isProcessPath(const std::filesystem::path& path) {
      // other processes' environments and memory (same uid) are readable through /proc
      const std::string s = path.string();
      if (!s.starts_with("/proc/")) {
        return false;
      }
      const auto rest = std::string_view(s).substr(6);
      return rest.starts_with("self")
          || rest.starts_with("thread-self")
          || (!rest.empty() && rest[0] >= '0' && rest[0] <= '9');
    }

    std::vector<std::filesystem::path> secretLocations() {
      const auto h = home();
      const auto data = xdg("XDG_DATA_HOME", ".local/share");
      const auto config = xdg("XDG_CONFIG_HOME", ".config");
      const auto state = xdg("XDG_STATE_HOME", ".local/state");
      return {
          h / ".ssh",
          h / ".gnupg",
          h / ".password-store",
          h / ".pki",
          h / ".netrc",
          h / ".git-credentials",
          h / ".aws",
          h / ".kube",
          h / ".docker",
          h / ".mozilla",
          h / ".zen",
          data / "keyrings",
          config / "gh",
          config / "google-chrome",
          config / "chromium",
          config / "BraveSoftware",
          state / "zynith-shell" / "clipboard",
          state / "zynith-shell" / "notification_history.json",
      };
    }

    // a write here becomes code execution or a change to someone else's permissions
    std::vector<std::filesystem::path> protectedLocations() {
      const auto h = home();
      const auto config = xdg("XDG_CONFIG_HOME", ".config");
      const auto data = xdg("XDG_DATA_HOME", ".local/share");
      const auto state = xdg("XDG_STATE_HOME", ".local/state");
      return {
          h / ".bashrc",
          h / ".bash_profile",
          h / ".profile",
          h / ".zshrc",
          h / ".zprofile",
          h / ".zshenv",
          h / ".zlogin",
          h / ".config" / "fish",
          h / ".local" / "bin",
          h / "bin",
          config / "autostart",
          config / "systemd",
          config / "environment.d",
          config / "niri",
          config / "hypr",
          config / "zynith-shell",
          config / "zynith",
          data / "applications",
          data / "zynith-shell" / "plugins",
          state / "zynith-shell",
      };
    }

  } // namespace

  std::string_view capabilityName(Capability cap) noexcept {
    for (const auto& [name, value] : kNames) {
      if (value == cap) {
        return name;
      }
    }
    return "unknown";
  }

  std::optional<Capability> parseCapability(std::string_view name) noexcept {
    for (const auto& [n, value] : kNames) {
      if (n == name) {
        return value;
      }
    }
    return std::nullopt;
  }

  std::string describeCapabilities(CapabilitySet set) {
    std::string out;
    for (const auto& [name, value] : kNames) {
      if (has(set, value)) {
        if (!out.empty()) {
          out += ", ";
        }
        out += name;
      }
    }
    return out.empty() ? std::string("none") : out;
  }

  CapabilitySet parseCapabilityList(std::string_view text, std::string* unknown) {
    CapabilitySet set = 0;
    std::size_t i = 0;
    while (i < text.size()) {
      while (i < text.size() && (text[i] == ' ' || text[i] == ',')) {
        ++i;
      }
      std::size_t j = i;
      while (j < text.size() && text[j] != ' ' && text[j] != ',') {
        ++j;
      }
      if (j > i) {
        const auto word = text.substr(i, j - i);
        if (const auto cap = parseCapability(word)) {
          set |= static_cast<CapabilitySet>(*cap);
        } else if (unknown != nullptr) {
          *unknown += (unknown->empty() ? "" : " ") + std::string(word);
        }
      }
      i = j;
    }
    return set;
  }

  CapabilitySet declaredCapabilities(const std::filesystem::path& pluginDir) {
    try {
      const auto table = toml::parse_file((pluginDir / "plugin.toml").string());
      const auto* list = table["capabilities"].as_array();
      if (list == nullptr) {
        return 0;
      }
      CapabilitySet set = 0;
      for (const auto& node : *list) {
        if (const auto name = node.value<std::string>()) {
          if (const auto cap = parseCapability(*name)) {
            set |= static_cast<CapabilitySet>(*cap);
          } else {
            kLog.warn("{}: unknown capability '{}' ignored", pluginDir.string(), *name);
          }
        }
      }
      return set;
    } catch (const toml::parse_error&) {
      return 0;
    }
  }

  std::filesystem::path pluginGrantsPath() {
    const char* override = std::getenv("ZYNITH_PLUGIN_GRANTS");
    if (override != nullptr && *override == '/') {
      return override;
    }
    return xdg("XDG_CONFIG_HOME", ".config") / "zynith" / "plugin-grants.toml";
  }

  PluginCapabilities& PluginCapabilities::instance() {
    static PluginCapabilities caps;
    return caps;
  }

  void PluginCapabilities::setDeclared(const std::string& pluginId, CapabilitySet declared) {
    std::scoped_lock lock(m_mutex);
    m_declared[pluginId] = declared;
  }

  CapabilitySet PluginCapabilities::declared(const std::string& pluginId) const {
    std::scoped_lock lock(m_mutex);
    const auto it = m_declared.find(pluginId);
    return it == m_declared.end() ? 0 : it->second;
  }

  CapabilitySet PluginCapabilities::granted(const std::string& pluginId) const {
    std::scoped_lock lock(m_mutex);
    loadGrantsLocked();
    const auto it = m_granted.find(pluginId);
    return it == m_granted.end() ? 0 : it->second;
  }

  CapabilitySet PluginCapabilities::effective(const std::string& pluginId) const {
    std::scoped_lock lock(m_mutex);
    loadGrantsLocked();
    const auto d = m_declared.find(pluginId);
    const auto g = m_granted.find(pluginId);
    if (d == m_declared.end() || g == m_granted.end()) {
      return 0;
    }
    return d->second & g->second;
  }

  std::map<std::string, CapabilitySet> PluginCapabilities::allGrants() const {
    std::scoped_lock lock(m_mutex);
    loadGrantsLocked();
    return m_granted;
  }

  void PluginCapabilities::reloadGrants() {
    std::scoped_lock lock(m_mutex);
    m_loaded = false;
    loadGrantsLocked();
  }

  void PluginCapabilities::loadGrantsLocked() const {
    if (m_loaded) {
      return;
    }
    m_loaded = true;
    m_granted.clear();
    const auto path = pluginGrantsPath();
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) {
      return;
    }
    try {
      const auto table = toml::parse_file(path.string());
      const auto* grants = table["grants"].as_table();
      if (grants == nullptr) {
        return;
      }
      for (const auto& [key, node] : *grants) {
        CapabilitySet set = 0;
        if (const auto* list = node.as_array()) {
          for (const auto& item : *list) {
            if (const auto name = item.value<std::string>()) {
              if (const auto cap = parseCapability(*name)) {
                set |= static_cast<CapabilitySet>(*cap);
              }
            }
          }
        }
        m_granted[std::string(key.str())] = set;
      }
    } catch (const toml::parse_error& e) {
      kLog.warn("{} unreadable, no capabilities granted: {}", path.string(), e.description());
    }
  }

  bool PluginCapabilities::saveGrantsLocked(std::string* error) const {
    const auto path = pluginGrantsPath();
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    std::ostringstream out;
    out
        << "# What each Luau plugin may do beyond drawing itself. Written by `zynith-shell msg plugins grant|revoke`;\n"
        << "# a plugin gets only what it declares in its plugin.toml AND what is granted here.\n"
        << "# Capabilities: exec shell network files notifications clipboard env\n\n[grants]\n";
    for (const auto& [id, set] : m_granted) {
      out << '"' << id << "\" = [";
      bool first = true;
      for (const auto& [name, value] : kNames) {
        if (has(set, value)) {
          out << (first ? "" : ", ") << '"' << name << '"';
          first = false;
        }
      }
      out << "]\n";
    }
    const auto tmp = path.string() + ".tmp";
    {
      std::ofstream file(tmp, std::ios::trunc);
      file << out.str();
      if (!file) {
        if (error != nullptr) {
          *error = "cannot write " + tmp;
        }
        return false;
      }
    }
    std::filesystem::rename(tmp, path, ec);
    if (ec) {
      if (error != nullptr) {
        *error = "cannot replace " + path.string() + ": " + ec.message();
      }
      return false;
    }
    return true;
  }

  bool PluginCapabilities::grant(const std::string& pluginId, CapabilitySet caps, std::string* error) {
    std::scoped_lock lock(m_mutex);
    loadGrantsLocked();
    m_granted[pluginId] |= caps;
    kLog.info("{}: granted {}", pluginId, describeCapabilities(caps));
    return saveGrantsLocked(error);
  }

  bool PluginCapabilities::revoke(const std::string& pluginId, CapabilitySet caps, std::string* error) {
    std::scoped_lock lock(m_mutex);
    loadGrantsLocked();
    auto it = m_granted.find(pluginId);
    if (it == m_granted.end()) {
      return true;
    }
    it->second &= static_cast<CapabilitySet>(~caps);
    if (it->second == 0) {
      m_granted.erase(it);
    }
    kLog.info("{}: revoked {}", pluginId, describeCapabilities(caps));
    return saveGrantsLocked(error);
  }

  bool fileAccessAllowed(
      const std::filesystem::path& path, FileAccess access, const std::filesystem::path& pluginDir,
      const std::filesystem::path& dataDir, CapabilitySet caps, std::string* reason
  ) {
    const auto target = resolvedPath(path);
    const auto deny = [&](std::string why) {
      if (reason != nullptr) {
        *reason = std::move(why);
      }
      return false;
    };
    if (isProcessPath(target)) {
      return deny("process information is off limits");
    }
    for (const auto& secret : secretLocations()) {
      if (target == secret || within(target, secret)) {
        return deny("secret store");
      }
    }
    const bool own = within(target, resolvedPath(pluginDir))
        || target == resolvedPath(pluginDir)
        || (!dataDir.empty() && (within(target, resolvedPath(dataDir)) || target == resolvedPath(dataDir)));
    if (own) {
      return true;
    }
    if (access == FileAccess::Write) {
      for (const auto& guarded : protectedLocations()) {
        if (target == guarded || within(target, guarded)) {
          return deny("protected location");
        }
      }
    }
    if (!has(caps, Capability::Files)) {
      return deny("outside the plugin's own directories (needs the files capability)");
    }
    return true;
  }

  bool envAllowedWithoutCapability(std::string_view name) noexcept {
    static constexpr std::array<std::string_view, 12> kPlain{
        "HOME", "USER", "LOGNAME",         "LANG",    "LANGUAGE",        "SHELL", "TERM",
        "TZ",   "PATH", "WAYLAND_DISPLAY", "DISPLAY", "DESKTOP_SESSION",
    };
    for (const auto plain : kPlain) {
      if (name == plain) {
        return true;
      }
    }
    return name.starts_with("LC_") || name.starts_with("XDG_");
  }

} // namespace scripting
