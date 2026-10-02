pragma Singleton

import QtQuick
import Quickshell

// The Settings map as data: the sidebar, search and deep links (`zynith-ui settings <route>`) all read it.
Singleton {
    readonly property var routes: [
        { id: "home", title: "Home", icon: "layout-grid", group: "", keywords: "profile picture name system about overview time" },
        { id: "appearance", title: "Appearance", icon: "adjustments-horizontal", group: "Personalization", keywords: "theme colours palette tint accent glass blur border radius contrast text size" },
        { id: "animation", title: "Animation", icon: "sparkles", group: "Personalization", keywords: "motion speed easing reduced" },
        { id: "wallpaper", title: "Wallpaper", icon: "photo", group: "Personalization", keywords: "live poster overview folder" },
        { id: "lock", title: "Lock screen", icon: "lock", group: "Personalization", keywords: "lock redaction" },
        { id: "experience", title: "Experience", icon: "gauge", group: "Personalization", keywords: "performance balanced enhanced max profile quality battery" },
        { id: "bars", title: "Bars", icon: "layers-intersect", group: "Desktop", keywords: "bar edge anchor widgets autohide smart" },
        { id: "control", title: "Control Panel", icon: "adjustments-horizontal", group: "Desktop", keywords: "modules quick settings" },
        { id: "launcher", title: "Launcher", icon: "search", group: "Desktop", keywords: "apps search position density" },
        { id: "notifications", title: "Notifications", icon: "bell", group: "Desktop", keywords: "popups dnd sound grouping location" },
        { id: "media", title: "Media", icon: "music", group: "Desktop", keywords: "visualizer spectrum player" },
        { id: "surfaces", title: "Zynith UI", icon: "layers-intersect", group: "Desktop", keywords: "native surfaces rollback owner" },
        { id: "window", title: "Window behaviour", icon: "device-desktop", group: "Window management", keywords: "scrolling tiling columns niri layout" },
        { id: "network", title: "Wi‑Fi", icon: "wifi", group: "Connections", keywords: "network wireless" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth", group: "Connections", keywords: "devices pairing" },
        { id: "plugins", title: "Plugins", icon: "apps", group: "System", keywords: "luau capabilities permissions" },
        { id: "about", title: "About", icon: "cpu", group: "System", keywords: "version hardware kernel quickshell niri" }
    ]

    function find(id: string): var {
        return routes.find(r => r.id === id) ?? routes[0];
    }
    function search(text: string): var {
        const q = text.trim().toLowerCase();
        if (!q)
            return routes;
        return routes.filter(r => (r.title + " " + r.group + " " + r.keywords).toLowerCase().includes(q));
    }
}
