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

  // --- lock screen layout: an editor save shadows the whole preset; reset returns to it ---------
  // The editor stores its snapshot through setLockscreenWidgetsState, i.e. as settings.toml overrides
  // that include widget_order. A widget missing from that order is dropped, so a layout saved before
  // the preset gained a widget hides it for good — until lockscreen-widgets-reset clears the table.
  {
    const auto widget = [](std::string_view id, std::string_view type, int cy) {
      return std::string("[lockscreen_widgets.widget.") + std::string(id) + "]\ntype = \"" + std::string(type)
          + "\"\noutput = \"eDP-1\"\ncx = 960.0\ncy = " + std::to_string(cy)
          + ".0\nbox_width = 200.0\nbox_height = 60.0\nrotation = 0.0\nplacement_width = 1920.0\n"
            "placement_height = 1200.0\n\n";
    };
    writeFile(
        root / "config" / "noctalia" / "lockscreen.toml",
        "[lockscreen_widgets]\nenabled = true\nschema_version = 2\n"
        "widget_order = [\"lockscreen-widget-0000000000000002\", \"lockscreen-widget-0000000000000013\"]\n\n"
            + widget("lockscreen-widget-0000000000000002", "clock", 452)
            + widget("lockscreen-widget-0000000000000013", "session_actions", 64)
    );
    ConfigService config;
    const auto widgetCount = [&]() { return config.config().lockscreenWidgets.widgets.size(); };
    expect(widgetCount() == 2, "the lock preset's two widgets are loaded");

    LockscreenWidgetsConfig saved = config.config().lockscreenWidgets;
    saved.widgets.pop_back(); // an older layout, saved before the preset had power controls
    expect(config.setLockscreenWidgetsState(saved), "an editor-style save is stored");
    expect(widgetCount() == 1, "the saved layout shadows the preset: the new widget is gone");
    const LockscreenWidgetsConfig afterSave = config.config().lockscreenWidgets;

    // Batch 7: the reset IPC parks the overrides before clearing them, and restore puts them back.
    std::string error;
    expect(config.stashOverrideTable("lockscreen_widgets", &error), "the overrides are stashed before a reset");
    const std::filesystem::path stash = settingsToml.string() + ".lockscreen_widgets.stash";
    expect(std::filesystem::exists(stash), "the stash is a sidecar next to settings.toml");

    expect(config.clearOverride({"lockscreen_widgets"}), "reset clears the lock layout overrides");
    expect(widgetCount() == 2, "after reset the preset's widgets are back");
    expect(readFile(settingsToml).find("lockscreen_widgets") == std::string::npos,
           "reset leaves no lock layout in settings.toml");
    expect(!config.clearOverride({"lockscreen_widgets"}), "a second reset reports nothing to clear");
    expect(!config.stashOverrideTable("lockscreen_widgets", &error) && error.empty(),
           "with nothing to stash, stash reports false without an error (the earlier stash is kept)");

    expect(config.restoreStashedOverrideTable("lockscreen_widgets", &error), "restore succeeds");
    expect(widgetCount() == 1, "restore brings the saved layout back (it shadows the preset again)");
    expect(config.config().lockscreenWidgets == afterSave, "the restored layout equals the one that was reset");

    std::filesystem::remove(stash);
    expect(!config.restoreStashedOverrideTable("lockscreen_widgets", &error) && !error.empty(),
           "restore without a stash fails with a reason");
  }

  std::filesystem::remove_all(root);
  if (failures == 0) {
    std::cout << "zynith config ownership test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
