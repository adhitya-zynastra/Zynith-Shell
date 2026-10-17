import QtQuick
import QtTest
import qs.Services
import "../../Components"

// Components/MaterialSettle: a moving surface has no compositor backdrop and a denser fill; at rest the backdrop is
// back and the fill thins; leaving, it condenses (backdrop still on) before it lets go.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_material_settle.qml
Item {
    id: root
    MaterialSettle {
        id: settle
    }
    property int leaves: 0

    TestCase {
        name: "MaterialSettle"
        when: windowShown

        function init() {
            Material.blur = true;
            settle.moving = false;
            settle.cancel();
            // a condensed surface at rest (it would be leaving): back to rest for the next case
            settle.settle();
            tryCompare(settle, "frost", 0);
            root.leaves = 0;
        }

        function test_moving_has_no_backdrop_and_a_dense_fill_at_once() {
            settle.moving = true;
            verify(!settle.settled);
            compare(settle.frost, 1, "dense from the first frame: the backdrop is already gone");
            compare(settle.alpha(0.44), 0.72);
        }
        function test_rest_brings_the_backdrop_back_and_the_fill_thins() {
            settle.moving = true;
            settle.moving = false;
            verify(settle.settled, "the backdrop at once");
            tryCompare(settle, "frost", 0);
            compare(settle.alpha(0.44), 0.44);
        }
        function test_condense_keeps_the_backdrop_until_dense_then_leaves() {
            settle.condense(() => root.leaves++);
            verify(settle.settled, "condensing keeps the backdrop");
            tryCompare(root, "leaves", 1);
            compare(settle.frost, 1);
        }
        function test_a_condense_taken_back_returns_to_rest() {
            settle.condense(() => root.leaves++);
            settle.cancel();
            verify(!settle.condensing);
            tryCompare(settle, "frost", 0);
            wait(20);
            compare(root.leaves, 0, "the leaving it preceded never happens");
        }
        function test_without_a_backdrop_nothing_changes() {
            Material.blur = false;
            settle.moving = true;
            compare(settle.alpha(0.44), 0.44, "no backdrop to stand in for");
            settle.moving = false;
            settle.condense(() => root.leaves++);
            compare(root.leaves, 1, "nothing to condense: leaves at once");
        }
        function test_the_dense_fill_never_thins_a_denser_rest() {
            settle.moving = true;
            compare(settle.alpha(0.9), 0.9);
        }
    }
}
