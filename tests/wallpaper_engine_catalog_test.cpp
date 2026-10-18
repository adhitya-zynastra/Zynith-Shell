#include "shell/wallpaper/live/wallpaper_engine_catalog.h"
#include "tests/test_check.h"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {

  namespace fs = std::filesystem;
  namespace we = live::wallpaper_engine;

  void writeFile(const fs::path& path, std::string_view text) {
    fs::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary) << text;
  }

} // namespace

int main() {
  // ── Workshop ids ──────────────────────────────────────────────────────────
  TEST_CHECK(we::isWorkshopId("1334736987"));
  TEST_CHECK(!we::isWorkshopId(""));
  TEST_CHECK(!we::isWorkshopId("../1334736987"));
  TEST_CHECK(!we::isWorkshopId("/home/x"));
  TEST_CHECK(!we::isWorkshopId("12a"));
  TEST_CHECK(!we::isWorkshopId("123456789012345678901"));

  // ── libraryfolders.vdf: current nested format, escapes, duplicates ─────────
  const auto nested = we::parseLibraryFolderPaths(R"("libraryfolders"
{
	"0"
	{
		"path"		"/home/u/.local/share/Steam"
		"label"		""
		"apps"
		{
			"431960"		"47700000000"
		}
	}
	"1"
	{
		"path"		"/mnt/games/Steam \"Library\""
	}
	"2"
	{
		"path"		"/home/u/.local/share/Steam"
	}
})");
  TEST_CHECK(nested.size() == 2);
  TEST_CHECK(nested[0] == "/home/u/.local/share/Steam");
  TEST_CHECK(nested[1] == "/mnt/games/Steam \"Library\"");

  // Legacy flat format.
  const auto legacy = we::parseLibraryFolderPaths(R"("LibraryFolders" { "TimeNextStatsReport" "1" "1" "/mnt/steam2" })");
  TEST_CHECK(legacy.size() == 1 && legacy[0] == "/mnt/steam2");

  // ── project.json ──────────────────────────────────────────────────────────
  const fs::path dir = "/lib/steamapps/workshop/content/431960/1334736987";
  auto scene = we::parseProject(
      "\xEF\xBB\xBF{\"title\":\"mount fuji\",\"type\":\"Scene\",\"preview\":\"preview.jpg\",\"file\":\"scene.json\"}",
      "1334736987", dir
  );
  TEST_CHECK(scene.has_value());
  TEST_CHECK(scene->kind == live::ItemKind::Scene);
  TEST_CHECK(scene->title == "mount fuji");
  TEST_CHECK(scene->preview == dir / "preview.jpg");
  TEST_CHECK(scene->id == "1334736987");

  // Missing "type": derived from the entry file.
  auto video = we::parseProject(R"({"title":"snow","file":"snow.MP4","preview":"preview.gif"})", "1", dir);
  TEST_CHECK(video.has_value() && video->kind == live::ItemKind::Video);
  auto web = we::parseProject(R"({"file":"index.html"})", "2", dir);
  TEST_CHECK(web.has_value() && web->kind == live::ItemKind::Web && web->title == "2");

  // Presets and unknown types are recognised, not rendered.
  auto preset = we::parseProject(R"({"title":"p","dependency":"1081733658","file":"","preset":{}})", "3", dir);
  TEST_CHECK(preset.has_value() && preset->kind == live::ItemKind::Preset && preset->dependency == "1081733658");
  TEST_CHECK(!live::isRenderable(preset->kind));
  auto app = we::parseProject(R"({"type":"application","file":"x.exe"})", "4", dir);
  TEST_CHECK(app.has_value() && app->kind == live::ItemKind::Unsupported);

  // A preview that escapes the item folder is dropped.
  auto escape = we::parseProject(R"({"type":"scene","preview":"../../../../etc/passwd"})", "5", dir);
  TEST_CHECK(escape.has_value() && escape->preview.empty());
  auto absolute = we::parseProject(R"({"type":"scene","preview":"/etc/passwd"})", "6", dir);
  TEST_CHECK(absolute.has_value() && absolute->preview.empty());

  TEST_CHECK(!we::parseProject("{not json", "7", dir).has_value());
  TEST_CHECK(!we::parseProject("[1,2]", "7", dir).has_value());

  // ── id lists ──────────────────────────────────────────────────────────────
  const auto ids = we::decodeIdList(" 3, 1,bad,3,,../x, 2 ");
  TEST_CHECK((ids == std::vector<std::string>{"3", "1", "2"}));
  TEST_CHECK(we::encodeIdList(ids) == "3,1,2");
  TEST_CHECK(we::decodeIdList("").empty());

  // ── layout resolution on a fake Steam tree ────────────────────────────────
  const fs::path root = fs::temp_directory_path()
      / ("zynith-we-catalog-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  const fs::path steam = root / "Steam";
  const fs::path second = root / "second-drive";
  fs::create_directories(steam / "steamapps/common/wallpaper_engine/assets");
  fs::create_directories(second / "steamapps/workshop/content/431960/42");
  writeFile(
      steam / "steamapps/libraryfolders.vdf",
      "\"libraryfolders\" { \"0\" { \"path\" \"" + steam.string() + "\" } \"1\" { \"path\" \"" + second.string()
          + "\" } }"
  );
  writeFile(second / "steamapps/workshop/content/431960/42/project.json", R"({"title":"Far","type":"video","preview":"p.jpg"})");
  writeFile(second / "steamapps/workshop/content/431960/42/p.jpg", "x");

  const we::Layout layout = we::resolveLayout({steam, root / "missing"});
  TEST_CHECK(layout.libraries.size() == 2);
  TEST_CHECK(layout.workshopDirs.size() == 1);
  TEST_CHECK(layout.assetsDir.has_value());
  const auto found = we::findItemDirectory(layout, "42");
  TEST_CHECK(found.has_value());
  TEST_CHECK(!we::findItemDirectory(layout, "43").has_value());
  TEST_CHECK(!we::findItemDirectory(layout, "../42").has_value());
  const auto loaded = we::loadItem(*found, "42");
  TEST_CHECK(loaded.has_value() && loaded->title == "Far" && loaded->kind == live::ItemKind::Video);
  TEST_CHECK(!loaded->preview.empty() && loaded->updatedNs != 0);

  // A configured root replaces the standard candidates.
  TEST_CHECK(we::steamRootCandidates("/x", "/home/u").size() == 1);
  TEST_CHECK(we::steamRootCandidates("", "/home/u").size() == 4);

  std::error_code ec;
  fs::remove_all(root, ec);
  return EXIT_SUCCESS;
}
