import QtQuick
import QtTest

// Who owns a tap or a drag in the desktop editor. The same arrangement as DesktopEditor.qml: one TapHandler and
// one DragHandler own the canvas and decide at the press, through slotAt (a slot's containment mask: body, frame,
// name tag, not its buttons), whether it moves a widget or draws the lasso; the frame's buttons and the resize
// handle (TakeOverForbidden) sit above and keep their own presses. Driven by Qt's own mouse delivery:
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_editor_drag.qml
Item {
    id: root
    width: 800
    height: 600

    property int lassoes: 0
    property int moves: 0
    property int resizes: 0
    property int buttonClicks: 0
    property string selected: ""
    property real movedX: 0
    property real movedY: 0

    function slotAt(scenePoint) {
        const s = slot;
        return s.contains(s.mapFromItem(null, scenePoint.x, scenePoint.y)) ? s : null;
    }

    Item {
        id: backdrop
        anchors.fill: parent
        TapHandler {
            onTapped: point => root.selected = root.slotAt(point.scenePosition) ? "widget" : ""
        }
        DragHandler {
            id: gesture
            target: null
            property string mode: ""
            onActiveChanged: {
                if (active) {
                    mode = root.slotAt(centroid.scenePressPosition) ? "move" : "lasso";
                    if (mode === "move")
                        root.moves++;
                    else
                        root.lassoes++;
                }
            }
            onCentroidChanged: if (active && mode === "move") {
                root.movedX = centroid.scenePosition.x - centroid.scenePressPosition.x;
                root.movedY = centroid.scenePosition.y - centroid.scenePressPosition.y;
            }
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
            HoverHandler {}
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
            Rectangle {
                width: 14
                height: 14
                x: slot.width - 7 + 4
                y: slot.height - 7 + 4
                DragHandler {
                    target: null
                    grabPermissions: PointerHandler.TakeOverForbidden
                    onActiveChanged: if (active) root.resizes++
                }
            }
        }
    }

    TestCase {
        name: "EditorDrag"
        when: windowShown

        function init() {
            root.lassoes = 0;
            root.moves = 0;
            root.resizes = 0;
            root.buttonClicks = 0;
            root.selected = "";
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
            compare(root.moves, 1);
            compare(root.lassoes, 0, "no lasso");
            fuzzyCompare(root.movedX, 40, 0.5);
            fuzzyCompare(root.movedY, -25, 0.5);
        }
        function test_tag_moves_widget() {
            drag(316, 281, 60, 30);
            compare(root.moves, 1);
            compare(root.lassoes, 0, "no lasso");
            fuzzyCompare(root.movedX, 60, 0.5);
        }
        function test_frame_line_moves_widget() {
            drag(297, 330, -30, 0);
            compare(root.moves, 1);
            compare(root.lassoes, 0, "no lasso");
        }
        function test_empty_desktop_lassoes() {
            drag(100, 100, 120, 80);
            compare(root.lassoes, 1);
            compare(root.moves, 0);
        }
        function test_button_clicks_without_moving() {
            mouseClick(root, 393, 281);
            compare(root.buttonClicks, 1);
            compare(root.moves, 0);
            compare(root.lassoes, 0);
        }
        function test_click_selects_and_does_not_drag() {
            mousePress(root, 350, 330);
            mouseMove(root, 352, 331);
            mouseRelease(root, 352, 331);
            compare(root.moves, 0, "a click is not a drag");
            compare(root.selected, "widget", "a click on a widget selects it (not cleared by the desktop)");
        }
        function test_click_on_desktop_clears() {
            root.selected = "widget";
            mouseClick(root, 100, 100);
            compare(root.selected, "");
        }
        function test_resize_handle_keeps_its_drag() {
            drag(404, 364, 30, 20);
            compare(root.resizes, 1);
            compare(root.moves, 0, "the canvas must not take the resize");
            compare(root.lassoes, 0);
        }
    }
}
