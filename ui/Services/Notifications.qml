pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Zynith.Native
import qs.Common

// The notification server, its popups and the history. Owning org.freedesktop.Notifications is an exclusive
// role: the server starts only when this UI owns notifications AND nobody else holds the name, so it never
// takes the role from the native shell by accident.
//
// What the native shell did, kept: a burst shows max_popups at once and the rest wait their turn (their
// timeouts start when they show); per-app filters; history across restarts. Added: progress (the "value"
// hint), inline replies, stack tags replacing one another, a history file only its owner can read.
Singleton {
    id: root

    // the Zynith UI owns notifications when zynith.toml hands them over (or notifications.toml server = true)
    readonly property bool wanted: (Config.surfaces?.notifications ?? "native") === "zynith" || Config.notifications.server || forceServer
    property bool forceServer: false     // test harness only (private bus)
    // once this process owns the name it keeps it across live reloads (keepOnReload), so a reload must not
    // mistake its own server for someone else's
    PersistentProperties {
        id: persist
        reloadableId: "zynith-notifications"
        property bool owned: false
    }
    property bool nameFree: false
    readonly property bool mayServe: nameFree || persist.owned
    onServingChanged: if (serving)
        persist.owned = true
    readonly property bool serving: wanted && mayServe
    readonly property bool dnd: Config.notifications.dnd

    // newest first: { key, n (live Notification or null), appName, appIcon, image, summary, body, urgency,
    // time, actions: [{ id, text }], progress (-1 or 0..100), reply (placeholder or ""), tag }
    property var history: []
    // keys shown as popups, newest first, at most max_popups; the rest wait in `queue`, oldest first
    property var popups: []
    property var queue: []
    readonly property int unread: history.length

    function setDnd(on: bool): void {
        Config.setNotificationsDnd(on);
        if (on) {
            popups = popups.filter(k => entry(k)?.urgency === NotificationUrgency.Critical || entry(k)?.bypassDnd);
            queue = queue.filter(k => entry(k)?.urgency === NotificationUrgency.Critical || entry(k)?.bypassDnd);
        }
    }

    function entry(key: int): var {
        return history.find(e => e.key === key) ?? null;
    }

    // what the sender asked for, or a calm default by urgency; critical stays until handled
    function timeoutFor(e: var): int {
        if (e.urgency === NotificationUrgency.Critical || e.resident)
            return 0;
        if (e.timeoutOverride > 0)
            return e.timeoutOverride;
        if (e.expireTimeout > 0)
            return Math.max(2000, Math.min(e.expireTimeout, 30000));
        return e.urgency === NotificationUrgency.Low ? Config.notifications.popupMs * 0.7 : Config.notifications.popupMs;
    }

    function plain(text: string): string {
        // the body may carry a small markup subset; popups show text only
        return (text ?? "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&").trim();
    }

    // ── filters (notifications.toml [[filter]]) ─────────────────────────────
    function urgencyName(u: int): string {
        return u === NotificationUrgency.Low ? "low" : u === NotificationUrgency.Critical ? "critical" : "normal";
    }
    // the first enabled rule that matches, or null
    function ruleFor(e: var): var {
        for (const f of Config.notifications.filters) {
            if (f.enabled === false)
                continue;
            const token = (f.match ?? "").toLowerCase();
            if (token !== "") {
                const fields = [e.appName, e.desktopEntry, e.category].map(x => (x ?? "").toLowerCase());
                if (!fields.some(x => x !== "" && x.includes(token)))
                    continue;
            }
            if ((f.match_content ?? "") !== "") {
                try {
                    if (!new RegExp(f.match_content, "i").test(e.summary + "\n" + e.body))
                        continue;
                } catch (err) {
                    continue;
                }
            }
            const urgencies = f.urgencies ?? [];
            if (urgencies.length > 0 && !urgencies.includes(urgencyName(e.urgency)))
                continue;
            return f;
        }
        return null;
    }

    property int nextKey: 1
    function add(n: var): void {
        n.tracked = true;
        const hints = n.hints ?? {};
        const value = Number(hints.value ?? -1);
        const e = {
            key: nextKey++,
            n: n,
            id: n.id,
            appName: n.appName || "",
            appIcon: n.appIcon || n.desktopEntry || "",
            desktopEntry: n.desktopEntry || "",
            category: String(hints.category ?? ""),
            image: n.image || "",
            summary: n.summary || "",
            body: plain(n.body),
            urgency: n.urgency,
            expireTimeout: n.expireTimeout,
            transient: n.transient,
            resident: n.resident,
            time: Date.now(),
            progress: value >= 0 && value <= 100 ? value : -1,
            reply: n.hasInlineReply ? (n.inlineReplyPlaceholder || "Reply") : "",
            tag: String(hints["x-canonical-private-synchronous"] ?? hints["x-dunst-stack-tag"] ?? ""),
            actions: n.actions.map(a => ({
                        id: a.identifier,
                        text: a.text
                    }))
        };
        const rule = ruleFor(e);
        e.timeoutOverride = rule?.timeout_ms ?? 0;
        e.bypassDnd = rule?.bypass_dnd === true;
        n.closed.connect(() => root.forgetLive(e.key));

        // a replacement (same id, or the same stack tag) takes the place of the old entry, popup included
        const replaced = history.find(x => (x.n && x.n.id === n.id && x.n !== n) || (e.tag !== "" && x.tag === e.tag && x.appName === e.appName));
        let rest = history;
        let wasShowing = false;
        if (replaced) {
            rest = history.filter(x => x !== replaced);
            wasShowing = popups.includes(replaced.key);
            popups = popups.filter(k => k !== replaced.key);
            queue = queue.filter(k => k !== replaced.key);
        }
        if (rule?.save_history === false)
            forgetLater(e.key);
        history = [e].concat(rest).slice(0, Config.notifications.historySize);

        const quiet = dnd && e.urgency !== NotificationUrgency.Critical && !e.bypassDnd;
        if (rule?.show_popup !== false && !quiet)
            show(e.key, wasShowing);
        if (rule?.play_sound !== false && !(hints["suppress-sound"] === true))
            chime(e);
        if (e.transient)
            forgetLater(e.key);
        save();
    }

    // shows a popup now if there is room (a replacement always is), else queues it
    function show(key: int, immediate: bool): void {
        if (immediate || popups.length < Config.notifications.maxPopups)
            popups = [key].concat(popups);
        else
            queue = queue.concat([key]);
    }
    function promote(): void {
        while (queue.length > 0 && popups.length < Config.notifications.maxPopups) {
            const next = queue[0];
            queue = queue.slice(1);
            if (entry(next))
                popups = [next].concat(popups);
        }
    }

    // transient (and filtered-out-of-history) notifications go once their popup is gone
    property var transientKeys: []
    function forgetLater(key: int): void {
        transientKeys = transientKeys.concat([key]);
    }

    function forgetLive(key: int): void {
        const e = entry(key);
        if (e)
            e.n = null;
        popups = popups.filter(k => k !== key);
        queue = queue.filter(k => k !== key);
        promote();
    }

    function hidePopup(key: int): void {
        popups = popups.filter(k => k !== key);
        if (transientKeys.includes(key))
            remove(key);
        promote();
    }

    // a popup closed (×, swipe): the sender is told; the history keeps it unless keep_dismissed is off
    function close(key: int): void {
        const e = entry(key);
        if (e?.n)
            e.n.dismiss();
        if (Config.notifications.keepDismissed === false)
            remove(key);
        else
            hidePopup(key);
    }

    // the user closed it: tell the sender, drop it from the history
    function dismiss(key: int): void {
        const e = entry(key);
        if (e?.n)
            e.n.dismiss();
        remove(key);
    }

    function remove(key: int): void {
        history = history.filter(e => e.key !== key);
        popups = popups.filter(k => k !== key);
        queue = queue.filter(k => k !== key);
        transientKeys = transientKeys.filter(k => k !== key);
        promote();
        save();
    }
    function removeApp(appName: string): void {
        for (const e of history.filter(x => (x.appName || "Notification") === appName))
            if (e.n)
                e.n.dismiss();
        const keys = history.filter(x => (x.appName || "Notification") === appName).map(x => x.key);
        history = history.filter(x => !keys.includes(x.key));
        popups = popups.filter(k => !keys.includes(k));
        queue = queue.filter(k => !keys.includes(k));
        promote();
        save();
    }

    function invoke(key: int, actionId: string): void {
        const e = entry(key);
        const action = e?.n?.actions.find(a => a.identifier === actionId);
        if (action)
            action.invoke();
        if (!e?.resident)
            remove(key);
    }
    function reply(key: int, text: string): void {
        const e = entry(key);
        if (e?.n && text.trim() !== "")
            e.n.sendInlineReply(text);
        remove(key);
    }

    function clearAll(): void {
        for (const e of history) {
            if (e.n)
                e.n.dismiss();
        }
        history = [];
        popups = [];
        queue = [];
        transientKeys = [];
        save();
    }

    // ── history across restarts (only its owner can read the file) ─────────
    PrivateStore {
        id: store
        path: Config.notifications.historyPersist ? Paths.state + "/notifications.json" : ""
        onLoaded: root.restore()
    }
    property bool restored: false
    function restore(): void {
        if (restored || !store.ready)
            return;
        restored = true;
        let saved = [];
        try {
            saved = JSON.parse(store.text || "[]");
        } catch (e) {
            return;
        }
        const cutoff = Config.notifications.retentionHours > 0 ? Date.now() - Config.notifications.retentionHours * 3600000 : 0;
        const old = saved.filter(e => e.time >= cutoff).map(e => Object.assign(e, {
                key: nextKey++,
                n: null,
                actions: []
            }));
        history = history.concat(old).slice(0, Config.notifications.historySize);
    }
    function save(): void {
        if (Config.notifications.historyPersist)
            saveLater.restart();
    }
    Timer {
        id: saveLater
        interval: 1500
        onTriggered: {
            const keep = root.history.filter(e => !root.transientKeys.includes(e.key)).map(e => ({
                        appName: e.appName,
                        appIcon: e.appIcon,
                        desktopEntry: e.desktopEntry,
                        category: e.category,
                        // an image path survives; inline image data does not
                        image: (e.image ?? "").startsWith("/") || (e.image ?? "").startsWith("file://") ? e.image : "",
                        summary: e.summary,
                        body: e.body,
                        urgency: e.urgency,
                        time: e.time,
                        progress: e.progress
                    }));
            store.save(JSON.stringify(keep));
        }
    }
    // turning persistence off removes the file
    Connections {
        target: Config
        function onNotificationsChanged(): void {
            if (Config.notifications.historyPersist === false)
                store.remove();
        }
    }

    // never take the name from someone else; while another owner is letting go (the native shell after a
    // handover), ask again for a little while
    property int ownerChecks: 0
    onWantedChanged: if (wanted && !persist.owned) {
        ownerChecks = 0;
        owner.running = true;
    }
    Component.onCompleted: if (wanted && !persist.owned)
        owner.running = true
    Timer {
        id: recheck
        interval: 1000
        onTriggered: owner.running = true
    }
    Process {
        id: owner
        command: ["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.Notifications"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.nameFree = text.trim() === "b false";
                if (root.nameFree || persist.owned || !root.wanted)
                    return;
                if (++root.ownerChecks < 20)
                    recheck.restart();
                else
                    console.warn("zynith: org.freedesktop.Notifications is owned by another process; not starting the notification server");
            }
        }
    }

    // the notification sound, as the native shell played it
    function chime(e: var): void {
        if (!(Config.notifications.sound ?? true) || (dnd && !e.bypassDnd) || e.urgency === NotificationUrgency.Low)
            return;
        Quickshell.execDetached(["pw-play", "--volume", String(Config.notifications.soundVolume ?? 0.6), Paths.home + "/.local/share/zynith/sounds/notification.wav"]);
    }

    LazyLoader {
        active: root.serving

        NotificationServer {
            keepOnReload: true
            actionsSupported: true
            actionIconsSupported: false
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: false
            imageSupported: true
            inlineReplySupported: true
            persistenceSupported: true
            extraHints: ["value", "category", "x-canonical-private-synchronous", "x-dunst-stack-tag", "suppress-sound"]
            onNotification: n => root.add(n)
        }
    }
}
