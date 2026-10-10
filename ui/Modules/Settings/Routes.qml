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
    readonly property var routes: [
        { id: "home", title: "Home", icon: "layout-grid", group: "", keywords: "profile picture name system about overview time" },

        { id: "appearance", title: "Appearance", icon: "adjustments-horizontal", group: "Personalization", keywords: "theme colours palette tint accent glass blur border radius contrast text size font scale dark light",
            native: [{ section: "appearance" }, { section: "personalization", groups: ["Glass"] }] },
        { id: "animation", title: "Animation", icon: "sparkles", group: "Personalization", keywords: "motion speed easing reduced",
            native: [{ section: "personalization", groups: ["Motion"] }] },
        { id: "wallpaper", title: "Wallpaper", icon: "photo", group: "Personalization", keywords: "live poster overview folder transition monitors automation directories",
            native: [{ section: "wallpaper" }, { section: "personalization", groups: ["Wallpaper Browser"], owner: "wallpaper" }] },
        { id: "native:templates", title: "Theme templates", icon: "palette", group: "Personalization", keywords: "matugen templates gtk qt community built-in", section: "templates" },
        { id: "lock", title: "Lock screen", icon: "lock", group: "Personalization", keywords: "lock redaction authentication password",
            native: [{ section: "security", groups: ["Lock Screen", "Authentication"] }] },
        { id: "experience", title: "Experience", icon: "gauge", group: "Personalization", keywords: "performance balanced enhanced max profile quality battery" },

        { id: "bars", title: "Bars", icon: "layers-intersect", group: "Desktop", keywords: "bar edge anchor widgets autohide smart capsule",
            native: [{ section: "bar", owner: "bar" }] },
        { id: "widgets", title: "Desktop widgets", icon: "layout-dashboard", group: "Desktop", keywords: "desktop widgets clock editor place grid",
            native: [{ section: "desktop", groups: ["Widgets"], owner: "desktop_widgets" }] },
        { id: "native:corners", title: "Screen & hot corners", icon: "layout-sidebar-right", group: "Desktop", keywords: "hot corners screen corners rounded actions", section: "desktop", groups: ["Screen Corners", "Hot Corners"] },
        { id: "native:dock", title: "Dock", icon: "layout-bottombar", group: "Desktop", keywords: "dock pinned apps magnification autohide", section: "dock" },
        { id: "osd", title: "On-screen display", icon: "message", group: "Desktop", keywords: "osd volume brightness popup card kinds",
            native: [{ section: "osd", owner: "osd" }, { section: "personalization", groups: ["OSD"], owner: "osd" }] },
        { id: "control", title: "Control Panel", icon: "adjustments-horizontal", group: "Desktop", keywords: "modules quick settings control center dashboard",
            native: [{ section: "control-center", owner: "control_center" }, { section: "personalization", groups: ["Control Center"], owner: "control_center" }] },
        { id: "launcher", title: "Launcher", icon: "search", group: "Desktop", keywords: "apps search position density providers calculator emoji",
            native: [{ section: "launcher", groups: ["Providers"] }, { section: "launcher", groups: ["Launcher"], owner: "launcher" }, { section: "personalization", groups: ["Launcher"], owner: "launcher" }] },
        { id: "notifications", title: "Notifications", icon: "bell", group: "Desktop", keywords: "popups dnd sound grouping location toasts history filtering sounds",
            native: [{ section: "personalization", groups: ["Sounds"] }, { section: "notifications", owner: "notifications" }, { section: "personalization", groups: ["Notifications"], owner: "notifications" }] },
        { id: "native:panels", title: "Panels", icon: "layout-sidebar", group: "Desktop", keywords: "clipboard polkit panel wallpaper panel effects", section: "panels" },
        { id: "native:screenshot", title: "Screenshots", icon: "screenshot", group: "Desktop", keywords: "screenshot capture annotation output region", section: "screenshot" },
        { id: "media", title: "Media", icon: "music", group: "Desktop", keywords: "visualizer spectrum player lyrics",
            native: [{ section: "services", groups: ["Media", "Audio"] }] },
        { id: "surfaces", title: "Zynith UI", icon: "layers-intersect", group: "Desktop", keywords: "native surfaces rollback owner" },

        { id: "window", title: "Window behaviour", icon: "device-desktop", group: "Window management", keywords: "scrolling tiling columns niri layout overview backdrop",
            native: [{ section: "niri" }] },
        { id: "native:keybinds", title: "Keybinds", icon: "keyboard", group: "Window management", keywords: "shortcuts keys bindings", section: "keybinds" },

        { id: "network", title: "Wi‑Fi", icon: "wifi", group: "Connections", keywords: "network wireless" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth", group: "Connections", keywords: "devices pairing" },

        { id: "native:shell", title: "Shell", icon: "settings", group: "System", keywords: "general keyboard layout clipboard window switcher", section: "shell" },
        { id: "native:system", title: "System monitor & battery", icon: "cpu", group: "System", keywords: "battery screen time poll intervals thresholds monitor", section: "system" },
        { id: "native:power", title: "Power & idle", icon: "power", group: "System", keywords: "session panel idle suspend lock timeout", section: "power" },
        { id: "native:location", title: "Location, weather & night light", icon: "map-pin", group: "System", keywords: "location weather night light units city", section: "location" },
        { id: "native:services", title: "Calendar & brightness", icon: "calendar", group: "System", keywords: "calendar brightness ddc services", section: "services", groups: ["Calendar", "Brightness"] },
        { id: "native:security", title: "Privacy & security", icon: "shield", group: "System", keywords: "network privacy security", section: "security", groups: ["Network", "Privacy"] },
        { id: "native:hooks", title: "Hooks", icon: "terminal-2", group: "System", keywords: "hooks lifecycle theme network power commands", section: "hooks" },
        { id: "plugins", title: "Plugins", icon: "apps", group: "System", keywords: "luau capabilities permissions" },
        { id: "shell", title: "All shell settings", icon: "list", group: "System", keywords: "native noctalia every setting registry" },
        { id: "about", title: "About", icon: "info-circle", group: "System", keywords: "version hardware kernel quickshell niri" }
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
