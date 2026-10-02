pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// The desktop widgets' edit state: whether the editor is open, what is selected, a draft of the geometry
// being dragged (written to widgets.toml once, on release), copy and paste, undo and redo. widgets.toml is
// the one source of truth; every change here goes through Config.setWidgets.
Singleton {
    id: root

    property bool editing: false
    property var selection: []          // widget ids
    property var draft: ({})            // id -> { cx, cy, width, height, rotation } while a gesture lasts
    property bool snap: true
    readonly property int grid: 16
    property bool inspecting: false     // the inspector card
    property bool picking: false        // the add-widget picker

    readonly property var widgets: Config.widgets
    function byId(id: string): var {
        return widgets.find(w => w.id === id) ?? null;
    }
    readonly property var selected: selection.length === 1 ? byId(selection[0]) : null

    // ── edit mode ────────────────────────────────────────────────────────────
    function setEditing(on: bool): void {
        if (editing === on)
            return;
        editing = on;
        if (!on) {
            selection = [];
            draft = {};
            inspecting = false;
            picking = false;
        }
    }
    function toggleEditing(): void {
        if (editing)
            close();
        else
            setEditing(true);
    }
    // leaving plays the editor's exit first
    property bool closing: false
    function close(): void {
        if (!editing || closing)
            return;
        closing = true;
        closeTimer.restart();
    }
    Timer {
        id: closeTimer
        interval: Motion.exit + 80
        onTriggered: {
            root.closing = false;
            root.setEditing(false);
        }
    }
    // widgets on their way out, drawn shrinking before the removal is written
    property var removing: []
    function removeAnimated(ids: var): void {
        if (ids.length === 0)
            return;
        removing = removing.concat(ids);
        removeTimer.ids = ids;
        removeTimer.restart();
    }
    Timer {
        id: removeTimer
        property var ids: []
        interval: Motion.exit
        onTriggered: {
            root.remove(ids);
            root.removing = root.removing.filter(i => !ids.includes(i));
        }
    }

    function select(id: string, additive: bool): void {
        if (additive)
            selection = selection.includes(id) ? selection.filter(s => s !== id) : selection.concat([id]);
        else
            selection = [id];
    }
    function clearSelection(): void {
        selection = [];
        inspecting = false;
    }

    // ── changes (each one undoable) ─────────────────────────────────────────
    property var undoStack: []
    property var redoStack: []
    function commit(list: var): void {
        undoStack = undoStack.concat([JSON.stringify(widgets)]).slice(-50);
        redoStack = [];
        Config.setWidgets(list);
    }
    function undo(): void {
        if (undoStack.length === 0)
            return;
        redoStack = redoStack.concat([JSON.stringify(widgets)]);
        const prev = JSON.parse(undoStack[undoStack.length - 1]);
        undoStack = undoStack.slice(0, -1);
        Config.setWidgets(prev);
    }
    function redo(): void {
        if (redoStack.length === 0)
            return;
        undoStack = undoStack.concat([JSON.stringify(widgets)]);
        const next = JSON.parse(redoStack[redoStack.length - 1]);
        redoStack = redoStack.slice(0, -1);
        Config.setWidgets(next);
    }

    function patch(ids: var, change: var): void {
        commit(widgets.map(w => ids.includes(w.id) ? Object.assign({}, w, typeof change === "function" ? change(w) : change) : w));
    }
    function setSetting(id: string, key: string, value: var): void {
        commit(widgets.map(w => w.id === id ? Object.assign({}, w, {
                settings: Object.assign({}, w.settings ?? {}, {
                    [key]: value
                })
            }) : w));
    }
    function resetSettings(id: string): void {
        commit(widgets.map(w => w.id === id ? Object.assign({}, w, {
                settings: {}
            }) : w));
    }

    // a new id like the native ones: 16 hex digits
    function newId(): string {
        let s = "";
        for (let i = 0; i < 16; i++)
            s += Math.floor(Math.random() * 16).toString(16);
        return s;
    }

    // a new widget of `type`, centred where asked, on that output and in its pixels
    function add(type: string, output: string, cx: real, cy: real, screenW: real, screenH: real): string {
        const t = WidgetTypes.find(type);
        if (!t)
            return "";
        const id = newId();
        commit(widgets.concat([{
                id: id,
                type: t.type,
                output: output,
                cx: snapped(cx),
                cy: snapped(cy),
                width: t.size[0],
                height: t.size[1],
                rotation: 0,
                flip: false,
                reference: [screenW, screenH],
                settings: {}
            }]));
        selection = [id];
        return id;
    }
    function remove(ids: var): void {
        commit(widgets.filter(w => !ids.includes(w.id)));
        selection = selection.filter(s => !ids.includes(s));
    }
    function clone(ids: var): void {
        const copies = widgets.filter(w => ids.includes(w.id)).map(w => Object.assign(JSON.parse(JSON.stringify(w)), {
                id: newId(),
                cx: w.cx + 32,
                cy: w.cy + 32
            }));
        commit(widgets.concat(copies));
        selection = copies.map(c => c.id);
    }
    // order in the list is paint order: last is on top
    function toFront(ids: var): void {
        commit(widgets.filter(w => !ids.includes(w.id)).concat(widgets.filter(w => ids.includes(w.id))));
    }
    function toBack(ids: var): void {
        commit(widgets.filter(w => ids.includes(w.id)).concat(widgets.filter(w => !ids.includes(w.id))));
    }
    function flip(ids: var): void {
        patch(ids, w => ({
                flip: !w.flip
            }));
    }
    function toggleHidden(ids: var): void {
        patch(ids, w => ({
                hidden: !w.hidden
            }));
    }

    property var clipboard: []
    function copy(ids: var): void {
        clipboard = widgets.filter(w => ids.includes(w.id)).map(w => JSON.parse(JSON.stringify(w)));
    }
    function paste(output: string): void {
        if (clipboard.length === 0)
            return;
        const copies = clipboard.map(w => Object.assign(JSON.parse(JSON.stringify(w)), {
                id: newId(),
                output: output || w.output,
                cx: w.cx + 32,
                cy: w.cy + 32
            }));
        commit(widgets.concat(copies));
        selection = copies.map(c => c.id);
    }

    // ── gestures: a draft while the pointer is down, one write when it lifts ──
    function setDraft(id: string, geometry: var): void {
        const d = Object.assign({}, draft);
        d[id] = Object.assign({}, d[id] ?? {}, geometry);
        draft = d;
    }
    function commitDraft(): void {
        const d = draft;
        if (Object.keys(d).length === 0)
            return;
        draft = {};
        commit(widgets.map(w => d[w.id] ? Object.assign({}, w, d[w.id]) : w));
    }
    function cancelDraft(): void {
        draft = {};
    }
    // geometry as shown: the draft over the stored widget
    function geometry(w: var): var {
        return Object.assign({
            cx: w.cx ?? 0,
            cy: w.cy ?? 0,
            width: w.width ?? 0,
            height: w.height ?? 0,
            rotation: w.rotation ?? 0
        }, draft[w.id] ?? {});
    }
    function snapped(v: real): real {
        return snap ? Math.round(v / grid) * grid : v;
    }

    // keys: nudge the selection
    function nudge(dx: real, dy: real): void {
        if (selection.length > 0)
            patch(selection, w => ({
                    cx: (w.cx ?? 0) + dx,
                    cy: (w.cy ?? 0) + dy
                }));
    }
}
