import QtQuick
import Quickshell.Io
import qs.Common
import qs.Components
import qs.Services
import "../../Common/SectionLayout.js" as Layout

// The Control Panel: where it opens, how it is laid out, which sections show and where, the hero and tabs,
// the shortcut tiles, what each section shows, and tiles of your own. Everything here is panels.toml
// [control_panel]; which sections show and where is one list, `columns` (ControlSections).
Column {
    id: root
    spacing: Metrics.s5

    readonly property var cp: Config.controlPanel ?? ({})
    function set(key: string, value: var): void {
        Config.write("panels", "control_panel." + key, value);
    }
    function clear(key: string): void {
        Config.reset("panels", "control_panel." + key);
    }
    function same(a: var, b: var): bool {
        return JSON.stringify(a) === JSON.stringify(b);
    }
    function moved(list: var, id: string, by: int): var {
        const out = list.slice();
        const i = out.indexOf(id), j = i + by;
        if (i < 0 || j < 0 || j >= out.length)
            return out;
        out.splice(i, 1);
        out.splice(j, 0, id);
        return out;
    }

    // ── the sections: one arrangement, edited whole ──
    readonly property var columns: ControlSections.arrangement(cp)
    readonly property var shown: ControlSections.flat(columns)
    readonly property var weights: ControlSections.weights(columns, cp.column_widths)
    readonly property bool dashboard: (cp.layout ?? "dashboard") === "dashboard"
    // the retired `modules` list is still in the file: the first arrangement made here backs panels.toml up
    // (panels.toml.pre-sections, never overwritten) and moves it into `columns`
    readonly property bool legacy: cp.modules !== undefined
    property var pending: null
    Process {
        id: backup
        command: ["cp", "-n", Paths.config + "/panels.toml", Paths.config + "/panels.toml.pre-sections"]
        onExited: code => {
            const go = root.pending;
            root.pending = null;
            if (code !== 0) {
                console.warn("zynith: panels.toml backup failed, the arrangement is not written");
                return;
            }
            if (go)
                go();
        }
    }
    function arrange(next: var, nextWeights: var): void {
        const write = () => {
            if (root.legacy)
                root.clear("modules");
            root.set("columns", ControlSections.validate(next));
            if (nextWeights !== undefined)
                root.set("column_widths", nextWeights);
        };
        if (!legacy)
            return write();
        pending = write;
        backup.running = true;
    }
    // the edits (Common/SectionLayout.js); a change in the number of columns carries the weights with them
    function step(id: string, by: int): void {
        const next = Layout.step(columns, id, by, !dashboard);
        if (next !== columns)
            arrange(next, undefined);
    }
    function shift(id: string, by: int): void {
        const next = Layout.shift(columns, weights, id, by);
        if (next.columns !== columns)
            arrange(next.columns, next.columns.length !== columns.length ? next.weights : undefined);
    }
    function hide(id: string): void {
        const next = Layout.hide(columns, weights, id);
        arrange(next.columns, next.columns.length !== columns.length ? next.weights : undefined);
    }
    function show(id: string): void {
        arrange(Layout.show(columns, id), undefined);
    }
    function setWeight(c: int, w: real): void {
        const next = weights.slice();
        next[c] = Math.round(w * 10) / 10;
        set("column_widths", next);
    }
    function restoreSections(): void {
        const reset = () => {
            if (root.legacy)
                root.clear("modules");
            root.clear("columns");
            root.clear("column_widths");
        };
        if (!legacy)
            return reset();
        pending = reset;
        backup.running = true;
    }

    PanelHeader {
        width: parent.width
        title: "Control Panel"
        caption: "Quick interaction; configuration lives here in Settings"
    }

    // ── where it opens ──
    readonly property string position: cp.position ?? "auto"
    Card {
        width: parent.width
        caption: "Position"

        Row {
            spacing: Metrics.s5
            // the nine spots, as a little screen
            Grid {
                columns: 3
                spacing: Metrics.s1
                Repeater {
                    model: PanelRouter.spots
                    delegate: Rectangle {
                        id: spot
                        required property string modelData
                        readonly property bool on: root.position === modelData
                        width: 44
                        height: 28
                        radius: 6
                        color: on ? Theme.signalFill : spotArea.containsMouse ? Theme.hover : Theme.well
                        border.width: Metrics.hairline
                        border.color: on ? Theme.signalEdge : Theme.hairline
                        Rectangle {
                            // where the card sits in that spot
                            width: 14
                            height: 8
                            radius: 2
                            color: spot.on ? Theme.accent : Theme.inkFaint
                            x: spot.modelData.endsWith("left") ? 4 : spot.modelData.endsWith("right") ? parent.width - width - 4 : (parent.width - width) / 2
                            y: spot.modelData.startsWith("top") ? 4 : spot.modelData.startsWith("bottom") ? parent.height - height - 4 : (parent.height - height) / 2
                        }
                        MouseArea {
                            id: spotArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.set("position", spot.modelData)
                        }
                    }
                }
            }
            Column {
                spacing: Metrics.s2
                width: 300
                Chip {
                    text: "Automatic"
                    active: root.position === "auto"
                    onClicked: root.clear("position")
                }
                Chip {
                    text: "Follow what opened it"
                    active: root.position === "follow"
                    onClicked: root.set("position", "follow")
                }
                Label {
                    width: parent.width
                    role: "micro"
                    tone: "faint"
                    wrapMode: Text.WordWrap
                    text: root.position === "auto" ? "Beside the bar icon that opened it; by a key, beside the bar below, else the top right." : root.position === "follow" ? "Beside the bar icon that opened it; by a key, where it last opened on that screen." : "At that spot of the screen, clear of the bars' reserved room, on whichever screen it opens."
                }
            }
        }
        SchemaForm {
            width: parent.width
            schema: [
                { key: "position_margin", label: "Gap to the screen edge (at a spot)", kind: "int", default: 12, from: 0, to: 64, step: 1 },
                { key: "anchor_bar", label: "Opened by a key, it sits by", kind: "select", default: "", options: [{ key: "", label: "The top right corner" }].concat(Config.bars.filter(b => (b.id ?? "") !== "").map(b => ({ key: b.id, label: "Bar " + b.id }))) }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default)
            shows: spec => spec.key === "position_margin" ? PanelRouter.spots.includes(root.position) : root.position === "auto" || root.position === "follow"
            onChanged: (key, value) => root.set(key, value)
            onCleared: key => root.clear(key)
        }
    }

    // ── how it is laid out ──
    Card {
        width: parent.width
        caption: "Layout"
        SchemaForm {
            width: parent.width
            schema: [
                { key: "layout", label: "Sections", kind: "choice", default: "dashboard", options: [{ key: "dashboard", label: "Columns side by side" }, { key: "column", label: "One column" }] },
                { key: "dashboard_width", label: "Width", kind: "int", default: 1080, from: 600, to: 1600, step: 10, when: "dashboard" },
                { key: "width", label: "Width", kind: "int", default: 420, from: 340, to: 760, step: 10, when: "column" },
                { key: "spacing", label: "Between sections", kind: "int", default: 16, from: 0, to: 40, step: 1 },
                { key: "module_style", label: "Sections sit", kind: "choice", default: "auto", options: [{ key: "auto", label: "Automatic" }, { key: "plain", label: "On the panel" }, { key: "cards", label: "Each on a card" }] },
                { key: "section_heads", label: "Numbered heads", kind: "choice", default: "auto", options: [{ key: "auto", label: "Automatic" }, { key: true, label: "Shown" }, { key: false, label: "Hidden" }] },
                { key: "session_button", label: "Session button in the clock section", kind: "toggle", default: true }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default)
            shows: spec => !spec.when || spec.when === (root.cp.layout ?? "dashboard")
            onChanged: (key, value) => root.set(key, value)
            onCleared: key => root.clear(key)
        }
    }

    // ── which sections, where ──
    Card {
        width: parent.width
        caption: "Sections"

        Label {
            width: parent.width
            role: "label"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: root.dashboard ? "Each column top to bottom, columns left to right. Arrows reorder; the side arrows move a section to the next column." : "One column, in this order (the side arrows still choose a column for the side-by-side layout)."
        }

        Flow {
            id: board
            width: parent.width
            spacing: Metrics.s3
            // side by side as on the panel where they fit, else one under another at full width
            readonly property real perColumn: root.columns.length > 0 ? (width - spacing * (root.columns.length - 1)) / root.columns.length : width
            readonly property real colWidth: perColumn >= 260 ? perColumn : width
            Repeater {
                model: root.columns
                delegate: Rectangle {
                    id: colBox
                    required property var modelData
                    required property int index
                    width: board.colWidth
                    height: colBody.implicitHeight + Metrics.s3 * 2
                    radius: Metrics.radiusPlate
                    color: Theme.well
                    border.width: Metrics.hairline
                    border.color: Theme.hairline
                    Column {
                        id: colBody
                        x: Metrics.s3
                        y: Metrics.s3
                        width: parent.width - Metrics.s3 * 2
                        spacing: Metrics.s1
                        Item {
                            width: parent.width
                            height: 26
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "data"
                                tone: "faint"
                                text: "COLUMN " + (colBox.index + 1)
                            }
                            // its share of the width (dashboard)
                            Row {
                                visible: root.dashboard && root.columns.length > 1
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                IconButton {
                                    size: 22
                                    iconSize: 12
                                    icon: "minus"
                                    tone: "muted"
                                    onClicked: root.setWeight(colBox.index, Math.max(0.5, (root.weights[colBox.index] ?? 1) - 0.1))
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    horizontalAlignment: Text.AlignHCenter
                                    role: "label"
                                    numeric: true
                                    tone: "muted"
                                    text: "×" + (root.weights[colBox.index] ?? 1).toFixed(1)
                                }
                                IconButton {
                                    size: 22
                                    iconSize: 12
                                    icon: "plus"
                                    tone: "muted"
                                    onClicked: root.setWeight(colBox.index, Math.min(3, (root.weights[colBox.index] ?? 1) + 0.1))
                                }
                            }
                        }
                        Repeater {
                            model: colBox.modelData
                            delegate: Rectangle {
                                id: sec
                                required property string modelData
                                required property int index
                                readonly property var entry: ControlSections.find(modelData)
                                readonly property bool available: ControlSections.available(modelData)
                                width: colBody.width
                                height: 40
                                radius: 8
                                color: Theme.plate
                                Icon {
                                    id: secIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: Metrics.s2
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: sec.entry?.icon ?? "layout-grid"
                                    size: 15
                                    tone: sec.available ? "ink" : "faint"
                                }
                                Column {
                                    anchors.left: secIcon.right
                                    anchors.leftMargin: Metrics.s2
                                    anchors.right: secActions.left
                                    anchors.rightMargin: Metrics.s1
                                    anchors.verticalCenter: parent.verticalCenter
                                    Label {
                                        width: parent.width
                                        role: "body"
                                        elide: Text.ElideRight
                                        tone: sec.available ? "ink" : "faint"
                                        text: sec.entry?.label ?? sec.modelData
                                    }
                                    Label {
                                        visible: !sec.available
                                        width: parent.width
                                        role: "micro"
                                        tone: "faint"
                                        elide: Text.ElideRight
                                        text: ControlSections.unavailableReason(sec.modelData) + " · hidden"
                                    }
                                }
                                Row {
                                    id: secActions
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    IconButton {
                                        size: 24
                                        iconSize: 13
                                        icon: "chevron-left"
                                        tone: "muted"
                                        visible: colBox.index > 0
                                        onClicked: root.shift(sec.modelData, -1)
                                    }
                                    IconButton {
                                        size: 24
                                        iconSize: 13
                                        icon: "arrow-up"
                                        tone: "muted"
                                        onClicked: root.step(sec.modelData, -1)
                                    }
                                    IconButton {
                                        size: 24
                                        iconSize: 13
                                        icon: "arrow-down"
                                        tone: "muted"
                                        onClicked: root.step(sec.modelData, 1)
                                    }
                                    IconButton {
                                        size: 24
                                        iconSize: 13
                                        icon: "chevron-right"
                                        tone: "muted"
                                        visible: colBox.index < root.columns.length - 1 || root.columns.length < ControlSections.maxColumns
                                        onClicked: root.shift(sec.modelData, 1)
                                    }
                                    IconButton {
                                        size: 24
                                        iconSize: 13
                                        icon: "eye-off"
                                        tone: "muted"
                                        onClicked: root.hide(sec.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Label {
            visible: root.columns.length === 0
            role: "label"
            tone: "faint"
            text: "No sections: the panel shows only its hero and tabs."
        }

        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Hidden"
        }
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: ControlSections.entries.filter(e => !root.shown.includes(e.id))
                delegate: Chip {
                    required property var modelData
                    icon: "plus"
                    text: modelData.label + (ControlSections.available(modelData.id) ? "" : " (" + ControlSections.unavailableReason(modelData.id).toLowerCase() + ")")
                    onClicked: root.show(modelData.id)
                }
            }
        }
        Row {
            spacing: Metrics.s2
            Chip {
                icon: "refresh"
                text: "Restore the default sections"
                active: false
                onClicked: root.restoreSections()
            }
            Label {
                visible: root.legacy
                anchors.verticalCenter: parent.verticalCenter
                role: "micro"
                tone: "faint"
                text: "the first change backs panels.toml up"
            }
        }
    }

    // ── the hero and the tabs ──
    Card {
        width: parent.width
        caption: "Hero and tabs"
        SchemaForm {
            width: parent.width
            schema: [
                { key: "hero", label: "The wallpaper across the top, with you on it", kind: "toggle", default: true },
                { key: "hero_style", label: "Hero", kind: "choice", default: "card", options: [{ key: "card", label: "Inset card" }, { key: "band", label: "Full-bleed band" }], when: "hero" },
                { key: "hero_pages", label: "Over", kind: "choice", default: "all", options: [{ key: "all", label: "Every tab" }, { key: "dashboard", label: "The dashboard only" }], when: "hero" },
                { key: "hero_height", label: "Height", kind: "int", default: 150, from: 90, to: 260, step: 2, when: "hero" },
                { key: "hero_avatar_size", label: "Picture", kind: "int", default: 64, from: 32, to: 120, step: 2, when: "hero" },
                { key: "hero_shade", label: "Shade under the type", kind: "slider", default: 0.7, from: 0, to: 1, step: 0.05, when: "hero" },
                { key: "hero_clock", label: "Clock", kind: "toggle", default: true, when: "hero" },
                { key: "hero_weather", label: "Weather", kind: "toggle", default: true, when: "hero" },
                { key: "hero_details", label: "User, machine, system, uptime", kind: "toggle", default: true, when: "hero" },
                { key: "hero_drift", label: "Picture drifts slowly", kind: "toggle", default: true, when: "hero" },
                { key: "tab_bar", label: "Tabs over the Control Panel and its pages", kind: "toggle", default: true },
                { key: "tab_style", label: "Tabs", kind: "choice", default: "connected", options: [{ key: "connected", label: "Joined to the page" }, { key: "inline", label: "A pill" }, { key: "stacked", label: "An underline" }], when: "tab_bar" },
                { key: "tabs", label: "Which tabs, in order", kind: "list", default: ["control", "media", "audio", "power", "weather", "calendar"], hint: "control media audio power monitor calendar weather screen-time system network bluetooth notifications", when: "tab_bar" },
                { key: "page_columns", label: "Columns on a tab's page", kind: "int", default: 2, from: 1, to: 3, step: 1, when: "tab_bar" }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default)
            shows: spec => !spec.when || (root.cp[spec.when] ?? true) !== false
            onChanged: (key, value) => root.set(key, value)
            onCleared: key => root.clear(key)
        }
    }

    // ── shortcut tiles ──
    readonly property var tiles: Array.from(cp.shortcuts ?? [])
    readonly property var sizes: cp.tile_sizes ?? ({})
    Card {
        width: parent.width
        caption: "Shortcuts"

        Repeater {
            model: root.tiles
            delegate: Item {
                id: tile
                required property string modelData
                readonly property var entry: ControlShortcuts.find(modelData)
                readonly property bool wide: root.sizes[modelData] === "wide"
                width: parent.width
                height: 40

                Icon {
                    id: tileIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: tile.entry ? tile.entry.icon() : "alert-triangle"
                    tone: tile.entry ? "ink" : "danger"
                }
                Label {
                    anchors.left: tileIcon.right
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    role: "body"
                    text: tile.entry ? tile.entry.label() : tile.modelData + " (unknown)"
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Chip {
                        visible: (root.cp.shortcut_size ?? "regular") === "regular"
                        text: "Wide"
                        active: tile.wide
                        onClicked: {
                            const s = Object.assign({}, root.sizes);
                            if (tile.wide)
                                delete s[tile.modelData];
                            else
                                s[tile.modelData] = "wide";
                            root.set("tile_sizes", s);
                        }
                    }
                    IconButton {
                        icon: "arrow-up"
                        tone: "muted"
                        onClicked: root.set("shortcuts", root.moved(root.tiles, tile.modelData, -1))
                    }
                    IconButton {
                        icon: "arrow-down"
                        tone: "muted"
                        onClicked: root.set("shortcuts", root.moved(root.tiles, tile.modelData, 1))
                    }
                    IconButton {
                        icon: "x"
                        tone: "muted"
                        onClicked: root.set("shortcuts", root.tiles.filter(t => t !== tile.modelData))
                    }
                }
            }
        }
        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Add"
        }
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: ControlShortcuts.ids.filter(id => !root.tiles.includes(id))
                delegate: Chip {
                    required property string modelData
                    readonly property var entry: ControlShortcuts.find(modelData)
                    icon: entry?.icon() ?? ""
                    text: entry?.label() ?? modelData
                    onClicked: root.set("shortcuts", root.tiles.concat([modelData]))
                }
            }
        }
        SchemaForm {
            width: parent.width
            schema: [
                { key: "shortcut_size", label: "Tiles", kind: "choice", default: "regular", options: [{ key: "compact", label: "Round buttons" }, { key: "regular", label: "Two lines" }, { key: "wide", label: "One per row" }] },
                { key: "shortcut_columns", label: "Per row (0 picks by size)", kind: "int", default: 0, from: 0, to: 6, step: 1, when: { shortcut_size: ["compact", "regular"] } },
                { key: "shortcut_labels", label: "Names and states shown", kind: "toggle", default: true }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default)
            shows: spec => !spec.when || Object.keys(spec.when).every(k => spec.when[k].includes(root.cp[k] ?? "regular"))
            onChanged: (key, value) => root.set(key, value)
            onCleared: key => root.clear(key)
        }
    }

    // ── what the sections show ──
    Card {
        width: parent.width
        caption: "Sections show"
        SchemaForm {
            width: parent.width
            schema: [
                { key: "levels", label: "Levels, in order", kind: "list", default: ["volume", "mic", "brightness"], hint: "any of volume, mic, brightness" },
                { key: "mixer_apps", label: "Apps in the Sound module", kind: "int", default: 3, from: 0, to: 10, step: 1 },
                { key: "calendar_week_numbers", label: "Week numbers", kind: "toggle", default: false },
                { key: "calendar_events", label: "Calendar events", kind: "toggle", default: true },
                { key: "week_start", label: "Weeks start on", kind: "choice", default: "monday", options: [{ key: "monday", label: "Monday" }, { key: "sunday", label: "Sunday" }] },
                { key: "weather_forecast", label: "Forecast", kind: "choice", default: "daily", options: [{ key: "daily", label: "Days" }, { key: "hourly", label: "Hours" }] },
                { key: "screen_time_range", label: "Screen time over", kind: "choice", default: "1", options: [{ key: "1", label: "Today" }, { key: "3", label: "3 days" }, { key: "14", label: "14 days" }] }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default) && !(key === "screen_time_range" && Number(root.cp[key]) === 1)
            onChanged: (key, value) => root.set(key, key === "screen_time_range" ? Number(value) : value)
            onCleared: key => root.clear(key)
        }
    }

    // ── tiles of your own ──
    readonly property var custom: cp.custom ?? ({})
    Card {
        width: parent.width
        caption: "Your tiles"

        Label {
            width: parent.width
            role: "label"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: "A tile that runs an action: a native command (nightlight-toggle, screenshot-region…), panel <id>, exec <shell command>."
        }
        Repeater {
            model: Object.keys(root.custom)
            delegate: Column {
                id: own
                required property string modelData
                readonly property var spec: root.custom[modelData] ?? ({})
                width: parent.width
                spacing: Metrics.s2
                Item {
                    width: parent.width
                    height: 30
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "body"
                        font.weight: Font.Medium
                        text: "custom:" + own.modelData
                    }
                    IconButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "trash"
                        tone: "muted"
                        onClicked: {
                            root.set("shortcuts", root.tiles.filter(t => t !== "custom:" + own.modelData));
                            root.clear("custom." + own.modelData);
                        }
                    }
                }
                SchemaForm {
                    width: parent.width
                    schema: [
                        { key: "label", label: "Name", kind: "text", default: own.modelData },
                        { key: "detail", label: "Second line", kind: "text", default: "" },
                        { key: "icon", label: "Icon", kind: "glyph", default: "bolt" },
                        { key: "action", label: "Action", kind: "text", default: "", hint: "e.g. exec kitty, panel wallpaper, caffeine-toggle" },
                        { key: "more", label: "Chevron opens (a page or an action)", kind: "text", default: "" },
                        { key: "close", label: "Closes the panel", kind: "toggle", default: true }
                    ]
                    valueOf: key => own.spec[key] ?? schema.find(s => s.key === key)?.default
                    isSet: key => own.spec[key] !== undefined
                    onChanged: (key, value) => root.set("custom." + own.modelData + "." + key, value)
                    onCleared: key => root.clear("custom." + own.modelData + "." + key)
                }
            }
        }
        Row {
            spacing: Metrics.s2
            Rectangle {
                width: 220
                height: 32
                radius: 10
                color: Theme.well
                border.width: Metrics.hairline
                border.color: newName.activeFocus ? Theme.accentLine : Theme.hairline
                TextInput {
                    id: newName
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.s3
                    anchors.rightMargin: Metrics.s3
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Type.ui
                    font.pixelSize: Type.label
                    clip: true
                    validator: RegularExpressionValidator {
                        regularExpression: /[a-z0-9_-]{0,24}/
                    }
                    onAccepted: addTile.clicked()
                    Label {
                        visible: newName.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "faint"
                        text: "a name: terminal, vpn…"
                    }
                }
            }
            Chip {
                id: addTile
                icon: "plus"
                text: "Add a tile"
                onClicked: {
                    const name = newName.text.trim();
                    if (name === "" || root.custom[name] !== undefined)
                        return;
                    root.set("custom." + name, { label: name, icon: "bolt", action: "" });
                    root.set("shortcuts", root.tiles.concat(["custom:" + name]));
                    newName.text = "";
                }
            }
        }
    }
}
