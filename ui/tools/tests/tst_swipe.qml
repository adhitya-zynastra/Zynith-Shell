import QtQuick
import QtTest
import "../../Components"

// Components/SwipeArea.qml: a sideways swipe turns the Control Panel's page once per gesture, even over a control
// that takes the wheel itself, and that control still gets the event. A first version sat on the panel as a plain
// WheelHandler: the page's children took every wheel event before it, so a swipe never reached it.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_swipe.qml
Item {
    id: root
    width: 400
    height: 300

    property int steps: 0
    property int lastBy: 0
    property int underneath: 0

    // something under the pointer that takes the wheel (a list, a slider that scrolls)
    MouseArea {
        anchors.fill: parent
        onWheel: wheel => {
            root.underneath++;
            wheel.accepted = true;
        }
    }
    SwipeArea {
        id: swipe
        anchors.fill: parent
        rest: 120
        onStepped: by => {
            root.steps++;
            root.lastBy = by;
        }
    }

    TestCase {
        name: "Swipe"
        when: windowShown

        function init() {
            wait(200);
            root.steps = 0;
            root.lastBy = 0;
            root.underneath = 0;
        }
        function swipeBy(dx: int, notches: int): void {
            for (let i = 0; i < notches; i++)
                mouseWheel(root, 200, 150, dx, 0);
        }

        function test_a_swipe_left_turns_to_the_next_page_over_a_wheel_taker() {
            swipeBy(-120, 3);
            compare(root.steps, 1);
            compare(root.lastBy, 1);
            compare(root.underneath, 3, "the control under the pointer still gets every event");
        }
        function test_a_swipe_right_goes_back() {
            swipeBy(120, 3);
            compare(root.steps, 1);
            compare(root.lastBy, -1);
        }
        function test_one_step_per_gesture_until_the_fingers_rest() {
            swipeBy(-120, 10);
            compare(root.steps, 1, "a long swipe is still one page");
            wait(200);
            swipeBy(-120, 3);
            compare(root.steps, 2, "a new gesture after a rest steps again");
        }
        function test_vertical_scrolling_is_not_a_swipe() {
            for (let i = 0; i < 6; i++)
                mouseWheel(root, 200, 150, 30, -120);
            compare(root.steps, 0);
            compare(root.underneath, 6);
        }
        function test_a_small_nudge_is_not_a_swipe() {
            swipeBy(-120, 1);
            compare(root.steps, 0);
        }
        function test_disabled_does_nothing() {
            swipe.enabled = false;
            swipeBy(-120, 3);
            swipe.enabled = true;
            compare(root.steps, 0);
        }
    }
}
