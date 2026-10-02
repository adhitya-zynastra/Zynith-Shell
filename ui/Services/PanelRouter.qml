pragma Singleton

import QtQuick
import Quickshell

// Which focused panel is open on which output, where it came from, and how to get back. One panel per
// output by default: opening another replaces it; navigate() moves within the same surface.
Singleton {
    id: root

    // screen name -> { id, originX, originY, edge, extent, history: [ids] }
    property var openPanels: ({})

    function current(screenName: string): var {
        return openPanels[screenName] ?? null;
    }
    function isOpen(id: string, screenName: string): bool {
        return (openPanels[screenName]?.id ?? "") === id;
    }
    function set(screenName: string, entry: var): void {
        const next = Object.assign({}, openPanels);
        if (entry)
            next[screenName] = entry;
        else
            delete next[screenName];
        openPanels = next;
    }
    function open(id: string, screenName: string, origin: var): void {
        set(screenName, {
            id: id,
            originX: origin?.x ?? -1,
            originY: origin?.y ?? -1,
            edge: origin?.edge ?? "top",
            extent: origin?.extent ?? 42,
            history: []
        });
    }
    function close(screenName: string): void {
        if (openPanels[screenName])
            set(screenName, null);
    }
    function toggle(id: string, screenName: string, origin: var): void {
        if (isOpen(id, screenName))
            close(screenName);
        else
            open(id, screenName, origin);
    }
    // within an open surface: keeps the origin, remembers where we came from
    function navigate(id: string, screenName: string): void {
        const cur = openPanels[screenName];
        if (!cur)
            return open(id, screenName, null);
        if (cur.id === id)
            return;
        set(screenName, Object.assign({}, cur, {
            id: id,
            history: (cur.history ?? []).concat([cur.id])
        }));
    }
    function back(screenName: string): void {
        const cur = openPanels[screenName];
        if (!cur || (cur.history ?? []).length === 0)
            return close(screenName);
        const history = cur.history.slice();
        const previous = history.pop();
        set(screenName, Object.assign({}, cur, {
            id: previous,
            history: history
        }));
    }
    function closeAll(): void {
        openPanels = {};
    }
}
