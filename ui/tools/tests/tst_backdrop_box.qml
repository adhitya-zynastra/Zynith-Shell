import QtQuick
import QtTest
import "../../Components"

// Components/BackdropBox: where a surface's compositor backdrop goes. At rest the surface's rectangle; in motion the
// overlap of this frame's and the last one's, so it lies inside what is drawn whichever frame the compositor pairs it with.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_backdrop_box.qml
Item {
    id: root
    width: 400
    height: 400
    BackdropBox {
        id: box
    }
    function r(x, y, w, h) {
        return { x: x, y: y, w: w, h: h };
    }
    function inside(b, a) {
        return b.x >= a.x - 1e-6 && b.y >= a.y - 1e-6 && b.x + b.width <= a.x + a.w + 1e-6 && b.y + b.height <= a.y + a.h + 1e-6;
    }

    TestCase {
        name: "BackdropBox"
        when: windowShown

        function init() {
            box.moving = false;
            box.rect = root.r(0, 0, 0, 0);
        }
        function test_at_rest_it_is_the_rectangle() {
            box.rect = root.r(10, 20, 300, 200);
            compare([box.x, box.y, box.width, box.height], [10, 20, 300, 200]);
        }
        function test_growing_it_stays_inside_both_frames() {
            box.rect = root.r(40, 300, 30, 40);
            box.moving = true;
            let last = box.rect;
            for (let i = 1; i <= 20; i++) {
                wait(17);
                const now = root.r(40, 300 - i * 12, 30 + i * 18, 40 + i * 12);
                box.rect = now;
                verify(root.inside(box, now), "inside this frame " + i);
                verify(root.inside(box, last) || box.width === 0, "inside the last frame " + i);
                last = now;
            }
        }
        function test_shrinking_it_stays_inside_both_frames() {
            box.rect = root.r(40, 60, 380, 300);
            box.moving = true;
            let last = box.rect;
            for (let i = 1; i <= 15; i++) {
                wait(17);
                const now = root.r(40, 60 + i * 10, 380 - i * 20, 300 - i * 16);
                box.rect = now;
                verify(root.inside(box, now), "inside this frame " + i);
                verify(root.inside(box, last), "inside the last frame " + i);
                last = now;
            }
        }
        function test_coming_to_rest_it_is_the_rectangle_again() {
            box.rect = root.r(0, 0, 100, 100);
            box.moving = true;
            wait(17);
            box.rect = root.r(0, 0, 200, 150);
            box.moving = false;
            compare([box.width, box.height], [200, 150]);
        }
    }
}
