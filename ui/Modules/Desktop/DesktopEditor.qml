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
        // for `ipc captureBar` (diagnostics): the window's own content item cannot be grabbed
        PanelRouter.barItems["editor-backdrop@" + output] = backdrop;
        PanelRouter.barItems["editor-slots@" + output] = slots;
        PanelRouter.barItems["editor-toolbar@" + output] = toolbar;
        PanelRouter.barItems["editor-root@" + output] = ed;
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
    // the widget a press at a window point lands on: the topmost whose hit area (body, frame, name tag; not its
    // buttons) holds it
    function slotAt(scenePoint: point): var {
        // later children draw over earlier ones; a higher z over both
        const kids = slots.children.map((c, i) => ({ c: c, i: i })).filter(k => k.c.entry !== undefined && k.c.visible);
        kids.sort((a, b) => (b.c.z - a.c.z) || (b.i - a.i));
        for (const k of kids)
            if (k.c.contains(k.c.mapFromItem(null, scenePoint.x, scenePoint.y)))
                return k.c;
        return null;
    }
    // with Desktop.traceInput (ipc editorTrace true), each tap and drag is logged: what it landed on, what it did
    function trace(what: string, detail: string): void {
        if (Desktop.traceInput)
            console.info("zynith editor:", what, detail);
    }
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

        // One owner for every tap and drag on the canvas, widgets included: what a press is for is decided where it
        // lands (ed.slotAt: a widget's body, its frame or its name tag), not by which of several handlers wins a race.
        // A tap selects the widget under it (Shift/Ctrl adds) or clears the selection; a drag that starts on a
        // widget moves it (with the rest of the selection), one that starts on bare desktop draws the lasso. The
        // frame's buttons and the resize/turn handles sit above and keep their own presses.
        TapHandler {
            onTapped: (point, button) => {
                const hit = ed.slotAt(point.scenePosition);
                if (hit)
                    Desktop.select(hit.entry.id, point.modifiers & (Qt.ShiftModifier | Qt.ControlModifier));
                else {
                    Desktop.clearSelection();
                    Desktop.picking = false;
                }
                ed.trace("tap", hit ? hit.entry.id : "desktop");
                keys.forceActiveFocus();
            }
            onDoubleTapped: point => {
                if (ed.slotAt(point.scenePosition))
                    Desktop.inspecting = true;
            }
        }
        DragHandler {
            id: gesture
            target: null
            property string mode: ""    // move | lasso
            property point from
            property var starts: ({})
            property string grabbed: ""
            onActiveChanged: {
                if (active) {
                    const hit = ed.slotAt(centroid.scenePressPosition);
                    if (hit) {
                        mode = "move";
                        grabbed = hit.entry.id;
                        if (!Desktop.selection.includes(grabbed))
                            Desktop.select(grabbed, false);
                        const s = {};
                        for (const id of Desktop.selection) {
                            const w = Desktop.byId(id);
                            if (w && (!w.output || w.output === ed.output))
                                s[id] = ed.screenGeometry(w);
                        }
                        starts = s;
                    } else {
                        mode = "lasso";
                        from = centroid.pressPosition;
                    }
                    ed.trace("drag-start", mode + " " + (hit ? grabbed : "") + " at " + Math.round(centroid.scenePressPosition.x) + "," + Math.round(centroid.scenePressPosition.y));
                } else {
                    if (mode === "move") {
                        ed.guideX = false;
                        ed.guideY = false;
                        ed.trace("drag-end", "move " + grabbed + " by " + Math.round(centroid.scenePosition.x - centroid.scenePressPosition.x) + "," + Math.round(centroid.scenePosition.y - centroid.scenePressPosition.y));
                        Desktop.commitDraft();
                    } else if (mode === "lasso") {
                        const r = lassoRect;
                        const hit = slots.children.filter(s => s.entry && s.x + s.width > r.x && s.x < r.x + r.width && s.y + s.height > r.y && s.y < r.y + r.height).map(s => s.entry.id);
                        Desktop.selection = (centroid.modifiers & Qt.ShiftModifier) ? Array.from(new Set(Desktop.selection.concat(hit))) : hit;
                        ed.trace("drag-end", "lasso selected " + hit.length);
                    }
                    mode = "";
                    grabbed = "";
                }
            }
            onCentroidChanged: if (active && mode === "move") {
                const mine = starts[grabbed];
                if (!mine)
                    return;
                // the pointer's travel on screen (this window is the output), so the widget keeps the point where it
                // was grabbed; the grid moves it in whole steps from where it was, so nothing jumps at the start
                const tx = centroid.scenePosition.x - centroid.scenePressPosition.x;
                const ty = centroid.scenePosition.y - centroid.scenePressPosition.y;
                let cx = mine.cx + Desktop.snapped(tx), cy = mine.cy + Desktop.snapped(ty);
                // the centre lines catch first
                ed.guideX = Math.abs(mine.cx + tx - ed.sw / 2) < 10;
                ed.guideY = Math.abs(mine.cy + ty - ed.sh / 2) < 10;
                if (ed.guideX)
                    cx = ed.sw / 2;
                if (ed.guideY)
                    cy = ed.sh / 2;
                const dx = cx - mine.cx, dy = cy - mine.cy;
                for (const [id, g] of Object.entries(starts))
                    Desktop.setDraft(id, Object.assign({}, g, {
                        cx: g.cx + dx,
                        cy: g.cy + dy
                    }));
            }
        }
        Rectangle {
            id: lassoRect
            visible: gesture.active && gesture.mode === "lasso"
            x: Math.min(gesture.from.x, gesture.centroid.position.x)
            y: Math.min(gesture.from.y, gesture.centroid.position.y)
            width: Math.abs(gesture.centroid.position.x - gesture.from.x)
            height: Math.abs(gesture.centroid.position.y - gesture.from.y)
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

                // a widget that sizes itself (width/height 0: weather, media) is as large as it draws, centred on
                // its point (as the desktop shows it), not an 8 px box nobody can grab
                width: place.width > 0 ? Math.max(8, place.width) : Math.max(24, preview.implicitWidth)
                height: place.height > 0 ? Math.max(8, place.height) : Math.max(24, preview.implicitHeight)
                x: place.x + (place.width > 0 ? 0 : -width / 2)
                y: place.y + (place.height > 0 ? 0 : -height / 2)
                rotation: Desktop.geometry(modelData).rotation * 180 / Math.PI
                z: selected ? 2 : 1

                // Where the pointer reaches this widget: the body with the frame drawn round it, and the name tag
                // above it (the grip), but not the frame's buttons. Without this the slot took presses only inside
                // its own rectangle: the frame line (4 px outside) and the tag (above) are drawn outside it, so a
                // press there fell through to the desktop and drew the selection lasso instead of moving the widget.
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
                    id: preview
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
                    // every widget wears its frame while editing (what is there, and that it can be moved)
                    border.width: slot.selected ? 1.5 : 1
                    border.color: slot.selected ? Theme.accent : Theme.alpha("#ffffff", body.hovered ? 0.55 : 0.22)
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                // what it is, above its top-left corner; also the grip (drag it, or the body, to move the widget)
                Rectangle {
                    id: tag
                    opacity: slot.selected || body.hovered ? 1 : 0.7
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
                            name: "grip-vertical"
                            size: 11
                            color: slot.selected ? Theme.onAccent : Theme.ink
                            opacity: 0.7
                        }
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

                // its own actions, on the frame (as Ryoku's): its settings, and hide / show
                Row {
                    id: frameActions
                    visible: slot.selected || body.hovered || actionsHover.hovered
                    anchors.right: parent.right
                    anchors.rightMargin: -4
                    y: -30
                    spacing: 4
                    z: 3
                    rotation: -slot.rotation
                    HoverHandler {
                        id: actionsHover
                    }
                    FrameButton {
                        icon: "adjustments"
                        tip: "Settings"
                        onClicked: {
                            Desktop.selection = [slot.modelData.id];
                            Desktop.inspecting = true;
                        }
                    }
                    FrameButton {
                        icon: slot.modelData.hidden ? "eye" : "eye-off"
                        tip: slot.modelData.hidden ? "Show" : "Hide"
                        onClicked: Desktop.toggleHidden([slot.modelData.id])
                    }
                }

                // the body, frame and tag show they can be moved (the canvas's handlers do the selecting and moving)
                HoverHandler {
                    id: body
                    cursorShape: Qt.SizeAllCursor
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
                            // a resize or turn in progress stays one: the widget's mover may not take it over
                            grabPermissions: PointerHandler.TakeOverForbidden
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
                        // a resize or turn in progress stays one: the widget's mover may not take it over
                        grabPermissions: PointerHandler.TakeOverForbidden
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
            Label {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Metrics.s3
                rightPadding: Metrics.s3
                role: "label"
                font.weight: Font.Medium
                text: "Edit widgets"
            }
            TextTool {
                icon: "plus"
                label: "Add widget"
                active: Desktop.picking
                onClicked: Desktop.picking = !Desktop.picking
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 24
                color: Theme.hairline
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
            // back to the layout this session started from (only once something changed)
            TextTool {
                visible: Desktop.sessionChanged
                icon: "restore"
                label: "Reset"
                onClicked: Desktop.resetSession()
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

    // a small round action on a widget's frame
    component FrameButton: Rectangle {
        id: fb
        property string icon
        property string tip
        signal clicked
        width: 22
        height: 22
        radius: 11
        color: fbArea.containsMouse ? Theme.accent : Theme.alpha(Theme.base, 0.85)
        border.width: Metrics.hairline
        border.color: Theme.hairline
        Icon {
            anchors.centerIn: parent
            name: fb.icon
            size: 12
            color: fbArea.containsMouse ? Theme.onAccent : Theme.ink
        }
        MouseArea {
            id: fbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fb.clicked()
        }
    }

    // a toolbar action with its name beside its icon
    component TextTool: Item {
        id: tt
        property string icon
        property string label
        property bool active: false
        signal clicked
        width: ttRow.implicitWidth + Metrics.s4 * 2
        height: 36
        anchors.verticalCenter: parent?.verticalCenter
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: tt.active ? Theme.accentSoft : ttArea.containsMouse ? Theme.hover : "transparent"
            border.width: Metrics.hairline
            border.color: tt.active ? Theme.accentLine : Theme.hairline
            Behavior on color {
                ColorAnim {}
            }
        }
        Row {
            id: ttRow
            anchors.centerIn: parent
            spacing: Metrics.s2
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: tt.icon
                size: 15
                tone: tt.active ? "accent" : "ink"
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                text: tt.label
            }
        }
        MouseArea {
            id: ttArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tt.clicked()
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
