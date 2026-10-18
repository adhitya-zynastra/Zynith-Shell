import QtQuick
import QtTest
import "../../Common/Emerge.js" as E

// Common/Emerge.js: a panel emerging from its icon.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_emerge.qml
TestCase {
    name: "Emerge"

    function test_the_spring_settles_without_overshoot() {
        compare(E.spring(0), 0);
        compare(E.spring(1), 1);
        let last = 0;
        for (let i = 1; i <= 100; i++) {
            const v = E.spring(i / 100);
            verify(v >= last - 1e-9, "never goes back");
            verify(v <= 1 + 1e-9, "never past 1");
            last = v;
        }
    }
    function test_a_left_bar_capsule_sits_on_the_joint_at_the_icon() {
        const card = { x: 40, y: 600, w: 380, h: 500 };
        const s = E.seed("left", { x: 20, y: 900 }, 34, card);
        compare(s.x, 40, "on the bar's edge");
        compare([s.y, s.h], [883, 34], "centred on the icon");
        verify(s.w < 40);
    }
    function test_the_capsule_stays_inside_the_card_span() {
        const card = { x: 100, y: 40, w: 300, h: 400 };
        compare(E.seed("top", { x: 90, y: 20 }, 34, card).x, 100);
        compare(E.seed("top", { x: 2000, y: 20 }, 34, card).x, 366);
    }
    function test_frames_run_from_capsule_to_card_and_back_the_same_way() {
        const from = { x: 40, y: 883, w: 26, h: 34 }, to = { x: 40, y: 600, w: 380, h: 500 };
        const a = E.frame(0, from, to, 16, "left"), b = E.frame(1, from, to, 16, "left");
        compare([a.x, a.y, a.w, a.h], [40, 883, 26, 34]);
        compare([b.x, b.y, b.w, b.h, b.radius, b.content], [40, 600, 380, 500, 16, 1]);
        compare(a.radius, 13, "a capsule's radius");
        compare(a.content, 0);
        // the joint side never moves on an attached panel (left edge: x stays the bar's edge)
        for (let p = 0; p <= 1; p += 0.1)
            compare(E.frame(p, from, to, 16, "left").x, 40);
    }
    function test_along_the_bar_leads_the_depth() {
        const from = { x: 40, y: 883, w: 26, h: 34 }, to = { x: 40, y: 600, w: 380, h: 500 };
        const f = E.frame(0.3, from, to, 16, "left");
        verify((f.h - 34) / (500 - 34) > (f.w - 26) / (380 - 26), "longer along the bar than deep, mid-way");
    }
    function test_the_page_waits_for_the_shape() {
        const from = { x: 0, y: 0, w: 30, h: 30 }, to = { x: 0, y: 0, w: 300, h: 300 };
        compare(E.frame(0.4, from, to, 16, "top").content, 0);
        verify(E.frame(0.7, from, to, 16, "top").content > 0.4);
    }
}
