pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common
import "../Common/Fuzzy.js" as Fuzzy

// Installed applications: how often each is opened, which are pinned, their categories and actions, and how to
// open one. Under niri apps are spawned by the compositor, so they get the session's environment rather than
// the shell's. The first run imports the native launcher's usage counts and recent list, so ranking carries over.
Singleton {
    id: root

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)

    // freedesktop main categories, folded into the groups a person browses by
    readonly property var categories: [
        { key: "internet", label: "Internet", icon: "world", match: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
        { key: "development", label: "Development", icon: "category", match: ["Development", "IDE", "TextEditor"] },
        { key: "media", label: "Media", icon: "music", match: ["AudioVideo", "Audio", "Video", "Player", "Music"] },
        { key: "graphics", label: "Graphics", icon: "palette", match: ["Graphics", "Photography", "2DGraphics", "3DGraphics"] },
        { key: "games", label: "Games", icon: "rocket", match: ["Game"] },
        { key: "office", label: "Office", icon: "letter-a", match: ["Office", "Education", "Science"] },
        { key: "system", label: "System", icon: "settings", match: ["System", "Settings", "Monitor", "TerminalEmulator", "Utility"] }
    ]
    function categoryOf(e: var): string {
        const cats = e.categories ?? [];
        for (const c of categories)
            if (c.match.some(m => cats.includes(m)))
                return c.key;
        return "other";
    }
    // the groups that have at least one app, for the launcher's chips
    readonly property var presentCategories: categories.filter(c => all.some(e => categoryOf(e) === c.key))

    // recently and often used apps rank higher, for a few weeks
    function boost(id: string, now: real): real {
        const u = store.launches[id];
        if (!u)
            return 0;
        const days = (now - u.t) / 86400000;
        return Math.log2(1 + u.n) * 40 + Math.max(0, 60 - days * 4);
    }

    function isPinned(id: string): bool {
        return store.pinned.includes(id);
    }
    function togglePin(id: string): void {
        store.pinned = isPinned(id) ? store.pinned.filter(p => p !== id) : store.pinned.concat([id]);
        file.writeAdapter();
    }

    // apps for a query, optionally within one category; pinned ones lead an empty query
    function search(query: string, limit: int, category: string): var {
        const q = query.trim().toLowerCase();
        const now = Date.now();
        // [launcher] sort_by_usage: how often and how lately an app was opened lifts it
        const byUsage = Config.launcher?.sort_by_usage !== false;
        const boost = (id, t) => byUsage ? root.boost(id, t) : 0;
        const pool = category && category !== "all" ? all.filter(e => categoryOf(e) === category) : all;
        if (q === "") {
            const pins = store.pinned.map(id => pool.find(e => e.id === id)).filter(e => e !== undefined);
            const rest = pool.filter(e => !isPinned(e.id)).map(e => ({
                        e: e,
                        s: boost(e.id, now)
                    })).sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).map(x => x.e);
            return pins.concat(rest).slice(0, limit);
        }
        const scored = [];
        for (const e of pool) {
            let s = Math.max(Fuzzy.score(q, e.name, true), Fuzzy.score(q, e.genericName, false) * 0.7, Fuzzy.score(q, e.id, false) * 0.6);
            for (const k of e.keywords)
                s = Math.max(s, Fuzzy.score(q, k, false) * 0.6);
            if (s === 0)
                s = Fuzzy.score(q, e.comment, false) * 0.3;
            if (s > 0)
                scored.push({
                    e: e,
                    s: s + boost(e.id, now) + (isPinned(e.id) ? 30 : 0)
                });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.slice(0, limit).map(x => x.e);
    }

    // actions whose name answers the query ("firefox private", "new window"): [{ entry, action, score }]
    function searchActions(query: string, limit: int): var {
        const q = query.trim().toLowerCase();
        if (q.length < 3)
            return [];
        const found = [];
        for (const e of all) {
            for (const a of e.actions ?? []) {
                const s = Math.max(Fuzzy.score(q, a.name, false), Fuzzy.score(q, e.name + " " + a.name, false) * 0.9);
                if (s >= 400)
                    found.push({
                        entry: e,
                        action: a,
                        score: s + boost(e.id, Date.now()) * 0.5
                    });
            }
        }
        return found.sort((a, b) => b.score - a.score).slice(0, limit);
    }

    function terminal(): var {
        const configured = Config.launcher.terminal;
        if (configured && configured.length > 0)
            return configured;
        const env = Quickshell.env("TERMINAL");
        return env ? [env, "-e"] : ["kitty"];
    }

    function spawn(cmd: var, inTerminal: bool, workingDirectory: string): void {
        if (cmd.length === 0)
            return;
        if (inTerminal)
            cmd = terminal().concat(cmd);
        if (workingDirectory)
            cmd = ["sh", "-c", "cd -- \"$1\" || exit 1; shift; exec \"$@\"", "zynith-launch", workingDirectory].concat(cmd);
        if (NiriState.connected)
            NiriState.action({
                Spawn: {
                    command: cmd
                }
            });
        else
            Quickshell.execDetached(cmd);
    }
    function launch(entry: var): void {
        spawn(Array.from(entry.command ?? []), entry.runInTerminal, entry.workingDirectory);
        record(entry.id);
    }
    function launchAction(entry: var, action: var): void {
        spawn(Array.from(action.command ?? []), entry.runInTerminal, entry.workingDirectory);
        record(entry.id);
    }

    function record(id: string): void {
        const launches = Object.assign({}, store.launches);
        const u = launches[id] ?? {
            n: 0,
            t: 0
        };
        launches[id] = {
            n: u.n + 1,
            t: Date.now()
        };
        store.launches = launches;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: Paths.state + "/launcher.json"
        printErrors: false
        onLoaded: if (!store.imported)
            root.importStep = 1
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.importStep = 1;
            else
                console.warn("zynith: launcher history unreadable:", FileViewError.toString(err));
        }

        JsonAdapter {
            id: store
            // desktop id -> { n: launches, t: last launch (ms) }
            property var launches: ({})
            // desktop ids shown first when the launcher opens
            property var pinned: []
            // the native launcher's history was folded in
            property bool imported: false
        }
    }

    // ── one-time import of the native launcher's ranking (read only) ─────────
    function idOf(path: string): string {
        return path.split("/").pop().replace(/\.desktop$/, "");
    }
    // 0 idle, 1 reading the counts, 2 reading the recent list; a path set is what starts a read
    property int importStep: 0
    FileView {
        id: nativeUsage
        path: root.importStep >= 1 ? Paths.home + "/.local/state/noctalia/usage_counts.json" : ""
        printErrors: false
        onLoaded: root.importStep = 2
        onLoadFailed: root.importStep = 2
    }
    FileView {
        id: nativeRecent
        path: root.importStep >= 2 ? Paths.home + "/.local/state/noctalia/recently_used.json" : ""
        printErrors: false
        onLoaded: root.importNative()
        onLoadFailed: root.importNative()
    }
    function importNative(): void {
        if (store.imported)
            return;
        let counts = {}, recent = [];
        try {
            counts = JSON.parse(nativeUsage.text()).Applications ?? {};
        } catch (e) {}
        try {
            recent = JSON.parse(nativeRecent.text()).Applications ?? [];
        } catch (e) {}
        const launches = Object.assign({}, store.launches);
        const now = Date.now();
        for (const [path, n] of Object.entries(counts)) {
            const id = idOf(path);
            const was = launches[id] ?? { n: 0, t: 0 };
            // most recent first in the native list; an hour apart keeps the order without inventing dates
            const rank = recent.indexOf(path);
            launches[id] = {
                n: Math.max(was.n, n),
                t: Math.max(was.t, rank >= 0 ? now - rank * 3600000 : now - 14 * 86400000)
            };
        }
        store.launches = launches;
        store.imported = true;
        file.writeAdapter();
        importStep = 0;
    }
}
