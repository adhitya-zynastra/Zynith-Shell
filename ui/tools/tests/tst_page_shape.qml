import QtQuick
import QtTest
import "../../Components"

// Components/PageShape.qml: the Control Panel's sheet and its tab as one outline. The path is the whole
// contract: a closed rounded sheet without a tab; with one, a single path that rises into the tab through two
// concave fillets; and the radii give way (never negative, never NaN) when the tab reaches a corner.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_page_shape.qml
Item {
    width: 600
    height: 400

    PageShape {
        id: shape
        anchors.fill: parent
        sheetX: 12
        sheetY: 60
        sheetWidth: 576
        sheetHeight: 300
        radius: 10
        tabTop: 20
        tabRadius: 10
        fillet: 10
    }

    TestCase {
        name: "PageShape"

        function numbers(path) {
            return path.match(/-?\d+(\.\d+)?/g).map(Number);
        }
        function arcs(path) {
            return (path.match(/ A /g) || []).length;
        }

        function test_no_tab_is_a_closed_rounded_sheet() {
            shape.tabLeft = 0;
            shape.tabRight = 0;
            const p = shape.outline;
            verify(p.startsWith("M "));
            verify(p.endsWith(" Z"));
            compare(arcs(p), 4, "four rounded corners");
            verify(p.indexOf("20.00") < 0, "nothing reaches the tab's top");
        }

        function test_tab_rises_through_two_fillets() {
            shape.tabLeft = 200;
            shape.tabRight = 320;
            const p = shape.outline;
            // 4 sheet corners + 2 tab corners + 2 concave fillets, one path
            compare(arcs(p), 8);
            compare((p.match(/M /g) || []).length, 1, "one path, no seam");
            verify(p.indexOf(" L 200.00 30.00") >= 0, "the tab's left side runs up to its rounded top");
            verify(p.indexOf("A 10.00 10.00 0 0 0 200.00 50.00") >= 0, "the left fillet is concave");
            verify(p.indexOf("A 10.00 10.00 0 0 0 330.00 60.00") >= 0, "the right fillet is concave");
        }

        function test_radii_give_way_at_the_corner() {
            // the tab starts right at the sheet's left edge: no room for a fillet or the corner
            shape.tabLeft = 12;
            shape.tabRight = 120;
            const p = shape.outline;
            const n = numbers(p);
            verify(n.every(v => isFinite(v)), "no NaN or infinity");
            verify(p.indexOf("A -") < 0, "no negative radius");
            verify(p.startsWith("M 12.00 60.00"), "the corner under the tab is square");
        }

        function test_narrow_tab_never_inverts() {
            shape.tabLeft = 300;
            shape.tabRight = 306;   // narrower than two tab radii
            const n = numbers(shape.outline);
            verify(n.every(v => isFinite(v)));
            verify(shape.outline.indexOf("A -") < 0);
        }

        function test_follows_moving_edges() {
            shape.tabLeft = 100;
            shape.tabRight = 200;
            const a = shape.outline;
            shape.tabLeft = 140;   // the leading edge on its way: the path changes with it
            verify(shape.outline !== a);
            verify(shape.outline.indexOf(" L 140.00 30.00") >= 0);
        }
    }
}
