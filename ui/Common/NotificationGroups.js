.pragma library
// The notification centre's model, kept apart from QML so it can be tested: the history (newest first) laid out
// as time sections holding one stack per app, the order the keyboard walks it in, and the age of a notification
// in words. Nothing here keeps state; the panel passes in what is open.

// sections in order: within the last hour, earlier today, before today
function sectionOf(time, now) {
    var startOfDay = new Date(now);
    startOfDay.setHours(0, 0, 0, 0);
    if (now - time < 3600000)
        return "now";
    if (time >= startOfDay.getTime())
        return "today";
    return "earlier";
}
var SECTIONS = [
    { key: "now", label: "Now" },
    { key: "today", label: "Today" },
    { key: "earlier", label: "Earlier" }
];

function appOf(e) {
    return e.appName || "Notification";
}

// rows for the list: { kind: "section", key, label } and { kind: "group", key, app, entries, open, stacked }
//   opts: { now, query, grouping (default true), opened: { app: true } }
// A group of one is never "stacked"; searching lists every match on its own.
function build(history, opts) {
    var now = opts.now;
    var q = (opts.query || "").trim().toLowerCase();
    var grouping = opts.grouping !== false && q === "";
    var opened = opts.opened || {};
    var all = history.filter(function (e) {
        return q === "" || (appOf(e) + " " + (e.summary || "") + " " + (e.body || "")).toLowerCase().indexOf(q) >= 0;
    });
    var out = [];
    SECTIONS.forEach(function (s) {
        var inSection = all.filter(function (e) {
            return sectionOf(e.time, now) === s.key;
        });
        if (inSection.length === 0)
            return;
        out.push({ kind: "section", key: "s:" + s.key, label: s.label });
        if (!grouping) {
            inSection.forEach(function (e) {
                out.push({ kind: "group", key: "g:" + s.key + ":e" + e.key, app: appOf(e), entries: [e], open: true, stacked: false });
            });
            return;
        }
        var order = [], groups = {};
        inSection.forEach(function (e) {
            var app = appOf(e);
            if (!groups[app]) {
                groups[app] = [];
                order.push(app);
            }
            groups[app].push(e);
        });
        order.forEach(function (app) {
            var list = groups[app];
            var open = list.length === 1 || opened[app] === true;
            out.push({ kind: "group", key: "g:" + s.key + ":" + app, app: app, entries: list, open: open, stacked: list.length > 1 && !open });
        });
    });
    return out;
}

// What the keyboard steps through, in order: a stacked group is one stop (its newest card); an open group of
// several is its header, then each card; a group of one is its card.
//   → [{ id, kind: "group" | "entry", group (row key), app, key (entry key, for an entry) }]
function stops(rows) {
    var out = [];
    rows.forEach(function (r) {
        if (r.kind !== "group")
            return;
        if (r.stacked) {
            out.push({ id: r.key, kind: "group", group: r.key, app: r.app });
            return;
        }
        if (r.entries.length > 1)
            out.push({ id: r.key, kind: "group", group: r.key, app: r.app });
        r.entries.forEach(function (e) {
            out.push({ id: "e" + e.key, kind: "entry", group: r.key, app: r.app, key: e.key });
        });
    });
    return out;
}

// the stop after a move by `by` from `id`, held at the ends; a stop that went away (dismissed) resolves to the
// one now in its place, so the keyboard keeps its spot in the list
function step(list, id, by, fallbackIndex) {
    if (list.length === 0)
        return "";
    var i = -1;
    for (var k = 0; k < list.length; k++)
        if (list[k].id === id)
            i = k;
    if (i < 0)
        return list[Math.max(0, Math.min(list.length - 1, fallbackIndex || 0))].id;
    return list[Math.max(0, Math.min(list.length - 1, i + by))].id;
}
function indexOf(list, id) {
    for (var k = 0; k < list.length; k++)
        if (list[k].id === id)
            return k;
    return -1;
}

// "now", "4m", "2h", "yesterday", "3d", then the date
function ago(time, now) {
    var s = Math.max(0, Math.floor((now - time) / 1000));
    if (s < 60)
        return "now";
    if (s < 3600)
        return Math.floor(s / 60) + "m";
    var startOfDay = new Date(now);
    startOfDay.setHours(0, 0, 0, 0);
    if (time >= startOfDay.getTime())
        return Math.floor(s / 3600) + "h";
    if (time >= startOfDay.getTime() - 86400000)
        return "yesterday";
    var days = Math.floor((startOfDay.getTime() - time) / 86400000) + 1;
    if (days < 7)
        return days + "d";
    var d = new Date(time);
    return d.getDate() + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getMonth()];
}
