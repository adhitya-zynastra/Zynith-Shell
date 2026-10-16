import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Launcher"
        caption: "Prefixes pick a mode; the native shell's calculator, and every plugin's search, answer here too"
    }

    Card {
        width: parent.width
        caption: "Layout"

        SettingChoice {
            title: "Position"
            domain: "panels"
            key: "launcher.position"
            options: [{ key: "center", label: "Centre" }, { key: "top", label: "Top" }]
        }
        SettingChoice {
            title: "Density"
            domain: "panels"
            key: "launcher.density"
            options: [{ key: "comfortable", label: "Comfortable" }, { key: "compact", label: "Compact" }]
        }
        SettingSlider {
            title: "Width"
            domain: "panels"
            key: "launcher.width"
            from: 480
            to: 900
            step: 20
            format: v => Math.round(v) + " px"
        }
        SettingSlider {
            title: "Icon size (0 by density)"
            domain: "panels"
            key: "launcher.icon_size"
            from: 0
            to: 64
            step: 2
            format: v => Math.round(v) === 0 ? "auto" : Math.round(v) + " px"
        }
        SettingSlider {
            title: "Results shown"
            domain: "panels"
            key: "launcher.rows"
            from: 4
            to: 14
            step: 1
            format: v => Math.round(v)
        }
    }

    Card {
        width: parent.width
        caption: "Results"
        SchemaForm {
            width: parent.width
            readonly property var own: Config.launcher ?? ({})
            schema: [
                { key: "layout", label: "With nothing typed", kind: "choice", default: "list", options: [{ key: "list", label: "A list" }, { key: "grid", label: "An icon grid" }] },
                { key: "sort_by_usage", label: "Apps you use often come first", kind: "toggle", default: true },
                { key: "show_icons", label: "App icons", kind: "toggle", default: true },
                { key: "show_origin", label: "Mark Flatpak, Snap and AppImage apps", kind: "toggle", default: true },
                { key: "categories", label: "Category chips", kind: "toggle", default: true },
                { key: "actions", label: "App actions (New Window…)", kind: "toggle", default: true },
                { key: "auto_paste", label: "Copied results paste into the window beneath", kind: "toggle", default: true }
            ]
            valueOf: key => own[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => own[key] !== undefined && own[key] !== schema.find(s => s.key === key)?.default
            onChanged: (key, value) => Config.change("panels", "launcher." + key, value, labelOf(key))
            onCleared: key => Config.change("panels", "launcher." + key, undefined, labelOf(key))
        }
    }

    // each mode's prefix, and whether it also answers the plain search
    Card {
        width: parent.width
        caption: "Modes"
        SchemaForm {
            width: parent.width
            readonly property var own: Config.launcher ?? ({})
            schema: [
                { key: "command_prefix", label: "Commands start with (/calc, /emo, a plugin's own)", kind: "text", default: "/" },
                { key: "calculator.prefix", label: "Calculator", kind: "text", default: "=" },
                { key: "calculator.global", label: "Calculations in the plain search", kind: "toggle", default: true },
                { key: "windows.prefix", label: "Windows", kind: "text", default: ">" },
                { key: "windows.global", label: "Windows in the plain search", kind: "toggle", default: false },
                { key: "wallpapers.prefix", label: "Wallpapers", kind: "text", default: "@" },
                { key: "wallpapers.global", label: "Wallpapers in the plain search", kind: "toggle", default: false },
                { key: "emoji.prefix", label: "Emoji", kind: "text", default: ":" },
                { key: "emoji.global", label: "Emoji in the plain search", kind: "toggle", default: false },
                { key: "session.prefix", label: "Session", kind: "text", default: "!" },
                { key: "session.global", label: "Session actions in the plain search", kind: "toggle", default: false }
            ]
            function path(key: string): string {
                return key === "command_prefix" ? "launcher.command_prefix" : "launcher.providers." + key;
            }
            function read(key: string): var {
                if (key === "command_prefix")
                    return own.command_prefix;
                const [id, field] = key.split(".");
                return own.providers?.[id]?.[field];
            }
            valueOf: key => read(key) ?? schema.find(s => s.key === key)?.default
            isSet: key => read(key) !== undefined
            onChanged: (key, value) => Config.change("panels", path(key), value, labelOf(key))
            onCleared: key => Config.change("panels", path(key), undefined, labelOf(key))
        }
    }
}
