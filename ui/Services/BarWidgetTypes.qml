pragma Singleton

import QtQuick
import Quickshell

// Every kind of bar widget the native shell had, with the same names, settings keys, choices and defaults, and
// the same gestures (left, right, middle, back, forward, scroll up/down/left/right → an action string). Nothing
// about a widget is fixed in its code: what it shows and what a click does come from here and from the user's
// bars.toml ([widget.<name>] tables, [widget.<name>.actions]).
//
// A setting: { key, label, kind, default, options?, from?, to?, step?, when? }  (as WidgetTypes)
Singleton {
    id: root

    // the names the first Zynith bars used, and other spellings
    readonly property var aliases: ({
            audio: "volume",
            power: "power_profile",
            control: "control-center",
            control_center: "control-center",
            quick: "control-center",
            visualizer: "audio_visualizer",
            keyboard: "keyboard_layout",
            idle_inhibitor: "caffeine",
            notification: "notifications"
        })
    function canonical(type: string): string {
        return aliases[type] ?? type;
    }

    readonly property var gestures: ["left", "right", "middle", "back", "forward", "scroll_up", "scroll_down", "scroll_left", "scroll_right", "hover"]
    readonly property var gestureLabels: ({
            left: "Click",
            right: "Right click",
            middle: "Middle click",
            back: "Back button",
            forward: "Forward button",
            scroll_up: "Scroll up",
            scroll_down: "Scroll down",
            scroll_left: "Scroll left",
            scroll_right: "Scroll right",
            // the pointer resting on it for hover_delay (the native Control Center's hover_open)
            hover: "Rest the pointer"
        })

    // settings every bar widget has
    readonly property var common: [
        { key: "color", label: "Colour", kind: "colour", default: "" },
        { key: "icon_color", label: "Icon colour", kind: "colour", default: "" },
        { key: "font_family", label: "Font", kind: "font", default: "" },
        { key: "font_scale", label: "Text size", kind: "slider", default: 1, from: 0.5, to: 2, step: 0.01 },
        { key: "scale", label: "Size", kind: "slider", default: 1, from: 0.5, to: 2, step: 0.01 },
        { key: "capsule", label: "Capsule", kind: "toggle", default: false },
        { key: "capsule_fill", label: "Capsule fill", kind: "colour", default: "surface_variant", when: { capsule: [true] } },
        { key: "capsule_opacity", label: "Capsule opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01, when: { capsule: [true] } },
        { key: "capsule_padding", label: "Capsule padding", kind: "int", default: 8, from: 0, to: 48, step: 1, when: { capsule: [true] } },
        { key: "capsule_radius", label: "Capsule radius", kind: "int", default: -1, from: -1, to: 32, step: 1, when: { capsule: [true] }, hint: "-1 is a pill" },
        { key: "capsule_border", label: "Capsule border", kind: "colour", default: "", when: { capsule: [true] } },
        { key: "interactive", label: "Takes clicks", kind: "toggle", default: true },
        { key: "open_on_hover", label: "Open its panel on hover", kind: "choice", default: "bar", options: [{ key: "bar", label: "As the bar" }, { key: "on", label: "On hover" }, { key: "off", label: "On click" }] },
        { key: "hover_delay", label: "Hover before it opens (ms)", kind: "int", default: -1, from: -1, to: 2000, step: 25, hint: "-1 follows the bar" },
        { key: "hover_close", label: "Close when the pointer leaves", kind: "choice", default: "bar", options: [{ key: "bar", label: "As the bar" }, { key: "on", label: "Yes" }, { key: "off", label: "No, click away" }] },
        { key: "hover_close_delay", label: "Leave before it closes (ms)", kind: "int", default: -1, from: -1, to: 3000, step: 25, hint: "-1 follows the bar" },
        { key: "tooltip", label: "Tooltip", kind: "text", default: "" }
    ]
    // a button that is a glyph or your own picture
    readonly property var glyphButton: [
        { key: "glyph", label: "Icon", kind: "glyph", default: "" },
        { key: "custom_image", label: "Picture instead", kind: "image", default: "" },
        { key: "custom_image_colorize", label: "Tint the picture", kind: "toggle", default: false, when: { custom_image_set: [true] } }
    ]
    readonly property var titleScroll: [{ key: "none", label: "Never" }, { key: "always", label: "Always" }, { key: "on_hover", label: "On hover" }]

    readonly property var types: [
        { type: "launcher", label: "Launcher", icon: "search", glyph: "search", settings: glyphButton, actions: { left: "panel-toggle launcher" } },
        { type: "control-center", label: "Control Panel", icon: "adjustments-horizontal", glyph: "adjustments-horizontal", settings: glyphButton, actions: { left: "panel-toggle control-center home" } },
        {
            type: "workspaces", label: "Workspaces", icon: "layout-grid",
            settings: [
                { key: "style", label: "Style", kind: "select", default: "regular", options: [{ key: "regular", label: "Classic pills" }, { key: "minimal", label: "Classic dots" }, { key: "focus_hint", label: "Classic focus hint" }, { key: "pills", label: "Pills" }, { key: "numbers", label: "Numbers" }, { key: "dots", label: "Dots" }, { key: "icons", label: "App icons" }, { key: "line", label: "Line" }] },
                { key: "indicator", label: "Active marker", kind: "choice", default: "auto", options: [{ key: "auto", label: "By style" }, { key: "pill", label: "Pill" }, { key: "mark", label: "Mark" }, { key: "dot", label: "Dot" }, { key: "line", label: "Line" }, { key: "ring", label: "Ring" }], when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "indicator_motion", label: "It moves", kind: "choice", default: "trail", options: [{ key: "trail", label: "Stretching" }, { key: "slide", label: "Gliding" }, { key: "none", label: "At once" }], when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "cell_size", label: "Cell size (0 fits the bar)", kind: "int", default: 0, from: 0, to: 64, step: 1, when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "spacing", label: "Between them (-1 automatic)", kind: "int", default: -1, from: -1, to: 24, step: 1, when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "pill_scale", label: "Mark thickness", kind: "slider", default: 1, from: 0.3, to: 2, step: 0.05, when: { style: ["regular", "minimal", "focus_hint", "pills", "dots"] } },
                { key: "active_pill_size", label: "Active length", kind: "slider", default: 2.2, from: 1, to: 8, step: 0.05, when: { style: ["regular", "pills"] } },
                { key: "capsule_radius", label: "Pill radius (-1 round)", kind: "int", default: -1, from: -1, to: 16, step: 1, when: { style: ["regular", "minimal", "focus_hint"] } },
                { key: "inactive_pill_size", label: "Inactive length", kind: "slider", default: 1, from: 0.5, to: 4, step: 0.05, when: { style: ["regular", "minimal", "pills"] } },
                { key: "occupied_bg", label: "Occupied ones share a background", kind: "toggle", default: false, when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "occupied_bg_color", label: "That background", kind: "colour", default: "surface_variant", when: { occupied_bg: [true] } },
                { key: "occupied_bg_opacity", label: "Its opacity", kind: "slider", default: 0.55, from: 0, to: 1, step: 0.01, when: { occupied_bg: [true] } },
                { key: "show_labels", label: "Labels", kind: "toggle", default: true },
                { key: "label_source", label: "Label from", kind: "choice", default: "id", options: [{ key: "id", label: "Number" }, { key: "name", label: "Name" }], when: { show_labels: [true] } },
                { key: "labels_only_when_occupied", label: "Labels only when occupied", kind: "toggle", default: false, when: { show_labels: [true] } },
                { key: "max_label_chars", label: "Label length", kind: "int", default: 2, from: 1, to: 20, step: 1, when: { show_labels: [true] } },
                { key: "label_case", label: "Letters", kind: "choice", default: "as_is", options: [{ key: "as_is", label: "As named" }, { key: "upper", label: "Upper" }, { key: "lower", label: "Lower" }], when: { style: ["pills", "numbers", "dots", "icons", "line"], show_labels: [true] } },
                { key: "active_label", label: "Active shows instead", kind: "text", default: "", hint: "a glyph or text, e.g. ●", when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "occupied_label", label: "Occupied show instead", kind: "text", default: "", when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "empty_label", label: "Empty show instead", kind: "text", default: "", when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "label_color", label: "Label colour", kind: "colour", default: "", when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "show_icons", label: "App icons in each", kind: "toggle", default: false },
                { key: "max_icons", label: "Icons at most", kind: "int", default: 3, from: 1, to: 8, step: 1, when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "icon_size", label: "Icon size (0 fits)", kind: "int", default: 0, from: 0, to: 48, step: 1, when: { style: ["pills", "numbers", "dots", "icons", "line"] } },
                { key: "focused_color", label: "Active", kind: "colour", default: "primary" },
                { key: "occupied_color", label: "Occupied", kind: "colour", default: "secondary" },
                { key: "empty_color", label: "Empty", kind: "colour", default: "secondary" },
                { key: "empty_opacity", label: "Empty opacity", kind: "slider", default: 0.55, from: 0, to: 1, step: 0.01 },
                { key: "urgent_color", label: "Urgent", kind: "colour", default: "error" },
                { key: "urgent_pulse", label: "Urgent ones breathe", kind: "toggle", default: true },
                { key: "change_color_on_hover", label: "Colour on hover", kind: "toggle", default: true },
                { key: "hide_when_empty", label: "Hide empty workspaces", kind: "toggle", default: false },
                { key: "show_all_outputs", label: "Every screen's workspaces", kind: "toggle", default: false },
                { key: "focused_output_only", label: "Only on the focused screen", kind: "toggle", default: false }
            ],
            actions: { scroll_up: "workspace-switch prev", scroll_down: "workspace-switch next" }, reserved: ["left"]
        },
        {
            type: "taskbar", label: "Taskbar", icon: "app-window",
            settings: [
                { key: "only_active_workspace", label: "Only this workspace", kind: "toggle", default: false },
                { key: "group_by_workspace", label: "Grouped by workspace", kind: "toggle", default: false },
                { key: "workspace_group_content", label: "A group shows", kind: "choice", default: "icons", options: [{ key: "icons", label: "Icons" }, { key: "count", label: "Count" }, { key: "dots", label: "Dots" }], when: { group_by_workspace: [true] } },
                { key: "workspace_group_capsule", label: "Groups in capsules", kind: "toggle", default: true, when: { group_by_workspace: [true] } },
                { key: "show_workspace_label", label: "Workspace label", kind: "toggle", default: true, when: { group_by_workspace: [true] } },
                { key: "workspace_label_placement", label: "Label sits", kind: "choice", default: "corner", options: [{ key: "corner", label: "Corner" }, { key: "centered", label: "Centred" }, { key: "inside", label: "Inside" }], when: { group_by_workspace: [true] } },
                { key: "hide_empty_workspaces", label: "Hide empty workspaces", kind: "toggle", default: false, when: { group_by_workspace: [true] } },
                { key: "group_single_icon_per_app", label: "One icon per app", kind: "toggle", default: false },
                { key: "show_window_title", label: "Window titles", kind: "toggle", default: false },
                { key: "window_title_max_width", label: "Title width", kind: "int", default: 100, from: 10, to: 200, step: 5, when: { show_window_title: [true] } },
                { key: "show_active_indicator", label: "Active indicator", kind: "toggle", default: true },
                { key: "active_indicator_color", label: "Indicator colour", kind: "colour", default: "primary", when: { show_active_indicator: [true] } },
                { key: "active_opacity", label: "Active opacity", kind: "slider", default: 1, from: 0.1, to: 1, step: 0.01 },
                { key: "inactive_opacity", label: "Inactive opacity", kind: "slider", default: 1, from: 0.1, to: 1, step: 0.01 },
                { key: "icon_scale", label: "Icon size", kind: "slider", default: 1, from: 0.1, to: 2, step: 0.05 },
                { key: "item_spacing", label: "Spacing", kind: "int", default: 4, from: 0, to: 48, step: 1 },
                { key: "pinned", label: "Pinned apps", kind: "list", default: [] },
                { key: "pinned_opacity", label: "Pinned (not running) opacity", kind: "slider", default: 0.5, from: 0, to: 1, step: 0.01 },
                { key: "minimal", label: "Minimal", kind: "toggle", default: false },
                { key: "show_all_outputs", label: "Every screen's windows", kind: "toggle", default: false },
                { key: "focused_output_only", label: "Only on the focused screen", kind: "toggle", default: false },
                { key: "taskbar_max_width", label: "Most length", kind: "int", default: 8192, from: 10, to: 8192, step: 10 },
                { key: "focused_color", label: "Focused workspace colour", kind: "colour", default: "primary", when: { group_by_workspace: [true] } },
                { key: "occupied_color", label: "Occupied workspace colour", kind: "colour", default: "secondary", when: { group_by_workspace: [true] } },
                { key: "empty_color", label: "Empty workspace colour", kind: "colour", default: "secondary", when: { group_by_workspace: [true] } },
                { key: "urgent_color", label: "Urgent workspace colour", kind: "colour", default: "error", when: { group_by_workspace: [true] } },
                { key: "capsule_radius", label: "Group capsule radius (-1 is a pill)", kind: "int", default: -1, from: -1, to: 32, step: 1, when: { workspace_group_capsule: [true] } }
            ],
            actions: { scroll_up: "taskbar-cycle prev", scroll_down: "taskbar-cycle next" }, reserved: ["left", "middle"]
        },
        {
            type: "active_window", label: "Active window", icon: "window",
            settings: [
                { key: "display", label: "Shows", kind: "choice", default: "icon_and_text", options: [{ key: "icon_and_text", label: "Icon and title" }, { key: "icon_only", label: "Icon" }, { key: "text_only", label: "Title" }] },
                { key: "min_length", label: "Least length", kind: "int", default: 80, from: 0, to: 800, step: 10 },
                { key: "max_length", label: "Most length", kind: "int", default: 260, from: 40, to: 800, step: 10 },
                { key: "icon_size", label: "Icon size", kind: "int", default: 13, from: 8, to: 64, step: 1 },
                { key: "title_scroll", label: "Long titles scroll", kind: "choice", default: "none", options: titleScroll },
                { key: "show_empty_label", label: "Say so when nothing is focused", kind: "toggle", default: false }
            ]
        },
        {
            type: "clock", label: "Clock", icon: "clock",
            settings: [
                { key: "format", label: "Format", kind: "text", default: "{:%H:%M}", hint: "strftime; \\n for a new line" },
                { key: "vertical_format", label: "On a vertical bar", kind: "text", default: "", hint: "empty: hours over minutes" },
                { key: "tooltip_format", label: "Tooltip", kind: "text", default: "" },
                { key: "timezone", label: "Time zone", kind: "text", default: "" }
            ],
            actions: { left: "panel-toggle calendar" }
        },
        {
            type: "media", label: "Media", icon: "music",
            settings: [
                { key: "album_art_only", label: "Cover only", kind: "toggle", default: false },
                { key: "hide_album_art", label: "No cover", kind: "toggle", default: false },
                { key: "art_size", label: "Cover size", kind: "int", default: 16, from: 8, to: 96, step: 1 },
                { key: "hide_artist", label: "No artist", kind: "toggle", default: false },
                { key: "artist_first", label: "Artist first", kind: "toggle", default: false },
                { key: "min_length", label: "Least length", kind: "int", default: 80, from: 0, to: 800, step: 10 },
                { key: "max_length", label: "Most length", kind: "int", default: 220, from: 40, to: 800, step: 10 },
                { key: "title_scroll", label: "Long titles scroll", kind: "choice", default: "none", options: titleScroll },
                { key: "show_progress", label: "Progress", kind: "toggle", default: false },
                { key: "hide_when_no_media", label: "Hide when nothing plays", kind: "toggle", default: false }
            ],
            actions: { left: "panel-toggle media", right: "media toggle", back: "media previous", forward: "media next", scroll_up: "media next", scroll_down: "media previous" }
        },
        {
            type: "audio_visualizer", label: "Visualizer", icon: "activity",
            settings: [
                { key: "width", label: "Length", kind: "int", default: 56, from: 8, to: 2048, step: 2 },
                { key: "bands", label: "Bands", kind: "int", default: 16, from: 2, to: 128, step: 1 },
                { key: "mirrored", label: "Mirrored", kind: "toggle", default: true },
                { key: "reversed", label: "Reversed", kind: "toggle", default: false },
                { key: "centered", label: "From the middle", kind: "toggle", default: true },
                { key: "show_when_idle", label: "Show when silent", kind: "toggle", default: false },
                { key: "bar_style", label: "Bars", hint: "Square: the sharp bars of the native visualizer", kind: "choice", default: "square", options: [{ key: "square", label: "Square" }, { key: "rounded", label: "Rounded" }] },
                { key: "smoothing", label: "Smoothing (ms)", hint: "How long a bar takes to glide to a new level; 0 jumps", kind: "int", default: 60, from: 0, to: 300, step: 5 },
                { key: "color_1", label: "Colour", kind: "colour", default: "primary" },
                { key: "color_2", label: "Second colour", kind: "colour", default: "primary" }
            ]
        },
        {
            type: "tray", label: "Tray", icon: "dots",
            settings: [
                { key: "drawer", label: "In a drawer", kind: "toggle", default: false },
                { key: "drawer_columns", label: "Drawer columns", kind: "int", default: 3, from: 1, to: 5, step: 1, when: { drawer: [true] } },
                { key: "drawer_item_size", label: "Drawer icon size", kind: "int", default: 18, from: 8, to: 64, step: 1, when: { drawer: [true] } },
                { key: "pinned", label: "Always on the bar", kind: "list", default: [], when: { drawer: [true] } },
                { key: "hidden", label: "Never shown", kind: "list", default: [] },
                { key: "hide_passive", label: "Hide passive items", kind: "toggle", default: true },
                { key: "match_adjacent_spacing", label: "Match neighbours' spacing", kind: "toggle", default: false },
                { key: "detached_panel", label: "Drawer as a separate panel", kind: "toggle", default: false, when: { drawer: [true] } }
            ],
            reserved: ["left", "right"]
        },
        {
            type: "network", label: "Network", icon: "wifi",
            settings: [
                { key: "show_label", label: "Name", kind: "toggle", default: true },
                { key: "vpn_status", label: "VPN", kind: "choice", default: "replace", options: [{ key: "replace", label: "Replaces Wi-Fi" }, { key: "both", label: "Both" }, { key: "hidden", label: "Hidden" }] },
                { key: "show_vpn_label", label: "VPN name", kind: "toggle", default: false }
            ],
            actions: { left: "panel-toggle network", right: "network-toggle" }
        },
        {
            type: "bluetooth", label: "Bluetooth", icon: "bluetooth",
            settings: [
                { key: "show_label", label: "Device name", kind: "toggle", default: false },
                { key: "hide_when_adapter_off", label: "Hide when off", kind: "toggle", default: false },
                { key: "hide_when_no_connected_device", label: "Hide with nothing connected", kind: "toggle", default: false }
            ],
            actions: { left: "panel-toggle bluetooth", right: "bluetooth-toggle" }
        },
        {
            type: "volume", label: "Volume", icon: "volume",
            settings: [
                { key: "device", label: "Device", kind: "choice", default: "output", options: [{ key: "output", label: "Output" }, { key: "input", label: "Microphone" }] },
                { key: "show_label", label: "Level", kind: "toggle", default: true },
                { key: "glyph", label: "Icon", kind: "glyph", default: "" },
                { key: "mute_glyph", label: "Muted icon", kind: "glyph", default: "" },
                { key: "mute_color", label: "Muted colour", kind: "colour", default: "error" },
                { key: "custom_image", label: "Picture instead", kind: "image", default: "" },
                { key: "custom_image_colorize", label: "Tint the picture", kind: "toggle", default: false, when: { custom_image_set: [true] } },
                { key: "effects_profile_glyphs", label: "Icon per EasyEffects profile", kind: "pairs", default: {}, placeholder: "profile = glyph, then Enter" },
                { key: "hide_when_inactive", label: "Hide when unused", kind: "toggle", default: false, when: { device: ["input"] } }
            ],
            actions: { left: "panel-toggle audio", right: "volume-mute", scroll_up: "volume-up", scroll_down: "volume-down" },
            inputActions: { left: "panel-toggle audio", right: "mic-mute", scroll_up: "mic-volume-up", scroll_down: "mic-volume-down" }
        },
        {
            type: "brightness", label: "Brightness", icon: "brightness-up",
            settings: [{ key: "show_label", label: "Level", kind: "toggle", default: true }],
            actions: { left: "panel-toggle monitor", scroll_up: "brightness-up", scroll_down: "brightness-down" }
        },
        {
            type: "battery", label: "Battery", icon: "battery",
            settings: [
                { key: "display_mode", label: "Shows", kind: "choice", default: "glyph", options: [{ key: "none", label: "Nothing" }, { key: "glyph", label: "Icon" }, { key: "graphic", label: "Gauge" }] },
                { key: "show_label", label: "Label", kind: "toggle", default: true },
                { key: "label_content", label: "Label says", kind: "choice", default: "percent", options: [{ key: "percent", label: "Percent" }, { key: "time", label: "Time left" }, { key: "rate", label: "Rate" }], when: { show_label: [true] } },
                { key: "hide_when_plugged", label: "Hide when plugged in", kind: "toggle", default: false },
                { key: "hide_when_full", label: "Hide when full", kind: "toggle", default: false },
                { key: "device", label: "Battery", kind: "text", default: "auto" },
                { key: "warning_threshold", label: "Warn below %", kind: "int", default: 0, from: 0, to: 100, step: 1 },
                { key: "warning_color", label: "Warning colour", kind: "colour", default: "error" }
            ],
            actions: { left: "panel-toggle power" }
        },
        {
            type: "power_profile", label: "Power profile", icon: "gauge", settings: [],
            actions: { left: "power-cycle next", right: "power-cycle prev", scroll_up: "power-cycle next", scroll_down: "power-cycle prev" }
        },
        {
            type: "notifications", label: "Notifications", icon: "bell",
            settings: [{ key: "hide_when_no_unread", label: "Hide when there is nothing", kind: "toggle", default: false }],
            actions: { left: "panel-toggle notifications", right: "notification-dnd-toggle" }
        },
        {
            type: "keyboard_layout", label: "Keyboard layout", icon: "keyboard",
            settings: [
                { key: "display", label: "Name", kind: "choice", default: "short", options: [{ key: "short", label: "Short" }, { key: "full", label: "Full" }] },
                { key: "show_label", label: "Name shown", kind: "toggle", default: true },
                { key: "show_glyph", label: "Icon", kind: "toggle", default: true },
                { key: "glyph", label: "Which icon", kind: "glyph", default: "keyboard", when: { show_glyph: [true] } },
                { key: "custom_image", label: "Picture instead", kind: "image", default: "" },
                { key: "custom_image_colorize", label: "Tint the picture", kind: "toggle", default: false, when: { custom_image_set: [true] } },
                { key: "hide_when_single_layout", label: "Hide with one layout", kind: "toggle", default: false }
            ],
            actions: { left: "keyboard-layout-cycle" }
        },
        {
            type: "lock_keys", label: "Lock keys", icon: "arrow-big-up-line",
            settings: [
                { key: "show_caps_lock", label: "Caps Lock", kind: "toggle", default: true },
                { key: "show_num_lock", label: "Num Lock", kind: "toggle", default: true },
                { key: "show_scroll_lock", label: "Scroll Lock", kind: "toggle", default: false },
                { key: "hide_when_off", label: "Hide when off", kind: "toggle", default: false },
                { key: "display", label: "Names", kind: "choice", default: "short", options: [{ key: "short", label: "Short" }, { key: "full", label: "Full" }] }
            ]
        },
        {
            type: "privacy", label: "Privacy", icon: "shield",
            settings: [
                { key: "hide_inactive", label: "Hide when nothing is in use", kind: "toggle", default: false },
                { key: "icon_spacing", label: "Spacing", kind: "int", default: 4, from: 0, to: 48, step: 1 },
                { key: "active_color", label: "In use", kind: "colour", default: "primary" },
                { key: "inactive_color", label: "Not in use", kind: "colour", default: "outline" }
            ]
        },
        {
            type: "sysmon", label: "System", icon: "cpu",
            settings: [
                { key: "stat", label: "Shows", kind: "select", default: "cpu_usage", options: [{ key: "cpu_usage", label: "CPU use" }, { key: "cpu_temp", label: "CPU temperature" }, { key: "cpu_freq", label: "CPU clock" }, { key: "gpu_temp", label: "GPU temperature" }, { key: "gpu_usage", label: "GPU use" }, { key: "gpu_vram", label: "GPU memory %" }, { key: "gpu_vram_used", label: "GPU memory used" }, { key: "ram_used", label: "Memory used" }, { key: "ram_pct", label: "Memory %" }, { key: "swap_pct", label: "Swap" }, { key: "disk_used_pct", label: "Disk used %" }, { key: "disk_used", label: "Disk used" }, { key: "disk_free_pct", label: "Disk free %" }, { key: "disk_free", label: "Disk free" }, { key: "net_rx", label: "Download" }, { key: "net_tx", label: "Upload" }] },
                { key: "path", label: "Disk (a mount point)", kind: "path", default: "/", when: { stat: ["disk_used_pct", "disk_used", "disk_free_pct", "disk_free"] } },
                { key: "visualization", label: "As", kind: "choice", default: "gauge", options: [{ key: "gauge", label: "Gauge" }, { key: "graph", label: "Graph" }, { key: "none", label: "Text" }] },
                { key: "show_value", label: "Value", kind: "toggle", default: true },
                { key: "label_show_units", label: "Units", kind: "toggle", default: true, when: { show_value: [true] } },
                { key: "label_min_width", label: "Value width", kind: "int", default: 0, from: 0, to: 200, step: 2, when: { show_value: [true] } },
                { key: "show_glyph", label: "Icon", kind: "toggle", default: true },
                { key: "glyph", label: "Which icon", kind: "glyph", default: "", when: { show_glyph: [true] } },
                { key: "custom_image", label: "Picture instead", kind: "image", default: "" },
                { key: "custom_image_colorize", label: "Tint the picture", kind: "toggle", default: false, when: { custom_image_set: [true] } },
                { key: "glyph_position", label: "Icon sits", kind: "choice", default: "before", options: [{ key: "before", label: "Before" }, { key: "after", label: "After" }], when: { show_glyph: [true] } },
                { key: "highlight_color", label: "High-load colour", kind: "colour", default: "error" },
                { key: "interface", label: "Network interface (empty: all)", kind: "text", default: "", when: { stat: ["net_rx", "net_tx"] } },
                { key: "network_speed_unit", label: "Speed in", kind: "choice", default: "auto", options: [{ key: "auto", label: "Auto" }, { key: "kb", label: "KB/s" }, { key: "mb", label: "MB/s" }], when: { stat: ["net_rx", "net_tx"] } },
                { key: "network_speed_compact", label: "Compact speed (1.2M)", kind: "toggle", default: false, when: { stat: ["net_rx", "net_tx"] } }
            ],
            actions: { left: "panel-toggle system" }
        },
        {
            type: "weather", label: "Weather", icon: "cloud",
            settings: [
                { key: "show_condition", label: "Condition", kind: "toggle", default: true },
                { key: "show_temperature", label: "Temperature", kind: "toggle", default: true },
                { key: "max_length", label: "Most length", kind: "int", default: 160, from: 40, to: 800, step: 10 }
            ],
            actions: { left: "panel-toggle weather" }
        },
        { type: "nightlight", label: "Night light", icon: "moon", settings: [], actions: { left: "nightlight-toggle", right: "nightlight-force-toggle" } },
        { type: "caffeine", label: "Caffeine", icon: "coffee", settings: [], actions: { left: "caffeine-toggle" } },
        { type: "theme_mode", label: "Light / dark", icon: "sun-moon", settings: [], actions: { left: "theme-mode-toggle" } },
        { type: "clipboard", label: "Clipboard", icon: "clipboard", glyph: "clipboard", settings: glyphButton, actions: { left: "panel-toggle clipboard" } },
        { type: "wallpaper", label: "Wallpaper", icon: "photo", glyph: "photo", settings: glyphButton, actions: { left: "panel-toggle wallpaper" } },
        { type: "screenshot", label: "Screenshot", icon: "screenshot", glyph: "screenshot", settings: glyphButton, actions: { left: "screenshot-region" }, reserved: ["right"] },
        { type: "settings", label: "Settings", icon: "settings", glyph: "settings", settings: glyphButton, actions: { left: "settings-open" } },
        { type: "session", label: "Session", icon: "power", glyph: "power", settings: glyphButton, actions: { left: "panel-toggle session" } },
        {
            type: "custom_button", label: "Button", icon: "rocket", glyph: "heart",
            settings: glyphButton.concat([{ key: "label", label: "Label", kind: "text", default: "" }]),
            actions: {}
        },
        { type: "text", label: "Text", icon: "letter-a", settings: [{ key: "text", label: "Text", kind: "text", default: "" }] },
        {
            type: "spacer", label: "Space", icon: "arrows-diagonal",
            settings: [{ key: "length", label: "Length", kind: "int", default: 20, from: 0, to: 400, step: 2 }]
        },
        { type: "divider", label: "Divider", icon: "minus", settings: [] }
    ]

    // ── the library, as the bar editor shows it: kinds in plain categories, each with a line on what it is for ──
    readonly property var categories: [
        { key: "navigate", label: "Apps & windows", kinds: ["launcher", "workspaces", "taskbar", "active_window"] },
        { key: "info", label: "Time & info", kinds: ["clock", "weather", "sysmon", "notifications"] },
        { key: "media", label: "Media", kinds: ["island", "media", "audio_visualizer"] },
        { key: "status", label: "Status", kinds: ["network", "bluetooth", "volume", "brightness", "battery", "power_profile", "tray", "keyboard_layout", "lock_keys", "privacy"] },
        { key: "controls", label: "Quick controls", kinds: ["control-center", "nightlight", "caffeine", "theme_mode", "clipboard", "wallpaper", "screenshot", "settings", "session", "custom_button"] },
        { key: "layout", label: "Layout", kinds: ["spacer", "divider", "text"] }
    ]
    readonly property var descriptions: ({
            launcher: "Opens the app launcher",
            workspaces: "Your workspaces; click one to go there",
            taskbar: "Running apps, one icon each",
            active_window: "The title of the focused window",
            clock: "The time and date, in any format",
            weather: "Current conditions where you are",
            sysmon: "CPU, memory and temperature",
            notifications: "Unread count; opens the notification centre",
            island: "A living pill: music, notifications and timers as they happen",
            media: "What is playing, with controls",
            audio_visualizer: "Bars that move with the sound",
            network: "Wi-Fi or wired; opens network settings",
            bluetooth: "Bluetooth and its devices",
            volume: "Sound level; scroll to change",
            brightness: "Screen brightness; scroll to change",
            battery: "Charge and time left",
            power_profile: "Performance, balanced or power saver",
            tray: "Icons of apps running in the background",
            keyboard_layout: "The current keyboard layout",
            lock_keys: "Caps Lock and Num Lock",
            privacy: "Shows when the camera, microphone or screen is in use",
            "control-center": "Opens the Control Panel",
            nightlight: "Warmer colours in the evening",
            caffeine: "Keeps the screen awake",
            theme_mode: "Switch light and dark",
            clipboard: "Clipboard history",
            wallpaper: "Change the wallpaper",
            screenshot: "Take a screenshot",
            settings: "Opens Settings",
            session: "Lock, log out, restart, shut down",
            custom_button: "Your own button: an icon that runs a command",
            spacer: "Empty room that pushes things apart",
            divider: "A thin line between components",
            text: "Words of your own"
        })
    function categoryOf(type: string): string {
        const t = canonical(type);
        return categories.find(c => c.kinds.includes(t))?.key ?? "controls";
    }
    // the library, filtered by a search (label, kind, description) and a category key ("" = all)
    function library(query: string, category: string): var {
        const q = String(query ?? "").trim().toLowerCase();
        return types.filter(t => (category === "" || categoryOf(t.type) === category) && (q === "" || t.label.toLowerCase().includes(q) || t.type.includes(q) || (descriptions[t.type] ?? "").toLowerCase().includes(q)));
    }

    function find(type: string): var {
        const t = canonical(type);
        return types.find(x => x.type === t) ?? null;
    }
    function schema(type: string): var {
        const t = find(type);
        return (t?.settings ?? []).concat(t?.type === "spacer" || t?.type === "divider" ? [] : common);
    }
    function value(type: string, settings: var, key: string): var {
        if (settings && settings[key] !== undefined)
            return settings[key];
        if (key === "glyph") {
            const t = find(type);
            return t?.glyph ?? "";
        }
        return schema(type).find(s => s.key === key)?.default;
    }
    function visible(type: string, spec: var, settings: var): bool {
        if (!spec.when)
            return true;
        for (const [k, values] of Object.entries(spec.when)) {
            const v = k === "custom_image_set" ? ((settings?.custom_image ?? "") !== "") : value(type, settings, k);
            if (!values.includes(v))
                return false;
        }
        return true;
    }

    // what a gesture does: the widget's own setting, else its kind's default (a microphone volume drives the
    // source), else middle opens the widget's settings
    function action(type: string, settings: var, actions: var, gesture: string): string {
        if (actions && actions[gesture] !== undefined)
            return actions[gesture];
        const t = find(type);
        const defaults = t?.type === "volume" && value("volume", settings, "device") === "input" ? t.inputActions : (t?.actions ?? {});
        if (defaults[gesture] !== undefined)
            return defaults[gesture];
        return gesture === "middle" ? "settings-open-widget" : "";
    }
    function reserved(type: string, gesture: string): bool {
        return (find(type)?.reserved ?? []).includes(gesture);
    }
}
