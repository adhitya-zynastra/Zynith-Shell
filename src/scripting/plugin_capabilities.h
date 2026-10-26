#pragma once

// zynith: what a Luau plugin may do beyond drawing itself.
//
// A plugin declares the capabilities it needs in plugin.toml (`capabilities = ["exec", "network"]`) and gets
// only those that are also granted in ~/.config/zynith/plugin-grants.toml. That file is written by the
// `plugins grant|revoke` IPC, never by a plugin. Declaring more in an update grants nothing new.
//
//   exec           run a program from an argv table (no shell)
//   shell          run a shell command string (sh -c): unrestricted execution, so separate from exec
//   network        http, httpStream, download
//   files          read, write or list outside the plugin's own directory and data directory
//   notifications  notify, notifyError
//   clipboard      read or set the clipboard
//   env            environment variables beyond a small non-secret set (HOME, USER, LANG, XDG_*, …)
//
// Independent of any grant: secret stores (ssh/gpg keys, keyrings, password stores, browser profiles, the
// shell's encrypted clipboard) are never readable, and files that would turn a write into code execution
// (shell startup files, autostart, niri/zynith-shell/zynith config, other plugins) are never writable.

#include <cstdint>
#include <filesystem>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>

namespace scripting {

  enum class Capability : std::uint8_t {
    Exec = 1U << 0U,
    Shell = 1U << 1U,
    Network = 1U << 2U,
    Files = 1U << 3U,
    Notifications = 1U << 4U,
    Clipboard = 1U << 5U,
    Env = 1U << 6U,
  };
  using CapabilitySet = std::uint8_t;

  [[nodiscard]] constexpr bool has(CapabilitySet set, Capability cap) noexcept {
    return (set & static_cast<CapabilitySet>(cap)) != 0;
  }
  [[nodiscard]] std::string_view capabilityName(Capability cap) noexcept;
  [[nodiscard]] std::optional<Capability> parseCapability(std::string_view name) noexcept;
  // "exec, files" or "none"
  [[nodiscard]] std::string describeCapabilities(CapabilitySet set);
  // Space or comma separated names; unknown names are reported in `unknown`.
  [[nodiscard]] CapabilitySet parseCapabilityList(std::string_view text, std::string* unknown = nullptr);

  // `capabilities` from <pluginDir>/plugin.toml (0 when absent or unreadable).
  [[nodiscard]] CapabilitySet declaredCapabilities(const std::filesystem::path& pluginDir);
  // $ZYNITH_PLUGIN_GRANTS, else $XDG_CONFIG_HOME/zynith/plugin-grants.toml
  [[nodiscard]] std::filesystem::path pluginGrantsPath();

  // Process-wide and thread-safe: script workers ask from their own threads.
  class PluginCapabilities {
  public:
    static PluginCapabilities& instance();

    void setDeclared(const std::string& pluginId, CapabilitySet declared);
    [[nodiscard]] CapabilitySet declared(const std::string& pluginId) const;
    [[nodiscard]] CapabilitySet granted(const std::string& pluginId) const;
    [[nodiscard]] CapabilitySet effective(const std::string& pluginId) const;
    [[nodiscard]] std::map<std::string, CapabilitySet> allGrants() const;

    // Rewrite the grants file atomically. Effective sets change at once; no reload needed.
    bool grant(const std::string& pluginId, CapabilitySet caps, std::string* error);
    bool revoke(const std::string& pluginId, CapabilitySet caps, std::string* error);
    void reloadGrants();

  private:
    PluginCapabilities() = default;
    void loadGrantsLocked() const;
    bool saveGrantsLocked(std::string* error) const;

    mutable std::mutex m_mutex;
    mutable bool m_loaded = false;
    mutable std::map<std::string, CapabilitySet> m_granted;
    std::map<std::string, CapabilitySet> m_declared;
  };

  enum class FileAccess : std::uint8_t { Read, Write, Inspect };

  // Whether a plugin with `caps` may touch `path` (already absolute) for `access`. `reason` explains a refusal.
  [[nodiscard]] bool fileAccessAllowed(
      const std::filesystem::path& path, FileAccess access, const std::filesystem::path& pluginDir,
      const std::filesystem::path& dataDir, CapabilitySet caps, std::string* reason
  );

  // Variables any plugin may read without the env capability.
  [[nodiscard]] bool envAllowedWithoutCapability(std::string_view name) noexcept;

} // namespace scripting
