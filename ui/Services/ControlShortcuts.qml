pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common

// The Control Panel's shortcut tiles. The native Control Center's catalogue under its own ids (so its
// [control_center] shortcuts list carries over unchanged), then Zynith's, then the user's custom:<name> tiles
// from [control_panel.custom.<name>] { icon, label, detail, action, more }.
// Each entry: label, icon, on (lit), detail (the second line), press (the tile), more (its chevron: a panel
// to open in place, or an action), needs (a service the tile keeps awake while shown).
Singleton {
    id: root

    // Do Not Disturb belongs to whichever notification server runs
    readonly property bool dnd: Notifications.serving ? Notifications.dnd : Core.dnd
    function setDnd(on: bool): void {
        if (Notifications.serving)
            Notifications.setDnd(on);
        else
            Core.setDnd(on);
    }

    readonly property string profile: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    readonly property var profileLabels: ({
            saver: "Power saver",
            balanced: "Balanced",
            performance: "Performance"
        })
    function cycleProfile(): void {
        const order = PowerProfiles.hasPerformanceProfile ? ["saver", "balanced", "performance"] : ["saver", "balanced"];
        const next = order[(order.indexOf(profile) + 1) % order.length];
        PowerProfiles.profile = next === "saver" ? PowerProfile.PowerSaver : next === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
    }

    readonly property var builtin: [
        {
            id: "wifi",
            label: () => "Wi‑Fi",
            icon: () => Network.glyph,
            on: () => Network.wifiEnabled,
            detail: () => !Network.wifiEnabled ? "Off" : Network.name || "Not connected",
            press: () => Network.setWifiEnabled(!Network.wifiEnabled),
            more: "network",
            available: () => Network.available
        },
        {
            id: "bluetooth",
            label: () => "Bluetooth",
            icon: () => Bluetooth.enabled ? (Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth") : "bluetooth-off",
            on: () => Bluetooth.enabled,
            detail: () => Bluetooth.available ? Bluetooth.summary : "Unavailable",
            press: () => Bluetooth.setEnabled(!Bluetooth.enabled),
            more: "bluetooth",
            available: () => Bluetooth.available
        },
        {
            id: "nightlight",
            label: () => "Night light",
            icon: () => Core.nightlight || Core.nightlightForced ? "sunset-2" : "sun",
            on: () => Core.nightlight || Core.nightlightForced,
            detail: () => !Core.known ? "…" : Core.nightlightForced ? "On now" : Core.nightlight ? (Core.nightlightActive ? "On · scheduled" : "Scheduled") : "Off",
            press: () => Core.toggleNightlight(),
            more: "monitor"
        },
        {
            id: "notification",
            label: () => "Do not disturb",
            icon: () => root.dnd ? "bell-off" : "bell",
            on: () => root.dnd,
            detail: () => root.dnd ? "Popups held back" : Notifications.unread > 0 ? Notifications.unread + " waiting" : "Off",
            press: () => root.setDnd(!root.dnd),
            more: "notifications"
        },
        {
            id: "dark_mode",
            label: () => Scheme.mode === "light" ? "Light mode" : "Dark mode",
            icon: () => Scheme.mode === "light" ? "sun" : "moon",
            on: () => Scheme.mode !== "light",
            detail: () => Scheme.mode === "light" ? "Light palette" : "Dark palette",
            press: () => Actions.run("theme-mode-toggle")
        },
        {
            id: "caffeine",
            label: () => "Stay awake",
            icon: () => Core.caffeine ? "coffee" : "coffee-off",
            on: () => Core.caffeine,
            detail: () => !Core.known ? "…" : Core.caffeine ? "Screen stays on" : "Off",
            press: () => Core.toggleCaffeine()
        },
        {
            id: "audio",
            label: () => "Sound",
            icon: () => Audio.glyph,
            on: () => Audio.ready && !Audio.muted,
            detail: () => !Audio.ready ? "No output" : Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "% · " + Audio.sinkName,
            press: () => Audio.toggleMute(),
            more: "audio"
        },
        {
            id: "mic_mute",
            label: () => "Microphone",
            icon: () => Audio.micMuted ? "microphone-off" : "microphone",
            on: () => Audio.micReady && !Audio.micMuted,
            detail: () => !Audio.micReady ? "None" : Audio.micMuted ? "Muted" : "Live",
            press: () => Audio.toggleMicMute(),
            more: "audio"
        },
        {
            id: "power_profile",
            label: () => "Power profile",
            icon: () => root.profile === "saver" ? "leaf" : root.profile === "performance" ? "gauge" : "scale",
            on: () => root.profile !== "balanced",
            detail: () => root.profileLabels[root.profile],
            press: () => root.cycleProfile(),
            more: "power"
        },
        {
            id: "media",
            label: () => Media.present ? Media.title || "Playing" : "Media",
            icon: () => Media.playing ? "player-pause-filled" : "player-play-filled",
            on: () => Media.playing,
            detail: () => Media.present ? Media.artist || Media.app : "Nothing playing",
            press: () => Media.toggle(),
            more: "media"
        },
        {
            id: "weather",
            label: () => "Weather",
            icon: () => Weather.valid ? Weather.glyph(Weather.data.current?.code ?? 0, Weather.data.current?.isDay ?? true) : "cloud",
            on: () => false,
            detail: () => Weather.valid ? Math.round(Weather.data.current?.temperature ?? 0) + (Weather.data.unit ?? "°") + " · " + (Weather.data.location ?? "") : (Weather.data.enabled === false ? "Off" : "…"),
            press: "weather",
            needs: "weather"
        },
        {
            id: "system",
            label: () => "System",
            icon: () => "activity",
            on: () => false,
            detail: () => "CPU " + Math.round(System.cpu * 100) + "% · memory " + Math.round(System.memUsed * 100) + "%",
            press: "system",
            needs: "system"
        },
        {
            id: "screen_time",
            label: () => "Screen time",
            icon: () => "hourglass",
            on: () => false,
            detail: () => ScreenTime.enabled ? ScreenTime.format(ScreenTime.total) + " today" : "Off",
            press: "screen-time",
            needs: "screen_time"
        },
        {
            id: "keyboard_layout",
            label: () => "Keyboard",
            icon: () => "keyboard",
            on: () => false,
            detail: () => Workspaces.keyboardLayout || "—",
            press: () => Actions.run("keyboard-layout-cycle")
        },
        {
            id: "wallpaper",
            label: () => "Wallpaper",
            icon: () => "photo",
            on: () => false,
            detail: () => "Browse and apply",
            press: "wallpaper"
        },
        {
            id: "session",
            label: () => "Session",
            icon: () => "power",
            on: () => false,
            detail: () => "Lock, log out, restart",
            press: "session"
        },
        {
            id: "clipboard",
            label: () => "Clipboard",
            icon: () => "clipboard",
            on: () => false,
            detail: () => "History",
            press: "clipboard"
        },
        // ── Zynith's own ──
        {
            id: "launcher",
            label: () => "Launcher",
            icon: () => "search",
            on: () => false,
            detail: () => "Apps and more",
            press: "launcher"
        },
        {
            id: "screenshot",
            label: () => "Screenshot",
            icon: () => "screenshot",
            on: () => false,
            detail: () => "A region",
            press: () => Actions.run("screenshot-region"),
            closes: true
        },
        {
            id: "lock",
            label: () => "Lock",
            icon: () => "lock",
            on: () => false,
            detail: () => "Lock the screen",
            press: () => Actions.run("lock"),
            closes: true
        },
        {
            id: "desktop_edit",
            label: () => "Edit desktop",
            icon: () => "layout-dashboard",
            on: () => Desktop.editing,
            detail: () => Desktop.editing ? "Editing" : "Widgets",
            press: () => Actions.run("desktop-edit"),
            closes: true
        },
        {
            id: "settings",
            label: () => "Settings",
            icon: () => "settings",
            on: () => false,
            detail: () => "Zynith",
            press: () => Actions.run("settings-open"),
            closes: true
        }
    ]

    // a custom:<name> tile, from [control_panel.custom.<name>]
    function custom(name: string): var {
        const c = (Config.controlPanel?.custom ?? {})[name];
        if (!c)
            return null;
        return {
            id: "custom:" + name,
            label: () => c.label ?? name,
            icon: () => c.icon ?? "bolt",
            on: () => false,
            detail: () => c.detail ?? "",
            press: () => Actions.run(c.action ?? ""),
            more: c.more ?? "",
            closes: c.close !== false
        };
    }

    function find(id: string): var {
        if (id.startsWith("custom:"))
            return custom(id.slice(7));
        return builtin.find(e => e.id === id) ?? null;
    }
    function available(entry: var): bool {
        return entry !== null && (entry.available === undefined || entry.available());
    }
    // every id a user can pick: the built-ins, then their own
    readonly property var ids: builtin.map(e => e.id).concat(Object.keys(Config.controlPanel?.custom ?? {}).map(n => "custom:" + n))
}
