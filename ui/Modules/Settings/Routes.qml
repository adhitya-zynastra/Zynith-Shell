pragma Singleton

import QtQuick
import Quickshell

// The Settings map as data: the sidebar, search and deep links (`zynith-ui settings <route>`) all read it.
//
// Every one of the native shell's settings has a place here, as the native Settings window had them:
// a Zynith page carries the native settings of its subject under it (`native`: a registry section, or some of
// its groups; `owner` names the [surfaces] key whose native surface those settings shape, shown folded and
// marked while Zynith draws that surface), and every other native section is a page of its own (`section`).
Singleton {
    // The groups, numbered as the rail shows them (Ryoku's Hub: a short rail of plain categories; the technical
    // pages wait behind the rail-foot "Advanced settings" switch, and search reaches them regardless).
    readonly property var groups: ["Overview", "Connections", "Desktop", "Apps & keys", "System", "Advanced"]
    function groupIndex(group: string): string {
        return String(groups.indexOf(group) + 1).padStart(2, "0");
    }

    // native: the native shell's settings on the page's subject — `title` names them for a person, `owner` marks
    // those shaping a native surface Zynith draws instead (shown only with Advanced on: they change nothing
    // while Zynith draws it), `advanced` keeps a block for Advanced, `exclude` drops settings a Zynith control
    // on the same page already owns
    readonly property var routes: [
        { id: "home", title: "Home", icon: "layout-grid", group: "Overview", keywords: "profile picture name system about overview time" },

        { id: "network", title: "Wi‑Fi", icon: "wifi", group: "Connections", keywords: "network wireless" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth", group: "Connections", keywords: "devices pairing" },

        { id: "appearance", title: "Appearance", icon: "adjustments-horizontal", group: "Desktop", keywords: "theme colours palette tint accent glass blur border radius contrast text size font scale dark light",
            native: [{ section: "appearance", title: "Light, dark and the wallpaper palette" }, { section: "personalization", groups: ["Glass"], title: "Glass on the lock screen and session menu", advanced: true }] },
        { id: "wallpaper", title: "Wallpaper", icon: "photo", group: "Desktop", keywords: "live poster overview folder transition monitors automation directories",
            native: [{ section: "wallpaper", title: "Wallpapers, transitions and rotation" }, { section: "personalization", groups: ["Wallpaper Browser"], owner: "wallpaper" }] },
        { id: "animation", title: "Animations", icon: "sparkles", group: "Desktop", keywords: "motion speed easing reduced window animations niri",
            native: [{ section: "personalization", groups: ["Motion"], title: "Window animations", exclude: ["shell.animation.enabled", "shell.animation.speed"] }] },
        { id: "bars", title: "Bars", icon: "layers-intersect", group: "Desktop", keywords: "bar edge anchor widgets autohide smart capsule",
            native: [{ section: "bar", owner: "bar" }] },
        { id: "widgets", title: "Desktop widgets", icon: "layout-dashboard", group: "Desktop", keywords: "desktop widgets clock editor place grid",
            native: [{ section: "desktop", groups: ["Widgets"], owner: "desktop_widgets" }] },
        { id: "control", title: "Control Panel", icon: "adjustments-horizontal", group: "Desktop", keywords: "modules quick settings control center dashboard",
            native: [{ section: "control-center", owner: "control_center" }, { section: "personalization", groups: ["Control Center"], owner: "control_center" }] },
        { id: "notifications", title: "Notifications", icon: "bell", group: "Desktop", keywords: "popups dnd sound grouping location toasts history filtering sounds",
            native: [{ section: "personalization", groups: ["Sounds"], title: "Sounds" }, { section: "notifications", owner: "notifications" }, { section: "personalization", groups: ["Notifications"], owner: "notifications" }] },
        { id: "osd", title: "On-screen display", icon: "message", group: "Desktop", keywords: "osd volume brightness popup card kinds",
            native: [{ section: "osd", owner: "osd" }, { section: "personalization", groups: ["OSD"], owner: "osd" }] },
        { id: "launcher", title: "Launcher", icon: "search", group: "Desktop", keywords: "apps search position density providers calculator emoji",
            native: [{ section: "launcher", groups: ["Providers"], title: "What the launcher searches" }, { section: "launcher", groups: ["Launcher"], owner: "launcher" }, { section: "personalization", groups: ["Launcher"], owner: "launcher" }] },
        { id: "lock", title: "Lock screen", icon: "lock", group: "Desktop", keywords: "lock redaction authentication password",
            native: [{ section: "security", groups: ["Lock Screen", "Authentication"], title: "Lock screen and sign-in" }] },
        { id: "media", title: "Media", icon: "music", group: "Desktop", keywords: "visualizer spectrum player lyrics",
            native: [{ section: "services", groups: ["Media", "Audio"], title: "Players and audio" }] },

        { id: "window", title: "Window behaviour", icon: "device-desktop", group: "Apps & keys", keywords: "scrolling tiling columns niri layout overview backdrop",
            native: [{ section: "niri", title: "niri" }] },
        { id: "native:keybinds", title: "Keybinds", icon: "keyboard", group: "Apps & keys", keywords: "shortcuts keys bindings", section: "keybinds" },

        { id: "displays", title: "Displays", icon: "device-desktop", group: "System", keywords: "display monitor screen output orientation rotate rotation portrait landscape flip transform" },
        { id: "experience", title: "Performance", icon: "gauge", group: "System", keywords: "performance efficiency battery power saver visualizer previews background reduce motion" },
        { id: "native:power", title: "Power & idle", icon: "power", group: "System", keywords: "session panel idle suspend lock timeout", section: "power" },
        { id: "native:location", title: "Location, weather & night light", icon: "map-pin", group: "System", keywords: "location weather night light units city", section: "location" },
        { id: "about", title: "About", icon: "info-circle", group: "System", keywords: "version hardware kernel quickshell niri" },

        // behind "Advanced settings"
        { id: "native:templates", title: "Theme templates", icon: "palette", group: "Advanced", advanced: true, keywords: "matugen templates gtk qt community built-in", section: "templates" },
        { id: "native:corners", title: "Screen & hot corners", icon: "layout-sidebar-right", group: "Advanced", advanced: true, keywords: "hot corners screen corners rounded actions", section: "desktop", groups: ["Screen Corners", "Hot Corners"] },
        { id: "native:dock", title: "Dock", icon: "layout-bottombar", group: "Advanced", advanced: true, keywords: "dock pinned apps magnification autohide", section: "dock" },
        { id: "native:panels", title: "Native panels", icon: "layout-sidebar", group: "Advanced", advanced: true, keywords: "clipboard polkit panel wallpaper panel effects", section: "panels" },
        { id: "native:screenshot", title: "Screenshots", icon: "screenshot", group: "Advanced", advanced: true, keywords: "screenshot capture annotation output region", section: "screenshot" },
        { id: "surfaces", title: "Zynith or native surfaces", icon: "layers-intersect", group: "Advanced", advanced: true, keywords: "native surfaces rollback owner zynith ui" },
        { id: "native:shell", title: "Shell", icon: "settings", group: "Advanced", advanced: true, keywords: "general keyboard layout clipboard window switcher", section: "shell" },
        { id: "native:system", title: "System monitor & battery", icon: "cpu", group: "Advanced", advanced: true, keywords: "battery screen time poll intervals thresholds monitor", section: "system" },
        { id: "native:services", title: "Calendar & brightness", icon: "calendar", group: "Advanced", advanced: true, keywords: "calendar brightness ddc services", section: "services", groups: ["Calendar", "Brightness"] },
        { id: "native:security", title: "Privacy & security", icon: "shield", group: "Advanced", advanced: true, keywords: "network privacy security", section: "security", groups: ["Network", "Privacy"] },
        { id: "native:hooks", title: "Hooks", icon: "terminal-2", group: "Advanced", advanced: true, keywords: "hooks lifecycle theme network power commands", section: "hooks" },
        { id: "plugins", title: "Plugins", icon: "apps", group: "Advanced", advanced: true, keywords: "luau capabilities permissions" },
        { id: "shell", title: "Every native setting", icon: "list", group: "Advanced", advanced: true, keywords: "native zynith-shell every setting registry all shell settings" }
    ]

    function find(id: string): var {
        return routes.find(r => r.id === id) ?? routes[0];
    }
    // where a native setting lives: the route that shows its section and group
    function routeFor(section: string, group: string): var {
        for (const r of routes) {
            if (r.section === section && (!(r.groups?.length > 0) || r.groups.includes(group)))
                return r;
            for (const n of (r.native ?? []))
                if (n.section === section && (!(n.groups?.length > 0) || n.groups.includes(group)))
                    return r;
        }
        return find("shell");
    }
    function search(text: string): var {
        const q = text.trim().toLowerCase();
        if (!q)
            return routes;
        return routes.filter(r => (r.title + " " + r.group + " " + r.keywords).toLowerCase().includes(q));
    }
}
