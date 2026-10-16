pragma Singleton

import QtQuick
import Quickshell

// Which focused panel is open on which output, where it came from, and how to get back. One panel per
// output by default: opening another replaces it; navigate() moves within the same surface.
Singleton {
    id: root

    // screen name -> { id, originX, originY, edge, extent, history: [ids], place }
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
    // the Control Panel and its pages: placed by [control_panel] position (placement() below)
    readonly property var controlPages: ["control", "home", "quick", "audio", "power", "monitor", "calendar", "weather", "screen-time", "network", "bluetooth", "notifications", "media", "system"]
    property var bars: ({})
    property var barItems: ({})
    function noteBar(id: string, screenName: string, origin: var): void {
        if (id === "")
            return;
        bars[id + "@" + screenName] = origin;
        const z = { screen: screenName, edge: origin.edge, size: origin.reserved ?? 0 };
        const key = id + "@" + screenName;
        const was = zones[key];
        if (!was || was.edge !== z.edge || was.size !== z.size || was.screen !== z.screen)
            zones = Object.assign({}, zones, { [key]: z });
        follow(id, screenName, origin);
    }
    // A panel open from a bar follows that bar: resized, moved along its edge or to another edge while the panel
    // is open, the panel keeps the opener's place along it and meets its new edge (it used to stay where it
    // opened — overlapping a thickened bar, or left behind, still drawn as joined, by a bar that moved).
    function follow(id: string, screenName: string, origin: var): void {
        const cur = openPanels[screenName];
        if (!cur || cur.barId !== id || cur.place !== "" || !cur.barSpan || !origin.barSpan)
            return;
        const was = cur.edge === "top" || cur.edge === "bottom";
        const now = origin.edge === "top" || origin.edge === "bottom";
        // the opener's distance from the start of the bar, kept; on another axis, the bar's middle
        const along = was === now ? (was ? cur.originX : cur.originY) - cur.barSpan[0] : (origin.barSpan[1] - origin.barSpan[0]) / 2;
        const x = now ? origin.barSpan[0] + along : origin.x;
        const y = now ? origin.y : origin.barSpan[0] + along;
        if (x === cur.originX && y === cur.originY && origin.edge === cur.edge && origin.extent === cur.extent && origin.reach === cur.reach && origin.barSpan[0] === cur.barSpan[0] && origin.barSpan[1] === cur.barSpan[1] && origin.fillOpacity === cur.fillOpacity)
            return;
        set(screenName, Object.assign({}, cur, {
            originX: x,
            originY: y,
            edge: origin.edge,
            extent: origin.extent,
            reach: origin.reach,
            barSpan: origin.barSpan,
            fillOpacity: origin.fillOpacity,
            barOpacity: origin.barOpacity
        }));
    }
    function forgetBar(id: string, screenName: string): void {
        const key = id + "@" + screenName;
        delete bars[key];
        if (zones[key] !== undefined) {
            const next = Object.assign({}, zones);
            delete next[key];
            zones = next;
        }
    }
    // a panel joined to a bar, per bar@screen: { start, end, progress } (PanelSurface writes, BarWindow reads)
    property var joins: ({})
    function setJoin(key: string, value: var): void {
        const cur = joins[key];
        if (!value && cur === undefined)
            return;
        if (value && cur && cur.start === value.start && cur.end === value.end && Math.abs(cur.progress - value.progress) < 0.01)
            return;
        const next = Object.assign({}, joins);
        if (value)
            next[key] = value;
        else
            delete next[key];
        joins = next;
    }
    // the room each bar keeps windows out of, per output: bar@screen -> { screen, edge, size }
    property var zones: ({})
    // an output's work area (the screen less the bars' reserved room; the bars on one edge share one reservation,
    // as deep as the deepest: EdgeReserve), in its own coordinates: { x, y, w, h }
    function workArea(screenName: string, width: real, height: real): var {
        const inset = { top: 0, bottom: 0, left: 0, right: 0 };
        for (const k in zones) {
            const z = zones[k];
            if (z.screen === screenName && z.size > 0 && inset[z.edge] !== undefined)
                inset[z.edge] = Math.max(inset[z.edge], z.size);
        }
        return {
            x: inset.left,
            y: inset.top,
            w: Math.max(0, width - inset.left - inset.right),
            h: Math.max(0, height - inset.top - inset.bottom)
        };
    }

    // [control_panel] position: where the Control Panel (and its pages, not opened alone) appears
    readonly property var spots: ["top-left", "top-center", "top-right", "middle-left", "center", "middle-right", "bottom-left", "bottom-center", "bottom-right"]
    // what last opened it from a bar, per output (position = follow)
    property var lastTrigger: ({})
    function placement(id: string, screenName: string, origin: var): var {
        if (!controlPages.includes(id) || (origin?.focused ?? false) || origin?.edge === "center")
            return { origin: origin, place: "" };
        const position = String(Config.controlPanel?.position ?? "auto");
        if (spots.includes(position))
            return { origin: origin, place: position };
        const fromBar = (origin?.x ?? -1) >= 0;
        if (fromBar) {
            // the whole origin, the bar's fill, span and id with it: without them a panel reopened from here (a
            // key) could not join the bar and floated beside it
            const t = Object.assign({}, origin);
            delete t.context;
            delete t.history;
            delete t.focused;
            lastTrigger[screenName] = t;
            return { origin: origin, place: "" };
        }
        const keep = { context: origin?.context ?? "", history: origin?.history ?? [], focused: false };
        // follow: where it was last opened from on this output
        const last = position === "follow" ? lastTrigger[screenName] : null;
        if (last)
            return { origin: Object.assign({}, last, keep), place: "" };
        // auto (and follow before any trigger): the bar [control_panel] anchor_bar names, else the top right
        const anchor = Config.controlPanel?.anchor_bar ?? "";
        const at = anchor !== "" ? bars[anchor + "@" + screenName] : null;
        if (at)
            return { origin: Object.assign({}, at, keep), place: "" };
        return { origin: origin, place: "top-right" };
    }

    function open(id: string, screenName: string, origin: var): void {
        const placed = placement(id, screenName, origin);
        origin = placed.origin;
        set(screenName, {
            id: id,
            originX: origin?.x ?? -1,
            originY: origin?.y ?? -1,
            edge: origin?.edge ?? "top",
            extent: origin?.extent ?? 42,
            context: origin?.context ?? "",
            // where back goes: a Control Center tab opened from a bar goes back to the Control Panel
            history: origin?.history ?? [],
            // a Control Panel page opened by itself: no hero, no tabs, its own size
            focused: origin?.focused ?? false,
            // a spot of the work area ([control_panel] position), or "" beside what opened it
            place: placed.place,
            // the bar it came from, for an attached panel: its fill opacity, its span along the edge and id
            fillOpacity: origin?.fillOpacity ?? -1,
            barOpacity: origin?.barOpacity ?? 0,
            barSpan: origin?.barSpan ?? null,
            barId: origin?.barId ?? "",
            reach: origin?.reach ?? -1,
            // how long the widget that opened it is along its bar (its signal mark is as wide; 0: not a widget)
            itemSpan: origin?.itemSpan ?? 0
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
    // A preview (from Settings): the panel as it is, beside the window changing it. It takes no keys and lays
    // no catcher, so clicks and typing still reach Settings; it stays until asked again (or closed).
    function preview(id: string, screenName: string): void {
        const cur = openPanels[screenName];
        if (cur && cur.id === id && cur.preview)
            return close(screenName);
        open(id, screenName, null);
        set(screenName, Object.assign({}, openPanels[screenName], { preview: true }));
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
    // where each output's panel card sits, in global coordinates (notification popups step past it; also
    // diagnostics and cropped captures). Reassigned, not mutated, so bindings on it follow.
    property var rects: ({})
    // the page showing in each screen's panel (PanelContent): what a key sent over IPC reaches (`ipc panelKey`)
    property var livePages: ({})
    // the panel window's actual size per output (diagnostics: should match its card's span)
    property var windowSizes: ({})
    function noteRect(screenName: string, rect: var): void {
        const prev = rects[screenName];
        if (prev && prev.x === rect.x && prev.y === rect.y && prev.w === rect.w && prev.h === rect.h)
            return;
        const next = Object.assign({}, rects);
        next[screenName] = rect;
        rects = next;
    }

    function closeAll(): void {
        openPanels = {};
    }
}
