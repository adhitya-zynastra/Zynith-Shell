pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/BarModel.js" as BarModel

// Every change to the bars goes through here: one BarModel edit, written in one atomic step (the bars and the
// component tables they name together), with the state before it kept so it can be undone. The history lives in
// this process (Settings has its own, `zynith-ui cmd bars` the shell's); bars.toml.pre-schema-<n> and the
// recovery copies are the lasting safety net.
Singleton {
    id: root

    readonly property var state: Config.barState
    // [{ label, before }] newest last
    property var history: []
    readonly property int depth: 30
    readonly property bool canUndo: history.length > 0
    readonly property string undoLabel: canUndo ? history[history.length - 1].label : ""
    // the last thing done (for a page to say so), and when
    property string lastLabel: ""
    property int revision: 0

    function commit(next: var, label: string): bool {
        if (next === state || JSON.stringify(next) === JSON.stringify(state))
            return false;
        if (Config.barsError !== "") {
            console.warn("zynith: bars.toml has an error; not changing it:", Config.barsError);
            return false;
        }
        const before = JSON.parse(JSON.stringify(state));
        if (!Config.applyBars(next))
            return false;
        const h = history.concat([{ label: label, before: before }]);
        history = h.length > depth ? h.slice(h.length - depth) : h;
        lastLabel = label;
        revision++;
        return true;
    }
    function undo(): string {
        if (!canUndo)
            return "";
        const last = history[history.length - 1];
        if (!Config.applyBars(last.before))
            return "";
        history = history.slice(0, -1);
        lastLabel = "Undid: " + last.label;
        revision++;
        return last.label;
    }

    // ── a value being dragged: shown on the bar at once, written only when let go ──
    // The preview travels through a small file in XDG_RUNTIME_DIR (memory, not disk), which the shell watches
    // (Config.barPreview): Settings is a process of its own. Nothing goes to bars.toml and nothing enters the
    // undo history until the release (setKey), which then ends the preview.
    function preview(id: string, key: string, value: var): void {
        previewFile.setText(JSON.stringify({ id: id, key: key, value: value, seq: ++previewSeq }));
    }
    function endPreview(id: string, key: string, value: var, cancel: bool): void {
        previewFile.setText(JSON.stringify({ ended: { id: id, key: key, value: value, cancel: cancel === true }, seq: ++previewSeq }));
    }
    // the same for one setting of a component instance ([widget.<name>])
    function previewComponent(name: string, key: string, value: var): void {
        previewFile.setText(JSON.stringify({ widget: name, key: key, value: value, seq: ++previewSeq }));
    }
    function endComponentPreview(name: string, key: string, value: var, cancel: bool): void {
        previewFile.setText(JSON.stringify({ ended: { widget: name, key: key, value: value, cancel: cancel === true }, seq: ++previewSeq }));
    }
    property int previewSeq: 0
    property FileView previewFile: FileView {
        path: Paths.runtime + "/bar-preview.json"
        printErrors: false
        blockLoading: true
    }

    // ── the operations, by bar id ──
    function create(position: var, name: string): string {
        const r = BarModel.create(state, position ?? {}, name);
        return commit(r.state, "New bar " + BarModel.find(r.state, r.id).name) ? r.id : "";
    }
    function rename(id: string, name: string): void {
        commit(BarModel.rename(state, id, name), "Rename");
    }
    function duplicate(id: string): string {
        const r = BarModel.duplicate(state, id);
        return commit(r.state, "Duplicate " + (BarModel.find(state, id)?.name ?? "")) ? r.id : "";
    }
    function remove(id: string): void {
        const name = BarModel.find(state, id)?.name ?? "";
        commit(BarModel.remove(state, id).state, "Delete " + name);
    }
    function setEnabled(id: string, on: bool): void {
        commit(BarModel.setEnabled(state, id, on), (on ? "Show " : "Hide ") + (BarModel.find(state, id)?.name ?? ""));
    }
    function move(id: string, by: int): void {
        commit(BarModel.move(state, id, by), "Reorder");
    }
    function place(id: string, edge: string, anchor: string): void {
        commit(BarModel.place(state, id, edge, anchor), "Move " + (BarModel.find(state, id)?.name ?? "") + " to " + BarModel.positionLabel({ edge: edge, anchor: anchor }));
    }
    function setKey(id: string, key: string, value: var): void {
        commit(BarModel.setKey(state, id, key, value), "Change " + key.replace(/_/g, " "));
    }
    function reset(id: string): void {
        commit(BarModel.reset(state, id), "Reset " + (BarModel.find(state, id)?.name ?? ""));
    }
    function addComponent(id: string, section: string, type: string): void {
        commit(BarModel.addComponent(state, id, section, type), "Add " + type.replace(/[_-]/g, " "));
    }
    function addGroup(id: string, section: string, groupId: string): void {
        const bar = BarModel.find(state, id);
        if (!bar)
            return;
        const w = Object.assign({}, bar.widgets ?? {});
        w[section] = (w[section] ?? []).concat(["group:" + groupId]);
        commit(BarModel.setKey(state, id, "widgets", w), "Add group " + groupId);
    }
    function removeComponent(id: string, section: string, index: int): void {
        commit(BarModel.removeComponent(state, id, section, index), "Remove a component");
    }
    function moveComponent(id: string, section: string, index: int, by: int): void {
        commit(BarModel.moveComponent(state, id, section, index, by), "Reorder components");
    }
    function separate(id: string, section: string, index: int): void {
        commit(BarModel.separate(state, id, section, index), "Give the component its own settings");
    }
    // one setting of one component instance ([widget.<name>]); undefined puts its default back
    function setComponentKey(name: string, key: string, value: var): void {
        const widgets = Object.assign({}, state.widgets ?? {});
        const table = Object.assign({}, widgets[name] ?? {});
        if (value === undefined)
            delete table[key];
        else
            table[key] = value;
        widgets[name] = table;
        commit({ bars: state.bars, widgets: widgets }, "Change " + key.replace(/_/g, " "));
    }
    function setComponentAction(name: string, gesture: string, action: var): void {
        const widgets = Object.assign({}, state.widgets ?? {});
        const table = Object.assign({}, widgets[name] ?? {});
        const actions = Object.assign({}, table.actions ?? {});
        if (action === undefined)
            delete actions[gesture];
        else
            actions[gesture] = action;
        table.actions = actions;
        widgets[name] = table;
        commit({ bars: state.bars, widgets: widgets }, "Change what " + gesture.replace(/_/g, " ") + " does");
    }
    // presets: mode "add" | "replace" (replace turns the bars there were off; nothing is deleted)
    function applyPreset(key: string, mode: string): var {
        const preset = BarModel.presetByKey(key, Config.barPresets);
        if (!preset)
            return [];
        const r = BarModel.applyPreset(state, preset, mode);
        return commit(r.state, (mode === "replace" ? "Switch to " : "Add ") + preset.label) ? r.ids : [];
    }
    function savePreset(barIds: var, label: string): bool {
        const clean = String(label ?? "").trim();
        if (clean === "" || barIds.length === 0)
            return false;
        const list = BarModel.list(Config.barPresets);
        const key = "custom-" + Date.now().toString(36);
        return Config.setBarPresets(list.concat([BarModel.presetFrom(state, barIds, clean, key)]));
    }
    function removePreset(key: string): bool {
        return Config.setBarPresets(BarModel.list(Config.barPresets).filter(p => p.key !== key));
    }
}
