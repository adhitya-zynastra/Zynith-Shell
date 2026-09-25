// Zynith transient UI configuration: the launcher style and geometry keys and the OSD hold, through
// the same layering as every other Zynith key (defaults -> rice.toml -> settings.toml overrides).
//
// Defaults must be the designed Zynith launcher; a preset must be able to select the classic one;
// out-of-range geometry is clamped by the schema (silently — upstream parser behaviour, recorded in
// zynith_config_ownership_test); and a GUI override resets back to the preset.

#include "config/config_service.h"
#include "config/config_types.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>

namespace {

  int failures = 0;

  void expect(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
  }

  void writeFile(const std::filesystem::path& path, std::string_view content) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream out(path, std::ios::trunc);
    out << content;
  }

} // namespace

int main() {
  // --- defaults ------------------------------------------------------------------------------
  {
    const ShellConfig::LauncherConfig launcher;
    expect(launcher.style == LauncherStyle::Zynith, "the Zynith launcher is the default");
    expect(launcher.width == 640 && launcher.height == 540, "default launcher geometry");
    expect(launcher.iconSize == 32, "default result icon size");
    expect(launcher.density == LayoutDensity::Comfortable, "default density is the neutral one");
    expect(launcher.keyHints, "key hints on by default");
    const OsdConfig osd;
    expect(osd.durationMs == 1400, "the OSD hold defaults to the pre-configurable 1.4 s");
  }

  const std::filesystem::path root =
      std::filesystem::temp_directory_path() / ("zynith-transient-ui-" + std::to_string(::getpid()));
  std::filesystem::remove_all(root);
  writeFile(
      root / "config" / "noctalia" / "rice.toml",
      "[shell.launcher]\n"
      "style = \"classic\"\n"
      "width = 2000\n"     // above the ceiling: clamped to 1200
      "icon_size = 10\n"   // below the floor: clamped to 20
      "density = \"spacious\"\n"
      "key_hints = false\n"
      "\n"
      "[osd]\n"
      "duration_ms = 100\n" // below the floor: clamped to 600
  );
  ::setenv("NOCTALIA_CONFIG_HOME", (root / "config").c_str(), 1);
  ::setenv("XDG_STATE_HOME", (root / "state").c_str(), 1);

  {
    ConfigService config;
    const auto& launcher = [&]() -> const ShellConfig::LauncherConfig& { return config.config().shell.launcher; };

    // --- the preset layer is read, with range clamping ------------------------------------------
    expect(launcher().style == LauncherStyle::Classic, "a preset can select the classic launcher");
    expect(launcher().width == 1200, "launcher width is clamped to its range");
    expect(launcher().iconSize == 20, "icon size is clamped to its range");
    expect(launcher().density == LayoutDensity::Spacious, "density is read");
    expect(!launcher().keyHints, "key hints can be turned off");
    expect(launcher().height == 540, "an absent key keeps its default");
    expect(config.config().osd.durationMs == 600, "OSD duration is clamped to its floor");

    // --- a GUI override wins, and reset falls back to the preset ------------------------------
    expect(config.setOverride({"shell", "launcher", "style"}, std::string("zynith")), "set style override");
    expect(launcher().style == LauncherStyle::Zynith, "the override wins");
    expect(config.clearOverride({"shell", "launcher", "style"}), "reset the style override");
    expect(launcher().style == LauncherStyle::Classic, "after reset the preset's classic style is back");
  }

  std::filesystem::remove_all(root);
  if (failures == 0) {
    std::cout << "transient ui config test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
