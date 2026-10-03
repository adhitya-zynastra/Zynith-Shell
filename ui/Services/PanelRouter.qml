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
    // the Control Panel and its pages, opened from nowhere (a key, IPC), sit by [control_panel] anchor_bar
    readonly property var controlPages: ["control", "home", "quick", "audio", "power", "monitor", "calendar", "weather", "screen-time", "network", "bluetooth", "notifications", "media", "system"]
    property var bars: ({})
    property var barItems: ({})
    function noteBar(id: string, screenName: string, origin: var): void {
        if (id !== "")
            bars[id + "@" + screenName] = origin;
    }

    function open(id: string, screenName: string, origin: var): void {
        if ((origin?.x ?? -1) < 0 && origin?.edge !== "center" && controlPages.includes(id)) {
            const anchor = Config.controlPanel?.anchor_bar ?? "";
            const at = anchor !== "" ? bars[anchor + "@" + screenName] : null;
            if (at)
                origin = Object.assign({}, at, {
                    context: origin?.context ?? "",
                    history: origin?.history ?? []
                });
        }
        set(screenName, {
            id: id,
            originX: origin?.x ?? -1,
            originY: origin?.y ?? -1,
            edge: origin?.edge ?? "top",
            extent: origin?.extent ?? 42,
            context: origin?.context ?? "",
            // where back goes: a Control Center tab opened from a bar goes back to the Control Panel
            history: origin?.history ?? []
        });
    }
    // Hover-opened ("transient") panels: shown while the pointer is on what opened them or on the panel,
    // gone a moment after it leaves both (the bar's hover_close_delay). A transient panel never replaces a
    // pinned one; a click pins it (open() without the flag).
    function peek(id: string, screenName: string, origin: var, owner: string, closeDelay: int, closeOnLeave: bool): void {
        const cur = openPanels[screenName];
        if (cur && !cur.transient && cur.id !== id)
            return;
        if (cur && !cur.transient && cur.id === id)
            return;
        open(id, screenName, origin);
        set(screenName, Object.assign({}, openPanels[screenName], {
            transient: true,
            owner: owner,
            closeDelay: closeDelay,
            closeOnLeave: closeOnLeave
        }));
    }
    function pin(screenName: string): void {
        const cur = openPanels[screenName];
        if (cur?.transient)
            set(screenName, Object.assign({}, cur, { transient: false }));
    }
    // what the pointer is on, per output: keys of hovered owners (bar items) and "panel"
    property var holds: ({})
    function hold(screenName: string, key: string, on: bool): void {
        const keys = (holds[screenName] ?? []).filter(k => k !== key);
        if (on)
            keys.push(key);
        const next = Object.assign({}, holds);
        next[screenName] = keys;
        holds = next;
    }
    function held(screenName: string): bool {
        return (holds[screenName] ?? []).length > 0;
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
    // a tab: another page of the same surface, side by side rather than deeper (no history)
    function switchTo(id: string, screenName: string): void {
        const cur = openPanels[screenName];
        if (!cur)
            return open(id, screenName, null);
        if (cur.id !== id)
            set(screenName, Object.assign({}, cur, {
                id: id,
                history: []
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
    // where each output's panel card sits, in global coordinates (for diagnostics and cropped captures)
    property var rects: ({})
    // the panel window's actual size per output (diagnostics: should match its card's span)
    property var windowSizes: ({})
    function noteRect(screenName: string, rect: var): void {
        rects[screenName] = rect;
    }

    function closeAll(): void {
        openPanels = {};
    }
}
