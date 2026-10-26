// zynith: the capability gates as a plugin meets them, through the real Luau bindings.
#include "core/toml.h"
#include "scripting/luau_host.h"
#include "scripting/plugin_capabilities.h"
#include "scripting/script_api_context.h"

#include <cstdlib>
#include <filesystem>
#include <memory>
#include <print>
#include <string>

namespace {

  bool run(LuauHost& host, const char* name, const char* source) {
    if (!host.exec(name, source)) {
      std::println(stderr, "plugin_capability_gates_test: {} failed: {}", name, host.lastError());
      return false;
    }
    return true;
  }

} // namespace

int main() {
  const std::filesystem::path root = "/tmp/zcapgates";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root / "home/.ssh");
  std::filesystem::create_directories(root / "plugin");
  ::setenv("HOME", (root / "home").c_str(), 1);
  ::setenv("ZYNITH_STATE_HOME", (root / "state").c_str(), 1);
  ::setenv("ZYNITH_PLUGIN_GRANTS", (root / "grants.toml").c_str(), 1);
  ::setenv("ZYNITH_TEST_SECRET", "hunter2", 1);
  {
    std::FILE* f = std::fopen((root / "home/notes.txt").c_str(), "w");
    std::fputs("notes", f);
    std::fclose(f);
  }
  {
    std::FILE* f = std::fopen((root / "home/.ssh/id_test").c_str(), "w");
    std::fputs("key", f);
    std::fclose(f);
  }

  scripting::ScriptApiContext api;
  api.setConfigSnapshot(std::make_shared<const toml::table>(toml::parse("[shell]\noffline_mode = true")));
  auto& caps = scripting::PluginCapabilities::instance();
  caps.setDeclared("test/gates", scripting::parseCapabilityList("exec files network notifications clipboard env"));

  LuauHost host(api, "test/gates:main");
  host.setPluginDir(root / "plugin");

  bool ok = true;
  // nothing granted: every gated call is refused, plain calls and own files still work
  ok = run(host, "=ungranted", R"(
local function refused(f, ...)
  local good, err = pcall(f, ...)
  return not good and string.find(tostring(err), "capability", 1, true) ~= nil
end
local function denied(f, ...)
  local good, err = pcall(f, ...)
  return not good and string.find(tostring(err), "refused", 1, true) ~= nil
end
assert(refused(zynith.runAsync, { "true" }, function() end), "argv exec without exec")
assert(refused(zynith.runAsync, "true", function() end), "shell string without shell")
assert(refused(zynith.http, { url = "https://example.invalid" }, function() end), "http without network")
assert(refused(zynith.notify, "x", "y"), "notify without notifications")
assert(refused(zynith.clipboardText), "clipboard without clipboard")
assert(refused(zynith.getenv, "ZYNITH_TEST_SECRET"), "secret env without env")
assert(zynith.getenv("HOME") ~= nil, "HOME is plain")
assert(denied(zynith.readFile, "~/notes.txt"), "home file without files")
assert(zynith.writeFile("own.txt", "mine"), "own directory needs nothing")
assert(zynith.readFile("own.txt") == "mine", "own file reads back")
)") && ok;

  std::string error;
  ok = caps.grant("test/gates", scripting::parseCapabilityList("exec files env"), &error) && ok;

  // granted: what is declared and granted works; shell (not declared) and secrets stay closed
  ok = run(host, "=granted", R"(
local function refused(f, ...)
  local good, err = pcall(f, ...)
  return not good and string.find(tostring(err), "capability", 1, true) ~= nil
end
local function denied(f, ...)
  local good, err = pcall(f, ...)
  return not good and string.find(tostring(err), "refused", 1, true) ~= nil
end
assert(zynith.runAsync({ "true" }), "argv exec granted")
assert(refused(zynith.runAsync, "true", function() end), "shell still needs shell")
assert(zynith.readFile("~/notes.txt") == "notes", "home file with files")
assert(denied(zynith.readFile, "~/.ssh/id_test"), "ssh key never")
assert(denied(zynith.listDir, "~/.ssh"), "ssh listing never")
assert(denied(zynith.writeFile, "~/.bashrc", "x"), "startup file write never")
assert(zynith.getenv("ZYNITH_TEST_SECRET") == "hunter2", "env granted")
assert(refused(zynith.http, { url = "https://example.invalid" }, function() end), "network declared but not granted")
)") && ok;

  std::filesystem::remove_all(root);
  return ok ? 0 : 1;
}
