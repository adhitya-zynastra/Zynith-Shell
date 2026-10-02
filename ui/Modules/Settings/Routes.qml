pragma Singleton

import QtQuick
import Quickshell

// The Settings map as data: the sidebar, search and deep links (`zynith-ui settings <route>`) all read it.
Singleton {
    readonly property var routes: [
        {
            id: "home",
            title: "Home",
            icon: "layout-grid",
            group: "",
            keywords: "profile system about overview"
        },
        {
            id: "experience",
            title: "Experience",
            icon: "sparkles",
            group: "Personalization",
            keywords: "performance balanced enhanced max profile blur animation quality"
        },
        {
            id: "appearance",
            title: "Appearance",
            icon: "adjustments-horizontal",
            group: "Personalization",
            keywords: "theme colours palette glass motion"
        },
        {
            id: "bars",
            title: "Bars",
            icon: "layers-intersect",
            group: "Desktop",
            keywords: "bar edge anchor widgets autohide smart"
        },
        {
            id: "window",
            title: "Window behaviour",
            icon: "device-desktop",
            group: "Window management",
            keywords: "scrolling tiling columns niri layout"
        },
        {
            id: "about",
            title: "About",
            icon: "cpu",
            group: "System",
            keywords: "version hardware kernel quickshell niri"
        }
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
