import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services
import "../../Common/Placement.js" as Placement

// The desktop widget editor: above the windows, over the wallpaper itself, so the desktop can be arranged
// without clearing it. Drag to move (the grid and the screen's centre lines catch it), a corner to scale
// (Shift stretches), the dot above to rotate (Shift: 15° steps), the empty desktop to select several.
//
// Keys: Esc steps back (picker, inspector, selection, editor) · Enter done · Delete remove · arrows nudge
//       (Shift ×10) · Ctrl+C/V copy/paste · Ctrl+D duplicate · Ctrl+Z / Ctrl+Shift+Z undo/redo · Ctrl+A all ·
//       A add · I inspector · G grid · F flip · H hide · PageUp/PageDown front/back
PanelWindow {
    id: ed

    readonly property real sw: width
    readonly property real sh: height
    readonly property string output: screen?.name ?? ""
    readonly property var widgets: Config.widgets.filter(w => !w.output || w.output === output)

    WlrLayershell.namespace: "zynith-desktop-editor"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: Desktop.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // 0 → 1 as the editor arrives, back to 0 as it leaves
    property real vp: 0
    Component.onCompleted: {
        vp = Desktop.closing ? 0 : 1;
        Wallpapers.retain();
        keys.forceActiveFocus();
    }
    Component.onDestruction: Wallpapers.release()
    Connections {
        target: Desktop
        function onClosingChanged(): void {
            ed.vp = Desktop.closing ? 0 : 1;
        }
    }
    Behavior on vp {
        Anim {
            role: ed.vp > 0.5 ? "exit" : "enter"
        }
    }
    function phase(delay: real, span: real): real {
        return Math.max(0, Math.min(1, (vp - delay) / span));
    }

    // the screen geometry of a widget, and its stored geometry rewritten in this screen's pixels
    function placeOf(w: var): var {
        return Placement.place(w, Desktop.geometry(w), sw, sh);
    }
    function screenGeometry(w: var): var {
        const p = placeOf(w);
        return {
            cx: p.x + p.width / 2,
            cy: p.y + p.height / 2,
            width: p.width,
            height: p.height,
            rotation: Desktop.geometry(w).rotation,
            reference: [sw, sh]
        };
    }

    // ── the desktop as it really is: the wallpaper, a dot grid while snapping ─
    Item {
        id: backdrop
        anchors.fill: parent
        opacity: Motion.bezier(Motion.enterCurve, ed.phase(0, 0.6))

        readonly property string still: Wallpapers.mode === "live" ? (Wallpapers.liveItems[Wallpapers.liveCurrent]?.preview ?? "") : Wallpapers.current
        Rectangle {
            anchors.fill: parent
            color: Theme.base
        }
        Image {
            anchors.fill: parent
            source: backdrop.still !== "" ? Thumbnails.url(backdrop.still, 1920) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.base, 0.18)
        }
        Canvas {
            id: dots
            anchors.fill: parent
            opacity: Desktop.snap ? 0.5 : 0
            visible: opacity > 0
            Behavior on opacity {
                Anim {
                    role: "effects"
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.22);
                const step = Desktop.grid * 2;
                for (let x = step; x < width; x += step)
                    for (let y = step; y < height; y += step)
                        ctx.fillRect(x - 0.75, y - 0.75, 1.5, 1.5);
            }
        }

        // a tap on the desktop clears the selection; a drag draws a lasso
        TapHandler {
            onTapped: {
                Desktop.clearSelection();
                Desktop.picking = false;
                keys.forceActiveFocus();
            }
        }
        DragHandler {
            id: lasso
            target: null
            property point from
            onActiveChanged: {
                if (active) {
                    from = centroid.pressPosition;
                } else {
                    const r = lassoRect;
                    const hit = slots.children.filter(s => s.entry && s.x + s.width > r.x && s.x < r.x + r.width && s.y + s.height > r.y && s.y < r.y + r.height).map(s => s.entry.id);
                    Desktop.selection = (centroid.modifiers & Qt.ShiftModifier) ? Array.from(new Set(Desktop.selection.concat(hit))) : hit;
                }
            }
        }
        Rectangle {
            id: lassoRect
            visible: lasso.active
            x: Math.min(lasso.from.x, lasso.centroid.position.x)
            y: Math.min(lasso.from.y, lasso.centroid.position.y)
            width: Math.abs(lasso.centroid.position.x - lasso.from.x)
            height: Math.abs(lasso.centroid.position.y - lasso.from.y)
            radius: Metrics.radiusSm
            color: Theme.alpha(Theme.accent, 0.12)
            border.width: 1
            border.color: Theme.accentLine
        }
    }

    // the screen's centre lines, shown while something is held on them
    property bool guideX: false
    property bool guideY: false
    Rectangle {
        visible: ed.guideX
        x: ed.sw / 2 - 0.5
        width: 1
        height: ed.sh
        color: Theme.accent
        opacity: 0.8
    }
    Rectangle {
        visible: ed.guideY
        y: ed.sh / 2 - 0.5
        width: ed.sw
        height: 1
        color: Theme.accent
        opacity: 0.8
    }

    // ── the widgets ──────────────────────────────────────────────────────────
    Item {
        id: slots
        anchors.fill: parent

        Repeater {
            model: ed.widgets

            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property var entry: modelData
                readonly property var place: ed.placeOf(modelData)
                readonly property bool selected: Desktop.selection.includes(modelData.id)
                readonly property bool leaving: Desktop.removing.includes(modelData.id)

                x: place.x
                y: place.y
                width: Math.max(8, place.width)
                height: Math.max(8, place.height)
                rotation: Desktop.geometry(modelData).rotation * 180 / Math.PI
                z: selected ? 2 : 1

                // arriving: each widget settles in after the backdrop, one after another
                readonly property real arrive: Motion.bezier(Motion.spatialCurve, ed.phase(0.1 + Math.min(0.3, index * 0.03), 0.6))
                opacity: (modelData.hidden ? 0.35 : 1) * Math.min(1, arrive * 1.5) * (leaving ? 0 : 1)
                scale: (0.94 + 0.06 * arrive) * (leaving ? 0.7 : 1)
                Behavior on opacity {
                    enabled: slot.leaving
                    Anim {
                        role: "exit"
                    }
                }
                Behavior on scale {
                    enabled: slot.leaving
                    Anim {
                        role: "exit"
                    }
                }

                WidgetView {
                    anchors.fill: parent
                    spec: slot.modelData
                    preview: true
                    enabled: false
                    transform: Scale {
                        origin.x: slot.width / 2
                        xScale: slot.modelData.flip ? -1 : 1
                    }
                }

                // hover and selection outlines
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: Metrics.radiusMd
                    color: slot.selected ? Theme.alpha(Theme.accent, 0.06) : "transparent"
                    border.width: slot.selected ? 1.5 : body.hovered ? 1 : 0
                    border.color: slot.selected ? Theme.accent : Theme.alpha("#ffffff", 0.45)
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                // what it is, above its top-left corner
                Rectangle {
                    visible: slot.selected || body.hovered
                    x: -4
                    y: -30
                    width: tagRow.implicitWidth + Metrics.s4
                    height: 22
                    radius: 11
                    color: slot.selected ? Theme.accent : Theme.alpha(Theme.base, 0.8)
                    rotation: -slot.rotation
                    Row {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: Metrics.s1
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: WidgetTypes.find(slot.modelData.type)?.icon ?? "apps"
                            size: 11
                            color: slot.selected ? Theme.onAccent : Theme.ink
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "micro"
                            color: slot.selected ? Theme.onAccent : Theme.ink
                            text: (WidgetTypes.find(slot.modelData.type)?.label ?? slot.modelData.type) + (slot.modelData.hidden ? " · hidden" : "")
                        }
                    }
                }

                // the body: select, and drag to move (with the rest of the selection)
                HoverHandler {
                    id: body
                    cursorShape: Qt.SizeAllCursor
                }
                TapHandler {
                    onTapped: (point, button) => {
                        Desktop.select(slot.modelData.id, point.modifiers & (Qt.ShiftModifier | Qt.ControlModifier));
                        keys.forceActiveFocus();
                    }
                    onDoubleTapped: Desktop.inspecting = true
                }
                DragHandler {
                    id: mover
                    target: null
                    property var starts: ({})
                    onActiveChanged: {
                        if (active) {
                            if (!slot.selected)
                                Desktop.select(slot.modelData.id, false);
                            const s = {};
                            for (const id of Desktop.selection) {
                                const w = Desktop.byId(id);
                                if (w && (!w.output || w.output === ed.output))
                                    s[id] = ed.screenGeometry(w);
                            }
                            starts = s;
                        } else {
                            ed.guideX = false;
                            ed.guideY = false;
                            Desktop.commitDraft();
                        }
                    }
                    onTranslationChanged: if (active) {
                        const mine = starts[slot.modelData.id];
                        if (!mine)
                            return;
                        let cx = mine.cx + translation.x, cy = mine.cy + translation.y;
                        // the centre lines catch first, then the grid
                        ed.guideX = Math.abs(cx - ed.sw / 2) < 10;
                        ed.guideY = Math.abs(cy - ed.sh / 2) < 10;
                        cx = ed.guideX ? ed.sw / 2 : Desktop.snapped(cx);
                        cy = ed.guideY ? ed.sh / 2 : Desktop.snapped(cy);
                        const dx = cx - mine.cx, dy = cy - mine.cy;
                        for (const [id, g] of Object.entries(starts))
                            Desktop.setDraft(id, Object.assign({}, g, {
                                cx: g.cx + dx,
                                cy: g.cy + dy
                            }));
                    }
                }

                // corners: scale about the centre (Shift stretches instead)
                Repeater {
                    model: slot.selected && Desktop.selection.length === 1 ? 4 : 0
                    delegate: Rectangle {
                        id: handle
                        required property int index
                        readonly property real sx: index % 2 === 0 ? -1 : 1
                        readonly property real sy: index < 2 ? -1 : 1
                        width: 14
                        height: 14
                        radius: 7
                        x: (sx < 0 ? 0 : slot.width) - width / 2 + sx * 4
                        y: (sy < 0 ? 0 : slot.height) - height / 2 + sy * 4
                        color: Theme.ink
                        border.width: 2
                        border.color: Theme.accent
                        scale: grab.active || hoverCorner.hovered ? 1.25 : 1
                        Glide on scale {
                            epsilon: 0.001
                        }
                        HoverHandler {
                            id: hoverCorner
                            cursorShape: (handle.sx * handle.sy) > 0 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                        }
                        DragHandler {
                            id: grab
                            target: null
                            property var start: null
                            property real d0: 1
                            onActiveChanged: {
                                if (active) {
                                    start = ed.screenGeometry(slot.modelData);
                                    const p = centroid.scenePressPosition;
                                    d0 = Math.max(1, Math.hypot(p.x - start.cx, p.y - start.cy));
                                } else {
                                    Desktop.commitDraft();
                                }
                            }
                            onCentroidChanged: if (active && start) {
                                const p = centroid.scenePosition;
                                if (centroid.modifiers & Qt.ShiftModifier) {
                                    // free: the pointer in the widget's own axes sets each side
                                    const a = -start.rotation;
                                    const dx = p.x - start.cx, dy = p.y - start.cy;
                                    const lx = dx * Math.cos(a) - dy * Math.sin(a), ly = dx * Math.sin(a) + dy * Math.cos(a);
                                    Desktop.setDraft(slot.modelData.id, Object.assign({}, start, {
                                        width: Math.max(24, Math.abs(lx) * 2 - 8),
                                        height: Math.max(24, Math.abs(ly) * 2 - 8)
                                    }));
                                } else {
                                    const f = Math.max(0.1, Math.hypot(p.x - start.cx, p.y - start.cy) / d0);
                                    Desktop.setDraft(slot.modelData.id, Object.assign({}, start, {
                                        width: Math.max(24, start.width * f),
                                        height: Math.max(24, start.height * f)
                                    }));
                                }
                            }
                        }
                    }
                }

                // the rotation dot, on a stem above the top edge
                Rectangle {
                    visible: slot.selected && Desktop.selection.length === 1
                    x: slot.width / 2 - 0.75
                    y: -34
                    width: 1.5
                    height: 26
                    color: Theme.accent
                }
                Rectangle {
                    id: spin
                    visible: slot.selected && Desktop.selection.length === 1
                    x: slot.width / 2 - width / 2
                    y: -44
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.accent
                    border.width: 2
                    border.color: Theme.ink
                    scale: turn.active || hoverSpin.hovered ? 1.25 : 1
                    Glide on scale {
                        epsilon: 0.001
                    }
                    HoverHandler {
                        id: hoverSpin
                        cursorShape: Qt.CrossCursor
                    }
                    DragHandler {
                        id: turn
                        target: null
                        property var start: null
                        property real a0: 0
                        onActiveChanged: {
                            if (active) {
                                start = ed.screenGeometry(slot.modelData);
                                const p = centroid.scenePressPosition;
                                a0 = Math.atan2(p.y - start.cy, p.x - start.cx);
                            } else {
                                Desktop.commitDraft();
                            }
                        }
                        onCentroidChanged: if (active && start) {
                            const p = centroid.scenePosition;
                            let r = start.rotation + Math.atan2(p.y - start.cy, p.x - start.cx) - a0;
                            const step = Math.PI / 12;
                            if (centroid.modifiers & Qt.ShiftModifier)
                                r = Math.round(r / step) * step;
                            else if (Math.abs(r - Math.round(r / (Math.PI / 2)) * (Math.PI / 2)) < 0.04)
                                r = Math.round(r / (Math.PI / 2)) * (Math.PI / 2);
                            Desktop.setDraft(slot.modelData.id, Object.assign({}, start, {
                                rotation: r
                            }));
                        }
                    }
                }
            }
        }
    }

    // ── the toolbar ──────────────────────────────────────────────────────────
    Glass {
        id: toolbar
        readonly property real p: Motion.bezier(Motion.spatialCurve, ed.phase(0.15, 0.6))
        anchors.horizontalCenter: parent.horizontalCenter
        y: 24 - (1 - p) * 40
        opacity: p
        width: tools.implicitWidth + Metrics.s3 * 2
        height: 52
        radius: 26
        raised: true
        readonly property bool any: Desktop.selection.length > 0

        TapHandler {}
        Row {
            id: tools
            anchors.centerIn: parent
            spacing: 2
            Tool {
                icon: "plus"
                label: "Add"
                active: Desktop.picking
                onClicked: Desktop.picking = !Desktop.picking
            }
            Tool {
                icon: "copy"
                label: "Duplicate"
                enabled: toolbar.any
                onClicked: Desktop.clone(Desktop.selection)
            }
            Tool {
                icon: "flip-horizontal"
                label: "Flip"
                enabled: toolbar.any
                onClicked: Desktop.flip(Desktop.selection)
            }
            Tool {
                icon: "arrow-up"
                label: "To front"
                enabled: toolbar.any
                onClicked: Desktop.toFront(Desktop.selection)
            }
            Tool {
                icon: "arrow-down"
                label: "To back"
                enabled: toolbar.any
                onClicked: Desktop.toBack(Desktop.selection)
            }
            Tool {
                icon: Desktop.selected?.hidden ? "eye" : "eye-off"
                label: Desktop.selected?.hidden ? "Show" : "Hide"
                enabled: toolbar.any
                onClicked: Desktop.toggleHidden(Desktop.selection)
            }
            Tool {
                icon: "adjustments"
                label: "Settings"
                enabled: Desktop.selection.length === 1
                active: Desktop.inspecting
                onClicked: Desktop.inspecting = !Desktop.inspecting
            }
            Tool {
                icon: "trash"
                label: "Remove"
                enabled: toolbar.any
                danger: true
                onClicked: Desktop.removeAnimated(Desktop.selection)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 24
                color: Theme.hairline
            }
            Tool {
                icon: "grid-dots"
                label: "Snap"
                active: Desktop.snap
                onClicked: Desktop.snap = !Desktop.snap
            }
            Tool {
                icon: "arrow-back-up"
                label: "Undo"
                enabled: Desktop.undoStack.length > 0
                onClicked: Desktop.undo()
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 24
                color: Theme.hairline
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: doneRow.implicitWidth + Metrics.s5 * 2
                height: 36
                radius: 18
                color: Theme.accent
                Row {
                    id: doneRow
                    anchors.centerIn: parent
                    spacing: Metrics.s2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        size: 14
                        color: Theme.onAccent
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        font.weight: Font.Medium
                        color: Theme.onAccent
                        text: "Done"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Desktop.close()
                }
            }
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: toolbar.y + toolbar.height + Metrics.s3
        opacity: toolbar.p * 0.8
        role: "caption"
        tone: "muted"
        text: "Drag to move · corners scale (Shift stretches) · the dot rotates · drag the desktop to select several · Esc leaves"
    }

    // ── the inspector: the selected widget's settings ─────────────────────────
    Loader {
        active: Desktop.inspecting && Desktop.selected !== null && (!Desktop.selected.output || Desktop.selected.output === ed.output)
        sourceComponent: WidgetInspector {
            widget: Desktop.selected
            side: ed.placeOf(Desktop.selected).x + ed.placeOf(Desktop.selected).width / 2 > ed.sw * 0.55 ? "left" : "right"
            screenW: ed.sw
            screenH: ed.sh
        }
        anchors.fill: parent
    }

    // ── the picker: every kind, previewed ────────────────────────────────────
    Loader {
        active: Desktop.picking
        anchors.fill: parent
        sourceComponent: WidgetPicker {
            onPicked: type => {
                Desktop.add(type, ed.output, ed.sw / 2, ed.sh / 2, ed.sw, ed.sh);
                Desktop.picking = false;
                Desktop.inspecting = true;
                keys.forceActiveFocus();
            }
        }
    }

    // ── keys ─────────────────────────────────────────────────────────────────
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier;
            const step = shift ? 10 : 1;
            const sel = Desktop.selection;
            switch (event.key) {
            case Qt.Key_Escape:
                if (Desktop.picking)
                    Desktop.picking = false;
                else if (Desktop.inspecting)
                    Desktop.inspecting = false;
                else if (sel.length > 0)
                    Desktop.clearSelection();
                else
                    Desktop.close();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                Desktop.close();
                break;
            case Qt.Key_Delete:
            case Qt.Key_Backspace:
                Desktop.removeAnimated(sel);
                break;
            case Qt.Key_Left:
                Desktop.nudge(-step, 0);
                break;
            case Qt.Key_Right:
                Desktop.nudge(step, 0);
                break;
            case Qt.Key_Up:
                Desktop.nudge(0, -step);
                break;
            case Qt.Key_Down:
                Desktop.nudge(0, step);
                break;
            case Qt.Key_PageUp:
                Desktop.toFront(sel);
                break;
            case Qt.Key_PageDown:
                Desktop.toBack(sel);
                break;
            case Qt.Key_C:
                if (ctrl)
                    Desktop.copy(sel);
                break;
            case Qt.Key_V:
                if (ctrl)
                    Desktop.paste(ed.output);
                break;
            case Qt.Key_D:
                if (ctrl)
                    Desktop.clone(sel);
                break;
            case Qt.Key_Z:
                if (ctrl && shift)
                    Desktop.redo();
                else if (ctrl)
                    Desktop.undo();
                break;
            case Qt.Key_Y:
                if (ctrl)
                    Desktop.redo();
                break;
            case Qt.Key_A:
                if (ctrl)
                    Desktop.selection = ed.widgets.map(w => w.id);
                else
                    Desktop.picking = !Desktop.picking;
                break;
            case Qt.Key_I:
                if (sel.length === 1)
                    Desktop.inspecting = !Desktop.inspecting;
                break;
            case Qt.Key_G:
                Desktop.snap = !Desktop.snap;
                break;
            case Qt.Key_F:
                Desktop.flip(sel);
                break;
            case Qt.Key_H:
                Desktop.toggleHidden(sel);
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }

    component Tool: Item {
        id: tool
        property string icon
        property string label
        property bool active: false
        property bool danger: false
        signal clicked
        width: 40
        height: 40
        opacity: enabled ? 1 : 0.35
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: tool.active ? Theme.accentSoft : toolArea.containsMouse ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnim {}
            }
        }
        Icon {
            anchors.centerIn: parent
            name: tool.icon
            size: 17
            tone: tool.danger && toolArea.containsMouse ? "danger" : tool.active ? "accent" : "ink"
        }
        // its name, under it while the pointer rests
        Rectangle {
            visible: toolArea.containsMouse
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height + 10
            width: tip.implicitWidth + Metrics.s4
            height: 22
            radius: 11
            color: Theme.alpha(Theme.base, 0.9)
            Label {
                id: tip
                anchors.centerIn: parent
                role: "micro"
                text: tool.label
            }
        }
        MouseArea {
            id: toolArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tool.clicked()
        }
    }
}
