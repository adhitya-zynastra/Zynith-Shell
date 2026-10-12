import QtQuick
import QtTest

// Who owns a drag in the desktop editor: the same handler arrangement as DesktopEditor.qml (the desktop's
// TapHandler + lasso DragHandler under the widgets; a widget slot with its containment mask, name tag, frame
// buttons, a resize handle and the mover), driven by Qt's own mouse delivery. Run offscreen:
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_editor_drag.qml
Item {
    id: root
    width: 800
    height: 600

    property int lassoActivations: 0
    property int moverActivations: 0
    property int resizeActivations: 0
    property int buttonClicks: 0
    property real movedX: 0
    property real movedY: 0

    Item {
        id: backdrop
        anchors.fill: parent
        TapHandler {}
        DragHandler {
            id: lasso
            target: null
            onActiveChanged: if (active) root.lassoActivations++
        }
    }

    Item {
        id: slots
        anchors.fill: parent
        Item {
            id: slot
            x: 300
            y: 300
            width: 100
            height: 60
            readonly property real reach: 6
            containmentMask: QtObject {
                function contains(point: point): bool {
                    if (frameActions.visible && point.x >= frameActions.x && point.x <= frameActions.x + frameActions.width && point.y >= frameActions.y && point.y <= frameActions.y + frameActions.height)
                        return false;
                    const inBody = point.x >= -slot.reach && point.y >= -slot.reach && point.x <= slot.width + slot.reach && point.y <= slot.height + slot.reach;
                    const inTag = point.x >= tag.x && point.x <= tag.x + tag.width && point.y >= tag.y && point.y <= tag.y + tag.height;
                    return inBody || inTag;
                }
            }
            Rectangle {
                id: tag
                x: -4
                y: -30
                width: 60
                height: 22
            }
            Row {
                id: frameActions
                anchors.right: parent.right
                anchors.rightMargin: -4
                y: -30
                Rectangle {
                    width: 22
                    height: 22
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.buttonClicks++
                    }
                }
            }
            TapHandler {}
            DragHandler {
                id: mover
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                onActiveChanged: if (active) root.moverActivations++
                onCentroidChanged: if (active) {
                    root.movedX = centroid.scenePosition.x - centroid.scenePressPosition.x;
                    root.movedY = centroid.scenePosition.y - centroid.scenePressPosition.y;
                }
            }
            Rectangle {
                id: handle
                width: 14
                height: 14
                x: slot.width - 7 + 4
                y: slot.height - 7 + 4
                DragHandler {
                    target: null
                    grabPermissions: PointerHandler.TakeOverForbidden
                    onActiveChanged: if (active) root.resizeActivations++
                }
            }
        }
    }

    TestCase {
        name: "EditorDrag"
        when: windowShown

        function init() {
            root.lassoActivations = 0;
            root.moverActivations = 0;
            root.resizeActivations = 0;
            root.buttonClicks = 0;
            root.movedX = 0;
            root.movedY = 0;
        }
        function drag(x, y, dx, dy) {
            mousePress(root, x, y);
            const steps = 20;
            for (let i = 1; i <= steps; i++)
                mouseMove(root, x + dx * i / steps, y + dy * i / steps);
            mouseRelease(root, x + dx, y + dy);
        }

        function test_body_moves_widget() {
            drag(350, 330, 40, -25);
            compare(root.moverActivations, 1, "mover");
            compare(root.lassoActivations, 0, "lasso must not start");
            fuzzyCompare(root.movedX, 40, 0.5);
            fuzzyCompare(root.movedY, -25, 0.5);
        }
        function test_tag_moves_widget() {
            drag(300 - 4 + 20, 300 - 30 + 11, 60, 30);   // on the name tag, above the box
            compare(root.moverActivations, 1, "mover");
            compare(root.lassoActivations, 0, "lasso must not start");
            fuzzyCompare(root.movedX, 60, 0.5);
        }
        function test_frame_line_moves_widget() {
            drag(300 - 3, 330, -30, 0);   // on the frame drawn 4 px outside the box
            compare(root.moverActivations, 1, "mover");
            compare(root.lassoActivations, 0, "lasso must not start");
        }
        function test_empty_desktop_lassos() {
            drag(100, 100, 120, 80);
            compare(root.lassoActivations, 1, "lasso");
            compare(root.moverActivations, 0, "mover must not start");
        }
        function test_button_clicks_without_moving() {
            mouseClick(root, 400 + 4 - 11, 300 - 30 + 11);
            compare(root.buttonClicks, 1, "button");
            compare(root.moverActivations, 0);
            compare(root.lassoActivations, 0);
        }
        function test_small_click_does_not_drag() {
            mousePress(root, 350, 330);
            mouseMove(root, 352, 331);
            mouseRelease(root, 352, 331);
            compare(root.moverActivations, 0, "a click is not a drag");
        }
        function test_resize_handle_is_not_taken_by_mover() {
            drag(300 + 100 + 4, 300 + 60 + 4, 30, 20);
            compare(root.resizeActivations, 1, "resize");
            compare(root.moverActivations, 0, "mover must not take the resize");
        }
    }
}
