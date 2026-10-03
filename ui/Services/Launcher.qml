pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common
import "../Common/Calc.js" as Calc

// What the launcher can find. A leading character picks the mode:
//   (none) apps, with a calculation when the text is arithmetic · = calculator · > windows · @ wallpapers
//   : emoji · ! session
// Every result has the same shape: { key, kind, title, subtitle, icon (theme icon name), glyph, emoji, run() }.
Singleton {
    id: root

    // [launcher.providers.<id>] prefix and global (also in the plain search); the native launcher's providers
    // (its calculator with units and currencies, and every plugin provider) answer through launcher-query
    readonly property var cfg: Config.launcher ?? ({})
    function pfx(id: string, fallback: string): string {
        return cfg.providers?.[id]?.prefix ?? fallback;
    }
    function inGlobal(id: string, fallback: bool): bool {
        return cfg.providers?.[id]?.global ?? fallback;
    }
    readonly property string commandPrefix: cfg.command_prefix ?? "/"

    // the native shell's providers: what it can answer for us
    property var nativeProviders: []
    readonly property bool nativeCalc: nativeProviders.some(p => p.id === "Calculator")
    readonly property var plugins: nativeProviders.filter(p => p.dynamic)
    function readProviders(): void {
        CoreClient.call("launcher-providers", text => {
            try {
                root.nativeProviders = JSON.parse(text);
            } catch (e) {}
        });
    }
    Component.onCompleted: readProviders()

    readonly property var modes: [
        { prefix: "", id: "apps", label: "Apps", glyph: "apps" },
        { prefix: pfx("calculator", "="), id: "calc", label: "Calculate", glyph: "calculator" },
        { prefix: pfx("windows", ">"), id: "windows", label: "Windows", glyph: "app-window" },
        { prefix: pfx("wallpapers", "@"), id: "wallpapers", label: "Wallpapers", glyph: "photo" },
        { prefix: pfx("emoji", ":"), id: "emoji", label: "Emoji", glyph: "mood-smile" },
        { prefix: pfx("session", "!"), id: "session", label: "Session", glyph: "power" }
    ].concat(plugins.map(p => ({
                prefix: "",
                command: p.prefix.replace(/^\//, ""),
                id: "native:" + p.id,
                provider: p.id,
                label: p.name,
                glyph: Icons.has(p.glyph) ? p.glyph : "puzzle"
            })))

    // the native launcher's commands still work: /calc /emo /win /wall /session, and each plugin's own
    readonly property var aliases: {
        const out = {
            calc: "calc",
            math: "calc",
            emo: "emoji",
            emoji: "emoji",
            win: "windows",
            windows: "windows",
            wall: "wallpapers",
            wallpaper: "wallpapers",
            session: "session",
            power: "session"
        };
        for (const m of modes)
            if (m.command)
                out[m.command.toLowerCase()] = m.id;
        return out;
    }
    // { mode, q }: the mode a text asks for and the query left once its prefix is taken off
    function parse(text: string): var {
        if (commandPrefix !== "" && text.startsWith(commandPrefix)) {
            const rest = text.slice(commandPrefix.length);
            const word = rest.match(/^(\S+)\s?(.*)$/);
            if (word && aliases[word[1].toLowerCase()] !== undefined)
                return {
                    mode: modes.find(m => m.id === aliases[word[1].toLowerCase()]),
                    q: word[2]
                };
        }
        const mode = modes.find(m => m.prefix !== "" && text.startsWith(m.prefix)) ?? modes[0];
        return {
            mode: mode,
            q: (mode.prefix ? text.slice(mode.prefix.length) : text).trim()
        };
    }
    function modeOf(text: string): var {
        return parse(text).mode;
    }

    function search(text: string, limit: int, category: string): var {
        const parsed = parse(text);
        const mode = parsed.mode;
        const q = parsed.q.trim();
        if (mode.provider)
            return remote(mode.provider, q);
        switch (mode.id) {
        case "calc":
            return calc(q);
        case "windows":
            return windows(q, limit);
        case "wallpapers":
            return wallpapers(q, limit);
        case "emoji":
            return emoji(q, limit);
        case "session":
            return session(q);
        }
        const apps = Apps.search(q, limit, category).map(e => app(e));
        // an action that answers the query directly ("firefox private") follows the apps
        const actions = category && category !== "all" ? [] : Apps.searchActions(q, 2).map(f => ({
                    key: "act:" + f.entry.id + ":" + f.action.name,
                    kind: "action",
                    title: f.action.name,
                    subtitle: f.entry.name,
                    icon: f.action.icon || f.entry.icon,
                    run: () => Apps.launchAction(f.entry, f.action)
                }));
        const merged = apps.slice(0, Math.max(1, limit - actions.length)).concat(actions);
        // the providers that also answer the plain search ([launcher.providers.<id>] global)
        let extra = [];
        if (q !== "") {
            if (inGlobal("calculator", true))
                extra = extra.concat(nativeCalc ? remote("Calculator", q) : Calc.looksLikeMath(q) ? calc(q) : []);
            if (inGlobal("windows", false))
                extra = extra.concat(windows(q, 3));
            if (inGlobal("emoji", false))
                extra = extra.concat(emoji(q, 3));
            if (inGlobal("session", false))
                extra = extra.concat(session(q).slice(0, 3));
            if (inGlobal("wallpapers", false))
                extra = extra.concat(wallpapers(q, 3));
        }
        return extra.concat(merged).slice(0, Math.max(limit, extra.length + 1));
    }

    // ── answers from the native shell's providers, asked once per query and kept a while ──
    property var answers: ({})
    property var lastFor: ({})
    property var asking: ({})
    function remote(provider: string, q: string): var {
        const key = provider + "\u0001" + q;
        if (answers[key] !== undefined)
            return answers[key];
        if (!asking[key]) {
            asking[key] = true;
            CoreClient.call("launcher-query " + provider + " " + q, text => {
                let list = [];
                try {
                    list = JSON.parse(text).map(r => root.nativeResult(provider, q, r));
                } catch (e) {}
                delete root.asking[key];
                const next = Object.keys(root.answers).length > 80 ? {} : Object.assign({}, root.answers);
                next[key] = list;
                root.answers = next;
                root.lastFor = Object.assign({}, root.lastFor, { [provider]: list });
            });
        }
        // what it said last, until it answers this one (no flicker while typing)
        return lastFor[provider] ?? [];
    }
    function nativeResult(provider: string, q: string, r: var): var {
        return {
            key: "n:" + provider + ":" + r.id,
            kind: provider === "Calculator" ? "calc" : "native",
            title: r.title.replace(/^= /, ""),
            subtitle: r.subtitle + (provider === "Calculator" ? "  ·  Enter copies" : ""),
            glyph: Icons.has(r.glyph) ? r.glyph : provider === "Calculator" ? "calculator" : "puzzle",
            icon: r.icon || r.iconPath || "",
            emoji: r.badge || "",
            run: () => CoreClient.call("launcher-activate " + JSON.stringify({ provider: provider, result: r.id, text: q }), reply => {
                if (reply.startsWith("ok copied") && (Config.launcher.auto_paste ?? true))
                    CoreClient.call("clipboard-paste text");
            })
        };
    }
    // a plugin's results came in later: ask again
    Connections {
        target: Events
        function onLauncher(): void {
            const keep = {};
            for (const k in root.answers)
                if (!root.plugins.some(p => k.startsWith(p.id + "\u0001")))
                    keep[k] = root.answers[k];
            root.answers = keep;
        }
    }

    function originOf(e: var): string {
        const x = (e.execString ?? "").toLowerCase();
        return x.includes("flatpak run") ? "flatpak" : x.includes("/snap/") || x.startsWith("snap ") ? "snap" : x.includes(".appimage") ? "appimage" : "";
    }
    function app(e: var): var {
        return {
            key: "app:" + e.id,
            kind: "app",
            id: e.id,
            title: e.name,
            subtitle: e.genericName || e.comment || "",
            icon: e.icon,
            pinned: Apps.isPinned(e.id),
            // where it was installed from, for the origin badge (the native show_app_origin_indicator)
            origin: originOf(e),
            actions: (e.actions ?? []).map(a => ({
                        key: "act:" + e.id + ":" + a.name,
                        kind: "action",
                        title: a.name,
                        subtitle: e.name,
                        icon: a.icon || e.icon,
                        run: () => Apps.launchAction(e, a)
                    })),
            run: () => Apps.launch(e)
        };
    }

    // copy results (calculator, emoji) go on the clipboard and, unless launcher auto_paste is off, into the
    // window the launcher was opened over
    function copy(text: string): void {
        CoreClient.call("clipboard-copy " + text, reply => {
            if (reply.startsWith("ok") && (Config.launcher.auto_paste ?? true))
                CoreClient.call("clipboard-paste text");
        });
    }

    function calc(q: string): var {
        if (nativeCalc && q !== "")
            return remote("Calculator", q);
        const v = Calc.evaluate(q);
        if (v === null)
            return [];
        const shown = Calc.format(v);
        return [{
                key: "calc",
                kind: "calc",
                title: shown,
                subtitle: q + "  ·  Enter copies",
                glyph: "calculator",
                run: () => copy(shown)
            }];
    }

    function windows(q: string, limit: int): var {
        const needle = q.toLowerCase();
        return NiriState.windowList().filter(w => needle === "" || w.title.toLowerCase().includes(needle) || w.appId.toLowerCase().includes(needle)).slice(0, limit).map(w => ({
                    key: "win:" + w.id,
                    kind: "window",
                    title: w.title || w.appId,
                    subtitle: w.appId + (w.focused ? "  ·  focused" : ""),
                    icon: (DesktopEntries.heuristicLookup(w.appId)?.icon) ?? w.appId,
                    run: () => NiriState.focusWindow(w.id)
                }));
    }

    function wallpapers(q: string, limit: int): var {
        Wallpapers.ensure();
        const images = Wallpapers.imagesFor("all", q, "az").slice(0, limit).map(i => ({
                    key: "wp:" + i.path,
                    kind: "wallpaper",
                    title: i.name,
                    subtitle: i.folder !== "" ? i.folder : "Image",
                    image: Thumbnails.url(i.path, 96),
                    run: () => Wallpapers.applyImage(i.path)
                }));
        const live = Wallpapers.liveFor("installed", q, "az").slice(0, limit).map(i => ({
                    key: "live:" + i.id,
                    kind: "wallpaper",
                    title: i.title,
                    subtitle: "Live  ·  " + i.kind,
                    image: i.preview !== "" ? Thumbnails.url(i.preview, 96) : "",
                    glyph: "photo",
                    run: () => Wallpapers.applyLive(i.id)
                }));
        // interleave, so a search shows both kinds near the top
        const out = [];
        for (let k = 0; out.length < limit && (k < images.length || k < live.length); k++) {
            if (k < live.length)
                out.push(live[k]);
            if (k < images.length && out.length < limit)
                out.push(images[k]);
        }
        return out;
    }

    // the emoji table loads on first use
    property var emojiTable: []
    function emoji(q: string, limit: int): var {
        wantEmoji = true;
        const needle = q.toLowerCase();
        return emojiTable.filter(e => needle === "" || e.name.includes(needle) || (e.keywords ?? []).some(k => k.startsWith(needle))).slice(0, limit).map(e => ({
                    key: "emoji:" + e.emoji,
                    kind: "emoji",
                    title: e.name,
                    subtitle: e.category ?? "",
                    emoji: e.emoji,
                    run: () => copy(e.emoji)
                }));
    }
    // the path is set on first use, which is what starts the read
    property bool wantEmoji: false
    FileView {
        id: emojiFile
        path: root.wantEmoji ? Quickshell.shellPath("../assets/emoji.json") : ""
        onLoaded: {
            try {
                root.emojiTable = JSON.parse(text());
            } catch (e) {}
        }
    }

    readonly property var sessionActions: [
        { id: "lock", label: "Lock", glyph: "lock" },
        { id: "suspend", label: "Sleep", glyph: "zzz" },
        { id: "logout", label: "Log out", glyph: "logout" },
        { id: "reboot", label: "Restart", glyph: "refresh" },
        { id: "shutdown", label: "Shut down", glyph: "power" }
    ]
    function session(q: string): var {
        const needle = q.toLowerCase();
        return sessionActions.filter(a => needle === "" || a.label.toLowerCase().includes(needle) || a.id.includes(needle)).map(a => ({
                    key: "session:" + a.id,
                    kind: "session",
                    title: a.label,
                    subtitle: a.id === "lock" || a.id === "suspend" ? "" : "Enter twice to confirm",
                    glyph: a.glyph,
                    confirm: a.id !== "lock" && a.id !== "suspend",
                    run: () => CoreClient.call("session " + a.id)
                }));
    }
}
