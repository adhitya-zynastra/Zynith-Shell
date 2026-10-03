import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The Control Panel: which modules in what order, which shortcut tiles and how big, how it looks, what each
// module shows, and tiles of your own. Everything here is panels.toml [control_panel].
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

    // ── modules ──
    readonly property var all: [
        { id: "header", label: "Who and when", detail: "Picture, name, date, the time, session and Settings" },
        { id: "shortcuts", label: "Shortcuts", detail: "The tiles below" },
        { id: "levels", label: "Levels", detail: "Volume, microphone, brightness sliders" },
        { id: "audio", label: "Sound", detail: "Output device and each app's level" },
        { id: "media", label: "Now playing" },
        { id: "monitor", label: "Displays", detail: "Each display's brightness, night light, light or dark" },
        { id: "power", label: "Power", detail: "Profiles, battery, charge limit, devices" },
        { id: "calendar", label: "Calendar", detail: "The month and what is coming up" },
        { id: "weather", label: "Weather", detail: "Now and the days ahead" },
        { id: "screen_time", label: "Screen time", detail: "Today's total and the apps" },
        { id: "system", label: "System", detail: "CPU and memory" },
        { id: "notifications", label: "Latest notifications" },
        { id: "clipboard", label: "Latest clipboard entries" }
    ]
    // the old switch rows are the shortcut tiles now
    readonly property var enabled: {
        const out = [];
        for (const m of Array.from(cp.modules ?? [])) {
            const id = m === "connectivity" || m === "toggles" ? "shortcuts" : m === "screen-time" ? "screen_time" : m;
            if (!out.includes(id))
                out.push(id);
        }
        return out;
    }
    readonly property var ordered: enabled.map(id => all.find(m => m.id === id)).filter(m => m).concat(all.filter(m => !enabled.includes(m.id)))

    function moved(list: var, id: string, by: int): var {
        const out = list.slice();
        const i = out.indexOf(id), j = i + by;
        if (i < 0 || j < 0 || j >= out.length)
            return out;
        out.splice(i, 1);
        out.splice(j, 0, id);
        return out;
    }

    PanelHeader {
        width: parent.width
        title: "Control Panel"
        caption: "Quick interaction; configuration lives here in Settings"
    }

    Card {
        width: parent.width
        caption: "Modules"

        Repeater {
            model: root.ordered
            delegate: Item {
                id: mod
                required property var modelData
                readonly property bool on: root.enabled.includes(modelData.id)
                width: parent.width
                height: 48

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label {
                        role: "body"
                        tone: mod.on ? "ink" : "faint"
                        text: mod.modelData.label
                    }
                    Label {
                        visible: !!mod.modelData.detail
                        role: "label"
                        tone: "faint"
                        text: mod.modelData.detail ?? ""
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    IconButton {
                        visible: mod.on
                        icon: "arrow-up"
                        tone: "muted"
                        onClicked: root.set("modules", root.moved(root.enabled, mod.modelData.id, -1))
                    }
                    IconButton {
                        visible: mod.on
                        icon: "arrow-down"
                        tone: "muted"
                        onClicked: root.set("modules", root.moved(root.enabled, mod.modelData.id, 1))
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: mod.on
                        onToggled: root.set("modules", mod.on ? root.enabled.filter(m => m !== mod.modelData.id) : root.enabled.concat([mod.modelData.id]))
                    }
                }
            }
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

    // ── how it looks ──
    Card {
        width: parent.width
        caption: "Look"
        SchemaForm {
            width: parent.width
            schema: [
                { key: "width", label: "Width", kind: "int", default: 420, from: 340, to: 760, step: 10 },
                { key: "spacing", label: "Between modules", kind: "int", default: 16, from: 0, to: 40, step: 1 },
                { key: "module_style", label: "Modules", kind: "choice", default: "plain", options: [{ key: "plain", label: "On the panel" }, { key: "cards", label: "Each on a card" }] },
                { key: "session_button", label: "Session button in the header", kind: "toggle", default: true },
                { key: "anchor_bar", label: "Opened by a key, it sits by", kind: "select", default: "", options: [{ key: "", label: "The top right corner" }].concat(Config.bars.filter(b => (b.id ?? "") !== "").map(b => ({ key: b.id, label: "Bar " + b.id }))) }
            ]
            valueOf: key => root.cp[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => !root.same(root.cp[key], schema.find(s => s.key === key)?.default)
            onChanged: (key, value) => root.set(key, value)
            onCleared: key => root.clear(key)
        }
    }

    // ── what the modules show ──
    Card {
        width: parent.width
        caption: "Modules show"
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
