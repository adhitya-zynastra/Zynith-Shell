#include "cli/parse.h"
#include "tests/test_check.h"

#include <array>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace {

  struct Args {
    explicit Args(std::initializer_list<std::string_view> values) {
      storage.reserve(values.size());
      pointers.reserve(values.size());
      for (const std::string_view value : values)
        storage.emplace_back(value);
      for (std::string& value : storage)
        pointers.push_back(value.data());
    }

    std::vector<std::string> storage;
    std::vector<char*> pointers;
  };

  constexpr std::array<std::string_view, 2> kModeChoices{"dark", "light"};
  constexpr std::array kFlags{
      zynith::cli::Flag{"--output", "-o", "<file>", "Output file", {}, {}, false, false},
      zynith::cli::Flag{"--verbose", "-v", {}, "Verbose", {}, {}, false, false},
      zynith::cli::Flag{"--render", "-r", "<spec>", "Render mapping", {}, {}, true, false},
      zynith::cli::Flag{"--mode", {}, "<mode>", "Mode", kModeChoices, "dark", false, false},
  };
  constexpr std::array kPositionals{
      zynith::cli::Positional{"input", "Input", {}, true, false, false},
  };
  constexpr zynith::cli::Command kCommand{
      "sample", "Sample", {}, {}, kFlags, kPositionals, {}, false,
  };

  void checkFlags() {
    Args args{"-v", "--output=result.json", "--render", "a:b", "-r", "c:d", "--mode", "light", "input.png"};
    auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK(parsed->has("--verbose"));
    TEST_CHECK(parsed->value("--verbose") == "1");
    TEST_CHECK(parsed->value("--output") == "result.json");
    TEST_CHECK(parsed->value("--mode") == "light");
    const auto renders = parsed->values("--render");
    TEST_CHECK((renders == std::vector<std::string_view>{"a:b", "c:d"}));
    TEST_CHECK(parsed->positionals.size() == 1);
    TEST_CHECK(parsed->positionals[0] == "input.png");
  }

  void checkLastFlagWins() {
    Args args{"--output", "first", "-o", "second", "input.png"};
    auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK(parsed->value("--output") == "second");
    TEST_CHECK(parsed->values("--output").size() == 1);
    TEST_CHECK(parsed->valueOr("--missing", "fallback") == "fallback");
  }

  void checkErrors() {
    {
      Args args{"--mode", "sideways", "input.png"};
      auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
      TEST_CHECK(!parsed.has_value());
      TEST_CHECK(parsed.error() == "error: invalid value 'sideways' for <mode> (expected dark, light)");
    }
    {
      Args args{"--output"};
      auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
      TEST_CHECK(!parsed.has_value());
      TEST_CHECK(parsed.error() == "error: --output requires a value");
    }
    {
      Args args{"--bogus"};
      auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
      TEST_CHECK(!parsed.has_value());
      TEST_CHECK(parsed.error() == "error: unknown argument: --bogus");
    }
    {
      Args args{};
      auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
      TEST_CHECK(!parsed.has_value());
      TEST_CHECK(parsed.error() == "error: missing required argument <input>");
    }
    {
      Args args{"input", "extra"};
      auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
      TEST_CHECK(!parsed.has_value());
      TEST_CHECK(parsed.error() == "error: unexpected argument: extra");
    }
  }

  void checkRequiredFlag() {
    static constexpr std::array flags{
        zynith::cli::Flag{"--target", {}, "<dir>", "Target", {}, {}, false, true},
    };
    static constexpr zynith::cli::Command command{"required", {}, {}, {}, flags, {}, {}, false};
    Args args{};
    auto parsed = zynith::cli::parseArgs(command, args.pointers);
    TEST_CHECK(!parsed.has_value());
    TEST_CHECK(parsed.error() == "error: missing required flag --target");
  }

  void checkVariadic() {
    static constexpr std::array positionals{
        zynith::cli::Positional{"path", {}, {}, false, true, false},
    };
    static constexpr zynith::cli::Command command{"lint", {}, {}, {}, {}, positionals, {}, false};
    Args args{"one", "two", "three"};
    auto parsed = zynith::cli::parseArgs(command, args.pointers);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK((parsed->positionals == std::vector<std::string_view>{"one", "two", "three"}));
  }

  void checkJoinedRemaining() {
    static constexpr std::array positionals{
        zynith::cli::Positional{"summary", {}, {}, true, false, false},
        zynith::cli::Positional{"body", {}, {}, true, false, true},
    };
    static constexpr zynith::cli::Command command{"notification-show", {}, {}, {}, {}, positionals, {}, false};
    Args args{"Hello", "World", "!"};
    auto parsed = zynith::cli::parseArgs(command, args.pointers);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK(parsed->positionals.size() == 1);
    TEST_CHECK(parsed->positionals[0] == "Hello");
    TEST_CHECK(parsed->joinedRemaining == "World !");
  }

  void checkHelpAnywhere() {
    Args args{"input.png", "--help", "--bogus"};
    auto parsed = zynith::cli::parseArgs(kCommand, args.pointers);
    TEST_CHECK(parsed.has_value());
    TEST_CHECK(parsed->helpRequested);
  }

} // namespace

int main() {
  static_assert(zynith::cli::validateCommand(kCommand));
  checkFlags();
  checkLastFlagWins();
  checkErrors();
  checkRequiredFlag();
  checkVariadic();
  checkJoinedRemaining();
  checkHelpAnywhere();
  return EXIT_SUCCESS;
}
