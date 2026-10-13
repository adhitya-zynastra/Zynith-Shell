import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// One section of the native shell's own settings registry (or some of its groups), drawn from what it says
// about each setting (settings-schema) and written back as the native Settings window would (settings-set /
// settings-reset: ConfigService overrides in settings.toml, validated by its schema). Nothing is copied by
// hand, so nothing is lost or drifts. Used as a page of its own and under Zynith's pages.
Column {
    id: root
    spacing: Metrics.s4

    property string section: ""
    // only these groups (by label); empty: all
    property var groupFilter: []
    property string query: ""
    property bool advanced: false
    property string message: ""
    property var entries: []
    property bool loading: false
    readonly property int count: visibleEntries.length

    // the values live apart from the structure: a write updates them in place, and the page is rebuilt only
    // when the settings themselves change (one appears, an option list changes), never mid-drag
    property var values: ({})
    property var overridden: ({})
    property string shape: ""
    function read(): void {
        if (section === "")
            return;
        loading = true;
        const want = section;
        CoreClient.call("settings-schema " + want, text => {
            if (want !== root.section)
                return;
            let list = [];
            try {
                list = JSON.parse(text).entries;
            } catch (e) {}
            const vals = {}, over = {};
            for (const e of list) {
                vals[root.keyOf(e.path)] = e.kind === "range" ? e.low : e.value;
                if (e.kind === "range")
                    vals[root.keyOf(e.highPath, true)] = e.high;
                over[root.keyOf(e.path)] = e.overridden === true;
            }
            // what is pending a write keeps what was just chosen
            for (const k in root.pending)
                vals[k] = root.pending[k].value;
            const nextShape = JSON.stringify(list.map(e => [e.path, e.kind, e.visible, e.advanced, (e.options ?? []).length, e.title]));
            if (nextShape !== root.shape) {
                root.shape = nextShape;
                root.entries = list;
            }
            root.values = vals;
            root.overridden = over;
            root.loading = false;
        });
    }
    Component.onCompleted: read()
    onSectionChanged: {
        shape = "";
        read();
    }

    // ── one native setting as a SchemaForm row ──
    function keyOf(path: var, high: bool): string {
        return JSON.stringify(path) + (high ? "#high" : "");
    }
    function specsOf(e: var): var {
        const base = {
            label: e.title,
            hint: e.subtitle
        };
        const opts = (e.options ?? []).map(o => ({ key: String(o.value), label: o.label }));
        switch (e.kind) {
        case "toggle":
            return [Object.assign(base, { key: keyOf(e.path), kind: "toggle", value: e.value })];
        case "select":
            // a font family: the font picker (every installed family, each in its own face), not a list of names
            if (String(e.path[e.path.length - 1]).endsWith("font_family"))
                return [Object.assign(base, { key: keyOf(e.path), kind: "font", placeholder: "The system font", value: String(e.value ?? "") })];
            return [Object.assign(base, {
                    key: keyOf(e.path),
                    kind: opts.length <= 4 && !e.search ? "choice" : opts.length <= 14 && !e.search ? "select" : "pick",
                    options: opts,
                    value: String(e.value)
                })];
        case "slider":
            return [Object.assign(base, { key: keyOf(e.path), kind: e.integer ? "int" : "slider", from: e.min, to: e.max, step: e.step || (e.integer ? 1 : 0.01), value: e.value })];
        case "stepper":
            return [Object.assign(base, { key: keyOf(e.path), kind: "int", from: e.min, to: e.max, step: e.step || 1, value: e.value ?? e.fallback ?? e.min })];
        case "range":
            return [Object.assign({}, base, { key: keyOf(e.path), label: e.title + " · from", kind: e.integer ? "int" : "slider", from: e.min, to: e.max, step: e.step || 1, value: e.low }), { key: keyOf(e.highPath, true), label: e.title + " · to", kind: e.integer ? "int" : "slider", from: e.min, to: e.max, step: e.step || 1, value: e.high }];
        case "text":
            return [Object.assign(base, { key: keyOf(e.path), kind: e.browse !== "" ? "path" : "text", browse: e.browse, placeholder: e.placeholder, default: e.placeholder, value: e.value })];
        case "number":
            return [Object.assign(base, { key: keyOf(e.path), kind: "number", placeholder: e.placeholder, value: e.value })];
        case "list":
            return [Object.assign(base, { key: keyOf(e.path), kind: opts.length > 0 ? "multi" : "list", options: opts, value: e.value })];
        case "multi":
            return [Object.assign(base, { key: keyOf(e.path), kind: "multi", options: opts, value: e.value })];
        case "color":
            return [Object.assign(base, { key: keyOf(e.path), kind: "colour", roles: e.roles, value: e.value })];
        default:
            return [Object.assign(base, { key: keyOf(e.path), kind: "button", action: "Edit in the native Settings", value: null, native: true })];
        }
    }
    readonly property var visibleEntries: entries.filter(e => e.visible !== false && (advanced || !e.advanced) && (groupFilter.length === 0 || groupFilter.includes(e.groupLabel)) && (query === "" || (e.title + " " + e.subtitle + " " + e.groupLabel).toLowerCase().includes(query.toLowerCase())))
    readonly property var groups: {
        const out = [];
        for (const e of visibleEntries) {
            const label = e.groupLabel || "General";
            let g = out.find(x => x.label === label);
            if (!g) {
                g = { label: label, entries: [] };
                out.push(g);
            }
            g.entries.push(e);
        }
        return out;
    }

    // a change shows at once and is written a moment after the last one (a slider drag is one write)
    property var pending: ({})
    function write(e: var, high: bool, value: var): void {
        const key = keyOf(high ? e.highPath : e.path, high);
        values = Object.assign({}, values, { [key]: value });
        pending = Object.assign({}, pending, { [key]: { title: e.title, path: high ? e.highPath : e.path, value: value } });
        settle.restart();
    }
    Timer {
        id: settle
        interval: 280
        onTriggered: root.flush()
    }
    function flush(): void {
        const batch = pending;
        pending = {};
        let left = Object.keys(batch).length;
        for (const k in batch) {
            const w = batch[k];
            CoreClient.call("settings-set " + JSON.stringify({ path: w.path, value: w.value }), reply => {
                if (reply.startsWith("error"))
                    root.message = w.title + ": " + reply.slice(7).trim();
                if (--left === 0)
                    root.read();
            });
        }
    }
    Component.onDestruction: flush()
    function reset(e: var, high: bool): void {
        CoreClient.call("settings-reset " + JSON.stringify({ path: high ? e.highPath : e.path }), reply => {
            root.message = reply.startsWith("error") ? e.title + ": " + reply.slice(7).trim() : "";
            root.read();
        });
    }


    Label {
        visible: root.message !== ""
        width: parent.width
        role: "label"
        tone: "danger"
        wrapMode: Text.WordWrap
        text: root.message
    }
    Label {
        visible: !root.loading && root.groups.length === 0 && root.section !== ""
        role: "label"
        tone: "faint"
        text: root.query !== "" ? "Nothing here matches" : "Nothing to set here"
    }

    // ── the settings, by group: a card each, rows as the native Settings lists them ──
    Repeater {
        model: root.groups
        delegate: Card {
            id: group
            required property var modelData
            width: root.width
            caption: modelData.label

            Repeater {
                model: group.modelData.entries
                delegate: SchemaForm {
                    id: form
                    required property var modelData
                    required property int index
                    readonly property var entry: modelData
                    width: parent.width
                    divided: index < group.modelData.entries.length - 1
                    schema: root.specsOf(entry)
                    valueOf: key => root.values[key]
                    isSet: key => root.overridden[key] === true
                    onChanged: (key, value) => {
                        if (form.entry.kind === "native" || form.entry.kind === undefined) {
                            CoreClient.call("settings-open " + root.section, () => {});
                            return;
                        }
                        const high = key.endsWith("#high");
                        let v = value;
                        if (form.entry.kind === "select" && form.entry.valueType === "int")
                            v = Number(value);
                        else if (form.entry.kind === "select" && form.entry.valueType === "bool")
                            v = value === "true";
                        else if (form.entry.kind === "list" || form.entry.kind === "multi")
                            v = Array.from(value);
                        root.message = "";
                        root.write(form.entry, high, v);
                    }
                    onCleared: key => root.reset(form.entry, key.endsWith("#high"))
                }
            }
        }
    }
}
