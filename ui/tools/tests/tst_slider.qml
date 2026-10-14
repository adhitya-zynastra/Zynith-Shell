import QtQuick
import QtTest
import "../../Components"

// Components/Slider.qml: it changes only when pressed on (or stepped with the keys while focused); the wheel is
// the page's. The old slider took the wheel and moved by 5 % a notch, so scrolling a Settings page past a slider
// changed it and the page did not scroll there: test_scrolling_over_a_slider_scrolls_the_page fails against it.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_slider.qml
Item {
    id: root
    width: 400
    height: 300

    Flickable {
        id: page
        anchors.fill: parent
        contentHeight: 1200
        boundsBehavior: Flickable.StopAtBounds
        Slider {
            id: slider
            x: 50
            y: 100
            width: 300
            value: 0.5
        }
        Slider {
            id: level
            x: 50
            y: 200
            width: 300
            value: 0.5
            wheelAdjusts: true
        }
    }

    SignalSpy {
        id: moved
        target: slider
        signalName: "moved"
    }
    SignalSpy {
        id: committed
        target: slider
        signalName: "committed"
    }

    TestCase {
        name: "Slider"
        when: windowShown

        function init() {
            page.contentY = 0;
            slider.value = 0.5;
            slider.follow();
            level.value = 0.5;
            level.follow();
            moved.clear();
            committed.clear();
            waitForRendering(root);
        }

        function test_hover_changes_nothing() {
            mouseMove(slider, 30, 11);
            mouseMove(slider, 250, 11);
            compare(moved.count, 0);
            compare(committed.count, 0);
            compare(slider.displayed, 0.5);
        }

        function test_scrolling_over_a_slider_scrolls_the_page() {
            mouseMove(slider, 60, 11);
            mouseWheel(slider, 60, 11, 0, -120);
            mouseWheel(slider, 60, 11, 0, -120);
            compare(moved.count, 0, "the wheel did not move it");
            compare(committed.count, 0);
            compare(slider.displayed, 0.5);
            tryVerify(() => page.contentY > 0, 1000, "the page scrolled under the pointer instead");
        }

        function test_scrolling_over_the_track_ends_changes_nothing() {
            for (const x of [1, 150, 299]) {
                mouseWheel(slider, x, 11, 0, 120);
                mouseWheel(slider, x, 11, 0, -120);
            }
            compare(moved.count, 0);
            compare(slider.displayed, 0.5);
        }

        function test_a_click_commits_where_it_lands() {
            mouseClick(slider, 75, 11);
            compare(committed.count, 1);
            fuzzyCompare(committed.signalArguments[0][0], 0.25, 0.01);
            fuzzyCompare(slider.displayed, 0.25, 0.01, "it shows what was chosen until the value catches up");
        }

        function test_a_drag_previews_then_commits_once_on_release() {
            mousePress(slider, 30, 11);
            for (let x = 30; x <= 270; x += 30)
                mouseMove(slider, x, 11);
            compare(committed.count, 0, "nothing is committed while dragging");
            verify(moved.count >= 8);
            mouseRelease(slider, 270, 11);
            compare(committed.count, 1);
            fuzzyCompare(committed.signalArguments[0][0], 0.9, 0.01);
        }

        function test_a_drag_keeps_the_pointer_when_it_drifts_vertically() {
            mousePress(slider, 30, 11);
            mouseMove(slider, 60, 40);
            mouseMove(slider, 120, 90);
            mouseMove(slider, 150, 140);
            mouseRelease(slider, 150, 140);
            compare(page.contentY, 0, "the page did not take the drag over");
            compare(committed.count, 1);
            fuzzyCompare(committed.signalArguments[0][0], 0.5, 0.01);
        }

        function test_scrolling_right_after_a_drag_changes_nothing() {
            mousePress(slider, 30, 11);
            mouseMove(slider, 90, 11);
            mouseRelease(slider, 90, 11);
            const commits = committed.count;
            moved.clear();
            mouseWheel(slider, 90, 11, 0, -120);
            compare(moved.count, 0, "no grab left behind");
            compare(committed.count, commits);
        }

        function test_hold_then_follow_the_value() {
            mouseClick(slider, 240, 11);
            fuzzyCompare(slider.displayed, 0.8, 0.01);
            slider.value = 0.8;
            verify(!slider.holding, "the value caught up: back to following it");
            slider.value = 0.3;
            fuzzyCompare(slider.displayed, 0.3, 0.01);
        }

        function test_keyboard_steps_it_when_focused() {
            slider.step = 0.1;
            slider.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(committed.count, 1);
            fuzzyCompare(committed.signalArguments[0][0], 0.6, 0.001);
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Left);
            fuzzyCompare(committed.signalArguments[2][0], 0.4, 0.001);
            keyClick(Qt.Key_End);
            fuzzyCompare(committed.signalArguments[3][0], 1, 0.001);
            slider.step = 0.01;
        }

        function test_a_level_slider_that_asks_for_the_wheel_gets_it() {
            mouseWheel(level, 100, 11, 0, 120);
            fuzzyCompare(level.displayed, 0.55, 0.001);
        }
    }
}
