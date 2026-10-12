import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Every bar, and everything about it: where it sits, its size and look, its widgets (each with its own
// settings and what its clicks and scrolls do), its capsule groups and its empty space. Changes apply live;
// bars.toml is the file underneath.
Column {
    id: root

    spacing: Metrics.s5

    property int selected: 0
    readonly property var bar: Config.bars[Math.min(selected, Config.bars.length - 1)] ?? null
    readonly property int barIndex: Math.min(selected, Config.bars.length - 1)
    property string openWidget: ""      // "section:index" of the entry whose settings show
    property string adding: ""          // the section the catalogue adds to

    function setBar(key: string, value: var): void {
        Config.updateBar(barIndex, key, value);
    }
    function sectionList(section: string): var {
        return (bar?.widgets?.[section] ?? []).slice();
    }
    function setSection(section: string, list: var): void {
        const w = Object.assign({}, bar?.widgets ?? {});
        w[section] = list;
        setBar("widgets", w);
    }
    function move(section: string, index: int, delta: int): void {
        const list = sectionList(section);
        const to = index + delta;
        if (to < 0 || to >= list.length)
            return;
        const [item] = list.splice(index, 1);
        list.splice(to, 0, item);
        setSection(section, list);
        openWidget = "";
    }
    function moveToSection(section: string, index: int, target: string): void {
        const from = sectionList(section);
        const [item] = from.splice(index, 1);
        const w = Object.assign({}, bar?.widgets ?? {});
        w[section] = from;
        w[target] = (w[target] ?? []).concat([item]);
        setBar("widgets", w);
        openWidget = "";
    }
    function removeEntry(section: string, index: int): void {
        const list = sectionList(section);
        list.splice(index, 1);
        setSection(section, list);
        openWidget = "";
    }
    function addEntry(section: string, type: string): void {
        // a kind already on this bar gets a copy of its own, so the two can differ
        const used = ["start", "center", "end"].some(s => sectionList(s).includes(type));
        let name = type;
        if (used) {
            let n = 2;
            while (Config.barWidgets[type + "-" + n] !== undefined)
                n++;
            name = type + "-" + n;
            Config.setBarWidget(name, {
                type: type
            });
        }
        setSection(section, sectionList(section).concat([name]));
        adding = "";
    }
    // a shared widget becomes this bar's own: a copy of its settings under a new name
    function separate(section: string, index: int, name: string): void {
        const spec = Config.resolveBarWidget(name);
        let n = 2;
        while (Config.barWidgets[spec.type + "-" + n] !== undefined)
            n++;
        const copy = spec.type + "-" + n;
        Config.setBarWidget(copy, Object.assign({
            type: spec.type
        }, spec.settings, Object.keys(spec.actions).length ? {
            actions: spec.actions
        } : {}));
        const list = sectionList(section);
        list[index] = copy;
        setSection(section, list);
        openWidget = section + ":" + index;
    }
    function usedBy(name: string): int {
        return Config.bars.filter(b => ["start", "center", "end"].some(s => (b.widgets?.[s] ?? []).includes(name)) || (b.group ?? []).some(g => (g.members ?? []).includes(name))).length;
    }

    readonly property var presets: [
        { label: "Top bar", spec: { id: "top", edge: "top", anchor: "fill", margin: 6, thickness: 34, reserve: true, layer: "top", visibility: "always", widgets: { start: ["launcher", "workspaces"], center: ["clock"], end: ["tray", "network", "volume", "battery", "control-center"] } } },
        { label: "Bottom dock", spec: { id: "dock", edge: "bottom", anchor: "center", margin: 8, thickness: 52, reserve: false, layer: "top", visibility: "smart", widgets: { center: ["taskbar"] } } },
        { label: "Left rail", spec: { id: "left", edge: "left", anchor: "fill", margin: 8, thickness: 40, reserve: true, layer: "top", visibility: "always", widgets: { start: ["launcher"], center: ["workspaces"], end: ["clock", "session"] } } },
        { label: "Right rail", spec: { id: "right", edge: "right", anchor: "fill", margin: 8, thickness: 40, reserve: true, layer: "top", visibility: "always", widgets: { center: ["workspaces"] } } },
        { label: "Floating clock", spec: { id: "float", edge: "top", anchor: "center", margin: 8, thickness: 34, reserve: false, layer: "overlay", visibility: "smart", widgets: { center: ["clock"] } } }
    ]
    function addBar(spec: var): void {
        const ids = Config.bars.map(b => b.id);
        let id = spec.id, n = 2;
        while (ids.includes(id))
            id = spec.id + "-" + n++;
        Config.setBars(Config.bars.concat([Object.assign({}, spec, {
                id: id,
                screens: ["*"]
            })]));
        selected = Config.bars.length - 1;
    }

    // ── which bar ──────────────────────────────────────────────────────────────
    PanelHeader {
        width: parent.width
        title: "Bars"
        caption: Config.bars.length + (Config.bars.length === 1 ? " bar" : " bars") + " · edit any of them; the changes show at once"
    }
    Flow {
        width: parent.width
        spacing: Metrics.s2
        Repeater {
            model: Config.bars
            delegate: Chip {
                required property var modelData
                required property int index
                icon: ({ top: "layout-navbar", bottom: "layout-bottombar", left: "layout-sidebar", right: "layout-sidebar-right" })[modelData.edge ?? "top"]
                text: (modelData.id ?? ("bar " + index)) + (modelData.enabled === false ? " (off)" : "")
                active: root.barIndex === index
                onClicked: {
                    root.selected = index;
                    root.openWidget = "";
                }
            }
        }
        Repeater {
            model: root.presets
            delegate: Chip {
                required property var modelData
                icon: "plus"
                text: modelData.label
                onClicked: root.addBar(modelData.spec)
            }
        }
    }

    Loader {
        width: parent.width
        active: root.bar !== null
        sourceComponent: Column {
            spacing: Metrics.s5

            Card {
                width: parent.width
                caption: "Where"
                SchemaForm {
                    width: parent.width
                    schema: [
                        { key: "enabled", label: "Shown", kind: "toggle", default: true },
                        { key: "edge", label: "Edge", kind: "choice", default: "top", options: [{ key: "top", label: "Top" }, { key: "bottom", label: "Bottom" }, { key: "left", label: "Left" }, { key: "right", label: "Right" }] },
                        { key: "anchor", label: "Along it", kind: "choice", default: "center", options: [{ key: "start", label: "Start" }, { key: "center", label: "Centre" }, { key: "end", label: "End" }, { key: "fill", label: "Full length" }] },
                        { key: "visibility", label: "Shows", kind: "choice", default: "always", options: [{ key: "always", label: "Always" }, { key: "smart", label: "When the desktop is clear" }, { key: "autohide", label: "On hover at the edge" }] },
                        { key: "layer", label: "Layer", kind: "choice", default: "top", options: [{ key: "bottom", label: "Under windows" }, { key: "top", label: "Above windows" }, { key: "overlay", label: "Above everything" }] },
                        { key: "reserve", label: "Windows keep clear of it", kind: "toggle", default: false },
                        { key: "margin_opposite", label: "Extra room kept on its inner side", kind: "int", default: 0, from: 0, to: 200, step: 1, when: { reserve: [true] } },
                        { key: "reveal_length", label: "Summoned along this much of the edge (0 = its own length)", kind: "int", default: 480, from: 0, to: 3840, step: 10, when: { visibility: ["smart", "autohide"] } },
                        { key: "reveal_size", label: "That strip's depth", kind: "int", default: 3, from: 1, to: 24, step: 1, when: { visibility: ["smart", "autohide"] } },
                        { key: "hide_delay_ms", label: "Hides this long after the pointer leaves (ms)", kind: "int", default: 350, from: 0, to: 3000, step: 50, when: { visibility: ["smart", "autohide"] } },
                        { key: "reveal_on_switch", label: "Shows briefly on a workspace switch", kind: "toggle", default: true, when: { visibility: ["smart", "autohide"] } },
                        { key: "reveal_on_switch_ms", label: "For (ms)", kind: "int", default: 1200, from: 200, to: 5000, step: 100, when: { visibility: ["smart", "autohide"] } },
                        { key: "reference", label: "Centred against", kind: "choice", default: "output", options: [{ key: "output", label: "The whole screen" }, { key: "workspace", label: "What other bars leave" }] },
                        { key: "panel_overlap", label: "Panels tuck under its edge by", kind: "int", default: 0, from: -2, to: 12, step: 1 },
                        { key: "screens", label: "Screens", kind: "list", default: ["*"], hint: "* is every screen; or output names, e.g. eDP-1" }
                    ]
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => root.setBar(key, value)
                    shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(root.bar?.[k] ?? schema.find(s => s.key === k)?.default))
                    onCleared: key => Config.clearBarKey(root.barIndex, key)
                }
            }

            Card {
                width: parent.width
                caption: "Size"
                SchemaForm {
                    width: parent.width
                    schema: [
                        { key: "thickness", label: "Thickness", kind: "int", default: 34, from: 20, to: 96, step: 1 },
                        { key: "length", label: "Length (0 fits the widgets)", kind: "int", default: 0, from: 0, to: 3840, step: 10 },
                        { key: "margin", label: "From the screen edge", kind: "int", default: 0, from: 0, to: 64, step: 1 },
                        { key: "offset", label: "From the ends", kind: "int", default: 0, from: 0, to: 3840, step: 2 },
                        { key: "padding", label: "Inner padding", kind: "int", default: 12, from: 0, to: 40, step: 1 },
                        { key: "spacing", label: "Between widgets (-1 follows the theme)", kind: "int", default: -1, from: -1, to: 24, step: 1 }
                    ]
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => root.setBar(key, value)
                    onCleared: key => Config.clearBarKey(root.barIndex, key)
                }
            }

            Card {
                width: parent.width
                caption: "Look"
                SchemaForm {
                    width: parent.width
                    schema: [
                        { key: "opacity", label: "Opacity (0 follows the profile)", kind: "slider", default: 0, from: 0, to: 1, step: 0.01 },
                        { key: "radius", label: "Corner radius (-1 is a pill)", kind: "int", default: -1, from: -1, to: 48, step: 1 },
                        // each corner on its own (the native per-corner radii); left out, the radius above
                        { key: "radius_top_left", label: "Top left corner", kind: "int", default: -1, from: -1, to: 48, step: 1, hint: "-1 follows the radius" },
                        { key: "radius_top_right", label: "Top right corner", kind: "int", default: -1, from: -1, to: 48, step: 1, hint: "-1 follows the radius" },
                        { key: "radius_bottom_right", label: "Bottom right corner", kind: "int", default: -1, from: -1, to: 48, step: 1, hint: "-1 follows the radius" },
                        { key: "radius_bottom_left", label: "Bottom left corner", kind: "int", default: -1, from: -1, to: 48, step: 1, hint: "-1 follows the radius" },
                        { key: "border", label: "Border", kind: "toggle", default: true },
                        { key: "border_color", label: "Border colour", kind: "colour", default: "", when: { border: [true] } },
                        { key: "border_width", label: "Border width (-1 follows the theme)", kind: "int", default: -1, from: -1, to: 4, step: 1, when: { border: [true] } },
                        { key: "shadow", label: "Shadow", kind: "toggle", default: true },
                        { key: "font_family", label: "Font", kind: "font", default: "" },
                        { key: "font_scale", label: "Text size", kind: "slider", default: 1, from: 0.6, to: 1.6, step: 0.01 },
                        { key: "font_weight", label: "Text weight", kind: "select", default: "400", options: [100, 200, 300, 400, 500, 600, 700, 800, 900].map(w => ({ key: String(w), label: String(w) })) },
                        { key: "scale", label: "Content size", kind: "slider", default: 1, from: 0.5, to: 2, step: 0.01 },
                        { key: "color", label: "Widget colour", kind: "colour", default: "" },
                        { key: "icon_color", label: "Widget icon colour", kind: "colour", default: "" },
                        { key: "concave_edge_corners", label: "Flows into the screen edge (with no edge margin)", kind: "toggle", default: false },
                        { key: "concave_radius", label: "Its curve", kind: "int", default: 18, from: 2, to: 48, step: 1, when: { concave_edge_corners: [true] } },
                        { key: "contact_shadow", label: "Shadow at the seam with an open panel", kind: "toggle", default: false },
                        { key: "group_style", label: "Groups look like", kind: "choice", default: "capsule", options: [{ key: "capsule", label: "Capsules (classic)" }, { key: "rule", label: "Set apart by rules" }, { key: "plate", label: "A tone step" }] },
                        { key: "readouts", label: "Values under the icons (vertical bars)", kind: "toggle", default: false },
                        { key: "open_on_hover", label: "Icons open their panel on hover", kind: "toggle", default: false },
                        { key: "hover_delay", label: "Hover before a panel opens (ms)", kind: "int", default: 0, from: 0, to: 2000, step: 25 },
                        { key: "hover_close", label: "A hovered panel closes when the pointer leaves", kind: "toggle", default: true },
                        { key: "hover_close_delay", label: "Leave before it closes (ms)", kind: "int", default: 300, from: 0, to: 3000, step: 25 },
                        { key: "hover_highlight", label: "Widgets light up on hover", kind: "toggle", default: true },
                        { key: "capsule", label: "Every widget in a capsule", kind: "toggle", default: false },
                        { key: "capsule_fill", label: "Capsule fill", kind: "colour", default: "surface_variant", when: { capsule: [true] } },
                        { key: "capsule_opacity", label: "Capsule opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01, when: { capsule: [true] } },
                        { key: "capsule_padding", label: "Capsule padding", kind: "int", default: 0, from: 0, to: 24, step: 1, when: { capsule: [true] } },
                        { key: "capsule_thickness", label: "Capsule thickness (of the bar)", kind: "slider", default: 1, from: 0.1, to: 1, step: 0.01 },
                        { key: "capsule_radius", label: "Capsule radius (-1 a pill)", kind: "int", default: -1, from: -1, to: 32, step: 1 },
                        { key: "capsule_border", label: "Capsule border", kind: "colour", default: "" },
                        { key: "capsule_foreground", label: "Inside a capsule, widgets are", kind: "colour", default: "" }
                    ]
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(root.bar?.[k] ?? schema.find(s => s.key === k)?.default))
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => root.setBar(key, value)
                    onCleared: key => Config.clearBarKey(root.barIndex, key)
                }
            }

            // ── the widgets ──
            Card {
                width: parent.width
                caption: "Widgets"
                Column {
                    width: parent.width
                    spacing: Metrics.s4
                    Repeater {
                        model: [{ key: "start", label: root.bar?.edge === "left" || root.bar?.edge === "right" ? "Top" : "Start" }, { key: "center", label: "Middle" }, { key: "end", label: root.bar?.edge === "left" || root.bar?.edge === "right" ? "Bottom" : "End" }]
                        delegate: Column {
                            id: sectionCol
                            required property var modelData
                            readonly property string key: modelData.key
                            readonly property var entries: root.bar?.widgets?.[key] ?? []
                            width: parent.width
                            spacing: 2

                            Item {
                                width: parent.width
                                height: 28
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "micro"
                                    caps: true
                                    tone: "faint"
                                    text: sectionCol.modelData.label
                                }
                                Chip {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: "plus"
                                    text: "Add"
                                    active: root.adding === sectionCol.key
                                    onClicked: root.adding = root.adding === sectionCol.key ? "" : sectionCol.key
                                }
                            }
                            Label {
                                visible: sectionCol.entries.length === 0
                                role: "caption"
                                tone: "faint"
                                text: "Nothing here"
                            }
                            Repeater {
                                model: sectionCol.entries
                                delegate: EntryRow {
                                    page: root
                                    required property string modelData
                                    required property int index
                                    width: sectionCol.width
                                    section: sectionCol.key
                                    entryIndex: index
                                    name: modelData
                                    count: sectionCol.entries.length
                                }
                            }
                            // the catalogue, under the section it adds to
                            Flow {
                                visible: root.adding === sectionCol.key
                                width: parent.width
                                spacing: 4
                                topPadding: Metrics.s2
                                Repeater {
                                    model: BarWidgetTypes.types.map(t => ({ key: t.type, label: t.label, icon: t.icon })).concat((root.bar?.group ?? []).map(g => ({ key: "group:" + g.id, label: "Group " + g.id, icon: "layers-intersect" })))
                                    delegate: Chip {
                                        required property var modelData
                                        icon: modelData.icon
                                        text: modelData.label
                                        onClicked: modelData.key.startsWith("group:") ? (root.setSection(sectionCol.key, root.sectionList(sectionCol.key).concat([modelData.key])), root.adding = "") : root.addEntry(sectionCol.key, modelData.key)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── capsule groups ──
            Card {
                width: parent.width
                caption: "Capsule groups"
                Column {
                    width: parent.width
                    spacing: Metrics.s4
                    Label {
                        width: parent.width
                        role: "caption"
                        tone: "faint"
                        wrapMode: Text.WordWrap
                        text: "Several widgets in one capsule. An accordion shows its first widget and opens while the pointer rests on it. Put a group on the bar with Add → Group."
                    }
                    Repeater {
                        model: root.bar?.group ?? []
                        delegate: Column {
                            id: groupItem
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: Metrics.s2
                            function setGroup(key: string, value: var): void {
                                const list = (root.bar.group ?? []).slice();
                                const g = Object.assign({}, list[index]);
                                if (value === undefined)
                                    delete g[key];
                                else
                                    g[key] = value;
                                list[index] = g;
                                root.setBar("group", list);
                            }
                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Theme.hairline
                            }
                            SchemaForm {
                                width: parent.width
                                schema: [
                                    { key: "enabled", label: "Drawn (off: the members sit loose)", kind: "toggle", default: true },
                                    { key: "members", label: "Widgets in it (in order)", kind: "list", default: [] },
                                    { key: "style", label: "Looks like (left out: the bar's)", kind: "choice", default: "", options: [{ key: "", label: "As the bar" }, { key: "capsule", label: "Capsule" }, { key: "plate", label: "Tone step" }, { key: "rule", label: "Rules" }] },
                                    { key: "accordion", label: "Accordion", kind: "toggle", default: false },
                                    { key: "accordion_direction", label: "Opens towards", kind: "choice", default: "end", options: [{ key: "start", label: "Start" }, { key: "end", label: "End" }], when: { accordion: [true] } },
                                    { key: "fill", label: "Fill", kind: "colour", default: "surface_variant" },
                                    { key: "opacity", label: "Opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01 },
                                    { key: "padding", label: "Padding", kind: "int", default: 8, from: 0, to: 32, step: 1 },
                                    { key: "widget_spacing", label: "Spacing", kind: "int", default: 4, from: 0, to: 32, step: 1 },
                                    { key: "border", label: "Border colour", kind: "colour", default: "" },
                                    { key: "foreground", label: "Widget colour inside", kind: "colour", default: "" },
                                    { key: "radius", label: "Corner radius (-1 is a pill)", kind: "int", default: -1, from: -1, to: 40, step: 1 }
                                ]
                                valueOf: key => groupItem.modelData[key] ?? schema.find(s => s.key === key)?.default
                                shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(groupItem.modelData[k] ?? false))
                                isSet: key => groupItem.modelData[key] !== undefined
                                onChanged: (key, value) => groupItem.setGroup(key, value)
                                onCleared: key => groupItem.setGroup(key, undefined)
                            }
                            Row {
                                spacing: Metrics.s2
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "label"
                                    text: "group:" + groupItem.modelData.id
                                }
                                Chip {
                                    icon: "trash"
                                    text: "Remove group"
                                    onClicked: {
                                        const list = (root.bar.group ?? []).filter((g, i) => i !== groupItem.index);
                                        root.setBar("group", list);
                                    }
                                }
                            }
                        }
                    }
                    Chip {
                        icon: "plus"
                        text: "New group"
                        onClicked: {
                            const ids = (root.bar.group ?? []).map(g => g.id);
                            let n = 1;
                            while (ids.includes("g" + n))
                                n++;
                            root.setBar("group", (root.bar.group ?? []).concat([{
                                    id: "g" + n,
                                    members: [],
                                    fill: "surface_variant",
                                    opacity: 0.5,
                                    padding: 10
                                }]));
                        }
                    }
                }
            }

            // ── the bar's empty space ──
            Card {
                width: parent.width
                caption: "Clicks on the bar itself"
                GestureForm {
                    width: parent.width
                    actions: root.bar?.actions ?? {}
                    defaults: ({ right: "panel-toggle control-center home" })
                    onChanged: (gesture, action) => {
                        const a = Object.assign({}, root.bar?.actions ?? {});
                        if (action === undefined)
                            delete a[gesture];
                        else
                            a[gesture] = action;
                        root.setBar("actions", a);
                    }
                }
            }

            Row {
                spacing: Metrics.s2
                Chip {
                    icon: "copy"
                    text: "Duplicate this bar"
                    onClicked: root.addBar(JSON.parse(JSON.stringify(root.bar)))
                }
                Chip {
                    icon: "trash"
                    text: confirmDelete ? "Delete — again to confirm" : "Delete this bar"
                    active: confirmDelete
                    property bool confirmDelete: false
                    onClicked: {
                        if (!confirmDelete) {
                            confirmDelete = true;
                            return;
                        }
                        Config.setBars(Config.bars.filter((b, i) => i !== root.barIndex));
                        root.selected = 0;
                    }
                }
            }
        }
    }

    // one entry in a section: what it is, its controls, and (opened) its settings and actions
    component EntryRow: Column {
        id: entry
        property var page
        property string section
        property int entryIndex
        property string name
        property int count
        readonly property bool isGroup: name.startsWith("group:")
        readonly property var spec: isGroup ? null : Config.resolveBarWidget(name)
        readonly property var info: isGroup ? null : BarWidgetTypes.find(spec.type)
        readonly property bool open: page.openWidget === section + ":" + entryIndex
        spacing: 0

        Rectangle {
            width: parent.width
            height: 40
            radius: Metrics.radiusMd
            color: entry.open ? Theme.selected : rowHover.containsMouse ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnim {}
            }
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: entry.isGroup ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: if (!entry.isGroup)
                    page.openWidget = entry.open ? "" : entry.section + ":" + entry.entryIndex
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s3
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s3
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: entry.isGroup ? "layers-intersect" : (entry.info?.icon ?? "apps")
                    size: 15
                    tone: entry.info || entry.isGroup ? "accent" : "danger"
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        role: "label"
                        text: entry.isGroup ? "Group " + entry.name.slice(6) : (entry.info?.label ?? "Unknown kind") + (entry.name !== entry.spec.type ? "  ·  " + entry.name : "")
                    }
                    Label {
                        visible: text !== ""
                        role: "micro"
                        tone: "faint"
                        text: entry.isGroup ? "" : !entry.info ? "No widget called " + entry.spec.type : page.usedBy(entry.name) > 1 ? "shared with " + (page.usedBy(entry.name) - 1) + " other bar" + (page.usedBy(entry.name) > 2 ? "s" : "") : ""
                    }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                IconButton {
                    size: 28
                    iconSize: 13
                    icon: "arrow-up"
                    tone: "muted"
                    enabled: entry.entryIndex > 0
                    onClicked: page.move(entry.section, entry.entryIndex, -1)
                }
                IconButton {
                    size: 28
                    iconSize: 13
                    icon: "arrow-down"
                    tone: "muted"
                    enabled: entry.entryIndex < entry.count - 1
                    onClicked: page.move(entry.section, entry.entryIndex, 1)
                }
                IconButton {
                    size: 28
                    iconSize: 13
                    icon: "arrows-sort"
                    tone: "muted"
                    onClicked: page.moveToSection(entry.section, entry.entryIndex, entry.section === "start" ? "center" : entry.section === "center" ? "end" : "start")
                }
                IconButton {
                    size: 28
                    iconSize: 13
                    icon: "x"
                    tone: "muted"
                    onClicked: page.removeEntry(entry.section, entry.entryIndex)
                }
            }
        }

        // its settings and its gestures, opened in place
        Item {
            width: parent.width
            height: entry.open ? sheet.implicitHeight + Metrics.s4 * 2 : 0
            clip: true
            Behavior on height {
                Anim {
                    role: "spatialFast"
                }
            }
            Column {
                id: sheet
                x: Metrics.s4
                y: Metrics.s4
                width: parent.width - Metrics.s4 * 2
                spacing: Metrics.s4
                Loader {
                    width: parent.width
                    active: entry.open
                    sourceComponent: Column {
                        spacing: Metrics.s4
                        Row {
                            visible: page.usedBy(entry.name) > 1 || entry.name === entry.spec.type
                            spacing: Metrics.s2
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "caption"
                                tone: "faint"
                                text: entry.name === entry.spec.type ? "These settings are this kind's ([widget." + entry.name + "])." : "Shared with other bars."
                            }
                            Chip {
                                icon: "copy"
                                text: "Give this bar its own"
                                onClicked: page.separate(entry.section, entry.entryIndex, entry.name)
                            }
                        }
                        SchemaForm {
                            width: parent.width
                            schema: BarWidgetTypes.schema(entry.spec.type)
                            valueOf: key => BarWidgetTypes.value(entry.spec.type, entry.spec.settings, key)
                            shows: spec => BarWidgetTypes.visible(entry.spec.type, spec, entry.spec.settings)
                            isSet: key => entry.spec.settings[key] !== undefined
                            onChanged: (key, value) => Config.setBarWidgetKey(entry.name, key, value)
                            onCleared: key => Config.setBarWidgetKey(entry.name, key, undefined)
                        }
                        Label {
                            role: "micro"
                            caps: true
                            tone: "faint"
                            text: "What it does"
                        }
                        GestureForm {
                            width: parent.width
                            actions: entry.spec.actions
                            defaults: {
                                const out = {};
                                for (const g of BarWidgetTypes.gestures)
                                    out[g] = BarWidgetTypes.action(entry.spec.type, entry.spec.settings, {}, g);
                                return out;
                            }
                            reserved: BarWidgetTypes.find(entry.spec.type)?.reserved ?? []
                            onChanged: (gesture, action) => Config.setBarWidgetAction(entry.name, gesture, action)
                        }
                    }
                }
            }
        }
    }

    // the nine gestures, each an action (a native command, exec …, none), its default shown when unset
    component GestureForm: Column {
        id: gf
        property var actions: ({})
        property var defaults: ({})
        property var reserved: []
        signal changed(string gesture, var action)
        spacing: Metrics.s2
        Repeater {
            model: BarWidgetTypes.gestures
            delegate: Row {
                id: g
                required property string modelData
                readonly property bool own: gf.actions[modelData] !== undefined
                width: gf.width
                spacing: Metrics.s3
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    role: "label"
                    tone: "muted"
                    text: BarWidgetTypes.gestureLabels[g.modelData]
                }
                // picked from the panels and commands there are (PanelCatalog); hover offers panels only
                ActionPicker {
                    width: g.width - 110 - Metrics.s3 - reset.width - Metrics.s3
                    value: gf.actions[g.modelData]
                    fallback: gf.reserved.includes(g.modelData) ? "" : (gf.defaults[g.modelData] ?? "")
                    panelsOnly: g.modelData === "hover"
                    enabled: !gf.reserved.includes(g.modelData)
                    onPicked: action => gf.changed(g.modelData, action)
                }
                Label {
                    id: reset
                    anchors.verticalCenter: parent.verticalCenter
                    visible: g.own
                    role: "micro"
                    tone: "faint"
                    text: "default"
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gf.changed(g.modelData, undefined)
                    }
                }
            }
        }
    }
}
