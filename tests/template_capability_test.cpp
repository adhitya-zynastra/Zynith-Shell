// zynith: capability-aware templates. An entry whose application is not installed does no work at all, an output
// whose directory cannot exist is skipped without failing the apply, and a hook only runs for rendered output.

#include "theme/hook_runner.h"
#include "theme/template_engine.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {

  using zynith::theme::HookRunner;
  using zynith::theme::TemplateEngine;

  const std::filesystem::path kRoot = std::filesystem::temp_directory_path() / "zynith_template_capability_test";
  int failures = 0;

  void check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
      ++failures;
    }
  }

  void writeFile(const std::filesystem::path& path, const std::string& text) {
    std::ofstream out(path);
    out << text;
  }

  bool process(const std::string& configText, bool force = false) {
    const auto configPath = kRoot / "templates.toml";
    writeFile(configPath, configText);
    TemplateEngine::Options options;
    options.defaultMode = "dark";
    options.verbose = true;
    options.rerunUnchangedHooks = force;
    TemplateEngine engine(TemplateEngine::ThemeData{{"primary", {{"dark", "#ff0000"}}}}, options);
    return engine.processConfigFile(configPath);
  }

  std::string entry(
      const std::string& name, const std::filesystem::path& output, const std::string& requiresCommand,
      const std::filesystem::path& hookMarker
  ) {
    return "[templates."
        + name
        + "]\ninput_path = \"input.tmpl\"\noutput_path = \""
        + output.string()
        + "\"\n"
        + (requiresCommand.empty() ? "" : "requires_command = " + requiresCommand + "\n")
        + "post_hook = \"touch "
        + hookMarker.string()
        + "\"\nhook_async = false\n\n";
  }

} // namespace

int main() {
  std::filesystem::remove_all(kRoot);
  std::filesystem::create_directories(kRoot);
  writeFile(kRoot / "input.tmpl", "static content; this test is about capability checks\n");

  // 1. The application is not installed: nothing is rendered, the hook does not run, and the apply succeeds.
  {
    const auto out = kRoot / "absent" / "theme.conf";
    const auto marker = kRoot / "absent.hook";
    const bool ok = process(entry("absent", out, "\"zynith-definitely-not-installed\"", marker));
    check(ok, "a skipped application does not fail the apply");
    check(!std::filesystem::exists(out), "no output for an application that is not installed");
    check(!std::filesystem::exists(kRoot / "absent"), "no directory is created for it either");
    check(!std::filesystem::exists(marker), "no hook for an application that is not installed");
  }

  // 2. An installed application (any alternative is enough): rendered, hook runs.
  {
    const auto out = kRoot / "present" / "theme.conf";
    const auto marker = kRoot / "present.hook";
    const bool ok = process(entry("present", out, "[\"zynith-definitely-not-installed\", \"sh\"]", marker));
    check(ok, "an installed application applies");
    check(std::filesystem::exists(out), "its output is rendered");
    check(std::filesystem::exists(marker), "its hook runs");
  }

  // 3. The output directory is a symlink to a missing target (stale dotfiles): skipped, no hook, no failure.
  {
    const auto dangling = kRoot / "dangling-dir";
    std::filesystem::create_directory_symlink(kRoot / "missing-target", dangling);
    const auto out = dangling / "theme.css";
    const auto marker = kRoot / "dangling.hook";
    const bool ok = process(entry("dangling", out, "", marker));
    check(ok, "an unusable output directory does not fail the apply");
    check(!std::filesystem::exists(kRoot / "missing-target"), "the missing target is not created behind the symlink");
    check(!std::filesystem::exists(marker), "no hook when nothing was rendered");
  }

  // 4. Several entries in one pass: the skipped one does not stop the next.
  {
    const auto out = kRoot / "second" / "theme.conf";
    const auto marker = kRoot / "second.hook";
    const bool ok = process(
        entry("first", kRoot / "x" / "y", "\"zynith-definitely-not-installed\"", kRoot / "first.hook")
        + entry("second", out, "", marker)
    );
    check(ok, "a mixed pass succeeds");
    check(std::filesystem::exists(out) && std::filesystem::exists(marker), "the entry after a skipped one applies");
  }

  // 5. Unchanged output: an automatic apply skips the hook (the application already has this theme); a forced
  //    apply (`templates-apply`, the CLI) re-runs it.
  {
    const auto out = kRoot / "steady" / "theme.conf";
    const auto marker = kRoot / "steady.hook";
    const std::string config = entry("steady", out, "", marker);
    process(config);
    check(std::filesystem::exists(marker), "the first apply writes the output and runs the hook");
    std::filesystem::remove(marker);
    process(config);
    check(!std::filesystem::exists(marker), "an unchanged output does not re-run the hook");
    process(config, /*force=*/true);
    check(std::filesystem::exists(marker), "a forced apply re-runs the hook");
  }

  std::filesystem::remove_all(kRoot);
  if (failures == 0) {
    std::cout << "template capability test passed\n";
    return 0;
  }
  std::cerr << failures << " check(s) failed\n";
  return 1;
}
