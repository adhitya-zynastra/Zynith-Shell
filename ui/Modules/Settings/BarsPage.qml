import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import "../../Common/BarModel.js" as BarModel

// The Bar Manager. A bar is something the user makes: as many as they like, each its own surface with its own name,
// place, look and components, side by side on an edge if they want. The page shows them on a sketch of the screen
// and in a list; picking one edits it below. Every change goes through BarEdits (one atomic write, undoable);
// bars.toml is the file underneath. Presets only ever add ordinary bars (or turn the old ones off), never limits.
Column {
    id: root

    spacing: Metrics.s5

    readonly property var state: BarEdits.state
    readonly property var bars: state.bars
    property string selectedId: ""
    readonly property var bar: BarModel.find(state, selectedId) ?? (bars.length > 0 ? bars[0] : null)
    readonly property string barId: bar?.id ?? ""
    readonly property bool vertical: bar?.edge === "left" || bar?.edge === "right"
    // the open component ("section:index"), a group member's ("section:index:name"), the section being added to
    property string openWidget: ""
    property string openMember: ""
    property string adding: ""
    property string query: ""
    property string confirmDelete: ""
    property bool picking: false
    property bool presetsOpen: false
    property bool advancedOpen: false
    property bool savingPreset: false

    function select(id: string): void {
        selectedId = id;
        openWidget = "";
        openMember = "";
        adding = "";
        confirmDelete = "";
    }
    function setBar(key: string, value: var): void {
        BarEdits.setKey(barId, key, value);
    }
    function sectionList(section: string): var {
        return BarModel.list(bar?.widgets?.[section]);
    }
    function sectionLabel(section: string): string {
        return section === "center" ? "Middle" : vertical ? (section === "start" ? "Top" : "Bottom") : (section === "start" ? "Left" : "Right");
    }
    function componentLabel(name: string): string {
        if (name.startsWith("group:"))
            return "Group " + name.slice(6);
        return BarWidgetTypes.find(BarModel.typeOf(state, name))?.label ?? name;
    }
    function componentIcon(name: string): string {
        if (name.startsWith("group:"))
            return "layers-intersect";
        return BarWidgetTypes.find(BarModel.typeOf(state, name))?.icon ?? "apps";
    }
    function summary(b: var): string {
        const names = BarModel.sections.reduce((all, s) => all.concat(BarModel.list(b.widgets?.[s])), []).map(n => componentLabel(n));
        return names.length === 0 ? "No components yet" : names.join(", ");
    }
    // a capsule group of this bar (or a shared one)
    function groupMembers(id: string): var {
        const g = BarModel.list(bar?.group).find(x => x.id === id) ?? BarModel.list(Config.barGroups).find(x => x.id === id);
        return BarModel.list(g?.members);
    }
    // the catalogue, matching what is typed (label, kind, or a word of either)
    function catalogue(): var {
        const q = query.trim().toLowerCase();
        const kinds = BarWidgetTypes.types.filter(t => q === "" || t.label.toLowerCase().includes(q) || t.type.includes(q));
        const groups = BarModel.list(bar?.group).filter(g => q === "" || ("group " + g.id).includes(q)).map(g => ({ type: "group:" + g.id, label: "Group " + g.id, icon: "layers-intersect" }));
        return kinds.concat(groups);
    }
    function add(section: string, type: string): void {
        if (type.startsWith("group:"))
            BarEdits.addGroup(barId, section, type.slice(6));
        else
            BarEdits.addComponent(barId, section, type);
        openWidget = section + ":" + (sectionList(section).length - 1);
    }

    // ── the page head ──────────────────────────────────────────────────────────
    PanelHeader {
        width: parent.width
        title: "Bars"
        caption: bars.length === 0 ? "No bars yet — make one below" : bars.length + (bars.length === 1 ? " bar" : " bars") + " · " + bars.filter(b => b.enabled !== false).length + " shown · each is its own surface, changes show at once"
    }

    // bars.toml could not be read: say so plainly, and offer the way out
    Rectangle {
        visible: Config.barsError !== ""
        width: parent.width
        height: errorCol.implicitHeight + Metrics.s4 * 2
        radius: Metrics.radiusMd
        color: Theme.alpha(Theme.danger, 0.12)
        border.width: 1
        border.color: Theme.alpha(Theme.danger, 0.4)
        Column {
            id: errorCol
            x: Metrics.s4
            y: Metrics.s4
            width: parent.width - Metrics.s4 * 2
            spacing: Metrics.s2
            Label {
                width: parent.width
                role: "label"
                text: "Your bars file has a mistake in it, so nothing here will change it until it is fixed."
                wrapMode: Text.WordWrap
            }
            Label {
                width: parent.width
                role: "caption"
                tone: "muted"
                text: Config.barsError
                wrapMode: Text.WrapAnywhere
            }
            Chip {
                icon: "restore"
                text: "Start again from the default bar (the file is kept beside it)"
                onClicked: Config.recoverBars()
            }
        }
    }

    // what was just done, and the way back
    Row {
        visible: BarEdits.lastLabel !== "" || BarEdits.canUndo
        spacing: Metrics.s3
        Label {
            anchors.verticalCenter: parent.verticalCenter
            role: "caption"
            tone: "muted"
            text: BarEdits.lastLabel
        }
        Chip {
            visible: BarEdits.canUndo
            icon: "arrow-back-up"
            text: "Undo " + BarEdits.undoLabel.charAt(0).toLowerCase() + BarEdits.undoLabel.slice(1)
            onClicked: BarEdits.undo()
        }
    }

    // ── the screen, with every bar on it ──────────────────────────────────────
    LayoutSketch {
        width: parent.width
        page: root
    }

    // ── your bars ───────────────────────────────────────────────────────────────
    Card {
        width: parent.width
        caption: "Your bars"
        Column {
            width: parent.width
            spacing: 2
            Label {
                visible: root.bars.length === 0
                role: "caption"
                tone: "faint"
                text: "Nothing yet. Make a bar where you want it, or start from a preset."
            }
            Repeater {
                model: root.bars
                delegate: BarRow {
                    required property var modelData
                    required property int index
                    width: parent.width
                    page: root
                    item: modelData
                    position: index
                    count: root.bars.length
                }
            }
            Row {
                topPadding: Metrics.s3
                spacing: Metrics.s2
                Chip {
                    icon: "plus"
                    text: "New bar"
                    active: root.picking
                    onClicked: {
                        root.picking = !root.picking;
                        root.presetsOpen = false;
                    }
                }
                Chip {
                    icon: "layout-dashboard"
                    text: "Start from a preset"
                    active: root.presetsOpen
                    onClicked: {
                        root.presetsOpen = !root.presetsOpen;
                        root.picking = false;
                    }
                }
            }
            // where the new bar goes; it starts empty, its components are the user's to choose
            Column {
                visible: root.picking
                width: parent.width
                topPadding: Metrics.s3
                spacing: Metrics.s2
                Label {
                    role: "caption"
                    tone: "muted"
                    text: "Where should it go? It starts empty; add its components next."
                }
                PositionGrid {
                    width: parent.width
                    onPicked: (edge, anchor) => {
                        const id = BarEdits.create({ edge: edge, anchor: anchor });
                        if (id !== "") {
                            root.select(id);
                            root.picking = false;
                            root.adding = anchor === "end" ? "end" : anchor === "start" ? "start" : "center";
                        }
                    }
                }
            }
            // presets: each makes ordinary bars, editable like any other
            Column {
                visible: root.presetsOpen
                width: parent.width
                topPadding: Metrics.s3
                spacing: Metrics.s2
                Label {
                    width: parent.width
                    role: "caption"
                    tone: "muted"
                    wrapMode: Text.WordWrap
                    text: "Add puts the preset's bars beside yours. Replace turns your bars off (nothing is deleted: turn them on again, or Undo) and adds the preset's. Either way they are ordinary bars you can rename, move and change."
                }
                Repeater {
                    model: BarModel.presets.concat(BarModel.list(Config.barPresets))
                    delegate: PresetRow {
                        required property var modelData
                        width: parent.width
                        page: root
                        preset: modelData
                    }
                }
            }
        }
    }

    // ── the selected bar ────────────────────────────────────────────────────────
    Loader {
        width: parent.width
        active: root.bar !== null
        sourceComponent: Column {
            spacing: Metrics.s5

            Card {
                width: parent.width
                caption: "This bar"
                Column {
                    width: parent.width
                    spacing: Metrics.s4
                    // its name: the user's, never derived from anything else
                    Item {
                        width: parent.width
                        height: 34
                        Label {
                            id: nameLabel
                            anchors.verticalCenter: parent.verticalCenter
                            width: 110
                            role: "label"
                            tone: "muted"
                            text: "Name"
                        }
                        Rectangle {
                            anchors.left: nameLabel.right
                            anchors.right: shownToggle.left
                            anchors.rightMargin: Metrics.s4
                            height: parent.height
                            radius: Metrics.radiusMd
                            color: Theme.well
                            border.width: nameField.activeFocus ? 1 : 0
                            border.color: Theme.accentLine
                            TextInput {
                                id: nameField
                                anchors.fill: parent
                                anchors.leftMargin: Metrics.s3
                                anchors.rightMargin: Metrics.s3
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.ink
                                selectionColor: Theme.accentSoft
                                font.family: Type.ui
                                font.pixelSize: Type.body
                                clip: true
                                text: root.bar?.name ?? ""
                                onEditingFinished: if (text.trim() !== "" && text !== root.bar?.name)
                                    BarEdits.rename(root.barId, text)
                                Keys.onEscapePressed: {
                                    text = root.bar?.name ?? "";
                                    focus = false;
                                }
                            }
                        }
                        Row {
                            id: shownToggle
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
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.bar?.enabled !== false
                                onToggled: BarEdits.setEnabled(root.barId, root.bar?.enabled === false)
                            }
                        }
                    }
                    Label {
                        role: "micro"
                        caps: true
                        tone: "faint"
                        text: "Where it sits — " + BarModel.positionLabel(root.bar ?? {})
                    }
                    PositionGrid {
                        width: parent.width
                        edge: root.bar?.edge ?? ""
                        anchor: root.bar?.anchor ?? ""
                        onPicked: (edge, anchor) => BarEdits.place(root.barId, edge, anchor)
                    }
                    SchemaForm {
                        width: parent.width
                        advanced: "hide"
                        schema: [
                            { key: "offset", label: root.bar?.anchor === "center" ? "Distance from its end (centred bars ignore it)" : "Distance from the " + (root.bar?.anchor === "end" ? "end" : "start") + " of the edge", kind: "int", default: 0, from: 0, to: 3840, step: 2, when: { anchor: ["start", "end", "fill"] } },
                            { key: "screens", label: "Screens", kind: "list", default: ["*"], hint: "* is every screen; or a screen's name, e.g. eDP-1" }
                        ]
                        valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                        isSet: key => root.bar?.[key] !== undefined
                        shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(root.bar?.[k] ?? "center"))
                        onChanged: (key, value) => root.setBar(key, value)
                        onCleared: key => root.setBar(key, undefined)
                        commitOnRelease: true
                        onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                        onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                    }
                }
            }

            // ── its components, as they sit on the bar ──
            Card {
                width: parent.width
                caption: "Components"
                Column {
                    width: parent.width
                    spacing: Metrics.s4
                    Label {
                        width: parent.width
                        role: "caption"
                        tone: "faint"
                        wrapMode: Text.WordWrap
                        text: "In order along the bar. Pick one to change it; each is configured on its own, even two of the same kind."
                    }
                    Repeater {
                        model: BarModel.sections
                        delegate: SectionStrip {
                            required property string modelData
                            width: parent.width
                            page: root
                            section: modelData
                        }
                    }
                }
            }

            Card {
                width: parent.width
                caption: "Corners"
                CornersEditor {
                    width: parent.width
                    page: root
                }
            }

            Card {
                width: parent.width
                caption: "Size and look"
                SchemaForm {
                    width: parent.width
                    advanced: "hide"
                    schema: root.lookSchema
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    shows: spec => root.applies(spec)
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => root.setBar(key, value)
                    onCleared: key => root.setBar(key, undefined)
                    commitOnRelease: true
                    onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                    onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                }
            }

            Card {
                width: parent.width
                caption: "Behaviour"
                SchemaForm {
                    width: parent.width
                    advanced: "hide"
                    schema: root.behaviourSchema
                    valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                    shows: spec => root.applies(spec)
                    isSet: key => root.bar?.[key] !== undefined
                    onChanged: (key, value) => root.setBar(key, value)
                    onCleared: key => root.setBar(key, undefined)
                    commitOnRelease: true
                    onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                    onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                }
            }

            GroupsCard {
                width: parent.width
                page: root
            }

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

            // the fine controls, apart from the rest
            Card {
                width: parent.width
                caption: "Advanced"
                Column {
                    width: parent.width
                    spacing: Metrics.s3
                    Chip {
                        icon: root.advancedOpen ? "chevron-up" : "chevron-down"
                        text: root.advancedOpen ? "Hide the fine controls" : "Show the fine controls (layer, per-corner radii, capsules, summoning strip …)"
                        onClicked: root.advancedOpen = !root.advancedOpen
                    }
                    SchemaForm {
                        visible: root.advancedOpen
                        width: parent.width
                        advanced: "only"
                        schema: root.behaviourSchema.concat(root.lookSchema)
                        valueOf: key => root.bar?.[key] ?? schema.find(s => s.key === key)?.default
                        shows: spec => root.applies(spec)
                        isSet: key => root.bar?.[key] !== undefined
                        onChanged: (key, value) => root.setBar(key, value)
                        onCleared: key => root.setBar(key, undefined)
                        commitOnRelease: true
                        onPreviewed: (key, value) => BarEdits.preview(root.barId, key, value)
                        onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(root.barId, key, value, canceled)
                    }
                }
            }

            // what can be done with the whole bar
            Flow {
                width: parent.width
                spacing: Metrics.s2
                Chip {
                    icon: "copy"
                    text: "Duplicate"
                    onClicked: {
                        const id = BarEdits.duplicate(root.barId);
                        if (id !== "")
                            root.select(id);
                    }
                }
                Chip {
                    icon: "restore"
                    text: "Reset its look to the defaults"
                    onClicked: BarEdits.reset(root.barId)
                }
                Chip {
                    icon: "bookmark"
                    text: "Save as a preset"
                    active: root.savingPreset
                    onClicked: root.savingPreset = !root.savingPreset
                }
                Chip {
                    icon: "trash"
                    text: root.confirmDelete === root.barId ? "Delete " + (root.bar?.name ?? "") + " — click again (Undo brings it back)" : "Delete"
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
            SavePresetForm {
                visible: root.savingPreset
                width: parent.width
                page: root
            }
        }
    }

    // a setting's `when`, against this bar
    function applies(spec: var): bool {
        return !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(bar?.[k] ?? lookSchema.concat(behaviourSchema).find(s => s.key === k)?.default));
    }

    readonly property var lookSchema: [
        { key: "thickness", label: "Thickness", kind: "int", default: 34, from: 20, to: 96, step: 1 },
        { key: "length", label: "Length (0 fits its components)", kind: "int", default: 0, from: 0, to: 3840, step: 10 },
        { key: "margin", label: "Gap to the screen edge", kind: "int", default: 0, from: 0, to: 64, step: 1 },
        { key: "padding", label: "Room inside its ends", kind: "int", default: 12, from: 0, to: 40, step: 1 },
        { key: "spacing", label: "Between components (-1 follows the theme)", kind: "int", default: -1, from: -1, to: 24, step: 1 },
        { key: "opacity", label: "Opacity (0 follows the profile)", kind: "slider", default: 0, from: 0, to: 1, step: 0.01 },
        { key: "blur", label: ExperiencePolicy.blur ? "Blur behind it" : "Blur behind it (the current profile turns blur off)", kind: "toggle", default: true },
        { key: "border", label: "Border", kind: "toggle", default: true },
        { key: "shadow", label: ExperiencePolicy.shadows ? "Shadow" : "Shadow (the current profile turns shadows off)", kind: "toggle", default: true },
        { key: "concave_edge_corners", label: "Flows into the screen edge (with no gap)", kind: "toggle", default: false },
        { key: "font_family", label: "Font", kind: "font", default: "" },
        { key: "font_scale", label: "Text size", kind: "slider", default: 1, from: 0.6, to: 1.6, step: 0.01 },
        { key: "font_weight", label: "Text weight", kind: "select", default: "400", options: [100, 200, 300, 400, 500, 600, 700, 800, 900].map(w => ({ key: String(w), label: String(w) })) },
        { key: "color", label: "Component colour", kind: "colour", default: "" },
        { key: "group_style", label: "Groups look like", kind: "choice", default: "capsule", options: [{ key: "capsule", label: "Capsules" }, { key: "rule", label: "Rules" }, { key: "plate", label: "A tone step" }] },
        { key: "capsule", label: "Every component in a capsule", kind: "toggle", default: false },
        { adv: true, key: "border_color", label: "Border colour", kind: "colour", default: "", when: { border: [true] } },
        { adv: true, key: "border_width", label: "Border width (-1 follows the theme)", kind: "int", default: -1, from: -1, to: 4, step: 1, when: { border: [true] } },
        { adv: true, key: "scale", label: "Content size", kind: "slider", default: 1, from: 0.5, to: 2, step: 0.01 },
        { adv: true, key: "icon_color", label: "Component icon colour", kind: "colour", default: "" },
        { adv: true, key: "concave_radius", label: "Its curve into the edge", kind: "int", default: 18, from: 2, to: 48, step: 1, when: { concave_edge_corners: [true] } },
        { adv: true, key: "contact_shadow", label: "Shadow at the seam with an open panel", kind: "toggle", default: false },
        { adv: true, key: "readouts", label: "Values under the icons (vertical bars)", kind: "toggle", default: false },
        { adv: true, key: "capsule_fill", label: "Capsule fill", kind: "colour", default: "surface_variant", when: { capsule: [true] } },
        { adv: true, key: "capsule_opacity", label: "Capsule opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01, when: { capsule: [true] } },
        { adv: true, key: "capsule_padding", label: "Capsule padding", kind: "int", default: 0, from: 0, to: 24, step: 1, when: { capsule: [true] } },
        { adv: true, key: "capsule_thickness", label: "Capsule thickness (of the bar)", kind: "slider", default: 1, from: 0.1, to: 1, step: 0.01 },
        { adv: true, key: "capsule_radius", label: "Capsule radius (-1 a pill)", kind: "int", default: -1, from: -1, to: 32, step: 1 },
        { adv: true, key: "capsule_border", label: "Capsule border", kind: "colour", default: "" },
        { adv: true, key: "capsule_foreground", label: "Inside a capsule, components are", kind: "colour", default: "" }
    ]
    readonly property var behaviourSchema: [
        { key: "visibility", label: "Shows", kind: "choice", default: "always", options: [{ key: "always", label: "Always" }, { key: "smart", label: "When the desktop is clear" }, { key: "autohide", label: "When the pointer reaches the edge" }] },
        { key: "reserve", label: "Windows keep clear of it", kind: "toggle", default: false, hint: "Bars on one edge share the room the deepest of them needs" },
        { key: "reference", label: "Its stretch of the edge", kind: "choice", default: "output", options: [{ key: "output", label: "The whole edge" }, { key: "workspace", label: "Clear of bars on the neighbouring edges" }] },
        { key: "hide_delay_ms", label: "Hides this long after the pointer leaves (ms)", kind: "int", default: 350, from: 0, to: 3000, step: 50, when: { visibility: ["smart", "autohide"] } },
        { key: "reveal_on_switch", label: "Shows briefly on a workspace switch", kind: "toggle", default: true, when: { visibility: ["smart", "autohide"] } },
        { key: "open_on_hover", label: "Icons open their panel on hover", kind: "toggle", default: false },
        { key: "hover_delay", label: "Hover before a panel opens (ms)", kind: "int", default: 0, from: 0, to: 2000, step: 25, when: { open_on_hover: [true] } },
        { key: "hover_close", label: "A hovered panel closes when the pointer leaves", kind: "toggle", default: true, when: { open_on_hover: [true] } },
        { key: "hover_highlight", label: "Components light up on hover", kind: "toggle", default: true },
        { adv: true, key: "layer", label: "Layer", kind: "choice", default: "top", options: [{ key: "bottom", label: "Under windows" }, { key: "top", label: "Above windows" }, { key: "overlay", label: "Above everything" }] },
        { adv: true, key: "margin_opposite", label: "Extra room kept on its inner side", kind: "int", default: 0, from: 0, to: 200, step: 1, when: { reserve: [true] } },
        { adv: true, key: "reveal_length", label: "Summoned along this much of the edge (0 = its own length)", kind: "int", default: 480, from: 0, to: 3840, step: 10, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "reveal_size", label: "That strip's depth", kind: "int", default: 3, from: 1, to: 24, step: 1, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "reveal_on_switch_ms", label: "Shows on a switch for (ms)", kind: "int", default: 1200, from: 200, to: 5000, step: 100, when: { visibility: ["smart", "autohide"] } },
        { adv: true, key: "hover_close_delay", label: "Leave before a hovered panel closes (ms)", kind: "int", default: 300, from: 0, to: 3000, step: 25, when: { open_on_hover: [true] } },
        { adv: true, key: "panel_overlap", label: "A floating panel tucks under its edge by", kind: "int", default: 0, from: -2, to: 12, step: 1 }
    ]

    // ── pieces ─────────────────────────────────────────────────────────────────

    // The four corners: linked (one radius for all) or each on its own. Every slider runs to what the bar can
    // show (half its thickness: a rounder corner is drawn at that), previews on the bar while dragged and is
    // written when let go. Corners squared because the bar flows into the screen edge say so instead of
    // pretending to move. The shape beside them is the bar's own corner rule (BarModel.cornerRadii).
    component CornersEditor: Column {
        id: corners
        property var page
        readonly property var bar: page.bar ?? ({})
        readonly property bool linked: BarModel.cornersLinked(bar)
        readonly property int most: Math.floor((bar.thickness ?? 34) / 2)
        readonly property var squared: BarModel.squaredCorners(bar)
        readonly property var drawn: BarModel.cornerRadii(Config.bars.find(b => b.id === page.barId) ?? bar, { w: 1e6, h: bar.thickness ?? 34 }, Metrics.radiusScale, null)
        readonly property var labels: ["Top left", "Top right", "Bottom right", "Bottom left"]
        spacing: Metrics.s4
        Row {
            width: parent.width
            spacing: Metrics.s4
            Segmented {
                width: Math.min(280, parent.width - shape.width - Metrics.s4)
                anchors.verticalCenter: parent.verticalCenter
                options: [{ key: "linked", label: "All the same" }, { key: "each", label: "Each corner" }]
                current: corners.linked ? "linked" : "each"
                onPicked: key => BarEdits.commit(BarModel.setCornersLinked(BarEdits.state, corners.page.barId, key === "linked"), key === "linked" ? "Link the corners" : "Set each corner")
            }
            // the bar's ends as they will be drawn (live while a corner is dragged)
            Rectangle {
                id: shape
                width: 150
                height: Math.max(16, Math.min(48, corners.bar.thickness ?? 34))
                readonly property real k: height / (corners.bar.thickness ?? 34)
                color: Theme.alpha(Theme.ink, 0.2)
                border.width: 1
                border.color: Theme.accentLine
                topLeftRadius: corners.drawn[0] * k
                topRightRadius: corners.drawn[1] * k
                bottomRightRadius: corners.drawn[2] * k
                bottomLeftRadius: corners.drawn[3] * k
            }
        }
        CornerSlider {
            visible: corners.linked
            width: parent.width
            label: "Radius"
            key: "radius"
            page: corners.page
            most: corners.most
            // a radius left out (or -1) is a pill: half the thickness
            current: (corners.bar.radius ?? -1) < 0 ? corners.most : corners.bar.radius
        }
        Repeater {
            model: corners.linked ? [] : [0, 1, 2, 3]
            delegate: CornerSlider {
                required property int modelData
                width: corners.width
                label: corners.labels[modelData]
                key: BarModel.cornerKeys[modelData]
                page: corners.page
                most: corners.most
                locked: corners.squared.includes(modelData)
                current: {
                    const own = corners.bar[BarModel.cornerKeys[modelData]];
                    const base = (corners.bar.radius ?? -1) < 0 ? corners.most : corners.bar.radius;
                    return own === undefined || own < 0 ? base : own;
                }
            }
        }
        Label {
            visible: corners.squared.length > 0
            width: parent.width
            role: "caption"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: "The " + corners.squared.map(i => corners.labels[i].toLowerCase()).join(" and ") + " corners are square because the bar flows into the screen edge there. Turn off \"Flows into the screen edge\" under Size and look to round them."
        }
    }

    component CornerSlider: Item {
        id: cs
        property var page
        property string label
        property string key
        property int most: 17
        property real current: 0
        property bool locked: false
        property var shown: undefined
        implicitHeight: 30
        opacity: locked ? 0.45 : 1
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            role: "label"
            tone: "muted"
            text: cs.label
        }
        Slider {
            x: 110
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 110 - 56 - Metrics.s3
            enabled: !cs.locked
            value: cs.most > 0 ? Math.min(1, cs.current / cs.most) : 0
            step: cs.most > 0 ? 1 / cs.most : 1
            function px(v: real): int {
                return Math.round(v * cs.most);
            }
            onMoved: v => {
                cs.shown = px(v);
                BarEdits.preview(cs.page.barId, cs.key, px(v));
            }
            onCommitted: v => {
                cs.shown = undefined;
                BarEdits.setKey(cs.page.barId, cs.key, px(v));
                BarEdits.endPreview(cs.page.barId, cs.key, px(v), false);
            }
            onCanceled: {
                cs.shown = undefined;
                BarEdits.endPreview(cs.page.barId, cs.key, undefined, true);
            }
        }
        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            horizontalAlignment: Text.AlignRight
            role: "label"
            numeric: true
            tone: "muted"
            text: cs.locked ? "square" : (cs.shown !== undefined ? cs.shown : Math.min(cs.current, cs.most)) + " px"
        }
    }

    // The screen with every bar drawn where it sits (a sketch from the settings: real lengths depend on what the
    // components show). The selected bar is the accent; a hidden one is an outline. Clicking one selects it.
    component LayoutSketch: Item {
        id: sketch
        property var page
        readonly property var screen: Quickshell.screens.find(s => (page.bar?.screens ?? ["*"]).includes(s.name)) ?? Quickshell.screens[0] ?? null
        readonly property real sw: screen?.width ?? 1920
        readonly property real sh: screen?.height ?? 1080
        readonly property real k: Math.min(width / sw, 260 / sh)
        readonly property var reserved: BarModel.reservations(page.bars, screen?.name ?? "")
        implicitHeight: sh * k + Metrics.s5
        Rectangle {
            id: monitor
            x: (parent.width - width) / 2
            width: sketch.sw * sketch.k
            height: sketch.sh * sketch.k
            radius: Metrics.radiusMd
            // the screen: the surface's own deepest tone, so bars (ink) and the selected one (accent) read on it
            color: Theme.surfaceLow
            border.width: 1
            border.color: Theme.rule
            // the room windows keep clear of
            Rectangle {
                x: sketch.reserved.left * sketch.k
                y: sketch.reserved.top * sketch.k
                width: parent.width - (sketch.reserved.left + sketch.reserved.right) * sketch.k
                height: parent.height - (sketch.reserved.top + sketch.reserved.bottom) * sketch.k
                color: "transparent"
                border.width: 1
                border.color: Theme.hairline
                radius: Metrics.radiusSm
            }
            Label {
                anchors.centerIn: parent
                role: "micro"
                caps: true
                tone: "faint"
                text: (sketch.screen?.name ?? "screen") + " · " + sketch.sw + "×" + sketch.sh
            }
            Repeater {
                model: sketch.page.bars.filter(b => BarModel.onScreen(b, sketch.screen?.name ?? ""))
                delegate: Rectangle {
                    id: shape
                    required property var modelData
                    readonly property bool v: modelData.edge === "left" || modelData.edge === "right"
                    readonly property bool selected: modelData.id === sketch.page.barId
                    readonly property bool on: modelData.enabled !== false
                    readonly property var r: sketch.rect(modelData)
                    x: r.x * sketch.k
                    y: r.y * sketch.k
                    width: Math.max(3, r.w * sketch.k)
                    height: Math.max(3, r.h * sketch.k)
                    radius: Math.min(width, height) / 2
                    color: !on ? "transparent" : selected ? Theme.accent : Theme.inkMuted
                    border.width: on ? 0 : 1
                    border.color: selected ? Theme.accent : Theme.inkFaint
                    Behavior on x {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Behavior on y {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Behavior on width {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Behavior on height {
                        Anim {
                            role: "spatial"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sketch.page.select(shape.modelData.id)
                    }
                }
            }
        }
        // where a bar sits, as its settings say: along its stretch of the edge; its length is the stretch (fill),
        // its fixed length, or an estimate from how many components it holds
        function rect(b: var): var {
            const vert = b.edge === "left" || b.edge === "right";
            const L = vert ? sh : sw;
            const range = BarModel.alongRange(b, L, reserved);
            const t = b.thickness ?? 34;
            const m = b.margin ?? 0;
            const off = b.anchor === "center" ? 0 : (b.offset ?? 0);
            const count = BarModel.sections.reduce((n, s) => n + BarModel.list(b.widgets?.[s]).length, 0);
            const len = b.anchor === "fill" ? (range[1] - range[0]) - off * 2 : (b.length ?? 0) > 0 ? b.length : Math.max(t, count * t * 0.95 + (b.padding ?? 12) * 2);
            const along = b.anchor === "fill" || b.anchor === "start" ? range[0] + off : b.anchor === "end" ? range[1] - off - len : range[0] + (range[1] - range[0] - len) / 2;
            const across = b.edge === "top" || b.edge === "left" ? m : (vert ? sw : sh) - m - t;
            return vert ? { x: across, y: along, w: t, h: len } : { x: along, y: across, w: len, h: t };
        }
    }

    // one bar in the list: its name, where it is, what it holds; shown or not, its order, quick actions
    component BarRow: Rectangle {
        id: row
        property var page
        property var item
        property int position
        property int count
        readonly property bool selected: item.id === page.barId
        height: 52
        radius: Metrics.radiusMd
        color: selected ? Theme.selected : rowArea.containsMouse ? Theme.hover : "transparent"
        Behavior on color {
            ColorAnim {}
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.page.select(row.item.id)
        }
        Icon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: ({ top: "layout-navbar", bottom: "layout-bottombar", left: "layout-sidebar", right: "layout-sidebar-right" })[row.item.edge ?? "top"] ?? "layout-navbar"
            size: 16
            tone: row.item.enabled === false ? "faint" : row.selected ? "accent" : "muted"
        }
        Column {
            anchors.left: rowIcon.right
            anchors.leftMargin: Metrics.s3
            anchors.right: rowActions.left
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Label {
                width: parent.width
                role: "label"
                tone: row.item.enabled === false ? "muted" : "ink"
                elide: Text.ElideRight
                text: row.item.name
            }
            Label {
                width: parent.width
                role: "micro"
                tone: "faint"
                elide: Text.ElideRight
                text: BarModel.positionLabel(row.item) + " · " + (row.item.enabled === false ? "Hidden" : "Shown") + " · " + row.page.summary(row.item)
            }
        }
        Row {
            id: rowActions
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: row.item.enabled !== false
                onToggled: BarEdits.setEnabled(row.item.id, row.item.enabled === false)
            }
            Item {
                width: Metrics.s2
                height: 1
            }
            IconButton {
                size: 28
                iconSize: 13
                icon: "arrow-up"
                tone: "muted"
                enabled: row.position > 0
                onClicked: BarEdits.move(row.item.id, -1)
            }
            IconButton {
                size: 28
                iconSize: 13
                icon: "arrow-down"
                tone: "muted"
                enabled: row.position < row.count - 1
                onClicked: BarEdits.move(row.item.id, 1)
            }
            IconButton {
                size: 28
                iconSize: 13
                icon: "copy"
                tone: "muted"
                onClicked: {
                    const id = BarEdits.duplicate(row.item.id);
                    if (id !== "")
                        row.page.select(id);
                }
            }
        }
    }

    // where a bar sits: each edge and each place along it, as one grid of plain words
    component PositionGrid: Column {
        id: grid
        property string edge: ""
        property string anchor: ""
        signal picked(string edge, string anchor)
        spacing: Metrics.s1
        Repeater {
            model: BarModel.edges
            delegate: Row {
                id: edgeRow
                required property string modelData
                readonly property bool vert: modelData === "left" || modelData === "right"
                spacing: Metrics.s1
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    role: "label"
                    tone: "muted"
                    text: edgeRow.modelData.charAt(0).toUpperCase() + edgeRow.modelData.slice(1)
                }
                Repeater {
                    model: BarModel.anchors
                    delegate: Rectangle {
                        id: cell
                        required property string modelData
                        readonly property bool current: grid.edge === edgeRow.modelData && grid.anchor === modelData
                        width: (grid.width - 70 - Metrics.s1 * 4) / 4
                        height: 30
                        radius: Metrics.radiusSm
                        color: current ? Theme.signalFill : cellArea.containsMouse ? Theme.hover : Theme.plate
                        border.width: current ? 1 : 0
                        border.color: Theme.signalEdge
                        Label {
                            anchors.centerIn: parent
                            role: "caption"
                            tone: cell.current ? "ink" : "muted"
                            text: cell.modelData === "fill" ? (edgeRow.vert ? "Full height" : "Full width") : cell.modelData === "center" ? "Centre" : edgeRow.vert ? (cell.modelData === "start" ? "Top" : "Bottom") : (cell.modelData === "start" ? "Left" : "Right")
                        }
                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: grid.picked(edgeRow.modelData, cell.modelData)
                        }
                    }
                }
            }
        }
    }

    // a preset: what it makes, and add / replace (a custom one can also go)
    component PresetRow: Rectangle {
        id: pr
        property var page
        property var preset
        height: 46
        radius: Metrics.radiusMd
        color: Theme.plate
        Column {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.right: prActions.left
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            Label {
                width: parent.width
                role: "label"
                elide: Text.ElideRight
                text: pr.preset.label + (pr.preset.custom ? "  ·  yours" : "")
            }
            Label {
                width: parent.width
                role: "micro"
                tone: "faint"
                elide: Text.ElideRight
                text: pr.preset.hint ?? ""
            }
        }
        Row {
            id: prActions
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.s1
            Chip {
                icon: "plus"
                text: "Add"
                onClicked: {
                    const ids = BarEdits.applyPreset(pr.preset.key, "add");
                    if (ids.length > 0)
                        pr.page.select(ids[0]);
                }
            }
            Chip {
                icon: "replace"
                text: "Replace"
                onClicked: {
                    const ids = BarEdits.applyPreset(pr.preset.key, "replace");
                    if (ids.length > 0)
                        pr.page.select(ids[0]);
                }
            }
            IconButton {
                visible: pr.preset.custom === true
                size: 28
                iconSize: 13
                icon: "trash"
                tone: "muted"
                onClicked: BarEdits.removePreset(pr.preset.key)
            }
        }
    }

    // this bar (or every shown bar) kept as a preset of the user's own
    component SavePresetForm: Column {
        id: sp
        property var page
        spacing: Metrics.s2
        Rectangle {
            width: parent.width
            height: 34
            radius: Metrics.radiusMd
            color: Theme.well
            TextInput {
                id: presetName
                anchors.fill: parent
                anchors.leftMargin: Metrics.s3
                anchors.rightMargin: Metrics.s3
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.ink
                font.family: Type.ui
                font.pixelSize: Type.body
                clip: true
                Label {
                    visible: presetName.text === "" && !presetName.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    role: "body"
                    tone: "faint"
                    text: "A name for the preset"
                }
            }
        }
        Row {
            spacing: Metrics.s2
            Chip {
                icon: "device-floppy"
                text: "Save this bar"
                onClicked: if (BarEdits.savePreset([sp.page.barId], presetName.text)) {
                    presetName.text = "";
                    sp.page.savingPreset = false;
                }
            }
            Chip {
                icon: "device-floppy"
                text: "Save every shown bar together"
                onClicked: if (BarEdits.savePreset(sp.page.bars.filter(b => b.enabled !== false).map(b => b.id), presetName.text)) {
                    presetName.text = "";
                    sp.page.savingPreset = false;
                }
            }
        }
    }

    // One section of the bar as it reads: its components as chips in order, then an add button; the open one's
    // controls and settings below. The catalogue opens under the section it adds to and searches as you type.
    component SectionStrip: Column {
        id: strip
        property var page
        property string section
        readonly property var entries: page.sectionList(section)
        spacing: Metrics.s2
        Label {
            role: "micro"
            caps: true
            tone: "faint"
            text: strip.page.sectionLabel(strip.section)
        }
        Flow {
            width: parent.width
            spacing: Metrics.s1
            Repeater {
                model: strip.entries
                delegate: Chip {
                    required property string modelData
                    required property int index
                    icon: strip.page.componentIcon(modelData)
                    text: strip.page.componentLabel(modelData)
                    active: strip.page.openWidget === strip.section + ":" + index
                    onClicked: {
                        const key = strip.section + ":" + index;
                        strip.page.openWidget = strip.page.openWidget === key ? "" : key;
                        strip.page.adding = "";
                    }
                }
            }
            Chip {
                icon: "plus"
                text: strip.entries.length === 0 ? "Add a component" : "Add"
                active: strip.page.adding === strip.section
                onClicked: {
                    strip.page.adding = strip.page.adding === strip.section ? "" : strip.section;
                    strip.page.query = "";
                    strip.page.openWidget = "";
                }
            }
        }
        // the catalogue
        Column {
            visible: strip.page.adding === strip.section
            width: parent.width
            spacing: Metrics.s2
            SearchField {
                id: search
                width: Math.min(parent.width, 360)
                placeholder: "Search components"
                onTextChanged: strip.page.query = text
                onVisibleChanged: if (visible)
                    forceActiveFocus()
                onAccepted: {
                    const first = strip.page.catalogue()[0];
                    if (first)
                        strip.page.add(strip.section, first.type);
                }
                onEscaped: strip.page.adding = ""
            }
            Flow {
                width: parent.width
                spacing: Metrics.s1
                Repeater {
                    model: strip.page.adding === strip.section ? strip.page.catalogue() : []
                    delegate: Chip {
                        required property var modelData
                        icon: modelData.icon
                        text: modelData.label
                        onClicked: strip.page.add(strip.section, modelData.type)
                    }
                }
            }
            Label {
                visible: strip.page.catalogue().length === 0
                role: "caption"
                tone: "faint"
                text: "No component matches"
            }
        }
        // the open component
        Loader {
            width: parent.width
            readonly property int openIndex: strip.page.openWidget.startsWith(strip.section + ":") ? parseInt(strip.page.openWidget.split(":")[1]) : -1
            active: openIndex >= 0 && openIndex < strip.entries.length
            sourceComponent: ComponentEditor {
                page: strip.page
                section: strip.section
                entryIndex: parent.openIndex
                name: strip.entries[parent.openIndex] ?? ""
                count: strip.entries.length
            }
        }
    }

    // a component's place on the bar and its settings
    component ComponentEditor: Rectangle {
        id: ce
        property var page
        property string section
        property int entryIndex
        property string name
        property int count
        readonly property bool isGroup: name.startsWith("group:")
        readonly property int sharedWith: isGroup ? 0 : BarModel.usage(page.state, name) - 1
        implicitHeight: ceCol.implicitHeight + Metrics.s4 * 2
        radius: Metrics.radiusMd
        color: Theme.plate
        Column {
            id: ceCol
            x: Metrics.s4
            y: Metrics.s4
            width: parent.width - Metrics.s4 * 2
            spacing: Metrics.s4
            Item {
                width: parent.width
                height: 30
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: ce.page.componentIcon(ce.name)
                        size: 16
                        tone: "accent"
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "title"
                        text: ce.page.componentLabel(ce.name)
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: ce.page.vertical ? "arrow-up" : "arrow-left"
                        tone: "muted"
                        enabled: !(ce.section === "start" && ce.entryIndex === 0)
                        onClicked: {
                            BarEdits.moveComponent(ce.page.barId, ce.section, ce.entryIndex, -1);
                            ce.page.openWidget = "";
                        }
                    }
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: ce.page.vertical ? "arrow-down" : "arrow-right"
                        tone: "muted"
                        enabled: !(ce.section === "end" && ce.entryIndex === ce.count - 1)
                        onClicked: {
                            BarEdits.moveComponent(ce.page.barId, ce.section, ce.entryIndex, 1);
                            ce.page.openWidget = "";
                        }
                    }
                    IconButton {
                        size: 28
                        iconSize: 13
                        icon: "trash"
                        tone: "muted"
                        onClicked: {
                            BarEdits.removeComponent(ce.page.barId, ce.section, ce.entryIndex);
                            ce.page.openWidget = "";
                        }
                    }
                }
            }
            // an older layout's component shared by several bars: say so, and offer its own copy
            Row {
                visible: ce.sharedWith > 0
                spacing: Metrics.s2
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    tone: "muted"
                    text: "Shared with " + ce.sharedWith + (ce.sharedWith === 1 ? " other bar" : " other bars") + ": a change here changes it there too."
                }
                Chip {
                    icon: "copy"
                    text: "Give this bar its own"
                    onClicked: BarEdits.separate(ce.page.barId, ce.section, ce.entryIndex)
                }
            }
            Loader {
                width: parent.width
                sourceComponent: ce.isGroup ? groupMembersEditor : settingsEditor
            }
            Component {
                id: settingsEditor
                WidgetSheet {
                    name: ce.name
                }
            }
            Component {
                id: groupMembersEditor
                Column {
                    spacing: 2
                    Label {
                        role: "caption"
                        tone: "faint"
                        text: "The group's components; its look is under Capsule groups."
                    }
                    Repeater {
                        model: ce.page.groupMembers(ce.name.slice(6))
                        delegate: MemberRow {
                            required property string modelData
                            width: parent.width
                            page: ce.page
                            name: modelData
                            key: ce.section + ":" + ce.entryIndex + ":" + modelData
                        }
                    }
                }
            }
        }
    }

    // capsule groups: several components in one capsule
    component GroupsCard: Card {
        id: groups
        property var page
        caption: "Capsule groups"
        Column {
            width: parent.width
            spacing: Metrics.s4
            Label {
                width: parent.width
                role: "caption"
                tone: "faint"
                wrapMode: Text.WordWrap
                text: "Several components in one capsule. An accordion shows its first component and opens while the pointer rests on it. Put a group on the bar with Add in Components."
            }
            Repeater {
                model: BarModel.list(groups.page.bar?.group)
                delegate: Column {
                    id: groupItem
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: Metrics.s2
                    function setGroup(key: string, value: var): void {
                        const list = BarModel.list(groups.page.bar.group);
                        const g = Object.assign({}, list[index]);
                        if (value === undefined)
                            delete g[key];
                        else
                            g[key] = value;
                        list[index] = g;
                        groups.page.setBar("group", list);
                    }
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.hairline
                    }
                    SchemaForm {
                        width: parent.width
                        advanced: "hide"
                        schema: [
                            { key: "enabled", label: "Drawn (off: the members sit loose)", kind: "toggle", default: true },
                            { key: "members", label: "Components in it (in order)", kind: "list", default: [] },
                            { key: "style", label: "Looks like (left out: the bar's)", kind: "choice", default: "", options: [{ key: "", label: "As the bar" }, { key: "capsule", label: "Capsule" }, { key: "plate", label: "Tone step" }, { key: "rule", label: "Rules" }] },
                            { key: "accordion", label: "Accordion", kind: "toggle", default: false },
                            { key: "accordion_direction", label: "Opens towards", kind: "choice", default: "end", options: [{ key: "start", label: "Start" }, { key: "end", label: "End" }], when: { accordion: [true] } },
                            { key: "fill", label: "Fill", kind: "colour", default: "surface_variant" },
                            { key: "opacity", label: "Opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01 },
                            { key: "padding", label: "Padding", kind: "int", default: 8, from: 0, to: 32, step: 1 },
                            { key: "widget_spacing", label: "Spacing", kind: "int", default: 4, from: 0, to: 32, step: 1 },
                            { key: "border", label: "Border colour", kind: "colour", default: "" },
                            { key: "foreground", label: "Component colour inside", kind: "colour", default: "" },
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
                            text: "Group " + groupItem.modelData.id
                        }
                        Chip {
                            icon: "trash"
                            text: "Remove group"
                            onClicked: groups.page.setBar("group", BarModel.list(groups.page.bar.group).filter((g, i) => i !== groupItem.index))
                        }
                    }
                }
            }
            Chip {
                icon: "plus"
                text: "New group"
                onClicked: {
                    const groups = BarModel.list(groups.page.bar.group);
                    const ids = groups.map(g => g.id);
                    let n = 1;
                    while (ids.includes("g" + n))
                        n++;
                    groups.page.setBar("group", groups.concat([{
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

    // a component inside a group: opened, its settings and gestures
    component MemberRow: Column {
        id: member
        property var page
        property string name
        property string key
        readonly property var spec: Config.resolveBarWidget(name)
        readonly property var info: BarWidgetTypes.find(spec.type)
        readonly property bool open: page.openMember === key
        Rectangle {
            width: parent.width
            height: 34
            radius: Metrics.radiusMd
            color: member.open ? Theme.selected : memberHover.containsMouse ? Theme.hover : "transparent"
            MouseArea {
                id: memberHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: member.page.openMember = member.open ? "" : member.key
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s3
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s3
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: member.info?.icon ?? "apps"
                    size: 14
                    tone: member.info ? "accent" : "danger"
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    text: member.info?.label ?? ("Unknown kind: " + member.spec.type)
                }
            }
            Icon {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s3
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-down"
                size: 13
                tone: "faint"
                rotation: member.open ? 180 : 0
            }
        }
        Loader {
            width: parent.width
            active: member.open
            sourceComponent: Item {
                implicitHeight: memberSheet.implicitHeight + Metrics.s3 * 2
                WidgetSheet {
                    id: memberSheet
                    x: Metrics.s3
                    y: Metrics.s3
                    width: parent.width - Metrics.s3 * 2
                    name: member.name
                }
            }
        }
    }

    // one component instance's settings and gestures (its [widget.<name>] table)
    component WidgetSheet: Column {
        id: ws
        property string name
        readonly property var spec: Config.resolveBarWidget(name)
        spacing: Metrics.s4
        SchemaForm {
            width: parent.width
            schema: BarWidgetTypes.schema(ws.spec.type)
            valueOf: key => BarWidgetTypes.value(ws.spec.type, ws.spec.settings, key)
            shows: spec => BarWidgetTypes.visible(ws.spec.type, spec, ws.spec.settings)
            isSet: key => ws.spec.settings[key] !== undefined
            onChanged: (key, value) => BarEdits.setComponentKey(ws.name, key, value)
            onCleared: key => BarEdits.setComponentKey(ws.name, key, undefined)
            commitOnRelease: true
            onPreviewed: (key, value) => BarEdits.previewComponent(ws.name, key, value)
            onPreviewEnded: (key, value, canceled) => BarEdits.endComponentPreview(ws.name, key, value, canceled)
        }
        Label {
            role: "micro"
            caps: true
            tone: "faint"
            text: "What it does"
        }
        GestureForm {
            width: parent.width
            actions: ws.spec.actions
            defaults: {
                const out = {};
                for (const g of BarWidgetTypes.gestures)
                    out[g] = BarWidgetTypes.action(ws.spec.type, ws.spec.settings, {}, g);
                return out;
            }
            reserved: BarWidgetTypes.find(ws.spec.type)?.reserved ?? []
            onChanged: (gesture, action) => BarEdits.setComponentAction(ws.name, gesture, action)
        }
    }

    // the gestures, each an action (a native command, exec …, none), its default shown when unset
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
