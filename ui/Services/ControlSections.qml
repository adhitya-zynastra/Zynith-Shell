pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import "../Common/SectionLayout.js" as Layout

// The Control Panel's sections: what each is, whether this machine can show it, and the one arrangement
// that decides which show and where — [control_panel] columns (the dashboard's columns, each a list of
// sections top to bottom; the column layout reads them in order, one after another). Settings edits that list
// and nothing else; the panel draws what layout() makes of it.
Singleton {
    id: root

    // id, title (the section head), label + detail (Settings), icon
    readonly property var entries: [
        { id: "header", title: "", label: "Clock and you", detail: "The time, the date, session and Settings", icon: "clock" },
        { id: "about", title: "System", label: "System info", detail: "Who, which machine, which system, how long up", icon: "device-laptop" },
        { id: "shortcuts", title: "Quick", label: "Shortcuts", detail: "The tiles: Wi‑Fi, Bluetooth, night light…", icon: "layout-grid" },
        { id: "levels", title: "Levels", label: "Levels", detail: "Volume, microphone and brightness together", icon: "adjustments-horizontal" },
        { id: "volume", title: "Volume", label: "Volume", detail: "The output level on its own", icon: "volume" },
        { id: "microphone", title: "Microphone", label: "Microphone", detail: "The input level on its own", icon: "microphone" },
        { id: "brightness", title: "Brightness", label: "Brightness", detail: "The screen's brightness on its own", icon: "brightness-up" },
        { id: "network", title: "Wi‑Fi", label: "Wi‑Fi", detail: "The network you are on, and a switch", icon: "wifi" },
        { id: "bluetooth", title: "Bluetooth", label: "Bluetooth", detail: "Connected devices, and a switch", icon: "bluetooth" },
        { id: "media", title: "Now playing", label: "Media", detail: "What is playing, its art and controls", icon: "music" },
        { id: "audio", title: "Sound", label: "Sound", detail: "Output device and each app's level", icon: "volume" },
        { id: "power", title: "Power", label: "Battery and power", detail: "Battery, profiles, charge limit", icon: "battery" },
        { id: "session", title: "Session", label: "Power actions", detail: "Lock, sleep, log out, restart, shut down", icon: "power" },
        { id: "profile", title: "Experience", label: "Experience profile", detail: "How rich the shell's effects are", icon: "sparkles" },
        { id: "weather", title: "Weather", label: "Weather", detail: "Now and the days ahead", icon: "cloud" },
        { id: "calendar", title: "Calendar", label: "Calendar", detail: "The month and what is coming up", icon: "calendar" },
        { id: "notifications", title: "Notifications", label: "Notifications", detail: "The latest ones, and Do not disturb", icon: "bell" },
        { id: "clipboard", title: "Clipboard", label: "Clipboard", detail: "The latest entries", icon: "clipboard-list" },
        { id: "system", title: "System", label: "System monitor", detail: "CPU and memory", icon: "activity" },
        { id: "monitor", title: "Display", label: "Displays", detail: "Brightness, night light, light or dark", icon: "device-desktop" },
        { id: "screen_time", title: "Screen time", label: "Screen time", detail: "Today's total and the apps", icon: "hourglass" }
    ]
    readonly property var ids: entries.map(e => e.id)
    function find(id: string): var {
        return entries.find(e => e.id === id) ?? null;
    }
    function title(id: string): string {
        return find(id)?.title ?? "";
    }

    // what is there to show on this machine (a section without its service hides; Settings says why)
    function available(id: string): bool {
        switch (id) {
        case "network":
            return Network.available && Network.hasWifi;
        case "bluetooth":
            return Bluetooth.available;
        case "brightness":
            return Backlight.available;
        case "power":
            return Power.present;
        default:
            return true;
        }
    }
    function unavailableReason(id: string): string {
        switch (id) {
        case "network":
            return "No Wi‑Fi device";
        case "bluetooth":
            return "No Bluetooth adapter";
        case "brightness":
            return "No adjustable backlight";
        case "power":
            return "No battery";
        default:
            return "";
        }
    }

    // the arrangement out of the box
    readonly property var defaultColumns: [["media"], ["shortcuts", "levels"], ["weather"]]
    readonly property int maxColumns: Layout.maxColumns

    // the arrangement logic is Common/SectionLayout.js (pure, tested): these name the catalogue for it
    function canonical(id: string): string {
        return Layout.canonical(id);
    }
    function validate(given: var): var {
        return Layout.validate(given, ids, defaultColumns);
    }
    function arrangement(cfg: var): var {
        return Layout.arrangement(cfg, ids, defaultColumns);
    }
    function flat(columns: var): var {
        return Layout.flat(columns);
    }
    function weights(columns: var, given: var): var {
        return Layout.weights(columns, given);
    }
}
