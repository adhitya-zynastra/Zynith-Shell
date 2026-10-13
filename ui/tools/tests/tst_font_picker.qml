import QtQuick
import QtTest
import "../../Components"

// Components/FontPicker.qml, the real file, over the editor canvas's arrangement (as tst_editor_menu.qml): the
// canvas TapHandler + DragHandler gated by where the pointer is, a widget under the picker's card. The list must
// come from the installed families, filter, take keys, keep an uninstalled value, and own its presses.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import tools/tests/stubs -input tools/tests/tst_font_picker.qml
Item {
    id: root
    width: 1000
    height: 800

    property var selection: []
    property int moves: 0
    property int lassoes: 0
    property var picks: []

    function overlayAt(p) {
        const q = card.mapFromItem(null, p.x, p.y);
        return q.x >= 0 && q.y >= 0 && q.x <= card.width && q.y <= card.height;
    }
    function slotAt(p) {
        const q = slot.mapFromItem(null, p.x, p.y);
        return q.x >= 0 && q.y >= 0 && q.x <= slot.width && q.y <= slot.height ? slot : null;
    }
    readonly property bool pointerOnOverlay: pointerWatch.hovered && overlayAt(pointerWatch.point.scenePosition)

    Item {
        anchors.fill: parent
        HoverHandler {
            id: pointerWatch
        }
        TapHandler {
            enabled: pressed || !root.pointerOnOverlay
            onTapped: point => {
                if (root.overlayAt(point.scenePosition))
                    return;
                root.selection = root.slotAt(point.scenePosition) ? ["widget"] : [];
            }
        }
        DragHandler {
            target: null
            enabled: active || !root.pointerOnOverlay
            grabPermissions: PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything
            onActiveChanged: if (active) {
                const p = centroid.scenePressPosition;
                if (root.overlayAt(p))
                    return;
                if (root.slotAt(p))
                    root.moves++;
                else
                    root.lassoes++;
            }
        }
    }

    // a widget the whole card lies over
    Item {
        id: slot
        x: 100
        y: 50
        width: 800
        height: 700
    }

    // the settings card, sized by what it holds (it grows as the picker unfolds)
    Rectangle {
        id: card
        x: 300
        y: 100
        width: 400
        height: picker.height + 40
        FontPicker {
            id: picker
            x: 20
            y: 20
            width: 360
            fallback: "The interface font"
            onPicked: family => {
                root.picks = root.picks.concat([family]);
                value = family;
            }
        }
    }

    TestCase {
        name: "FontPicker"
        when: windowShown

        property var installed: Qt.fontFamilies()

        function init() {
            picker.fold();
            picker.value = "";
            root.selection = [];
            root.moves = 0;
            root.lassoes = 0;
            root.picks = [];
            mouseMove(root, 5, 5);
        }
        function clickAt(x, y) {
            mouseMove(root, x, y);
            mouseClick(root, x, y);
        }
        function fieldCentre() {
            return picker.mapToItem(root, picker.width / 2, 17);
        }
        function openPicker() {
            const p = fieldCentre();
            clickAt(p.x, p.y);
            tryVerify(() => picker.open, 1000, "the field opens the list");
            // the columns lay out on the next frame (as on screen): wait for it before aiming at the list
            tryVerify(() => card.height > 200, 1000, "the card grows with the list");
            waitForRendering(card);
        }
        function noCanvas() {
            compare(root.selection.length, 0, "the widget under the card must not be selected");
            compare(root.moves, 0, "nothing moves");
            compare(root.lassoes, 0, "no lasso");
        }

        function test_01_lists_installed_families() {
            verify(installed.length > 0, "the machine has fonts");
            openPicker();
            compare(picker.families.length, installed.length, "every installed family, none invented");
            compare(picker.shown.length, installed.length);
            noCanvas();
        }
        function test_02_search_filters() {
            openPicker();
            const probe = installed[installed.length - 1];
            const q = probe.substring(0, Math.min(4, probe.length)).toLowerCase();
            keyClick(q[0]);
            for (let i = 1; i < q.length; i++)
                keyClick(q[i]);
            compare(picker.query, q, "typing goes to the search field");
            verify(picker.shown.length > 0 && picker.shown.length <= installed.length);
            verify(picker.shown.every(f => f.toLowerCase().includes(q)), "only matches");
            verify(picker.shown.includes(probe));
            noCanvas();
        }
        function test_03_keyboard_selects() {
            openPicker();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(root.picks.length, 1);
            compare(root.picks[0], picker.shown[1] ?? picker.families[1], "the second family");
            compare(picker.open, false, "Enter folds");
        }
        function test_04_escape_folds_without_picking() {
            openPicker();
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Escape);
            compare(picker.open, false);
            compare(root.picks.length, 0);
        }
        function test_05_click_on_entry_picks_without_canvas() {
            openPicker();
            // the first entry: below the search field and the default chip
            const lv = picker.children[1];
            const firstRowY = lv.mapToItem(root, 0, 0).y + 4 + 30 + 4 + 26 + 4 + 17;
            const p = picker.mapToItem(root, picker.width / 2, 0);
            clickAt(p.x, firstRowY);
            compare(root.picks.length, 1, "one pick");
            verify(installed.includes(root.picks[0]), "an installed family: " + root.picks[0]);
            noCanvas();
        }
        function test_06_scroll_list_without_canvas() {
            if (installed.length < 12)
                skip("too few fonts to scroll");
            openPicker();
            const lv = picker.children[1];
            const p = lv.mapToItem(root, lv.width / 2, lv.height - 60);
            mouseMove(root, p.x, p.y);
            mouseWheel(root, p.x, p.y, 0, -360);
            const view = lv.children[0].children[2];
            tryVerify(() => view.contentY > 0, 2000, "the list scrolls: " + view.contentY);
            // the list moved, the canvas did nothing
            noCanvas();
            // a drag on the list flicks it, not the widget
            mousePress(root, p.x, p.y);
            for (let i = 1; i <= 10; i++)
                mouseMove(root, p.x, p.y - 8 * i);
            mouseRelease(root, p.x, p.y - 80);
            noCanvas();
        }
        function test_07_uninstalled_value_kept_and_marked() {
            picker.value = "No Such Family Zz";
            openPicker();
            compare(picker.missing, true, "marked as not installed");
            keyClick(Qt.Key_Escape);
            compare(picker.value, "No Such Family Zz", "kept until something else is chosen");
            compare(root.picks.length, 0, "nothing written");
        }
        function test_08_default_chip_picks_empty() {
            picker.value = installed[0];
            openPicker();
            compare(picker.shown.indexOf(installed[0]) >= 0, true);
            const lv = picker.children[1];
            const chipY = lv.mapToItem(root, 0, 0).y + 4 + 30 + 4 + 13;
            const chipX = lv.mapToItem(root, 0, 0).x + 4 + 30;
            clickAt(chipX, chipY);
            compare(root.picks.length, 1);
            compare(root.picks[0], "", "the default");
            noCanvas();
        }
        function test_09_outside_card_still_canvas() {
            clickAt(150, 400);   // on the widget, beside the card
            compare(root.selection.length, 1);
        }
    }
}
