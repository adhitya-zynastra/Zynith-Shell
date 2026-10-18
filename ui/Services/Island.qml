pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import "../Common/IslandModel.js" as IslandModel

// The island's one state, for every island on every bar: what is happening (IslandModel activities) from the
// services that already know it — Media, Notifications, Audio, Power — never a poller or a store of its own.
// It does nothing until an island exists (retain / release, counted), and then nothing on a clock: one timer, for
// the next activity to end.
//
// Notifications: while an island that takes them is on screen, it is where new ones appear — the popup window
// stands down (NotificationPopups reads takesNotifications) and the island lets each go after the popup's own
// timeout (Notifications.timeoutFor), so there is one presenter and one queue.
Singleton {
    id: root

    // island instances: { id: settings } (the last one to say is the one that rules: two islands share one state)
    property var islands: ({})
    readonly property int consumers: Object.keys(islands).length
    readonly property var options: {
        const keys = Object.keys(islands);
        return keys.length ? islands[keys[keys.length - 1]] : ({});
    }
    function retain(id: string, settings: var): void {
        const m = Object.assign({}, islands);
        m[id] = settings ?? {};
        islands = m;
    }
    function release(id: string): void {
        const m = Object.assign({}, islands);
        delete m[id];
        islands = m;
    }

    readonly property bool showsMedia: options.show_media !== false
    readonly property bool keepPaused: options.keep_paused === true
    readonly property bool showsDevices: options.show_devices !== false
    readonly property bool showsPower: options.show_power !== false
    readonly property string privacy: options.privacy ?? "full"
    readonly property bool takesNotifications: consumers > 0 && options.take_notifications !== false && Notifications.serving

    property var activities: []
    // the one the user picked to look at (it stays first while it lasts)
    property string pinned: ""
    readonly property var primary: IslandModel.primary(activities, pinned)
    readonly property var secondary: IslandModel.secondary(activities, pinned)
    readonly property var ordered: IslandModel.order(activities)

    function put(a: var): void {
        if (a)
            activities = IslandModel.upsert(activities, a);
        arm();
    }
    function drop(id: string): void {
        activities = IslandModel.remove(activities, id);
        if (pinned === id)
            pinned = "";
        arm();
    }
    // the user is done with what is shown: a notification is dismissed (the sender told), anything else set aside
    function dismiss(id: string): void {
        const a = activities.find(x => x.id === id);
        if (!a)
            return;
        if (a.kind === "notification")
            Notifications.close(a.data.key);
        drop(id);
    }
    function pick(id: string): void {
        pinned = id;
    }

    // ── the one timer: the next end ──
    function arm(): void {
        const end = IslandModel.nextEnd(activities);
        if (end === 0) {
            ends.stop();
            return;
        }
        ends.interval = Math.max(16, end - Date.now());
        ends.restart();
    }
    Timer {
        id: ends
        onTriggered: {
            const now = Date.now();
            const gone = root.activities.filter(a => a.until > 0 && a.until <= now);
            root.activities = IslandModel.live(root.activities, now);
            for (const a of gone)
                if (a.kind === "notification")
                    Notifications.hidePopup(a.data.key);
            if (gone.some(a => a.id === root.pinned))
                root.pinned = "";
            root.arm();
        }
    }

    // ── media ──
    function syncMedia(): void {
        const a = showsMedia && consumers > 0 ? IslandModel.media({
            present: Media.present,
            playing: Media.playing,
            title: Media.title,
            artist: Media.artist,
            art: Media.art,
            app: Media.app
        }, keepPaused, Date.now()) : null;
        if (a) {
            // the same player keeps its place in time (a new track is not a new arrival)
            const was = activities.find(x => x.id === "media");
            if (was && was.data.playing === a.data.playing)
                a.since = was.since;
            put(a);
        } else if (activities.some(x => x.id === "media")) {
            drop("media");
        }
    }
    Connections {
        target: root.consumers > 0 ? Media : null
        function onPresentChanged(): void {
            root.syncMedia();
        }
        function onPlayingChanged(): void {
            root.syncMedia();
        }
        function onTitleChanged(): void {
            root.syncMedia();
        }
        function onArtChanged(): void {
            root.syncMedia();
        }
    }
    onConsumersChanged: {
        syncMedia();
        syncNotifications();
        lastSink = Audio.sinkName;
        lastCharging = Power.charging;
    }
    onShowsMediaChanged: syncMedia()
    onKeepPausedChanged: syncMedia()

    // ── notifications: the popups, while the island takes them ──
    function syncNotifications(): void {
        if (!takesNotifications) {
            const had = activities.filter(a => a.kind === "notification");
            if (had.length) {
                activities = activities.filter(a => a.kind !== "notification");
                arm();
            }
            return;
        }
        const now = Date.now();
        let next = activities.filter(a => a.kind !== "notification" || Notifications.popups.includes(a.data.key));
        for (const key of Notifications.popups) {
            if (next.some(a => a.id === "notification:" + key))
                continue;
            const e = Notifications.entry(key);
            if (!e)
                continue;
            next = IslandModel.upsert(next, IslandModel.notification(Object.assign({}, e, {
                icon: Notifications.iconFor(e)
            }), Notifications.timeoutFor(e), privacy, now));
        }
        activities = next;
        arm();
    }
    Connections {
        target: root.takesNotifications ? Notifications : null
        function onPopupsChanged(): void {
            root.syncNotifications();
        }
    }
    onTakesNotificationsChanged: syncNotifications()

    // ── the sound moved; power came or went ──
    property string lastSink: ""
    Connections {
        target: root.consumers > 0 && root.showsDevices ? Audio : null
        function onSinkNameChanged(): void {
            const name = Audio.sinkName;
            if (name !== "" && root.lastSink !== "" && name !== root.lastSink)
                root.put(IslandModel.device(name, /head|bud|pod|earph/i.test(name) ? "headphones" : "device-speaker", Date.now(), 3000));
            root.lastSink = name;
        }
    }
    property bool lastCharging: false
    Connections {
        target: root.consumers > 0 && root.showsPower && Power.present ? Power : null
        function onChargingChanged(): void {
            if (Power.charging !== root.lastCharging)
                root.put(IslandModel.power(Power.charging, Power.level, Date.now(), 3000));
            root.lastCharging = Power.charging;
        }
    }
}
