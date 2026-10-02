pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Common

// The notification server, its popups and a history kept in memory only. Owning
// org.freedesktop.Notifications is an exclusive role: the server starts only when notifications.server is
// on AND nobody else holds the name, so it never takes the role from the native shell by accident.
Singleton {
    id: root

    // the Zynith UI owns notifications when zynith.toml hands them over (or notifications.toml server = true)
    readonly property bool wanted: (Config.surfaces?.notifications ?? "native") === "zynith" || Config.notifications.server || forceServer
    property bool forceServer: false     // test harness only (private bus)
    property bool nameFree: false
    readonly property bool serving: wanted && nameFree
    readonly property bool dnd: Config.notifications.dnd

    // newest first: { key, n (live Notification or null), appName, appIcon, image, summary, body, urgency,
    // time, actions: [{ id, text }] }
    property var history: []
    // keys of entries currently shown as popups, newest first
    property var popups: []
    readonly property int unread: history.length

    function setDnd(on: bool): void {
        Config.setNotificationsDnd(on);
        if (on)
            popups = popups.filter(k => entry(k)?.urgency === NotificationUrgency.Critical);
    }

    function entry(key: int): var {
        return history.find(e => e.key === key) ?? null;
    }

    // what the sender asked for, or a calm default by urgency; critical stays until handled
    function timeoutFor(e: var): int {
        if (e.urgency === NotificationUrgency.Critical)
            return 0;
        if (e.expireTimeout > 0)
            return Math.max(2000, Math.min(e.expireTimeout, 30000));
        return e.urgency === NotificationUrgency.Low ? Config.notifications.popupMs * 0.7 : Config.notifications.popupMs;
    }

    function plain(text: string): string {
        // the body may carry a small markup subset; popups show text only
        return (text ?? "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&").trim();
    }

    property int nextKey: 1
    function add(n: var): void {
        n.tracked = true;
        const e = {
            key: nextKey++,
            n: n,
            appName: n.appName || "",
            appIcon: n.appIcon || n.desktopEntry || "",
            image: n.image || "",
            summary: n.summary || "",
            body: plain(n.body),
            urgency: n.urgency,
            expireTimeout: n.expireTimeout,
            transient: n.transient,
            time: Date.now(),
            actions: n.actions.map(a => ({
                        id: a.identifier,
                        text: a.text
                    }))
        };
        n.closed.connect(() => root.forgetLive(e.key));
        // a replacement (same id) takes the place of the old entry
        const replaced = history.find(x => x.n && x.n.id === n.id && x.n !== n);
        let rest = history;
        if (replaced) {
            rest = history.filter(x => x !== replaced);
            popups = popups.filter(k => k !== replaced.key);
        }
        history = [e].concat(rest).slice(0, Config.notifications.historySize);
        if (!dnd || e.urgency === NotificationUrgency.Critical)
            popups = [e.key].concat(popups).slice(0, Config.notifications.maxPopups);
        chime(e);
        if (e.transient)
            forgetLater(e.key);
    }

    // transient notifications do not stay in the history once their popup is gone
    property var transientKeys: []
    function forgetLater(key: int): void {
        transientKeys = transientKeys.concat([key]);
    }

    function forgetLive(key: int): void {
        const e = entry(key);
        if (e)
            e.n = null;
        popups = popups.filter(k => k !== key);
    }

    function hidePopup(key: int): void {
        popups = popups.filter(k => k !== key);
        if (transientKeys.includes(key))
            remove(key);
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
        transientKeys = transientKeys.filter(k => k !== key);
    }

    function invoke(key: int, actionId: string): void {
        const e = entry(key);
        const action = e?.n?.actions.find(a => a.identifier === actionId);
        if (action)
            action.invoke();
        remove(key);
    }

    function clearAll(): void {
        for (const e of history) {
            if (e.n)
                e.n.dismiss();
        }
        history = [];
        popups = [];
        transientKeys = [];
    }

    // never take the name from someone else; while another owner is letting go (the native shell after a
    // handover), ask again for a little while
    property int ownerChecks: 0
    onWantedChanged: if (wanted) {
        ownerChecks = 0;
        owner.running = true;
    }
    Component.onCompleted: if (wanted)
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
                if (root.nameFree || !root.wanted)
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
        if (!(Config.notifications.sound ?? true) || dnd || e.urgency === NotificationUrgency.Low)
            return;
        Quickshell.execDetached(["pw-play", "--volume", String(Config.notifications.soundVolume ?? 0.6), Paths.home + "/.local/share/zynith/sounds/notification.wav"]);
    }

    LazyLoader {
        active: root.serving

        NotificationServer {
            keepOnReload: true
            actionsSupported: true
            bodySupported: true
            bodyMarkupSupported: true
            imageSupported: true
            persistenceSupported: false
            onNotification: n => root.add(n)
        }
    }
}
