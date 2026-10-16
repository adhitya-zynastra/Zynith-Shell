import QtQuick
import QtTest
import "../../Common/KeyNav.js" as K

// Common/KeyNav.js: the keyboard through the dashboard's modules.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_key_nav.qml
TestCase {
    name: "KeyNav"

    // the dials (7 in rows of 4), the levels (3, one per row), a module with nothing to stop on, the glance (3)
    readonly property var zones: [{ count: 7, cols: 4 }, { count: 3, cols: 1 }, { count: 0, cols: 1 }, { count: 3, cols: 1 }]
    function at(z: int, s: int): var {
        return { zone: z, stop: s };
    }
    function go(pos: var, key: string): var {
        return K.move(zones, pos, key);
    }

    function test_first_move_lands_somewhere() {
        compare(go(at(-1, -1), "down"), at(0, 0));
        compare(go(at(-1, -1), "tab"), at(0, 0));
        compare(go(at(-1, -1), "backtab"), at(3, 0));
    }
    function test_tab_skips_empty_zones_and_wraps() {
        compare(go(at(1, 2), "tab"), at(3, 0));
        compare(go(at(3, 1), "tab"), at(0, 0));
        compare(go(at(0, 3), "backtab"), at(3, 0));
    }
    function test_grid_moves() {
        compare(go(at(0, 1), "down"), at(0, 5));
        compare(go(at(0, 3), "down"), at(0, 6), "a short last row is still a step down");
        compare(go(at(0, 5), "up"), at(0, 1));
        compare(go(at(0, 0), "left"), at(0, 0));
        compare(go(at(0, 6), "right"), at(0, 6));
    }
    function test_rows_run_on_into_the_next_zone() {
        compare(go(at(0, 5), "down"), at(1, 0));
        compare(go(at(1, 2), "down"), at(3, 0), "an empty zone is passed over");
        compare(go(at(1, 0), "up"), at(0, 4), "back into the grid's last row");
        compare(go(at(3, 2), "down"), at(3, 2), "held at the end");
        compare(go(at(0, 2), "up"), at(0, 2), "held at the start");
    }
    function test_nothing_to_stop_on() {
        compare(K.move([], at(-1, -1), "down"), at(-1, -1));
        compare(K.move([{ count: 0 }], at(-1, -1), "tab"), at(-1, -1));
    }
}
