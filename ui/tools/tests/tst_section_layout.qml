import QtQuick
import QtTest
import "../../Common/SectionLayout.js" as Layout

// Common/SectionLayout.js: the Control Panel's one arrangement (columns of section ids), as Settings edits it.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_section_layout.qml
TestCase {
    name: "SectionLayout"

    readonly property var known: ["header", "about", "shortcuts", "levels", "volume", "microphone", "media", "weather", "session", "profile", "screen_time"]
    readonly property var fallback: [["media"], ["shortcuts", "levels"], ["weather"]]

    function test_validate_drops_unknown_and_duplicates() {
        compare(Layout.validate([["media", "nope", "media"], ["toggles", "screen-time"], []], known, fallback), [["media"], ["shortcuts", "screen_time"]]);
    }
    function test_validate_lone_string_and_old_names() {
        compare(Layout.validate(["weather", ["mic"]], known, fallback), [["weather"], ["microphone"]]);
    }
    function test_validate_missing_is_default_but_empty_is_a_choice() {
        compare(Layout.validate(undefined, known, fallback), fallback);
        compare(Layout.validate([], known, fallback), []);
    }
    function test_validate_caps_columns() {
        compare(Layout.validate([["header"], ["about"], ["media"], ["weather"], ["session"], ["profile"]], known, fallback), [["header"], ["about"], ["media"], ["weather", "session", "profile"]]);
    }
    function test_arrangement_reads_retired_modules_only_for_the_column_layout() {
        compare(Layout.arrangement({ layout: "column", modules: ["header", "connectivity", "levels"] }, known, fallback), [["header", "shortcuts", "levels"]]);
        compare(Layout.arrangement({ modules: ["header"] }, known, fallback), fallback, "the dashboard never showed modules");
        compare(Layout.arrangement({ layout: "column", modules: ["header"], columns: [["weather"]] }, known, fallback), [["weather"]], "columns win once written");
    }
    function test_step_within_and_across_columns() {
        const a = [["media"], ["shortcuts", "levels"], ["weather"]];
        compare(Layout.step(a, "levels", -1), [["media"], ["levels", "shortcuts"], ["weather"]]);
        compare(Layout.step(a, "shortcuts", -1), [["media", "shortcuts"], ["levels"], ["weather"]]);
        compare(Layout.step(a, "levels", 1), [["media"], ["shortcuts"], ["levels", "weather"]]);
        compare(Layout.step(a, "media", -1), a, "nothing before the first");
        compare(Layout.step(a, "weather", 1), a, "nothing after the last");
        compare(Layout.step([["media"], ["weather"]], "media", 1), [["media", "weather"]], "to the top of the next column; the emptied one goes");
        compare(a, [["media"], ["shortcuts", "levels"], ["weather"]], "the input is untouched");
    }
    function test_step_in_reading_order() {
        const a = [["media"], ["shortcuts", "levels"], ["weather"]];
        compare(Layout.step(a, "media", 1, true), [["shortcuts"], ["media", "levels"], ["weather"]]);
        compare(Layout.flat(Layout.step(a, "levels", 1, true)), ["media", "shortcuts", "weather", "levels"]);
        compare(Layout.step(a, "media", -1, true), a);
        compare(Layout.step(a, "weather", 1, true), a);
    }
    function test_shift_moves_between_columns_with_weights() {
        const a = [["media"], ["shortcuts", "levels"], ["weather"]];
        const w = [1.6, 1, 1];
        let r = Layout.shift(a, w, "levels", 1);
        compare(r.columns, [["media"], ["shortcuts"], ["weather", "levels"]]);
        compare(r.weights, w);
        r = Layout.shift(a, w, "media", 1);
        compare(r.columns, [["shortcuts", "levels", "media"], ["weather"]]);
        compare(r.weights, [1, 1], "the emptied first column took its 1.6 with it");
        r = Layout.shift(a, w, "weather", 1);
        compare(r.columns, [["media"], ["shortcuts", "levels"], [], ["weather"]].filter(c => c.length > 0));
        compare(r.weights, [1.6, 1, 1], "weather left its column for a new one");
        r = Layout.shift(a, w, "media", -1);
        compare(r.columns, a, "no column before the first");
    }
    function test_shift_respects_max_columns() {
        const a = [["header"], ["about"], ["media"], ["weather"]];
        compare(Layout.shift(a, [1, 1, 1, 1], "weather", 1).columns, a);
    }
    function test_hide_and_show() {
        const a = [["media"], ["shortcuts", "levels"], ["weather"]];
        const h = Layout.hide(a, [1.6, 1, 1], "weather");
        compare(h.columns, [["media"], ["shortcuts", "levels"]]);
        compare(h.weights, [1.6, 1]);
        compare(Layout.show(h.columns, "session"), [["media", "session"], ["shortcuts", "levels"]], "onto the shortest column");
        compare(Layout.show([], "media"), [["media"]], "a column of its own when there is none");
        compare(Layout.show(a, "media"), a, "already shown");
    }
    function test_weights() {
        compare(Layout.weights([[1], [2], [3]], [1.6, 0, "x"]), [1.6, 1, 1]);
        compare(Layout.weights([[1], [2]], [9, 0.01]), [5, 0.2]);
    }
}
