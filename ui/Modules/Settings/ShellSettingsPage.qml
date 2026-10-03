import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Everything the native shell keeps — its own settings registry, section by section, drawn here from what it
// says about each setting (settings-schema) and written back as the native Settings window would
// (settings-set / settings-reset: ConfigService overrides in settings.toml, validated by its schema). Nothing
// is copied by hand, so nothing is lost or drifts. A section whose surface Zynith now draws says so and points
// to Zynith's own page; the few settings that are whole editors (keybinds, idle behaviours, notification
// filters) open the native Settings at their section.
Column {
    id: root
    spacing: Metrics.s5

    property var sections: []
    property string current: ""
    property var entries: []
    property bool loading: false
    property string query: ""
    property bool advanced: false
    property string message: ""

    // native sections whose surface the Zynith UI draws when zynith.toml [surfaces] says so
    readonly property var zynithOwned: ({
            bar: { surface: "bar", route: "bars", label: "Bars" },
            launcher: { surface: "launcher", route: "launcher", label: "Launcher" },
            "control-center": { surface: "control_center", route: "control", label: "Control Panel" },
            notifications: { surface: "notifications", route: "notifications", label: "Notifications" },
            osd: { surface: "osd", route: "osd", label: "On-screen display" },
            desktop: { surface: "desktop_widgets", route: "widgets", label: "Desktop widgets" }
        })
    function ownedByZynith(id: string): var {
        const o = zynithOwned[id];
        return o && (Config.surfaces?.[o.surface] ?? "native") === "zynith" ? o : null;
    }

    signal navigate(string route)

    function readSections(): void {
        CoreClient.call("settings-schema", text => {
            try {
                root.sections = JSON.parse(text).sections.filter(s => s.count > 0);
                if (root.current === "" && root.sections.length > 0)
                    root.open(root.sections[0].id);
            } catch (e) {
                root.message = "The native shell did not answer (is it running, and new enough?)";
            }
        });
    }
    function open(id: string): void {
        flush();
        current = id;
        shape = "";
        read();
    }
    // the values live apart from the structure: a write updates them in place, and the page is rebuilt only
    // when the settings themselves change (one appears, an option list changes), never mid-drag
    property var values: ({})
    property var overridden: ({})
    property string shape: ""
    function read(): void {
        if (current === "")
            return;
        loading = true;
        const want = current;
        CoreClient.call("settings-schema " + want, text => {
            if (want !== root.current)
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
    Component.onCompleted: readSections()

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
    readonly property var visibleEntries: entries.filter(e => e.visible !== false && (advanced || !e.advanced) && (query === "" || (e.title + " " + e.subtitle + " " + e.groupLabel).toLowerCase().includes(query.toLowerCase())))
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

    PanelHeader {
        width: parent.width
        title: "Shell settings"
        caption: "Everything the native shell keeps, written as its own Settings would"
    }

    // ── sections ──
    Flow {
        width: parent.width
        spacing: Metrics.s2
        Repeater {
            model: root.sections
            delegate: Chip {
                required property var modelData
                text: modelData.label
                count: modelData.count
                active: root.current === modelData.id
                onClicked: root.open(modelData.id)
            }
        }
    }
    Label {
        visible: root.message !== ""
        width: parent.width
        role: "label"
        tone: "danger"
        wrapMode: Text.WordWrap
        text: root.message
    }

    // ── a surface Zynith draws now ──
    Card {
        readonly property var owned: root.ownedByZynith(root.current)
        visible: owned !== null
        width: parent.width
        Label {
            width: parent.width
            role: "body"
            wrapMode: Text.WordWrap
            text: "Zynith draws the " + (parent.owned?.label ?? "").toLowerCase() + " now, so these settings shape the native one, which is off. Zynith's own are in Settings → " + (parent.owned?.label ?? "") + "."
        }
        Chip {
            icon: "chevron-right"
            text: "Open " + (parent.owned?.label ?? "")
            onClicked: root.navigate(parent.owned.route)
        }
    }

    // ── filter ──
    Row {
        width: parent.width
        spacing: Metrics.s3
        Rectangle {
            width: parent.width - advancedRow.width - Metrics.s3
            height: 34
            radius: Metrics.radiusMd
            color: Theme.well
            border.width: Metrics.hairline
            border.color: filter.activeFocus ? Theme.accentLine : Theme.hairline
            TextInput {
                id: filter
                anchors.fill: parent
                anchors.leftMargin: Metrics.s3
                anchors.rightMargin: Metrics.s3
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.ink
                font.family: Type.ui
                font.pixelSize: Type.label
                clip: true
                onTextChanged: root.query = text
                Label {
                    visible: filter.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    tone: "faint"
                    text: "Filter this section"
                }
            }
        }
        Row {
            id: advancedRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.s2
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                tone: "muted"
                text: "Advanced"
            }
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: root.advanced
                onToggled: root.advanced = !root.advanced
            }
        }
    }

    Label {
        visible: !root.loading && root.groups.length === 0 && root.current !== ""
        role: "label"
        tone: "faint"
        text: root.query !== "" ? "Nothing here matches" : "Nothing to set here"
    }

    // ── the settings, by group ──
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
                    readonly property var entry: modelData
                    width: parent.width
                    schema: root.specsOf(entry)
                    valueOf: key => root.values[key]
                    isSet: key => root.overridden[key] === true
                    onChanged: (key, value) => {
                        if (form.entry.kind === "native" || form.entry.kind === undefined) {
                            CoreClient.call("settings-open " + root.current, () => {});
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
