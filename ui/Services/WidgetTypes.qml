pragma Singleton

import QtQuick
import Quickshell

// Every kind of desktop widget: what it is called, its default box, and the settings it takes (a schema the
// editor's inspector draws from). The settings keys are the native shell's, so layouts carry over unchanged.
//
// A setting: { key, label, kind, default, options?, from?, to?, step?, when? }
//   kind: toggle | choice | select | slider | int | text | colour | font | image | glyph
//   when: { key: [values] } — shown only while every named setting has one of those values
Singleton {
    id: root

    readonly property var colourRoles: ["on_surface", "on_surface_variant", "primary", "secondary", "tertiary", "surface", "surface_variant", "error"]
    readonly property var anchors: [
        { key: "free", label: "Scales" },
        { key: "top_left", label: "Top left" },
        { key: "top", label: "Top" },
        { key: "top_right", label: "Top right" },
        { key: "left", label: "Left" },
        { key: "center", label: "Centre" },
        { key: "right", label: "Right" },
        { key: "bottom_left", label: "Bottom left" },
        { key: "bottom", label: "Bottom" },
        { key: "bottom_right", label: "Bottom right" }
    ]

    // settings every widget has (session buttons and command buttons only the anchor)
    function common(type: string): var {
        const anchor = { key: "anchor", label: "Keeps its place to", kind: "select", default: "free", options: anchors };
        if (type === "button" || type === "session_actions")
            return [anchor];
        const on = { background: [true] };
        return [anchor,
            // on by default, as natively (the native fancy visualizer was the one exception)
            { key: "background", label: "Background", kind: "toggle", default: true },
            { key: "background_color", label: "Background colour", kind: "colour", default: "surface", when: on },
            { key: "background_opacity", label: "Background opacity", kind: "slider", default: 0.8, from: 0, to: 1, step: 0.01, when: on },
            { key: "background_radius", label: "Corner radius", kind: "int", default: 12, from: 0, to: 32, step: 1, when: on },
            { key: "background_padding", label: "Padding", kind: "int", default: 10, from: 0, to: 32, step: 1, when: on }];
    }

    readonly property var types: [
        {
            type: "clock", label: "Clock", icon: "clock", size: [360, 140],
            settings: [
                { key: "clock_style", label: "Style", kind: "choice", default: "digital", options: [{ key: "digital", label: "Digital" }, { key: "analog", label: "Analog" }] },
                { key: "format", label: "Format", kind: "text", default: "{:%H:%M}", when: { clock_style: ["digital"] }, hint: "strftime, e.g. {:%H:%M} or {:%A %d}" },
                { key: "timezone", label: "Time zone", kind: "text", default: "", hint: "e.g. Asia/Tokyo; empty is local" },
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" },
                { key: "font_family", label: "Font", kind: "font", default: "", when: { face: ["custom"] } },
                { key: "face", label: "Face", kind: "choice", default: "custom", options: [{ key: "custom", label: "Custom" }, { key: "display", label: "Display" }, { key: "interface", label: "Interface" }], when: { clock_style: ["digital"] } },
                { key: "weight", label: "Weight", kind: "choice", default: "bold", options: [{ key: "light", label: "Light" }, { key: "regular", label: "Regular" }, { key: "bold", label: "Bold" }], when: { clock_style: ["digital"] } },
                { key: "tabular", label: "Even digits", kind: "toggle", default: false, when: { clock_style: ["digital"] } },
                { key: "shadow", label: "Shadow", kind: "toggle", default: true },
                { key: "circle", label: "Dial", kind: "toggle", default: true, when: { clock_style: ["analog"] } }
            ]
        },
        {
            type: "label", label: "Text", icon: "letter-a", size: [420, 120],
            settings: [
                { key: "title", label: "Title", kind: "text", default: "Title" },
                { key: "description", label: "Line", kind: "text", default: "" },
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" },
                { key: "opacity", label: "Opacity", kind: "slider", default: 1, from: 0, to: 1, step: 0.01 },
                { key: "font_family", label: "Font", kind: "font", default: "" },
                { key: "shadow", label: "Shadow", kind: "toggle", default: true }
            ]
        },
        {
            type: "sticker", label: "Image", icon: "photo", size: [240, 240],
            settings: [
                { key: "image_path", label: "Image", kind: "image", default: "" },
                { key: "opacity", label: "Opacity", kind: "slider", default: 1, from: 0, to: 1, step: 0.01 }
            ]
        },
        {
            type: "audio_visualizer", label: "Visualizer", icon: "activity", size: [640, 160],
            settings: [
                { key: "visualization_mode", label: "Shape", kind: "select", default: "bars", options: [{ key: "bars", label: "Bars" }, { key: "wave", label: "Wave" }, { key: "rings", label: "Rings" }, { key: "bars_rings", label: "Bars and rings" }, { key: "wave_rings", label: "Wave and rings" }] },
                { key: "bands", label: "Bands", kind: "int", default: 32, from: 4, to: 128, step: 4 },
                { key: "mirrored", label: "Mirrored", kind: "toggle", default: true },
                { key: "reversed", label: "Reversed", kind: "toggle", default: false },
                { key: "centered", label: "From the middle", kind: "toggle", default: true },
                { key: "show_when_idle", label: "Show when silent", kind: "toggle", default: true },
                { key: "color_1", label: "Colour", kind: "colour", default: "primary" },
                { key: "color_2", label: "Second colour", kind: "colour", default: "secondary" },
                { key: "sensitivity", label: "Sensitivity", kind: "slider", default: 1, from: 0.5, to: 3, step: 0.1 },
                { key: "edge", label: "Stands on", hint: "The edge the bars rise from; they grow into the widget", kind: "choice", default: "bottom", options: [{ key: "bottom", label: "Bottom" }, { key: "top", label: "Top" }, { key: "left", label: "Left" }, { key: "right", label: "Right" }] },
                { key: "skew", label: "Lean", hint: "Tilts the bars (degrees); their feet stay on the edge", kind: "slider", default: 0, from: -30, to: 30, step: 1 }
            ]
        },
        {
            type: "weather", label: "Weather", icon: "cloud", size: [320, 140],
            settings: [
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" },
                { key: "font_family", label: "Font", kind: "font", default: "" },
                { key: "shadow", label: "Shadow", kind: "toggle", default: true },
                { key: "show_forecast", label: "Forecast", kind: "toggle", default: false },
                { key: "forecast_days", label: "Days", kind: "int", default: 3, from: 1, to: 6, step: 1, when: { show_forecast: [true] } }
            ]
        },
        {
            type: "media_player", label: "Media", icon: "music", size: [420, 140],
            settings: [
                { key: "layout", label: "Layout", kind: "choice", default: "horizontal", options: [{ key: "horizontal", label: "Wide" }, { key: "vertical", label: "Tall" }] },
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" },
                { key: "font_family", label: "Font", kind: "font", default: "" },
                { key: "shadow", label: "Shadow", kind: "toggle", default: true },
                { key: "hide_when_no_media", label: "Hide when nothing plays", kind: "toggle", default: false }
            ]
        },
        {
            type: "calendar", label: "Calendar", icon: "calendar", size: [300, 300],
            settings: [
                { key: "show_week_numbers", label: "Week numbers", kind: "toggle", default: false },
                { key: "first_day", label: "Week starts", kind: "choice", default: "monday", options: [{ key: "monday", label: "Monday" }, { key: "sunday", label: "Sunday" }] },
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" },
                { key: "font_family", label: "Font", kind: "font", default: "" }
            ]
        },
        {
            type: "sysmon", label: "System", icon: "cpu", size: [300, 140],
            settings: [
                { key: "stat", label: "Shows", kind: "select", default: "cpu_usage", options: [{ key: "cpu_usage", label: "CPU use" }, { key: "cpu_temp", label: "CPU temperature" }, { key: "cpu_freq", label: "CPU clock" }, { key: "ram_pct", label: "Memory" }, { key: "swap_pct", label: "Swap" }, { key: "net_rx", label: "Download" }, { key: "net_tx", label: "Upload" }] },
                { key: "stat2", label: "And", kind: "select", default: "", options: [{ key: "", label: "Nothing" }, { key: "cpu_usage", label: "CPU use" }, { key: "cpu_temp", label: "CPU temperature" }, { key: "ram_pct", label: "Memory" }, { key: "net_rx", label: "Download" }, { key: "net_tx", label: "Upload" }] },
                { key: "display", label: "Display", kind: "choice", default: "graph", options: [{ key: "graph", label: "Graph" }, { key: "gauge", label: "Gauge" }] },
                { key: "show_label", label: "Label", kind: "toggle", default: true },
                { key: "color", label: "Colour", kind: "colour", default: "primary" },
                { key: "color_2", label: "Second colour", kind: "colour", default: "tertiary" }
            ]
        },
        {
            type: "volume", label: "Volume", icon: "volume", size: [300, 64],
            settings: [
                { key: "device", label: "Device", kind: "choice", default: "output", options: [{ key: "output", label: "Output" }, { key: "input", label: "Microphone" }] },
                { key: "layout", label: "Layout", kind: "choice", default: "regular", options: [{ key: "regular", label: "Regular" }, { key: "compact", label: "Compact" }] },
                { key: "color", label: "Colour", kind: "colour", default: "primary" }
            ]
        },
        {
            type: "session_actions", label: "Session", icon: "power", size: [300, 64],
            settings: [
                { key: "vertical", label: "Vertical", kind: "toggle", default: false },
                { key: "show_labels", label: "Labels", kind: "toggle", default: false }
            ]
        },
        {
            type: "button", label: "Button", icon: "rocket", size: [64, 64],
            settings: [
                { key: "glyph", label: "Icon", kind: "glyph", default: "heart" },
                { key: "label", label: "Label", kind: "text", default: "" },
                { key: "command", label: "Runs", kind: "text", default: "", hint: "a command line" },
                { key: "variant", label: "Look", kind: "select", default: "default", options: [{ key: "default", label: "Default" }, { key: "primary", label: "Accent" }, { key: "outline", label: "Outline" }, { key: "ghost", label: "Ghost" }, { key: "destructive", label: "Warning" }] },
                { key: "background", label: "Background", kind: "toggle", default: true },
                { key: "color", label: "Colour", kind: "colour", default: "on_surface" }
            ]
        }
    ]

    // the native names some layouts use
    readonly property var aliases: ({
            visualizer: "audio_visualizer",
            fancy_audio_visualizer: "audio_visualizer",
            media: "media_player"
        })
    function canonical(type: string): string {
        return aliases[type] ?? type;
    }
    function find(type: string): var {
        const t = canonical(type);
        return types.find(x => x.type === t) ?? null;
    }
    // the whole schema for a type: its own settings, then the common ones
    function schema(type: string): var {
        const t = find(type);
        return t ? t.settings.concat(common(t.type)) : common(type);
    }
    function defaults(type: string): var {
        const out = {};
        for (const s of schema(type))
            out[s.key] = s.default;
        return out;
    }
    // a setting shows when every condition in its `when` holds against the current settings
    function visible(type: string, spec: var, settings: var): bool {
        if (!spec.when)
            return true;
        for (const [k, values] of Object.entries(spec.when)) {
            if (!values.includes(value(type, settings, k)))
                return false;
        }
        return true;
    }
    function value(type: string, settings: var, key: string): var {
        if (settings && settings[key] !== undefined)
            return settings[key];
        return schema(type).find(s => s.key === key)?.default;
    }
}
