#include "cli/schema_msg.h"
#include "tests/test_check.h"
#include "theme/builtin_palettes.h"
#include "theme/scheme.h"

#include <algorithm>
#include <cstdlib>
#include <string_view>

namespace {

  const zynith::cli::Command& child(const zynith::cli::Command& command, std::string_view name) {
    const auto it = std::ranges::find(command.subcommands, name, &zynith::cli::Command::name);
    TEST_CHECK(it != command.subcommands.end());
    return *it;
  }

} // namespace

int main() {
  const zynith::cli::Command* colorSchemeSet = zynith::cli::findMsgCommand("color-scheme-set");
  TEST_CHECK(colorSchemeSet != nullptr);

  const auto& builtin = child(*colorSchemeSet, "builtin");
  TEST_CHECK(builtin.positionals.size() == 1);
  const auto palettes = zynith::theme::builtinPalettes();
  TEST_CHECK(builtin.positionals.front().choices.size() == palettes.size());
  for (std::size_t i = 0; i < palettes.size(); ++i)
    TEST_CHECK(builtin.positionals.front().choices[i] == palettes[i].name);

  const auto& wallpaper = child(*colorSchemeSet, "wallpaper");
  TEST_CHECK(wallpaper.positionals.size() == 1);
  TEST_CHECK(wallpaper.positionals.front().choices.size() == zynith::theme::kSchemeNames.size());
  for (std::size_t i = 0; i < zynith::theme::kSchemeNames.size(); ++i) {
    const std::string_view name = zynith::theme::kSchemeNames[i];
    TEST_CHECK(wallpaper.positionals.front().choices[i] == name);
    const auto parsed = zynith::theme::schemeFromString(name);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK(zynith::theme::schemeToString(*parsed) == name);
  }

  return EXIT_SUCCESS;
}
