pragma Singleton

import QtQuick
import Quickshell

// Every panel this UI draws, once: its name and icon, whether it opens on its own (`alone`: a focused panel
// sized to its content, e.g. Sound from the volume icon) and whether it is also a page of the Control Panel
// (`page`: opened among the Control Panel's tabs, under its hero). The router, the Control Panel's tab labels and
// the bar icons' click/hover pickers in Settings all read this, so a new panel is added here and nowhere else.
// PanelContent checks at start that each id here has a component.
Singleton {
    id: root

    readonly property var entries: [
        { id: "control", label: "Control Panel", icon: "layout-dashboard", alone: true, page: true },
        { id: "media", label: "Media", icon: "music", alone: true, page: true },
        { id: "audio", label: "Sound", icon: "volume", alone: true, page: true },
        { id: "network", label: "Wi‑Fi & network", icon: "wifi", alone: true, page: true },
        { id: "bluetooth", label: "Bluetooth", icon: "bluetooth", alone: true, page: true },
        { id: "power", label: "Battery & power", icon: "bolt", alone: true, page: true },
        { id: "monitor", label: "Display & brightness", icon: "device-desktop", alone: true, page: true },
        { id: "calendar", label: "Calendar", icon: "calendar", alone: true, page: true },
        { id: "weather", label: "Weather", icon: "cloud", alone: true, page: true },
        { id: "screen-time", label: "Screen time", icon: "hourglass", alone: true, page: true },
        { id: "system", label: "System monitor", icon: "cpu", alone: true, page: true },
        { id: "notifications", label: "Notifications", icon: "bell", alone: true, page: true },
        { id: "launcher", label: "Launcher", icon: "search", alone: true, page: false },
        { id: "clipboard", label: "Clipboard", icon: "clipboard", alone: true, page: false },
        { id: "wallpaper", label: "Wallpapers", icon: "photo", alone: true, page: false },
        { id: "session", label: "Power menu", icon: "power", alone: true, page: false },
        { id: "island", label: "Island", icon: "sparkles", alone: true, page: false }
    ]
    // older names that still arrive (bars.toml, keybinds): they open the same panel
    readonly property var aliases: ({ home: "control", quick: "control" })

    function byId(id: string): var {
        const key = aliases[id] ?? id;
        return entries.find(e => e.id === key) ?? null;
    }
    function label(id: string): string {
        return byId(id)?.label ?? id;
    }
    function icon(id: string): string {
        return byId(id)?.icon ?? "";
    }
    // a page of the Control Panel (opened as `panel-toggle control-center <id>`)
    function isPage(id: string): bool {
        return byId(id)?.page === true && (aliases[id] ?? id) !== "control";
    }
    function opensAlone(id: string): bool {
        return byId(id)?.alone === true;
    }

    // what a bar icon's click or hover can open, as action strings with names, grouped. Hover offers panels
    // only (a pointer resting on an icon should show something, not change the volume).
    function panelActions(): var {
        const out = [];
        for (const e of entries) {
            if (e.alone)
                out.push({ action: "panel-toggle " + (e.id === "control" ? "control-center home" : e.id), label: e.id === "control" ? "Control Panel" : e.label, group: "Panels", icon: e.icon });
        }
        for (const e of entries) {
            if (e.page && e.id !== "control")
                out.push({ action: "panel-toggle control-center " + e.id, label: e.label, group: "In the Control Panel", icon: e.icon });
        }
        return out;
    }
    // the commands a gesture can run besides opening a panel, named for Settings (Actions runs them; verbs it
    // does not handle go to the native shell as they are)
    readonly property var commands: [
        { action: "volume-up", label: "Volume up", group: "Sound" },
        { action: "volume-down", label: "Volume down", group: "Sound" },
        { action: "volume-mute", label: "Mute", group: "Sound" },
        { action: "mic-volume-up", label: "Microphone up", group: "Sound" },
        { action: "mic-volume-down", label: "Microphone down", group: "Sound" },
        { action: "mic-mute", label: "Mute the microphone", group: "Sound" },
        { action: "brightness-up", label: "Brighter", group: "Display" },
        { action: "brightness-down", label: "Dimmer", group: "Display" },
        { action: "nightlight-toggle", label: "Night light", group: "Display" },
        { action: "theme-mode-toggle", label: "Light / dark", group: "Display" },
        { action: "media toggle", label: "Play / pause", group: "Media" },
        { action: "media next", label: "Next track", group: "Media" },
        { action: "media previous", label: "Previous track", group: "Media" },
        { action: "workspace-switch next", label: "Next workspace", group: "Workspaces" },
        { action: "workspace-switch prev", label: "Previous workspace", group: "Workspaces" },
        { action: "notification-dnd-toggle", label: "Do not disturb", group: "System" },
        { action: "caffeine-toggle", label: "Keep awake", group: "System" },
        { action: "power-cycle next", label: "Next power profile", group: "System" },
        { action: "keyboard-layout-cycle", label: "Next keyboard layout", group: "System" },
        { action: "screenshot-region", label: "Screenshot a region", group: "System" },
        { action: "desktop-edit", label: "Edit desktop widgets", group: "System" },
        { action: "settings-open", label: "Settings", group: "System" },
        { action: "settings-open-widget", label: "This widget's settings", group: "System" }
    ]
    // the action string's name, for showing what a gesture does
    function describe(action: string): string {
        const a = (action ?? "").trim();
        if (a === "" || a === "none")
            return "Nothing";
        const known = commands.find(c => c.action === a);
        if (known)
            return known.label;
        const words = a.split(/\s+/);
        if (words[0] === "panel-toggle" || words[0] === "panel-open") {
            if (words[1] === "control-center")
                return (words[2] ?? "home") === "home" ? "Control Panel" : "Control Panel · " + label(words[2]);
            return label(words[1]) + " panel";
        }
        return a;
    }
}
