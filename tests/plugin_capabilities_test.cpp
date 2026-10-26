#include "scripting/plugin_capabilities.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <print>

using namespace scripting;

namespace {

  int failures = 0;

  void expect(bool condition, const char* message) {
    if (!condition) {
      std::println(stderr, "plugin_capabilities_test: {}", message);
      ++failures;
    }
  }

  bool allowed(const std::filesystem::path& path, FileAccess access, CapabilitySet caps) {
    return fileAccessAllowed(
        path, access, "/tmp/zcap/home/.local/share/zynith-shell/plugins/me",
        "/tmp/zcap/home/.local/state/zynith-shell/plugins/data/me/plugin", caps, nullptr
    );
  }

} // namespace

int main() {
  const std::filesystem::path root = "/tmp/zcap";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root / "home/.local/share/zynith-shell/plugins/me");
  std::filesystem::create_directories(root / "home/.ssh");
  std::filesystem::create_directories(root / "home/.config/zynith");
  ::setenv("HOME", (root / "home").c_str(), 1);
  ::unsetenv("XDG_CONFIG_HOME");
  ::unsetenv("XDG_DATA_HOME");
  ::unsetenv("XDG_STATE_HOME");
  ::setenv("ZYNITH_PLUGIN_GRANTS", (root / "grants.toml").c_str(), 1);

  const CapabilitySet files = static_cast<CapabilitySet>(Capability::Files);
  const auto home = root / "home";
  const auto own = home / ".local/share/zynith-shell/plugins/me";

  // own directories need nothing
  expect(allowed(own / "data.json", FileAccess::Write, 0), "own directory writable without capabilities");
  // elsewhere needs files
  expect(!allowed(home / "notes.txt", FileAccess::Read, 0), "home read refused without files");
  expect(allowed(home / "notes.txt", FileAccess::Read, files), "home read allowed with files");
  // secrets never
  expect(!allowed(home / ".ssh/id_ed25519", FileAccess::Read, files), "ssh key refused even with files");
  expect(!allowed(home / ".local/state/zynith-shell/clipboard/x", FileAccess::Read, files), "clipboard store refused");
  expect(!allowed("/proc/self/environ", FileAccess::Read, files), "own environment via /proc refused");
  expect(!allowed("/proc/1234/environ", FileAccess::Read, files), "other environments via /proc refused");
  // symlink out of the plugin directory is judged by its target
  std::filesystem::create_symlink(home / ".ssh", own / "keys");
  expect(!allowed(own / "keys/id_ed25519", FileAccess::Read, files), "symlink into ~/.ssh refused");
  // writes that would become code execution
  expect(!allowed(home / ".bashrc", FileAccess::Write, files), "shell startup file write refused");
  expect(!allowed(home / ".config/zynith/plugin-grants.toml", FileAccess::Write, files), "grants file write refused");
  expect(!allowed(home / ".config/niri/config.kdl", FileAccess::Write, files), "niri config write refused");
  expect(
      !allowed(home / ".local/share/zynith-shell/plugins/other/x.luau", FileAccess::Write, files),
      "other plugin's code write refused"
  );
  expect(allowed(home / ".config/niri/config.kdl", FileAccess::Read, files), "niri config readable with files");

  // env
  expect(envAllowedWithoutCapability("USER"), "USER plain");
  expect(envAllowedWithoutCapability("XDG_RUNTIME_DIR"), "XDG_* plain");
  expect(!envAllowedWithoutCapability("GITHUB_TOKEN"), "tokens need env");

  // declared ∩ granted
  {
    std::ofstream manifest(own / "plugin.toml");
    manifest << "id = \"me/plugin\"\ncapabilities = [\"exec\", \"files\", \"bogus\"]\n";
  }
  const CapabilitySet declared = declaredCapabilities(own);
  expect(declared == (static_cast<CapabilitySet>(Capability::Exec) | files), "declared parsed, unknown ignored");
  auto& registry = PluginCapabilities::instance();
  registry.setDeclared("me/plugin", declared);
  expect(registry.effective("me/plugin") == 0, "nothing effective before a grant");
  std::string error;
  expect(registry.grant("me/plugin", parseCapabilityList("files network"), &error), "grant written");
  expect(registry.effective("me/plugin") == files, "effective is declared ∩ granted");
  registry.reloadGrants();
  expect(
      registry.granted("me/plugin") == (files | static_cast<CapabilitySet>(Capability::Network)),
      "grants survive a reload from disk"
  );
  expect(registry.revoke("me/plugin", files, &error), "revoke written");
  expect(registry.effective("me/plugin") == 0, "revoked capability gone");

  std::string unknown;
  (void)parseCapabilityList("exec, nope", &unknown);
  expect(unknown == "nope", "unknown names reported");

  std::filesystem::remove_all(root);
  return failures == 0 ? 0 : 1;
}
