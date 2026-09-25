// Zynith configuration ownership (ADR-0014): defaults -> ~/.config/noctalia/*.toml (the Zynith
// preset, rice.toml) -> settings.toml (the user's deviations).
//
// The property that matters most is reset: clearing a setting must DELETE the override so the
// value falls back to the preset, never write today's value into settings.toml — which would
// freeze the key and detach it from every later change to the preset. Also records the parser's
// actual handling of out-of-range values for the motion and glass keys: clamped, silently.

#include "config/config_service.h"
#include "config/config_types.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
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

  std::string readFile(const std::filesystem::path& path) {
    std::ifstream in(path);
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
  }

} // namespace

int main() {
  const std::filesystem::path root =
      std::filesystem::temp_directory_path() / ("zynith-config-ownership-" + std::to_string(::getpid()));
  std::filesystem::remove_all(root);
  // The Zynith preset layer, exactly where rice.toml lives on a real install.
  writeFile(
      root / "config" / "noctalia" / "rice.toml",
      "[shell.animation]\n"
      "preset = \"cinematic\"\n"
      "speed = 1.0\n"
      "niri_open = 0\n"      // below the floor: clamped to 50
      "niri_close = 900\n"   // above the ceiling: clamped to 200
      "\n"
      "[shell.glass]\n"
      "tint = true\n"
      "tint_strength = 0.2\n"
      "blur_strength = 70\n"
  );
  ::setenv("NOCTALIA_CONFIG_HOME", (root / "config").c_str(), 1);
  ::setenv("XDG_STATE_HOME", (root / "state").c_str(), 1);
  const auto settingsToml = root / "state" / "noctalia" / "settings.toml";

  {
    ConfigService config;
    const auto& anim = [&]() -> const ShellConfig::AnimationConfig& { return config.config().shell.animation; };
    const auto& glass = [&]() -> const ShellConfig::GlassConfig& { return config.config().shell.glass; };

    // --- the preset layer is read -----------------------------------------------------------
    expect(anim().preset == MotionPreset::Cinematic, "preset comes from rice.toml");
    expect(glass().tint && glass().blurStrength == 70, "glass comes from rice.toml");

    // --- out-of-range values: clamped, silently (upstream parser behaviour) ------------------
    expect(anim().niriOpen == 50, "niri_open = 0 is clamped to the 50 floor");
    expect(anim().niriClose == 200, "niri_close = 900 is clamped to 200");

    // --- a user change becomes an override that wins ---------------------------------------
    expect(config.setOverride({"shell", "animation", "preset"}, std::string("fast")), "set preset override");
    expect(anim().preset == MotionPreset::Fast, "the override wins over the preset layer");
    expect(config.hasOverride({"shell", "animation", "preset"}), "override is recorded");
    expect(readFile(settingsToml).find("preset") != std::string::npos, "override is persisted to settings.toml");

    expect(config.setOverride({"shell", "glass", "tint"}, false), "set glass override");
    expect(!glass().tint, "glass override wins");

    // --- reset deletes the override; the preset shows through again ------------------------
    expect(config.clearOverride({"shell", "animation", "preset"}), "clear preset override");
    expect(anim().preset == MotionPreset::Cinematic, "after reset the rice.toml preset is back");
    expect(!config.hasOverride({"shell", "animation", "preset"}), "no override remains");
    expect(readFile(settingsToml).find("preset") == std::string::npos,
           "reset REMOVES the key from settings.toml rather than writing today's value");

    expect(config.clearOverride({"shell", "glass", "tint"}), "clear glass override");
    expect(glass().tint, "glass falls back to the preset layer after reset");

    // --- a changed preset reaches a key that was reset, i.e. nothing was frozen --------------
    writeFile(root / "config" / "noctalia" / "rice.toml",
              "[shell.animation]\npreset = \"smooth\"\n\n[shell.glass]\ntint = true\n");
    config.forceReload();
    expect(anim().preset == MotionPreset::Smooth, "a later preset change reaches the reset key");
  }

  std::filesystem::remove_all(root);
  if (failures == 0) {
    std::cout << "zynith config ownership test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
