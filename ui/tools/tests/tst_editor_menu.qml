import QtQuick
import QtTest

// The widget settings card over the editor canvas: its controls must own their presses. Same arrangement as
// DesktopEditor.qml + WidgetInspector.qml: the canvas (one TapHandler, one DragHandler, gated by where the pointer is
// and checking the press point) under the widgets, a widget with frame buttons and resize/turn handles, and the
// inspector card above, overlapping the widget, with MouseArea controls as in Components (button, toggle, slider),
// a text field, a dropdown, a scrolling list and empty padding. Driven by Qt's own mouse delivery:
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_editor_menu.qml
// `fixed: false` is the arrangement before the fix (no gate, the canvas may take drags from items): the menu cases
// fail there.
Item {
    id: root
    width: 1000
    height: 700
    property bool fixed: true

    // what happened
    property var selection: []
    property int moves: 0
    property int lassoes: 0
    property int resizes: 0
    property int turns: 0
    property int buttonClicks: 0
    property bool toggled: false
    property real sliderValue: 0
    property string option: "a"
    property bool dropdownOpen: false
    property int settingsOpened: 0

    function overlayAt(p) {
        for (const it of [card, frameActions]) {
            if (!it.visible)
                continue;
            const q = it.mapFromItem(null, p.x, p.y);
            if (q.x >= 0 && q.y >= 0 && q.x <= it.width && q.y <= it.height)
                return true;
        }
        return false;
    }
    function slotAt(p) {
        return slot.contains(slot.mapFromItem(null, p.x, p.y)) ? slot : null;
    }
    readonly property bool pointerOnOverlay: fixed && pointerWatch.hovered && overlayAt(pointerWatch.point.scenePosition)

    // ── the canvas ──
    Item {
        anchors.fill: parent
        HoverHandler {
            id: pointerWatch
        }
        TapHandler {
            enabled: pressed || !root.pointerOnOverlay
            onTapped: point => {
                if (root.fixed && root.overlayAt(point.scenePosition))
                    return;
                root.selection = root.slotAt(point.scenePosition) ? ["widget"] : [];
            }
        }
        DragHandler {
            target: null
            enabled: active || !root.pointerOnOverlay
            grabPermissions: root.fixed ? (PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything) : (PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything)
            property string mode: ""
            onActiveChanged: if (active) {
                const p = centroid.scenePressPosition;
                mode = root.fixed && root.overlayAt(p) ? "none" : root.slotAt(p) ? "move" : "lasso";
                if (mode === "move")
                    root.moves++;
                else if (mode === "lasso")
                    root.lassoes++;
            }
        }
    }

    // ── a widget, with its frame buttons and handles ──
    Item {
        id: slot
        x: 300
        y: 200
        width: 300
        height: 200
        containmentMask: QtObject {
            function contains(point: point): bool {
                if (frameActions.visible && point.x >= frameActions.x && point.x <= frameActions.x + frameActions.width && point.y >= frameActions.y && point.y <= frameActions.y + frameActions.height)
                    return false;
                return point.x >= -6 && point.y >= -30 && point.x <= slot.width + 6 && point.y <= slot.height + 6;
            }
        }
        Row {
            id: frameActions
            anchors.right: parent.right
            y: -30
            Rectangle {
                width: 22
                height: 22
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.settingsOpened++;
                        root.selection = ["widget"];
                    }
                }
            }
        }
        Rectangle {   // resize corner
            width: 14
            height: 14
            x: -11
            y: slot.height - 3
            DragHandler {
                target: null
                grabPermissions: PointerHandler.TakeOverForbidden
                onActiveChanged: if (active) root.resizes++
            }
        }
        Rectangle {   // turn dot, above the widget's left side (clear of the card)
            width: 14
            height: 14
            x: 40
            y: -60
            DragHandler {
                target: null
                grabPermissions: PointerHandler.TakeOverForbidden
                onActiveChanged: if (active) root.turns++
            }
        }
    }

    // ── the settings card, over the widget's right part ──
    Rectangle {
        id: card
        x: 450
        y: 150
        width: 360
        height: 420
        // controls as in Components: MouseAreas
        Rectangle {
            id: button
            x: 20
            y: 20
            width: 100
            height: 30
            MouseArea {
                anchors.fill: parent
                onClicked: root.buttonClicks++
            }
        }
        Rectangle {
            id: toggle
            x: 20
            y: 60
            width: 44
            height: 24
            MouseArea {
                anchors.fill: parent
                onClicked: root.toggled = !root.toggled
            }
        }
        Rectangle {
            id: slider
            x: 20
            y: 100
            width: 200
            height: 20
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPressed: mouse => root.sliderValue = Math.max(0, Math.min(1, mouse.x / width))
                onPositionChanged: mouse => {
                    if (pressed)
                        root.sliderValue = Math.max(0, Math.min(1, mouse.x / width));
                }
            }
        }
        TextInput {
            id: field
            x: 20
            y: 140
            width: 200
            height: 24
            text: "label"
        }
        Rectangle {   // a dropdown: a chip that opens a list of options in place
            id: dropdown
            x: 20
            y: 180
            width: 120
            height: 26
            MouseArea {
                anchors.fill: parent
                onClicked: root.dropdownOpen = !root.dropdownOpen
            }
        }
        Column {
            x: 20
            y: 210
            visible: root.dropdownOpen
            Repeater {
                model: ["a", "b", "c"]
                delegate: Rectangle {
                    required property string modelData
                    width: 120
                    height: 24
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.option = modelData;
                            root.dropdownOpen = false;
                        }
                    }
                }
            }
        }
        Flickable {
            id: list
            x: 160
            y: 200
            width: 180
            height: 120
            contentHeight: 600
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        }
        // empty padding: x 20..340, y 340..400
    }

    TestCase {
        name: "EditorMenu"
        when: windowShown

        function init() {
            root.selection = [];
            root.moves = 0;
            root.lassoes = 0;
            root.resizes = 0;
            root.turns = 0;
            root.buttonClicks = 0;
            root.toggled = false;
            root.sliderValue = 0;
            root.option = "a";
            root.dropdownOpen = false;
            root.settingsOpened = 0;
            list.contentY = 0;
            field.text = "label";
            mouseMove(root, 5, 5);   // the pointer starts on bare canvas
        }
        // a real pointer arrives before it presses: hover there first
        function clickAt(x, y) {
            mouseMove(root, x, y);
            mouseClick(root, x, y);
        }
        function dragFrom(x, y, dx, dy) {
            mouseMove(root, x, y);
            mousePress(root, x, y);
            for (let i = 1; i <= 20; i++)
                mouseMove(root, x + dx * i / 20, y + dy * i / 20);
            mouseRelease(root, x + dx, y + dy);
        }
        function noCanvas() {
            compare(root.selection.length, 0, "the widget under the menu must not be selected");
            compare(root.moves, 0, "nothing moves");
            compare(root.lassoes, 0, "no lasso");
        }

        function test_01_button_does_not_select_widget() {
            clickAt(card.x + 70, card.y + 35);
            compare(root.buttonClicks, 1);
            noCanvas();
        }
        function test_02_toggle_does_not_select_widget() {
            clickAt(card.x + 40, card.y + 72);
            compare(root.toggled, true);
            noCanvas();
        }
        function test_03_slider_drag_does_not_move_widget() {
            dragFrom(card.x + 30, card.y + 110, 150, 6);
            verify(root.sliderValue > 0.7, "the slider follows: " + root.sliderValue);
            noCanvas();
        }
        function test_04_text_field_edits_without_selecting() {
            clickAt(card.x + 100, card.y + 152);
            verify(field.activeFocus, "the field takes focus");
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_X);
            compare(field.text, "labelx");
            noCanvas();
        }
        function test_05_dropdown_option_without_widget_action() {
            clickAt(card.x + 60, card.y + 193);
            compare(root.dropdownOpen, true);
            clickAt(card.x + 60, card.y + 210 + 24 + 12);   // option "b"
            compare(root.option, "b");
            noCanvas();
        }
        function test_06_padding_does_not_select_widget() {
            // a gap between controls that lies over the widget (the card covers the widget's right part)
            const gx = card.x + 120, gy = card.y + 90;
            verify(root.slotAt(Qt.point(gx, gy)) !== null, "the test point is over the widget");
            clickAt(gx, gy);
            noCanvas();
            dragFrom(gx, gy, -120, 0);   // nor does a drag on it
            noCanvas();
            clickAt(card.x + 200, card.y + 380);   // the card's bottom padding
            noCanvas();
        }
        function test_07_list_scrolls_without_canvas() {
            mouseMove(root, card.x + 250, card.y + 260);
            mouseWheel(root, card.x + 250, card.y + 260, 0, -240);
            tryVerify(() => list.contentY > 0, 2000, "the list scrolls: " + list.contentY);
            noCanvas();
        }
        function test_08_click_outside_menu_follows_canvas() {
            clickAt(330, 300);   // on the widget, outside the card: selects it
            compare(root.selection.length, 1);
            clickAt(100, 600);   // bare desktop: clears (the inspector closes with the selection)
            compare(root.selection.length, 0);
        }
        function test_09_frame_settings_button_only_opens_settings() {
            clickAt(slot.x + slot.width - 11, slot.y - 19);
            compare(root.settingsOpened, 1);
            compare(root.selection.length, 1, "selected by the button, not cleared by the canvas");
            compare(root.moves, 0);
        }
        function test_10_widget_select_and_drag_still_work() {
            clickAt(330, 300);
            compare(root.selection.length, 1);
            dragFrom(330, 300, 60, 40);
            compare(root.moves, 1);
            compare(root.lassoes, 0);
        }
        function test_11_lasso_on_empty_space() {
            dragFrom(50, 500, 150, 100);
            compare(root.lassoes, 1);
            compare(root.moves, 0);
        }
        function test_12_resize_and_turn_still_work() {
            dragFrom(slot.x - 4, slot.y + slot.height + 4, -30, 20);
            compare(root.resizes, 1);
            dragFrom(slot.x + 47, slot.y - 53, 30, 0);
            compare(root.turns, 1);
            compare(root.moves, 0, "the canvas takes neither");
        }
    }
}
