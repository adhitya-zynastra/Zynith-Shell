.pragma library

// The island's activities as data: what is happening that it shows, how important each is, and when each ends.
// Every function is pure (Services/Island.qml feeds it from Media, Notifications, Audio and Power; the island
// widget and its panel draw what it says; tools/tests/tst_island_model.qml tests it).
//
// An activity: { id, kind, priority, since (ms), until (ms, 0 = while its source lasts), data }
//   kind: "media" | "notification" | "device" | "power"
// The island shows the most important one (priority, then the newest); the next one waits beside it as a small
// bubble. Nothing here runs on a clock: the service sets one timer, for the next activity to end.

var priorities = {
    critical: 6,        // a notification that stays until handled
    notification: 4,
    device: 3,          // the sound moved to another output
    power: 3,           // plugged in, unplugged
    media: 2,           // playing
    paused: 1           // a paused player, if the island keeps it
};

// put `a` in the list (replacing one with its id)
function upsert(list, a) {
    var out = list.filter(function (x) { return x.id !== a.id; });
    out.push(a);
    return out;
}
function remove(list, id) {
    return list.filter(function (x) { return x.id !== id; });
}
// what is still on at `now`
function live(list, now) {
    return list.filter(function (x) { return !x.until || x.until > now; });
}
// most important first; the newest of equals first
function order(list) {
    return list.slice().sort(function (a, b) {
        return b.priority !== a.priority ? b.priority - a.priority : b.since - a.since;
    });
}
// the one shown: the one the user picked (while it lasts), else the most important
function primary(list, pinned) {
    if (pinned) {
        var p = list.filter(function (x) { return x.id === pinned; })[0];
        if (p)
            return p;
    }
    return order(list)[0] || null;
}
// the one waiting beside it
function secondary(list, pinned) {
    var first = primary(list, pinned);
    return order(list).filter(function (x) { return !first || x.id !== first.id; })[0] || null;
}
// when the next one ends (0: none does)
function nextEnd(list) {
    var ends = list.filter(function (x) { return x.until > 0; }).map(function (x) { return x.until; });
    return ends.length ? Math.min.apply(null, ends) : 0;
}

// ── the activities, from their sources ──

// media: while a player is playing (or, if kept, paused); its id is the player's, so a new track replaces it
function media(m, keepPaused, now) {
    if (!m || !m.present || (!m.playing && !keepPaused))
        return null;
    return { id: "media", kind: "media", priority: m.playing ? priorities.media : priorities.paused, since: now, until: 0, data: { title: m.title, artist: m.artist, art: m.art, playing: m.playing, app: m.app } };
}
// a notification: until its timeout (0 for one that stays until handled), its words as privacy allows
//   privacy: "full" (summary and body) | "summary" | "app" (only which app)
function notification(e, timeoutMs, privacy, now) {
    var critical = timeoutMs === 0;
    var words = privacy === "app" ? { summary: "", body: "" } : privacy === "summary" ? { summary: e.summary, body: "" } : { summary: e.summary, body: e.body };
    return { id: "notification:" + e.key, kind: "notification", priority: critical ? priorities.critical : priorities.notification, since: now, until: critical ? 0 : now + timeoutMs, data: { key: e.key, app: e.appName, icon: e.icon, summary: words.summary, body: words.body } };
}
// the sound now goes to another output
function device(name, icon, now, ms) {
    return { id: "device", kind: "device", priority: priorities.device, since: now, until: now + (ms || 3000), data: { name: name, icon: icon } };
}
// plugged in or unplugged
function power(charging, level, now, ms) {
    return { id: "power", kind: "power", priority: priorities.power, since: now, until: now + (ms || 3000), data: { charging: charging, level: level } };
}
