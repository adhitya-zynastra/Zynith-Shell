import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import "../../Common/BarModel.js" as BarModel

// The bar editor. Your bars as tabs; your display, with every bar where it sits (click one to edit it, drag it to
// another edge); then the bar you are editing, a tab at a time — Components (its three regions, its groups, the
// library), Corners, Position, Look, More. Every change goes through BarEdits: one atomic write of bars.toml,
// undoable (Ctrl+Z) and redoable (Ctrl+Shift+Z). A new bar starts empty, where you click.
Item {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var state: BarEdits.state
    readonly property var bars: state.bars
    property string selectedId: ""
    readonly property var bar: BarModel.find(state, selectedId) ?? (bars.length > 0 ? bars[0] : null)
    readonly property string barId: bar?.id ?? ""
    readonly property bool vertical: bar?.edge === "left" || bar?.edge === "right"
    readonly property string screenName: Quickshell.screens.find(s => (bar?.screens ?? ["*"]).includes(s.name))?.name ?? Quickshell.screens[0]?.name ?? ""
    property string tab: "components"
    property bool placing: bars.length === 0
    property bool renaming: false
    property bool menuOpen: false
    property string confirmDelete: ""

    function select(id: string): void {
        selectedId = id;
        sel = null;
        picked = [];
        placing = false;
        renaming = false;
        menuOpen = false;
        confirmDelete = "";
    }

    // ── selection: one entry (at: { section, index } or { group, index }), and the components picked to group ──
    property var sel: null
    property var picked: []
    onBarIdChanged: {
        sel = null;
        picked = [];
    }
    function same(a: var, b: var): bool {
        return a !== null && b !== null && a !== undefined && b !== undefined && a.section === b.section && a.group === b.group && a.index === b.index;
    }
    function isSelected(at: var): bool {
        return same(sel, at);
    }
    function isPicked(at: var): bool {
        return picked.some(p => same(p, at));
    }
    function entryName(at: var): string {
        return at && bar ? (BarModel.entryAt(bar, at) ?? "") : "";
    }
    readonly property string selName: entryName(sel)
    readonly property bool selIsGroup: selName.startsWith("group:")
    function clickEntry(at: var, modifiers: int): void {
        if (modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
            // picking several loose components of one region, to group them
            if (at.group !== undefined || entryName(at).startsWith("group:"))
                return;
            const others = picked.filter(p => p.section === at.section);
            if (sel && sel.group === undefined && sel.section === at.section && !entryName(sel).startsWith("group:") && !others.some(p => same(p, sel)))
                others.push(sel);
            picked = isPicked(at) ? others.filter(p => !same(p, at)) : others.concat([at]);
            sel = at;
            return;
        }
        picked = [];
        sel = same(sel, at) ? null : at;
    }
    readonly property bool canGroupPicked: picked.length >= 2
    function groupPicked(): void {
        if (!canGroupPicked)
            return;
        const section = picked[0].section;
        const gid = BarEdits.groupEntries(barId, section, picked.map(p => p.index), "");
        picked = [];
        if (gid !== "")
            sel = { section: section, index: BarModel.list(BarModel.find(BarEdits.state, barId)?.widgets?.[section]).indexOf("group:" + gid) };
    }

    // ── adding from the library: to the region of what is selected, else where the kind usually sits ──
    function addKind(type: string): void {
        let to;
        if (sel && sel.group !== undefined)
            to = { group: sel.group, index: sel.index + 1 };
        else if (sel)
            to = { section: sel.section, index: sel.index + 1 };
        else {
            const usual = ({ launcher: "start", workspaces: "start", clock: "center", island: "center", media: "center", active_window: "center" })[type] ?? "end";
            to = { section: usual, index: BarModel.list(bar?.widgets?.[usual]).length };
        }
        const name = BarEdits.insertComponent(barId, type, to);
        if (name !== "")
            sel = to;
    }

    // ── dragging: a component, a group, or a new one from the library; the strip says where it would land ──
    property bool dragging: false
    property var dragFrom: null
    property string dragType: ""
    property point dragPoint: Qt.point(0, 0)
    property var pressOffset: Qt.point(0, 0)
    readonly property Item dragProxy: proxy
    function draggingGroup(): bool {
        return dragFrom !== null && entryName(dragFrom).startsWith("group:");
    }
    function canMergeWith(section: string, index: int): bool {
        if (dragType !== "")
            return false;
        if (!dragFrom || draggingGroup())
            return false;
        return !(dragFrom.group === undefined && dragFrom.section === section && dragFrom.index === index);
    }
    function pressEntry(item: Item, at: var, modifiers: int): void {
        dragFrom = at;
        dragType = "";
    }
    function pressNew(item: Item, type: string): void {
        dragFrom = null;
        dragType = type;
    }
    function dragMove(item: Item, x: real, y: real, at: var, icon: string, label: string): void {
        const p = item.mapToItem(root, x, y);
        dragPoint = p;
        ghost.icon = icon;
        ghost.label = label;
        dragging = true;
    }
    function dragRelease(): void {
        if (!dragging) {
            dragType = "";
            return;
        }
        const target = strip.item?.hover ?? null;
        dragging = false;
        if (target) {
            if (dragType !== "") {
                const to = target.merge ? { section: target.merge.section, index: target.merge.index + 1 } : target;
                if (BarEdits.insertComponent(barId, dragType, to) !== "")
                    sel = to;
            } else if (target.merge) {
                mergeInto(dragFrom, target.merge);
            } else if (dragFrom) {
                BarEdits.moveEntry(barId, dragFrom, target);
                sel = null;
            }
        }
        dragFrom = null;
        dragType = "";
        proxy.x = 0;
        proxy.y = 0;
    }
    // a component dropped on another: the two become a group, in one undo step
    function mergeInto(from: var, onto: var): void {
        const target = entryName(onto);
        const dragged = entryName(from);
        let next = BarModel.moveEntry(state, barId, from, { section: onto.section, index: onto.index + 1 });
        const list = BarModel.list(BarModel.find(next, barId)?.widgets?.[onto.section]);
        const r = BarModel.groupEntries(next, barId, onto.section, [list.indexOf(target), list.indexOf(dragged)], "");
        if (r.id !== "" && BarEdits.commit(r.state, "Group two components"))
            sel = { section: onto.section, index: BarModel.list(BarModel.find(BarEdits.state, barId)?.widgets?.[onto.section]).indexOf("group:" + r.id) };
    }

    // ── keys on the strip ──
    function stripKey(event: var): void {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const fwd = vertical ? Qt.Key_Down : Qt.Key_Right, back = vertical ? Qt.Key_Up : Qt.Key_Left;
        const order = flatOrder();
        if (event.key === fwd || event.key === back || event.key === Qt.Key_Right || event.key === Qt.Key_Left || event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            const by = (event.key === Qt.Key_Right || event.key === Qt.Key_Down) ? 1 : -1;
            if (ctrl && sel) {
                moveSelected(by);
            } else {
                const i = sel ? order.findIndex(o => same(o, sel)) : -1;
                const n = Math.max(0, Math.min(order.length - 1, i + by));
                sel = order.length > 0 ? order[i < 0 ? 0 : n] : null;
            }
            event.accepted = true;
        } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && sel) {
            removeSelected();
            event.accepted = true;
        } else if (event.key === Qt.Key_G && !(event.modifiers & Qt.ShiftModifier)) {
            if (canGroupPicked)
                groupPicked();
            else if (sel && sel.group === undefined && !selIsGroup)
                sel = { section: sel.section, index: BarModel.list(BarModel.find(BarEdits.state, barId)?.widgets?.[sel.section]).indexOf("group:" + BarEdits.groupEntries(barId, sel.section, [sel.index], "")) };
            event.accepted = true;
        } else if (event.key === Qt.Key_G && selIsGroup) {
            BarEdits.ungroup(barId, selName.slice(6));
            sel = null;
            event.accepted = true;
        } else if (event.key === Qt.Key_Space && sel) {
            clickEntry(sel, Qt.ControlModifier);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            sel = null;
            picked = [];
            event.accepted = true;
        }
    }
    // every entry in reading order, members right after their group
    function flatOrder(): var {
        const out = [];
        for (const s of BarModel.sections)
            BarModel.list(bar?.widgets?.[s]).forEach((n, i) => {
                out.push({ section: s, index: i });
                if (String(n).startsWith("group:"))
                    BarModel.list(BarModel.groupById(bar, String(n).slice(6))?.members).forEach((m, k) => out.push({ group: String(n).slice(6), index: k }));
            });
        return out;
    }
    function moveSelected(by: int): void {
        if (!sel)
            return;
        if (sel.group !== undefined) {
            const count = BarModel.list(BarModel.groupById(bar, sel.group)?.members).length;
            const to = sel.index + by;
            if (to < 0 || to >= count)
                return;
            BarEdits.moveEntry(barId, sel, { group: sel.group, index: by > 0 ? to + 1 : to });
            sel = { group: sel.group, index: to };
            return;
        }
        const list = BarModel.list(bar?.widgets?.[sel.section]);
        const to = sel.index + by;
        if (to >= 0 && to < list.length) {
            BarEdits.moveEntry(barId, sel, { section: sel.section, index: by > 0 ? to + 1 : to });
            sel = { section: sel.section, index: to };
        } else {
            const s = BarModel.sections.indexOf(sel.section) + by;
            if (s < 0 || s > 2)
                return;
            const target = BarModel.sections[s];
            const idx = by > 0 ? 0 : BarModel.list(bar?.widgets?.[target]).length;
            BarEdits.moveEntry(barId, sel, { section: target, index: idx });
            sel = { section: target, index: idx };
        }
    }
    function removeSelected(): void {
        if (!sel)
            return;
        BarEdits.removeEntry(barId, sel);
        sel = null;
        picked = [];
    }

    // ── the page ──
    Column {
        id: content
        width: parent.width
        spacing: Metrics.s4

        // title, undo and redo
        Item {
            width: parent.width
            height: 40
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    role: "title"
                    text: "Bars"
                }
                Label {
                    role: "caption"
                    tone: "muted"
                    text: BarEdits.lastLabel !== "" ? BarEdits.lastLabel : "Build the bars on your screen. Changes show on the real bar at once."
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s1
                IconButton {
                    objectName: "bars-undo"
                    icon: "arrow-back-up"
                    tone: "muted"
                    enabled: BarEdits.canUndo
                    opacity: enabled ? 1 : 0.35
                    onClicked: BarEdits.undo()
                }
                IconButton {
                    objectName: "bars-redo"
                    icon: "arrow-forward-up"
                    tone: "muted"
                    enabled: BarEdits.canRedo
                    opacity: enabled ? 1 : 0.35
                    onClicked: BarEdits.redo()
                }
            }
        }

        // the bars file could not be read: say so, and the way out (nothing here writes over it meanwhile)
        Rectangle {
            visible: Config.barsError !== ""
            width: parent.width
            height: errCol.implicitHeight + Metrics.s4 * 2
            radius: Metrics.radiusMd
            color: Theme.alpha(Theme.danger, 0.12)
            border.width: 1
            border.color: Theme.alpha(Theme.danger, 0.4)
            Column {
                id: errCol
                x: Metrics.s4
                y: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                spacing: Metrics.s2
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    role: "label"
                    text: "Your bars file has a mistake in it, so nothing here changes it until it is fixed."
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    role: "caption"
                    tone: "muted"
                    text: Config.barsError
                }
                Chip {
                    icon: "restore"
                    text: "Start again with one plain bar (your file is kept beside it)"
                    onClicked: Config.recoverBars()
                }
            }
        }

        // your bars, as tabs
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: root.bars
                delegate: Rectangle {
                    id: barTab
                    required property var modelData
                    readonly property bool current: modelData.id === root.barId && !root.placing
                    objectName: "bar-tab-" + modelData.name
                    width: tabRow.implicitWidth + Metrics.s4 * 2
                    height: 34
                    radius: 17
                    color: current ? Theme.accentSoft : tabArea.containsMouse ? Theme.hover : Theme.plate
                    border.width: current ? 1 : 0
                    border.color: Theme.accent
                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(barTab.modelData.id)
                    }
                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: Metrics.s2
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: ({ top: "layout-navbar", bottom: "layout-bottombar", left: "layout-sidebar", right: "layout-sidebar-right" })[barTab.modelData.edge ?? "top"] ?? "layout-navbar"
                            size: 14
                            tone: barTab.modelData.enabled === false ? "faint" : barTab.current ? "accent" : "muted"
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "label"
                            tone: barTab.modelData.enabled === false ? "faint" : "ink"
                            font.strikeout: barTab.modelData.enabled === false
                            text: barTab.modelData.name
                        }
                    }
                }
            }
            Rectangle {
                objectName: "bar-new"
                width: newRow.implicitWidth + Metrics.s4 * 2
                height: 34
                radius: 17
                color: root.placing ? Theme.accent : newArea.containsMouse ? Theme.hover : "transparent"
                border.width: 1
                border.color: Theme.accentLine
                Row {
                    id: newRow
                    anchors.centerIn: parent
                    spacing: Metrics.s2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "plus"
                        size: 14
                        tone: root.placing ? "onAccent" : "accent"
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        color: root.placing ? Theme.onAccent : Theme.accent
                        text: root.placing && root.bars.length > 0 ? "Cancel" : "New bar"
                    }
                }
                MouseArea {
                    id: newArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.placing = root.bars.length === 0 ? true : !root.placing
                }
            }
        }

        // the display
        BarCanvas {
            id: canvas
            width: parent.width
            height: Math.min(230, width * 0.42)
            page: root
            placing: root.placing
            onPlaced: (edge, anchor) => {
                const id = BarEdits.create({ edge: edge, anchor: anchor, margin: anchor === "fill" ? 0 : 6 }, "");
                if (id !== "") {
                    root.select(id);
                    root.tab = "components";
                }
            }
        }
        Label {
            visible: root.placing
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            role: "caption"
            tone: "muted"
            text: root.bars.length === 0 ? "You have no bars yet. Click a spot on the screen above: the bar appears there, empty, and you fill it next." : "Click a spot for the new bar: an edge of the screen, and where along it."
        }

        // ── the bar being edited ──
        Column {
            visible: root.bar !== null && !root.placing
            width: parent.width
            spacing: Metrics.s4

            // its name, shown or hidden, and what can be done with it
            Item {
                width: parent.width
                height: 36
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3
                    Rectangle {
                        visible: root.renaming
                        width: 240
                        height: 34
                        radius: Metrics.radiusMd
                        color: Theme.well
                        border.width: 1
                        border.color: Theme.accentLine
                        TextInput {
                            id: nameField
                            objectName: "bar-name"
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.s3
                            anchors.rightMargin: Metrics.s3
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            selectionColor: Theme.accentSoft
                            font.family: Type.ui
                            font.pixelSize: Type.body
                            clip: true
                            onAccepted: {
                                if (text.trim() !== "")
                                    BarEdits.rename(root.barId, text);
                                root.renaming = false;
                            }
                            Keys.onEscapePressed: root.renaming = false
                        }
                    }
                    Label {
                        visible: !root.renaming
                        anchors.verticalCenter: parent.verticalCenter
                        role: "title"
                        text: root.bar?.name ?? ""
                    }
                    IconButton {
                        visible: !root.renaming
                        anchors.verticalCenter: parent.verticalCenter
                        size: 28
                        iconSize: 13
                        icon: "pencil"
                        tone: "muted"
                        onClicked: {
                            nameField.text = root.bar?.name ?? "";
                            root.renaming = true;
                            nameField.forceActiveFocus();
                            nameField.selectAll();
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "caption"
                        tone: "faint"
                        text: BarModel.positionLabel(root.bar ?? {})
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "caption"
                        tone: "muted"
                        text: root.bar?.enabled === false ? "Hidden" : "Shown"
                    }
                    Toggle {
                        objectName: "bar-shown"
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.bar?.enabled !== false
                        onToggled: BarEdits.setEnabled(root.barId, root.bar?.enabled === false)
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 28
                        iconSize: 13
                        icon: "copy"
                        tone: "muted"
                        onClicked: {
                            const id = BarEdits.duplicate(root.barId);
                            if (id !== "")
                                root.select(id);
                        }
                    }
                    Chip {
                        objectName: "bar-delete"
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "trash"
                        text: root.confirmDelete === root.barId ? "Delete it? Click again (Undo brings it back)" : "Delete"
                        active: root.confirmDelete === root.barId
                        onClicked: {
                            if (root.confirmDelete !== root.barId) {
                                root.confirmDelete = root.barId;
                                return;
                            }
                            const i = BarModel.indexOf(root.state, root.barId);
                            BarEdits.remove(root.barId);
                            root.select(root.bars[Math.max(0, Math.min(i, root.bars.length - 1))]?.id ?? "");
                        }
                    }
                }
            }

            Segmented {
                objectName: "bar-tabs"
                width: Math.min(parent.width, 560)
                options: [{ key: "components", label: "Components" }, { key: "corners", label: "Corners" }, { key: "position", label: "Position" }, { key: "look", label: "Look" }, { key: "more", label: "More" }]
                current: root.tab
                onPicked: key => root.tab = key
            }

            // ── Components ──
            Item {
                id: componentsTab
                visible: root.tab === "components"
                width: parent.width
                height: visible ? (root.vertical ? Math.max(strip.height, side.implicitHeight) : strip.height + Metrics.s4 + side.implicitHeight) : 0
                Loader {
                    id: strip
                    width: root.vertical ? 132 : parent.width
                    active: root.bar !== null
                    sourceComponent: BarStrip {
                        page: root
                    }
                }
                Column {
                    id: side
                    x: root.vertical ? strip.width + Metrics.s5 : 0
                    y: root.vertical ? 0 : strip.height + Metrics.s4
                    width: parent.width - x
                    spacing: Metrics.s4

                    // what is selected, or how the bar is arranged
                    Loader {
                        width: parent.width
                        sourceComponent: root.picked.length >= 2 ? pickedPanel : root.sel === null ? guidePanel : root.selIsGroup ? groupPanel : componentPanel
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.hairline
                    }
                    Label {
                        role: "micro"
                        caps: true
                        tone: "faint"
                        text: root.sel !== null ? "Add next to it" : "Add to the bar"
                    }
                    BarLibrary {
                        id: library
                        width: parent.width
                        page: root
                    }
                }
            }

            // ── Corners ──
            Loader {
                active: root.tab === "corners" && root.bar !== null
                visible: active
                width: parent.width
                sourceComponent: BarCorners {
                    page: root
                }
            }

            // ── Position ──
            Loader {
                active: root.tab === "position" && root.bar !== null
                visible: active
                width: parent.width
                sourceComponent: BarPosition {
                    page: root
                }
            }

            // ── Look ──
            Loader {
                active: root.tab === "look" && root.bar !== null
                visible: active
                width: parent.width
                sourceComponent: SchemaForm {
                    advanced: "hide"
                    schema: root.lookSchema
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    shows: spec => root.applies(spec)
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => BarEdits.setKey(root.barId, key, value)
                    onCleared: key => BarEdits.setKey(root.barId, key, undefined)
                    commitOnRelease: true
                    onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                    onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                }
            }

            // ── More: behaviour, the fine controls, clicks on the bar itself ──
            Loader {
                active: root.tab === "more" && root.bar !== null
                visible: active
                width: parent.width
                sourceComponent: Column {
                    spacing: Metrics.s5
                    Label {
                        role: "micro"
                        caps: true
                        tone: "faint"
                        text: "When it shows"
                    }
                    SchemaForm {
                        width: parent.width
                        advanced: "hide"
                        schema: root.behaviourSchema
                        valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                        shows: spec => root.applies(spec)
                        isSet: key => root.bar?.[key] !== undefined
                        onChanged: (key, value) => BarEdits.setKey(root.barId, key, value)
                        onCleared: key => BarEdits.setKey(root.barId, key, undefined)
                        commitOnRelease: true
                        onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                        onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                    }
                    Label {
                        role: "micro"
                        caps: true
                        tone: "faint"
                        text: "Fine controls"
                    }
                    SchemaForm {
                        width: parent.width
                        advanced: "only"
                        schema: root.behaviourSchema.concat(root.lookSchema)
                        valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                        shows: spec => root.applies(spec)
                        isSet: key => root.bar?.[key] !== undefined
                        onChanged: (key, value) => BarEdits.setKey(root.barId, key, value)
                        onCleared: key => BarEdits.setKey(root.barId, key, undefined)
                        commitOnRelease: true
                        onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                        onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                    }
                    Label {
                        role: "micro"
                        caps: true
                        tone: "faint"
                        text: "Clicks on the bar's empty space"
                    }
                    BarGestureForm {
                        width: parent.width
                        actions: root.bar?.actions ?? {}
                        defaults: ({ right: "panel-toggle control-center home" })
                        onChanged: (gesture, action) => {
                            const a = Object.assign({}, root.bar?.actions ?? {});
                            if (action === undefined)
                                delete a[gesture];
                            else
                                a[gesture] = action;
                            BarEdits.setKey(root.barId, "actions", a);
                        }
                    }
                    Chip {
                        icon: "restore"
                        text: "Reset its look and behaviour (keeps where it is and what it holds)"
                        onClicked: BarEdits.reset(root.barId)
                    }
                }
            }
        }
    }

    // ── side panels for the Components tab ──
    Component {
        id: guidePanel
        Column {
            spacing: Metrics.s2
            Label {
                role: "label"
                text: "How a bar is arranged"
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                role: "caption"
                tone: "muted"
                text: root.vertical ? "Top, Middle and Bottom are the bar's three places: what is in Top stacks from the top end, Middle stays centred, Bottom stacks up from the bottom end." : "Start, Center and End are the bar's three places: Start packs to the left end, Center stays in the middle, End packs to the right end."
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                role: "caption"
                tone: "muted"
                text: "Drag a component between them to move it. Drop it onto another component to put the two in a group — they then share one capsule and move together. Ctrl-click several, then Group, does the same."
            }
        }
    }
    Component {
        id: pickedPanel
        Column {
            spacing: Metrics.s3
            Label {
                role: "label"
                text: root.picked.length + " components picked"
            }
            Row {
                spacing: Metrics.s2
                Chip {
                    objectName: "group-picked"
                    icon: "layers-intersect"
                    text: "Group them"
                    active: true
                    onClicked: root.groupPicked()
                }
                Chip {
                    text: "Clear"
                    onClicked: root.picked = []
                }
            }
        }
    }
    Component {
        id: componentPanel
        Column {
            id: cp
            spacing: Metrics.s4
            readonly property var info: BarWidgetTypes.find(BarModel.typeOf(root.state, root.selName))
            readonly property bool inGroup: root.sel?.group !== undefined
            Item {
                width: parent.width
                height: 34
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: cp.info?.icon ?? "help"
                        size: 18
                        tone: "accent"
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            role: "label"
                            text: cp.info?.label ?? root.selName
                        }
                        Label {
                            role: "micro"
                            tone: "faint"
                            text: (BarWidgetTypes.descriptions[cp.info?.type ?? ""] ?? "") + (cp.inGroup ? " · in " + (BarModel.groupById(root.bar, root.sel.group)?.name ?? "a group") : "")
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: root.vertical ? "arrow-up" : "arrow-left"
                        tone: "muted"
                        onClicked: root.moveSelected(-1)
                    }
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: root.vertical ? "arrow-down" : "arrow-right"
                        tone: "muted"
                        onClicked: root.moveSelected(1)
                    }
                    IconButton {
                        visible: !cp.inGroup
                        size: 28
                        iconSize: 13
                        icon: "layers-intersect"
                        tone: "muted"
                        onClicked: {
                            const s = root.sel.section;
                            const gid = BarEdits.groupEntries(root.barId, s, [root.sel.index], "");
                            if (gid !== "")
                                root.sel = { section: s, index: BarModel.list(BarModel.find(BarEdits.state, root.barId)?.widgets?.[s]).indexOf("group:" + gid) };
                        }
                    }
                    IconButton {
                        visible: cp.inGroup
                        size: 28
                        iconSize: 13
                        icon: "logout"
                        tone: "muted"
                        onClicked: {
                            const gid = root.sel.group;
                            const s = BarModel.sections.find(x => BarModel.list(root.bar?.widgets?.[x]).includes("group:" + gid)) ?? "center";
                            const gi = BarModel.list(root.bar?.widgets?.[s]).indexOf("group:" + gid);
                            BarEdits.moveEntry(root.barId, root.sel, { section: s, index: gi + 1 });
                            root.sel = null;
                        }
                    }
                    IconButton {
                        objectName: "component-remove"
                        size: 28
                        iconSize: 13
                        icon: "trash"
                        tone: "muted"
                        onClicked: root.removeSelected()
                    }
                }
            }
            BarWidgetSheet {
                width: parent.width
                name: root.selName
            }
        }
    }
    Component {
        id: groupPanel
        Column {
            id: gp
            spacing: Metrics.s4
            readonly property string gid: root.selName.slice(6)
            readonly property var group: BarModel.groupById(root.bar, gid) ?? ({})
            Item {
                width: parent.width
                height: 34
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "layers-intersect"
                        size: 18
                        tone: "accent"
                    }
                    Rectangle {
                        width: 200
                        height: 30
                        radius: Metrics.radiusMd
                        color: Theme.well
                        TextInput {
                            id: groupName
                            objectName: "group-name"
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.s3
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            font.family: Type.ui
                            font.pixelSize: Type.body
                            text: gp.group.name ?? ("Group " + gp.gid)
                            onEditingFinished: if (text.trim() !== "" && text !== gp.group.name)
                                BarEdits.renameGroup(root.barId, gp.gid, text)
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "micro"
                        tone: "faint"
                        text: BarModel.list(gp.group.members).length + " in it"
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Chip {
                        objectName: "group-ungroup"
                        icon: "layers-off"
                        text: "Ungroup"
                        onClicked: {
                            BarEdits.ungroup(root.barId, gp.gid);
                            root.sel = null;
                        }
                    }
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: "trash"
                        tone: "muted"
                        onClicked: root.removeSelected()
                    }
                }
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                role: "caption"
                tone: "muted"
                text: "Its members share one capsule and move together. Drag a component into it to add it, or out of it to take it out."
            }
            SchemaForm {
                width: parent.width
                schema: [
                    { key: "style", label: "Looks like", kind: "choice", default: "", options: [{ key: "", label: "As the bar" }, { key: "capsule", label: "Capsule" }, { key: "plate", label: "Tone step" }, { key: "rule", label: "Rules" }] },
                    { key: "accordion", label: "Folds up, opens on hover", kind: "toggle", default: false },
                    { key: "accordion_direction", label: "Opens towards", kind: "choice", default: "end", options: [{ key: "start", label: "Start" }, { key: "end", label: "End" }], when: { accordion: [true] } },
                    { key: "padding", label: "Room inside", kind: "int", default: 8, from: 0, to: 32, step: 1 },
                    { key: "widget_spacing", label: "Space between its members", kind: "int", default: 4, from: 0, to: 32, step: 1 },
                    { key: "fill", label: "Fill", kind: "colour", default: "surface_variant" },
                    { key: "opacity", label: "Fill opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01 },
                    { key: "radius", label: "Corners", hint: "−1 rounds the ends fully", kind: "int", default: -1, from: -1, to: 40, step: 1 },
                    { key: "border", label: "Border colour", kind: "colour", default: "" },
                    { key: "foreground", label: "Colour of what is inside", kind: "colour", default: "" }
                ]
                valueOf: key => gp.group[key] ?? schema.find(s => s.key === key)?.default
                shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(gp.group[k] ?? false))
                isSet: key => gp.group[key] !== undefined
                onChanged: (key, value) => BarEdits.setGroupKey(root.barId, gp.gid, key, value)
                onCleared: key => BarEdits.setGroupKey(root.barId, gp.gid, key, undefined)
            }
        }
    }

    // what follows the pointer while dragging
    Item {
        id: proxy
    }
    Rectangle {
        id: ghost
        property string icon: ""
        property string label: ""
        visible: root.dragging
        z: 100
        x: root.dragPoint.x + 12
        y: root.dragPoint.y + 8
        width: ghostRow.implicitWidth + Metrics.s3 * 2
        height: 30
        radius: 15
        color: Theme.surfaceHighest
        border.width: 1
        border.color: Theme.accent
        Row {
            id: ghostRow
            anchors.centerIn: parent
            spacing: Metrics.s2
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: ghost.icon
                size: 14
                tone: "accent"
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "caption"
                text: ghost.label
            }
        }
    }

    // ── the look and behaviour settings (sizes and corners have tabs of their own) ──
    function applies(spec: var): bool {
        return !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(bar?.[k] ?? lookSchema.concat(behaviourSchema).find(s => s.key === k)?.default));
    }
    readonly property var lookSchema: [
        { key: "opacity", label: "Opacity", hint: "All the way down follows your surface style", kind: "slider", default: 0, from: 0, to: 1, step: 0.01 },
        { key: "blur", label: Material.style === "blur" ? "Blur behind it" : "Blur behind it (with the Blur surface style)", kind: "toggle", default: true },
        { key: "border", label: "Border", kind: "toggle", default: true },
        { key: "shadow", label: Material.shadows ? "Shadow" : "Shadow (" + (Material.style === "blur" ? "the Blur style floats without one" : "paused while power is short") + ")", kind: "toggle", default: true },
        { key: "group_style", label: "Groups look like", kind: "choice", default: "capsule", options: [{ key: "capsule", label: "Capsules" }, { key: "rule", label: "Rules" }, { key: "plate", label: "A tone step" }] },
        { key: "capsule", label: "Every component in its own capsule", kind: "toggle", default: false },
        { key: "font_family", label: "Font", kind: "font", default: "" },
        { key: "font_scale", label: "Text size", kind: "slider", default: 1, from: 0.6, to: 1.6, step: 0.01 },
        { key: "font_weight", label: "Text weight", kind: "select", default: "400", options: [100, 200, 300, 400, 500, 600, 700, 800, 900].map(w => ({ key: String(w), label: String(w) })) },
        { key: "color", label: "Component colour", kind: "colour", default: "" },
        { adv: true, key: "border_color", label: "Border colour", kind: "colour", default: "", when: { border: [true] } },
        { adv: true, key: "border_width", label: "Border width (-1 follows the theme)", kind: "int", default: -1, from: -1, to: 4, step: 1, when: { border: [true] } },
        { adv: true, key: "scale", label: "Content size", kind: "slider", default: 1, from: 0.5, to: 2, step: 0.01 },
        { adv: true, key: "icon_color", label: "Component icon colour", kind: "colour", default: "" },
        { adv: true, key: "contact_shadow", label: "Shadow at the seam with an open panel", kind: "toggle", default: false },
        { adv: true, key: "readouts", label: "Values under the icons (vertical bars)", kind: "toggle", default: false },
        { adv: true, key: "capsule_fill", label: "Capsule fill", kind: "colour", default: "surface_variant", when: { capsule: [true] } },
        { adv: true, key: "capsule_opacity", label: "Capsule opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01, when: { capsule: [true] } },
        { adv: true, key: "capsule_padding", label: "Capsule padding", kind: "int", default: 0, from: 0, to: 24, step: 1, when: { capsule: [true] } },
        { adv: true, key: "capsule_thickness", label: "Capsule thickness (of the bar)", kind: "slider", default: 1, from: 0.1, to: 1, step: 0.01 },
        { adv: true, key: "capsule_radius", label: "Capsule corners", hint: "−1 rounds the ends fully (a pill)", kind: "int", default: -1, from: -1, to: 32, step: 1 },
        { adv: true, key: "capsule_border", label: "Capsule border", kind: "colour", default: "" },
        { adv: true, key: "capsule_foreground", label: "Inside a capsule, components are", kind: "colour", default: "" }
    ]
    readonly property var behaviourSchema: [
        { key: "visibility", label: "Shows", kind: "choice", default: "always", options: [{ key: "always", label: "Always" }, { key: "smart", label: "When the desktop is clear" }, { key: "autohide", label: "When the pointer reaches the edge" }] },
        { key: "reserve", label: "Windows keep clear of it", kind: "toggle", default: false, hint: "Bars on one edge share the room the deepest of them needs" },
        { key: "open_on_hover", label: "Icons open their panel on hover", kind: "toggle", default: false },
        { key: "hover_delay", label: "Hover before a panel opens (ms)", kind: "int", default: 0, from: 0, to: 2000, step: 25, when: { open_on_hover: [true] } },
        { key: "hover_switch_delay", label: "Hover before another open panel switches (ms)", kind: "int", default: 110, from: 0, to: 1000, step: 10, when: { open_on_hover: [true] }, hint: "a sweep across icons opens only where it stops" },
        { key: "hover_close", label: "A hovered panel closes when the pointer leaves", kind: "toggle", default: true, when: { open_on_hover: [true] } },
        { key: "hover_highlight", label: "Components light up on hover", kind: "toggle", default: true },
        { key: "hide_delay_ms", label: "Hides this long after the pointer leaves (ms)", kind: "int", default: 350, from: 0, to: 3000, step: 50, when: { visibility: ["smart", "autohide"] } },
        { key: "reveal_on_switch", label: "Shows briefly on a workspace switch", kind: "toggle", default: true, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "reference", label: "Its stretch of the edge", kind: "choice", default: "output", options: [{ key: "output", label: "The whole edge" }, { key: "workspace", label: "Clear of bars on the neighbouring edges" }] },
        { adv: true, key: "layer", label: "Stacking", kind: "choice", default: "top", options: [{ key: "bottom", label: "Under windows" }, { key: "top", label: "Above windows" }, { key: "overlay", label: "Above everything" }] },
        { adv: true, key: "margin_opposite", label: "Extra room kept on its inner side", kind: "int", default: 0, from: 0, to: 200, step: 1, when: { reserve: [true] } },
        { adv: true, key: "reveal_length", label: "Summoned along this much of the edge (0 = its own length)", kind: "int", default: 480, from: 0, to: 3840, step: 10, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "reveal_size", label: "That strip's depth", kind: "int", default: 3, from: 1, to: 24, step: 1, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "reveal_on_switch_ms", label: "Shows on a switch for (ms)", kind: "int", default: 1200, from: 200, to: 5000, step: 100, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "hover_close_delay", label: "Leave before a hovered panel closes (ms)", kind: "int", default: 300, from: 0, to: 3000, step: 25, when: { open_on_hover: [true] } },
        { adv: true, key: "panel_overlap", label: "A floating panel tucks under its edge by", kind: "int", default: 0, from: -2, to: 12, step: 1 }
    ]
}
