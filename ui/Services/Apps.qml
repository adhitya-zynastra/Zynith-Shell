pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common
import "../Common/Fuzzy.js" as Fuzzy

// Installed applications, how often each is opened, and how to open one. Under niri apps are spawned by
// the compositor, so they get the session's environment rather than the shell's.
Singleton {
    id: root

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)

    // recently and often used apps rank higher, for a few weeks
    function boost(id: string, now: real): real {
        const u = store.launches[id];
        if (!u)
            return 0;
        const days = (now - u.t) / 86400000;
        return Math.log2(1 + u.n) * 40 + Math.max(0, 60 - days * 4);
    }

    function search(query: string, limit: int): var {
        const q = query.trim().toLowerCase();
        const now = Date.now();
        if (q === "")
            return all.map(e => ({ e: e, s: boost(e.id, now) })).sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).slice(0, limit).map(x => x.e);
        const scored = [];
        for (const e of all) {
            let s = Math.max(Fuzzy.score(q, e.name, true), Fuzzy.score(q, e.genericName, false) * 0.7, Fuzzy.score(q, e.id, false) * 0.6);
            for (const k of e.keywords)
                s = Math.max(s, Fuzzy.score(q, k, false) * 0.6);
            if (s === 0)
                s = Fuzzy.score(q, e.comment, false) * 0.3;
            if (s > 0)
                scored.push({ e: e, s: s + boost(e.id, now) });
        }
        scored.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        return scored.slice(0, limit).map(x => x.e);
    }

    function terminal(): var {
        const configured = Config.launcher.terminal;
        if (configured && configured.length > 0)
            return configured;
        const env = Quickshell.env("TERMINAL");
        return env ? [env, "-e"] : ["kitty"];
    }

    function launch(entry: var): void {
        let cmd = Array.from(entry.command ?? []);
        if (cmd.length === 0)
            return;
        if (entry.runInTerminal)
            cmd = terminal().concat(cmd);
        if (entry.workingDirectory)
            cmd = ["sh", "-c", "cd -- \"$1\" || exit 1; shift; exec \"$@\"", "zynith-launch", entry.workingDirectory].concat(cmd);
        if (NiriState.connected)
            NiriState.action({ Spawn: { command: cmd } });
        else
            Quickshell.execDetached(cmd);
        record(entry.id);
    }

    function record(id: string): void {
        const launches = Object.assign({}, store.launches);
        const u = launches[id] ?? { n: 0, t: 0 };
        launches[id] = { n: u.n + 1, t: Date.now() };
        store.launches = launches;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: Paths.state + "/launcher.json"
        printErrors: false
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("zynith: launcher history unreadable:", FileViewError.toString(err));
        }

        JsonAdapter {
            id: store
            // desktop id -> { n: launches, t: last launch (ms) }
            property var launches: ({})
        }
    }
}
