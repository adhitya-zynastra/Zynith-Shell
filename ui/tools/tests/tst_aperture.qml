import QtQuick
import QtTest
import "../../Components"

// Components/ApertureDial.qml: where on its ring a point falls (turning a reading by hand), and the iris following
// lit and awake.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_aperture.qml
Item {
    width: 200
    height: 200

    ApertureDial {
        id: dial
        size: 100
        reading: ({ value: 0.5, segments: 0 })
    }

    TestCase {
        name: "Aperture"
        when: windowShown

        // a point on a circle around the centre, at an angle in degrees (0 = right, 90 = down, as on screen)
        function at(deg: real): var {
            const r = 40, a = deg * Math.PI / 180;
            return [50 + r * Math.cos(a), 50 + r * Math.sin(a)];
        }
        function valueAtAngle(deg: real): real {
            const p = at(deg);
            return dial.valueAt(p[0], p[1]);
        }

        function test_the_ring_runs_clockwise_from_bottom_left_to_bottom_right() {
            fuzzyCompare(valueAtAngle(135), 0, 0.001, "start: bottom left");
            fuzzyCompare(valueAtAngle(180), 45 / 270, 0.001, "left");
            fuzzyCompare(valueAtAngle(270), 0.5, 0.001, "top is the middle");
            fuzzyCompare(valueAtAngle(0), 225 / 270, 0.001, "right");
            fuzzyCompare(valueAtAngle(45), 1, 0.001, "end: bottom right");
        }
        function test_the_gap_at_the_bottom_snaps_to_the_nearer_end() {
            compare(valueAtAngle(100), 0, "just right of the start: stays at the start");
            compare(valueAtAngle(80), 1, "just left of the end: stays at the end");
            compare(valueAtAngle(91), 0);
            compare(valueAtAngle(89), 1);
        }
        function test_values_stay_within_the_ring() {
            for (let d = 0; d < 360; d += 7) {
                const v = valueAtAngle(d);
                verify(v >= 0 && v <= 1, d + "° → " + v);
            }
        }
        function test_a_lit_dial_waits_to_open_until_awake() {
            dial.awake = false;
            dial.lit = true;
            wait(600);
            compare(dial.open, 0, "shut while the panel arrives");
            dial.awake = true;
            tryCompare(dial, "open", 1, 2000);
            dial.lit = false;
            tryCompare(dial, "open", 0, 2000);
        }
    }
}
