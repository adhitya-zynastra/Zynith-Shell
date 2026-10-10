pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// Every native setting, searchable: read once when Settings opens (one settings-schema call per section over
// the native socket), so the sidebar's search finds a setting by its name, what it does or its group, and
// takes you to the page that shows it.
Singleton {
    id: root

    property var entries: []
    property bool ready: false
    property bool loading: false

    function load(): void {
        if (loading || ready)
            return;
        loading = true;
        CoreClient.call("settings-schema", text => {
            let sections = [];
            try {
                sections = JSON.parse(text).sections.filter(s => s.count > 0);
            } catch (e) {
                root.loading = false;
                return;
            }
            let left = sections.length;
            const all = [];
            for (const s of sections) {
                CoreClient.call("settings-schema " + s.id, body => {
                    try {
                        for (const e of JSON.parse(body).entries) {
                            if (e.visible === false)
                                continue;
                            const group = e.groupLabel || "General";
                            all.push({
                                title: e.title,
                                subtitle: e.subtitle ?? "",
                                group: group,
                                section: s.id,
                                sectionLabel: s.label,
                                advanced: e.advanced === true,
                                route: Routes.routeFor(s.id, group)
                            });
                        }
                    } catch (e) {}
                    if (--left === 0) {
                        root.entries = all;
                        root.ready = true;
                        root.loading = false;
                    }
                });
            }
        });
    }

    // every word must appear in the title, the description or the group; titles that start with the
    // query come first
    function search(text: string): var {
        const q = text.trim().toLowerCase();
        if (q.length < 2)
            return [];
        const words = q.split(/\s+/);
        const hits = entries.filter(e => {
            const hay = (e.title + " " + e.subtitle + " " + e.group + " " + e.sectionLabel).toLowerCase();
            return words.every(w => hay.includes(w));
        });
        hits.sort((a, b) => (b.title.toLowerCase().startsWith(q) ? 1 : 0) - (a.title.toLowerCase().startsWith(q) ? 1 : 0));
        return hits.slice(0, 40);
    }
}
