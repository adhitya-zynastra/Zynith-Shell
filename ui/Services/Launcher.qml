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

    readonly property var modes: [
        { prefix: "", id: "apps", label: "Apps", glyph: "apps" },
        { prefix: "=", id: "calc", label: "Calculate", glyph: "calculator" },
        { prefix: ">", id: "windows", label: "Windows", glyph: "app-window" },
        { prefix: "@", id: "wallpapers", label: "Wallpapers", glyph: "photo" },
        { prefix: ":", id: "emoji", label: "Emoji", glyph: "mood-smile" },
        { prefix: "!", id: "session", label: "Session", glyph: "power" }
    ]

    // the native launcher's commands still work: /calc /emo /win /wall /session
    readonly property var aliases: ({
            calc: "=",
            math: "=",
            emo: ":",
            emoji: ":",
            win: ">",
            windows: ">",
            wall: "@",
            wallpaper: "@",
            session: "!",
            power: "!"
        })
    // { mode, q }: the mode a text asks for and the query left once its prefix is taken off
    function parse(text: string): var {
        const slash = text.match(/^\/(\w+)\s?(.*)$/);
        if (slash && aliases[slash[1].toLowerCase()] !== undefined) {
            const prefix = aliases[slash[1].toLowerCase()];
            return {
                mode: modes.find(m => m.prefix === prefix),
                q: slash[2]
            };
        }
        const c = text.charAt(0);
        const mode = modes.find(m => m.prefix !== "" && m.prefix === c) ?? modes[0];
        return {
            mode: mode,
            q: (mode.prefix ? text.slice(1) : text).trim()
        };
    }
    function modeOf(text: string): var {
        return parse(text).mode;
    }

    function search(text: string, limit: int, category: string): var {
        const parsed = parse(text);
        const mode = parsed.mode;
        const q = parsed.q.trim();
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
        return Calc.looksLikeMath(q) ? calc(q).concat(merged.slice(0, limit - 1)) : merged;
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
