.pragma library

// The bars as data. A bar is an instance the user made: a stable id (never shown, never derived from its name),
// a name they chose, where it sits (an edge, its place along it, offsets), how it looks, and its components in
// order. A component is an instance too: an entry in a bar's start / center / end list names a [widget.<name>]
// table holding its kind (`type`) and its own settings, so two clocks on two bars (or one) are configured apart.
// A plain kind name with no table of its own (an older layout's "clock") still works: it is that kind with the
// kind's shared settings.
//
// Every function is pure: it takes the state { bars, widgets } (bars.toml's `bar` list and `widget` table) and
// returns a new one; nothing here touches a file. Services/Config.qml writes, Modules/Settings/BarsPage.qml
// edits, Modules/Bar/* draws, tools/tests/tst_bar_model.qml tests.

var schemaVersion = 2;

var edges = ["top", "bottom", "left", "right"];
var anchors = ["start", "center", "end", "fill"];
var sections = ["start", "center", "end"];
var visibilities = ["always", "smart", "autohide"];
var layers = ["bottom", "top", "overlay"];

// a list as the config store hands it over (a QVariantList arrives list-like, not as an Array) or as JS made it.
// Not "anything with a numeric length": a bar table has a `length` key of its own (its length along the edge).
function isList(v) {
    if (Array.isArray(v))
        return true;
    if (v === null || typeof v !== "object" || typeof v.length !== "number")
        return false;
    const keys = Object.keys(v);
    return keys.indexOf("length") < 0 && keys.every(function (k) { return /^[0-9]+$/.test(k); });
}
function list(v) {
    return isList(v) ? Array.prototype.slice.call(v) : [];
}

function clone(v) {
    return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

// a place along an edge as a person says it: left/top → start, right/bottom → end, centre/middle → center,
// full/full width → fill; anything else is returned as given (and validation reports it)
function anchorWord(word) {
    var w = String(word || "").toLowerCase().replace(/[^a-z]/g, "");
    var map = { left: "start", top: "start", start: "start", right: "end", bottom: "end", end: "end", center: "center", centre: "center", middle: "center", fill: "fill", full: "fill", fullwidth: "fill", fullheight: "fill", fulllength: "fill" };
    return map[w] !== undefined ? map[w] : word;
}

function vertical(bar) {
    return bar.edge === "left" || bar.edge === "right";
}

// ── naming ──────────────────────────────────────────────────────────────────

// "Top · Left", "Right · Centre", "Bottom · Full length"
function positionLabel(bar) {
    var edge = edges.indexOf(bar.edge) >= 0 ? bar.edge : "top";
    var anchor = anchors.indexOf(bar.anchor) >= 0 ? bar.anchor : "center";
    var along = anchor === "fill" ? "Full length" : anchor === "center" ? "Centre" : vertical({ edge: edge }) ? (anchor === "start" ? "Top" : "Bottom") : (anchor === "start" ? "Left" : "Right");
    return edge.charAt(0).toUpperCase() + edge.slice(1) + " · " + along;
}

// a name for a bar where it sits: "Top left", "Right", "Bottom centre", made unique among `taken`
function suggestName(bar, taken) {
    var edge = edges.indexOf(bar.edge) >= 0 ? bar.edge : "top";
    var anchor = anchors.indexOf(bar.anchor) >= 0 ? bar.anchor : "center";
    var e = edge.charAt(0).toUpperCase() + edge.slice(1);
    var base;
    if (anchor === "fill")
        base = e;
    else if (anchor === "center")
        base = e + " centre";
    else if (vertical({ edge: edge }))
        base = e + (anchor === "start" ? " top" : " bottom");
    else
        base = e + (anchor === "start" ? " left" : " right");
    return uniqueName(base, taken || []);
}

function uniqueName(base, taken) {
    if (taken.indexOf(base) < 0)
        return base;
    var n = 2;
    while (taken.indexOf(base + " " + n) >= 0)
        n++;
    return base + " " + n;
}

// an older layout's id ("rail", "top-2") as a name ("Rail", "Top 2")
function nameFromId(id) {
    var s = String(id || "Bar").replace(/[-_]+/g, " ").trim();
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// a new id: never one in use; `seed` (a number) only makes tests repeatable
function newId(taken, seed) {
    var n = seed !== undefined ? seed : Date.now();
    var id = "bar-" + Math.floor(n).toString(36);
    var k = 2;
    while (taken.indexOf(id) >= 0)
        id = "bar-" + Math.floor(n).toString(36) + "-" + k++;
    return id;
}

function ids(state) {
    return state.bars.map(function (b) { return b.id; });
}
function names(state) {
    return state.bars.map(function (b) { return b.name; });
}
function indexOf(state, id) {
    for (var i = 0; i < state.bars.length; i++)
        if (state.bars[i].id === id)
            return i;
    return -1;
}
function find(state, id) {
    var i = indexOf(state, id);
    return i < 0 ? null : state.bars[i];
}

function withBars(state, bars) {
    return { bars: bars, widgets: state.widgets };
}
function withBar(state, id, change) {
    var i = indexOf(state, id);
    if (i < 0)
        return state;
    var bars = state.bars.slice();
    bars[i] = change(Object.assign({}, bars[i]));
    return withBars(state, bars);
}

// ── components ──────────────────────────────────────────────────────────────

// every name a bar uses: its sections' entries and its groups' members (groups themselves are "group:<id>")
function entriesOf(bar) {
    var out = [];
    var w = bar.widgets || {};
    sections.forEach(function (s) {
        (w[s] || []).forEach(function (n) {
            if (String(n).indexOf("group:") !== 0)
                out.push(String(n));
        });
    });
    (bar.group || []).forEach(function (g) {
        (g.members || []).forEach(function (n) { out.push(String(n)); });
    });
    return out;
}

// how many bars name this component
function usage(state, name) {
    return state.bars.filter(function (b) { return entriesOf(b).indexOf(name) >= 0; }).length;
}

// a component's kind: its table's type, else its own name (a plain kind)
function typeOf(state, name) {
    var t = (state.widgets || {})[name];
    return t && t.type ? String(t.type) : String(name);
}

// a new instance name for a kind: "clock-2", "clock-3" … never one with a table or in use
function newInstanceName(state, type) {
    var taken = function (n) {
        return (state.widgets || {})[n] !== undefined || state.bars.some(function (b) { return entriesOf(b).indexOf(n) >= 0; });
    };
    var n = 2;
    while (taken(type + "-" + n))
        n++;
    return type + "-" + n;
}

// a component of its own, configured as `from` (another instance's name), else as the kind's own settings (the
// [widget.<kind>] table the user tuned: a new clock starts as their clock, not a blank one); returns { state, name }
function instantiate(state, type, from) {
    var name = newInstanceName(state, type);
    var widgets = Object.assign({}, state.widgets || {});
    var source = (state.widgets || {})[from !== undefined ? from : type];
    widgets[name] = Object.assign({}, clone(source) || {}, { type: type });
    return { state: { bars: state.bars, widgets: widgets }, name: name };
}

// a component added to the end of a section: always an instance of its own, so configuring it changes nothing
// else (adding a kind never silently shares another bar's settings)
function addComponent(state, id, section, type) {
    if (sections.indexOf(section) < 0 || !find(state, id))
        return state;
    var made = instantiate(state, type);
    return withBar(made.state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        w[section] = (w[section] || []).concat([made.name]);
        b.widgets = w;
        return b;
    });
}

// a component table nobody names any more goes with its last user, unless it is a kind's shared settings (a
// table under the kind's own name, which the user may have tuned and other layouts may name again)
function dropOrphans(state, candidates) {
    var widgets = Object.assign({}, state.widgets || {});
    var changed = false;
    candidates.forEach(function (n) {
        if (widgets[n] === undefined || usage(state, n) > 0)
            return;
        if (typeOf(state, n) === n)
            return;
        delete widgets[n];
        changed = true;
    });
    return changed ? { bars: state.bars, widgets: widgets } : state;
}

function removeComponent(state, id, section, index) {
    var bar = find(state, id);
    if (!bar)
        return state;
    var list = ((bar.widgets || {})[section] || []).slice();
    if (index < 0 || index >= list.length)
        return state;
    var gone = list.splice(index, 1)[0];
    var next = withBar(state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        w[section] = list;
        b.widgets = w;
        return b;
    });
    return dropOrphans(next, [String(gone)]);
}

// within its section by `by`; past either end it moves on into the neighbouring section (start ↔ center ↔ end),
// so any order across the bar is reachable one step at a time
function moveComponent(state, id, section, index, by) {
    var bar = find(state, id);
    if (!bar)
        return state;
    var w = Object.assign({}, bar.widgets || {});
    var list = (w[section] || []).slice();
    if (index < 0 || index >= list.length)
        return state;
    var to = index + by;
    var item = list[index];
    if (to >= 0 && to < list.length) {
        list.splice(index, 1);
        list.splice(to, 0, item);
        w[section] = list;
    } else {
        var s = sections.indexOf(section) + (by < 0 ? -1 : 1);
        if (s < 0 || s >= sections.length)
            return state;
        list.splice(index, 1);
        w[section] = list;
        var target = sections[s];
        w[target] = by < 0 ? (w[target] || []).concat([item]) : [item].concat(w[target] || []);
    }
    return withBar(state, id, function (b) {
        b.widgets = w;
        return b;
    });
}

// a component shared with other bars (an older layout's) becomes this bar's own: a copy of its settings
function separate(state, id, section, index) {
    var bar = find(state, id);
    if (!bar)
        return state;
    var list = ((bar.widgets || {})[section] || []).slice();
    var name = list[index];
    if (name === undefined || String(name).indexOf("group:") === 0)
        return state;
    var made = instantiate(state, typeOf(state, name), name);
    list[index] = made.name;
    return withBar(made.state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        w[section] = list;
        b.widgets = w;
        return b;
    });
}

// ── groups: components that sit together in one capsule ─────────────────────
// A group lives in its bar ([[bar.group]]: id, name, members, look) and sits on the bar as one entry,
// "group:<id>", in a section. Its members are ordinary component instances. Groups do not nest.

function groupsOf(bar) {
    return list(bar.group);
}
function groupById(bar, gid) {
    var g = groupsOf(bar).filter(function (x) { return x && x.id === gid; })[0];
    return g || null;
}
function newGroupId(bar) {
    var taken = groupsOf(bar).map(function (g) { return g.id; });
    var n = 1;
    while (taken.indexOf("g" + n) >= 0)
        n++;
    return "g" + n;
}
// where an entry is: { section, index } for one on the bar, { group, index } for a group's member
function entryAt(bar, at) {
    if (at.group !== undefined) {
        var g = groupById(bar, at.group);
        return g ? list(g.members)[at.index] : undefined;
    }
    return list((bar.widgets || {})[at.section])[at.index];
}

// the components at `indices` of a section become a group in place (at the first of them); returns { state, id }
function groupEntries(state, id, section, indices, name) {
    var bar = find(state, id);
    if (!bar || sections.indexOf(section) < 0)
        return { state: state, id: "" };
    var entries = list((bar.widgets || {})[section]);
    var picked = indices.filter(function (i, k) { return indices.indexOf(i) === k && i >= 0 && i < entries.length; }).sort(function (a, b) { return a - b; });
    var members = picked.map(function (i) { return entries[i]; }).filter(function (n) { return String(n).indexOf("group:") !== 0; });
    if (members.length === 0)
        return { state: state, id: "" };
    var gid = newGroupId(bar);
    var rest = [];
    entries.forEach(function (n, i) {
        if (i === picked[0])
            rest.push("group:" + gid);
        if (picked.indexOf(i) < 0 || String(n).indexOf("group:") === 0)
            rest.push(n);
    });
    var next = withBar(state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        w[section] = rest;
        b.widgets = w;
        b.group = groupsOf(b).concat([{ id: gid, name: name || "Group " + gid.slice(1), members: members }]);
        return b;
    });
    return { state: next, id: gid };
}

// a group's members back on the bar where the group was; the group goes
function ungroup(state, id, gid) {
    var bar = find(state, id);
    var g = bar ? groupById(bar, gid) : null;
    if (!g)
        return state;
    return withBar(state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        sections.forEach(function (s) {
            var out = [];
            list(w[s]).forEach(function (n) {
                if (n === "group:" + gid)
                    out = out.concat(list(g.members));
                else
                    out.push(n);
            });
            w[s] = out;
        });
        b.widgets = w;
        b.group = groupsOf(b).filter(function (x) { return x.id !== gid; });
        if (b.group.length === 0)
            delete b.group;
        return b;
    });
}

function setGroupKey(state, id, gid, key, value) {
    return withBar(state, id, function (b) {
        b.group = groupsOf(b).map(function (g) {
            if (g.id !== gid)
                return g;
            var c = Object.assign({}, g);
            if (value === undefined)
                delete c[key];
            else
                c[key] = value;
            return c;
        });
        return b;
    });
}
function renameGroup(state, id, gid, name) {
    var clean = String(name || "").trim();
    return clean === "" ? state : setGroupKey(state, id, gid, "name", clean);
}

// Moves one entry (a component, or a whole group) from `from` to `to`, each { section, index } or
// { group, index }: a drop of the editor. A group cannot go into a group. A group left with no members goes
// (its entry too). Indices of `to` are positions in the list as it is before the move.
function moveEntry(state, id, from, to) {
    var bar = find(state, id);
    if (!bar)
        return state;
    var item = entryAt(bar, from);
    if (item === undefined)
        return state;
    var isGroup = String(item).indexOf("group:") === 0;
    if (to.group !== undefined && (isGroup || !groupById(bar, to.group)))
        return state;
    if (to.group === undefined && sections.indexOf(to.section) < 0)
        return state;
    var sameList = from.group !== undefined ? to.group === from.group : (to.group === undefined && to.section === from.section);
    var target = to.index;
    if (sameList && target > from.index)
        target--;
    if (sameList && target === from.index)
        return state;
    return withBar(state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        var groups = groupsOf(b).map(function (g) { return Object.assign({}, g, { members: list(g.members) }); });
        var take = function (at) {
            if (at.group !== undefined) {
                var g = groups.filter(function (x) { return x.id === at.group; })[0];
                g.members.splice(at.index, 1);
            } else {
                var l = list(w[at.section]);
                l.splice(at.index, 1);
                w[at.section] = l;
            }
        };
        var put = function (at, index) {
            if (at.group !== undefined) {
                var g = groups.filter(function (x) { return x.id === at.group; })[0];
                g.members.splice(Math.max(0, Math.min(index, g.members.length)), 0, item);
            } else {
                var l = list(w[at.section]);
                l.splice(Math.max(0, Math.min(index, l.length)), 0, item);
                w[at.section] = l;
            }
        };
        take(from);
        put(to, target);
        // an emptied group goes
        groups = groups.filter(function (g) {
            if (g.members.length > 0)
                return true;
            sections.forEach(function (s) {
                w[s] = list(w[s]).filter(function (n) { return n !== "group:" + g.id; });
            });
            return false;
        });
        b.widgets = w;
        if (groups.length > 0)
            b.group = groups;
        else
            delete b.group;
        return b;
    });
}

// a component (not a group) at `at` removed; its table goes if nothing else names it
function removeEntry(state, id, at) {
    var bar = find(state, id);
    if (!bar)
        return state;
    var item = entryAt(bar, at);
    if (item === undefined)
        return state;
    if (String(item).indexOf("group:") === 0) {
        // a whole group: it and its members
        var g = groupById(bar, String(item).slice(6));
        var gone = withBar(state, id, function (b) {
            var w = Object.assign({}, b.widgets || {});
            w[at.section] = list(w[at.section]).filter(function (n, i) { return i !== at.index; });
            b.widgets = w;
            b.group = groupsOf(b).filter(function (x) { return !g || x.id !== g.id; });
            if (b.group.length === 0)
                delete b.group;
            return b;
        });
        return dropOrphans(gone, g ? list(g.members).map(String) : []);
    }
    if (at.group === undefined)
        return removeComponent(state, id, at.section, at.index);
    var next = withBar(state, id, function (b) {
        var w = Object.assign({}, b.widgets || {});
        var groups = groupsOf(b).map(function (g) {
            return g.id === at.group ? Object.assign({}, g, { members: list(g.members).filter(function (n, i) { return i !== at.index; }) }) : g;
        }).filter(function (g) {
            if (list(g.members).length > 0)
                return true;
            sections.forEach(function (s) {
                w[s] = list(w[s]).filter(function (n) { return n !== "group:" + g.id; });
            });
            return false;
        });
        b.widgets = w;
        if (groups.length > 0)
            b.group = groups;
        else
            delete b.group;
        return b;
    });
    return dropOrphans(next, [String(item)]);
}

// a new component of `type` at `to` ({ section, index } or { group, index }); returns { state, name }
function insertComponent(state, id, type, to) {
    var bar = find(state, id);
    if (!bar)
        return { state: state, name: "" };
    var made = instantiate(state, type);
    var next = withBar(made.state, id, function (b) {
        if (to.group !== undefined) {
            b.group = groupsOf(b).map(function (g) {
                if (g.id !== to.group)
                    return g;
                var m = list(g.members);
                m.splice(Math.max(0, Math.min(to.index, m.length)), 0, made.name);
                return Object.assign({}, g, { members: m });
            });
        } else {
            var w = Object.assign({}, b.widgets || {});
            var l = list(w[to.section]);
            l.splice(Math.max(0, Math.min(to.index === undefined ? l.length : to.index, l.length)), 0, made.name);
            w[to.section] = l;
            b.widgets = w;
        }
        return b;
    });
    return { state: next, name: made.name };
}

// ── bars ────────────────────────────────────────────────────────────────────

// what a new bar starts as: a small floating bar where asked, holding nothing (its components are the user's)
function blank(position) {
    var p = Object.assign({}, position || {});
    if (p.anchor !== undefined)
        p.anchor = anchorWord(p.anchor);
    return {
        enabled: true,
        edge: edges.indexOf(p.edge) >= 0 ? p.edge : "top",
        anchor: anchors.indexOf(p.anchor) >= 0 ? p.anchor : "center",
        margin: 6,
        offset: 0,
        thickness: 34,
        length: 0,
        reserve: false,
        layer: "top",
        visibility: "always",
        screens: ["*"],
        widgets: { start: [], center: [], end: [] }
    };
}

// a bar made from `spec` (a preset's, or blank): a new id, a name (asked for, else from where it sits), and
// components of its own — kind names in the spec become instances; settings given as { type, settings } too
function create(state, spec, name, seed) {
    var bar = Object.assign(blank(spec), clone(spec) || {});
    if (bar.anchor !== undefined)
        bar.anchor = anchorWord(bar.anchor);
    bar.id = newId(ids(state), seed);
    bar.name = name ? uniqueName(String(name), names(state)) : suggestName(bar, names(state));
    var next = state;
    var w = {};
    sections.forEach(function (s) {
        w[s] = ((spec && spec.widgets && spec.widgets[s]) || []).map(function (entry) {
            if (typeof entry === "string" && entry.indexOf("group:") === 0)
                return entry;
            var type = typeof entry === "string" ? entry : entry.type;
            var made = instantiate(next, type);
            next = made.state;
            if (typeof entry !== "string" && entry.settings) {
                var widgets = Object.assign({}, next.widgets);
                widgets[made.name] = Object.assign({}, entry.settings, { type: type });
                next = { bars: next.bars, widgets: widgets };
            }
            return made.name;
        });
    });
    bar.widgets = w;
    return { state: withBars(next, next.bars.concat([bar])), id: bar.id };
}

function rename(state, id, name) {
    var clean = String(name || "").trim();
    if (clean === "")
        return state;
    var others = state.bars.filter(function (b) { return b.id !== id; }).map(function (b) { return b.name; });
    return withBar(state, id, function (b) {
        b.name = uniqueName(clean, others);
        return b;
    });
}

// a copy beside it: everything the same, its components copied into instances of their own (so editing the copy
// leaves the original alone); groups keep their ids, their members are copied the same way
function duplicate(state, id, seed) {
    var bar = find(state, id);
    if (!bar)
        return { state: state, id: "" };
    var copy = clone(bar);
    copy.id = newId(ids(state), seed);
    copy.name = uniqueName(bar.name + " copy", names(state));
    var next = state;
    var renamed = {};
    var copyOf = function (n) {
        if (renamed[n] !== undefined)
            return renamed[n];
        var made = instantiate(next, typeOf(next, n), n);
        next = made.state;
        renamed[n] = made.name;
        return made.name;
    };
    var w = {};
    sections.forEach(function (s) {
        w[s] = ((copy.widgets || {})[s] || []).map(function (n) { return String(n).indexOf("group:") === 0 ? n : copyOf(String(n)); });
    });
    copy.widgets = w;
    if (copy.group)
        copy.group = copy.group.map(function (g) {
            return Object.assign({}, g, { members: (g.members || []).map(function (n) { return copyOf(String(n)); }) });
        });
    var i = indexOf(next, id);
    var bars = next.bars.slice();
    bars.splice(i + 1, 0, copy);
    return { state: withBars(next, bars), id: copy.id };
}

// removes the bar and the component instances only it named; returns { state, removed } where removed is what
// restore() needs to put it all back
function remove(state, id) {
    var i = indexOf(state, id);
    if (i < 0)
        return { state: state, removed: null };
    var bar = state.bars[i];
    var bars = state.bars.slice();
    bars.splice(i, 1);
    var next = withBars(state, bars);
    var used = entriesOf(bar);
    var pruned = dropOrphans(next, used);
    var tables = {};
    used.forEach(function (n) {
        if ((state.widgets || {})[n] !== undefined && (pruned.widgets || {})[n] === undefined)
            tables[n] = clone(state.widgets[n]);
    });
    return { state: pruned, removed: { index: i, bar: clone(bar), widgets: tables } };
}

function restore(state, removed) {
    if (!removed || !removed.bar || indexOf(state, removed.bar.id) >= 0)
        return state;
    var widgets = Object.assign({}, state.widgets || {});
    for (var n in removed.widgets)
        if (widgets[n] === undefined)
            widgets[n] = clone(removed.widgets[n]);
    var bars = state.bars.slice();
    bars.splice(Math.min(removed.index, bars.length), 0, clone(removed.bar));
    return { bars: bars, widgets: widgets };
}

function setEnabled(state, id, on) {
    return withBar(state, id, function (b) {
        b.enabled = !!on;
        return b;
    });
}

// one place up or down the list (the manager's order; bars drawn later sit above earlier ones on a layer)
function move(state, id, by) {
    var i = indexOf(state, id);
    var to = i + by;
    if (i < 0 || to < 0 || to >= state.bars.length)
        return state;
    var bars = state.bars.slice();
    var item = bars.splice(i, 1)[0];
    bars.splice(to, 0, item);
    return withBars(state, bars);
}

function setKey(state, id, key, value) {
    return withBar(state, id, function (b) {
        if (value === undefined)
            delete b[key];
        else
            b[key] = value;
        return b;
    });
}

// where it sits, in one step: an edge and a place along it (the offset goes back to 0, so the new spot is exact)
function place(state, id, edge, anchor) {
    anchor = anchorWord(anchor);
    if (edges.indexOf(edge) < 0 || anchors.indexOf(anchor) < 0)
        return state;
    var others = state.bars.filter(function (x) { return x.id !== id; }).map(function (x) { return x.name; });
    return withBar(state, id, function (b) {
        // a name the bar was given for where it sat ("Bottom left", "Bottom left 2") follows it; a name of the
        // user's own is never touched
        var auto = suggestName(b, others);
        var plain = String(b.name || "").replace(/ [0-9]+$/, "");
        var wasAuto = b.name === auto || plain === suggestName(b, []);
        b.edge = edge;
        b.anchor = anchor;
        b.offset = 0;
        if (wasAuto)
            b.name = suggestName(b, others);
        return b;
    });
}

// back to a plain bar: what it is (id, name, on/off, screens), where it is and what it holds stay; every look,
// size and behaviour key goes, so appearance.toml's defaults show through
var identityKeys = ["id", "name", "enabled", "screens", "edge", "anchor", "widgets", "group", "actions"];
function reset(state, id) {
    return withBar(state, id, function (b) {
        var out = {};
        identityKeys.forEach(function (k) {
            if (b[k] !== undefined)
                out[k] = b[k];
        });
        return out;
    });
}

// ── validation and migration ───────────────────────────────────────────────

// a bar as read, made safe to lay out: wrong kinds of values fall back (and are reported), unknown keys are kept
// untouched (a later version's keys survive a round trip through this one)
function sanitizeBar(raw, problems) {
    var b = Object.assign({}, raw);
    var label = "bar " + (b.name || b.id || "?");
    var oneOf = function (key, allowed, fallback) {
        if (b[key] !== undefined && allowed.indexOf(b[key]) < 0) {
            problems.push(label + ": " + key + " = " + JSON.stringify(b[key]) + " is not one of " + allowed.join(", "));
            b[key] = fallback;
        }
    };
    oneOf("edge", edges, "top");
    oneOf("anchor", anchors, "center");
    oneOf("visibility", visibilities, "always");
    oneOf("layer", layers, "top");
    ["thickness", "margin", "offset", "length", "padding"].forEach(function (key) {
        if (b[key] !== undefined && !(typeof b[key] === "number" && isFinite(b[key]) && b[key] >= 0)) {
            problems.push(label + ": " + key + " = " + JSON.stringify(b[key]) + " is not a number of at least 0");
            delete b[key];
        }
    });
    if (b.enabled !== undefined && typeof b.enabled !== "boolean") {
        problems.push(label + ": enabled is not true or false");
        b.enabled = b.enabled !== "false" && b.enabled !== 0;
    }
    var tableOk = b.widgets && typeof b.widgets === "object" && !isList(b.widgets);
    if (b.widgets !== undefined && !tableOk)
        problems.push(label + ": widgets is not a table of start / center / end lists");
    var w = tableOk ? Object.assign({}, b.widgets) : {};
    sections.forEach(function (s) {
        if (w[s] === undefined)
            return;
        if (!isList(w[s])) {
            problems.push(label + ": widgets." + s + " is not a list");
            w[s] = typeof w[s] === "string" ? [w[s]] : [];
        }
        w[s] = list(w[s]).filter(function (n) { return typeof n === "string" && n !== ""; });
    });
    b.widgets = w;
    if (b.group !== undefined)
        b.group = list(b.group).map(function (g) {
            return g && typeof g === "object" ? Object.assign({}, g, { members: list(g.members) }) : g;
        });
    if (b.screens !== undefined)
        b.screens = isList(b.screens) ? list(b.screens) : typeof b.screens === "string" ? [b.screens] : ["*"];
    return b;
}

// the bars as read → bars that can all be drawn: each a table with a unique, non-empty id and a name
function validate(state) {
    var problems = [];
    var seen = [];
    var bars = [];
    (list(state.bars)).forEach(function (raw, i) {
        if (!raw || typeof raw !== "object" || isList(raw)) {
            problems.push("bar " + (i + 1) + " is not a table; left out");
            return;
        }
        var b = sanitizeBar(raw, problems);
        var id = typeof b.id === "string" && b.id.trim() !== "" ? b.id : "";
        if (id === "" || seen.indexOf(id) >= 0) {
            var fresh = newId(seen.concat(ids(state)), i + 1);
            problems.push(id === "" ? "bar " + (i + 1) + " had no id; now " + fresh : "two bars had the id " + id + "; the second is now " + fresh);
            id = fresh;
        }
        b.id = id;
        seen.push(id);
        if (typeof b.name !== "string" || b.name.trim() === "")
            b.name = nameFromId(id);
        bars.push(b);
    });
    var widgets = state.widgets && typeof state.widgets === "object" && !isList(state.widgets) ? state.widgets : {};
    return { state: { bars: bars, widgets: widgets }, problems: problems };
}

// bars.toml as read (its whole table) → { file, changed, notes }. Version 1 (no `schema`): bars were known by
// their id alone. Version 2 gives each a name of its own, beside an id that never changes; nothing else moves,
// and every key is kept. Running it again changes nothing.
function migrate(file) {
    var from = typeof file.schema === "number" ? file.schema : 1;
    if (from >= schemaVersion)
        return { file: file, changed: false, notes: [] };
    var notes = [];
    var checked = validate({ bars: file.bar || [], widgets: file.widget || {} });
    var out = Object.assign({}, file);
    out.bar = checked.state.bars;
    out.schema = schemaVersion;
    notes = notes.concat(checked.problems);
    notes.push("version " + from + " → " + schemaVersion + ": " + out.bar.length + " bars named from their ids");
    return { file: out, changed: true, notes: notes };
}

// ── presets: starting points, made of ordinary bars ─────────────────────────

// each preset is bars to create; components by kind (each becomes an instance of its own)
var presets = [
    { key: "top", label: "Top bar", hint: "One bar across the top", bars: [
        { name: "Top", spec: { edge: "top", anchor: "fill", margin: 6, thickness: 34, reserve: true, widgets: { start: ["launcher", "workspaces"], center: ["clock"], end: ["tray", "network", "volume", "battery", "control-center"] } } }
    ] },
    { key: "three-top", label: "Three top bars", hint: "Left, centre and right, each on its own", bars: [
        { name: "Top left", spec: { edge: "top", anchor: "start", offset: 8, margin: 6, thickness: 34, reserve: true, widgets: { start: ["launcher", "workspaces"] } } },
        { name: "Top centre", spec: { edge: "top", anchor: "center", margin: 6, thickness: 34, reserve: true, widgets: { center: ["clock"] } } },
        { name: "Top right", spec: { edge: "top", anchor: "end", offset: 8, margin: 6, thickness: 34, reserve: true, widgets: { end: ["tray", "network", "volume", "battery", "control-center"] } } }
    ] },
    { key: "rail", label: "Side rail", hint: "A full-height bar on the left", bars: [
        { name: "Left rail", spec: { edge: "left", anchor: "fill", margin: 0, thickness: 40, reserve: true, concave_edge_corners: true, widgets: { start: ["launcher"], center: ["workspaces"], end: ["network", "volume", "battery", "session"] } } }
    ] },
    { key: "right-rail", label: "Right rail", hint: "System indicators down the right edge", bars: [
        { name: "Right rail", spec: { edge: "right", anchor: "center", margin: 6, thickness: 40, reserve: false, widgets: { center: ["network", "bluetooth", "volume", "battery"] } } }
    ] },
    { key: "dock", label: "Dock", hint: "Running apps at the bottom, out of the way", bars: [
        { name: "Dock", spec: { edge: "bottom", anchor: "center", margin: 8, thickness: 52, visibility: "smart", widgets: { center: ["taskbar"] } } }
    ] },
    { key: "clock", label: "Floating clock", hint: "Just the time, centred, above everything", bars: [
        { name: "Clock", spec: { edge: "top", anchor: "center", margin: 8, thickness: 34, layer: "overlay", visibility: "smart", widgets: { center: ["clock"] } } }
    ] }
];

function presetByKey(key, custom) {
    var all = presets.concat(custom || []);
    for (var i = 0; i < all.length; i++)
        if (all[i].key === key)
            return all[i];
    return null;
}

// adds the preset's bars; mode "replace" also turns every bar there was off (nothing is deleted, so turning them
// back on, or undo, restores the layout). Returns { state, ids }
function applyPreset(state, preset, mode, seed) {
    var next = state;
    if (mode === "replace")
        next = withBars(next, next.bars.map(function (b) { return Object.assign({}, b, { enabled: false }); }));
    var made = [];
    (preset.bars || []).forEach(function (pb, k) {
        var r = create(next, pb.spec, pb.name, seed !== undefined ? seed + k : undefined);
        next = r.state;
        made.push(r.id);
    });
    return { state: next, ids: made };
}

// the given bars as a preset of the user's own: each bar's spec (without its id), its components by kind with
// their settings, so applying it later makes fresh instances
function presetFrom(state, barIds, label, key) {
    var bars = barIds.map(function (id) { return find(state, id); }).filter(function (b) { return b; }).map(function (b) {
        var spec = clone(b);
        delete spec.id;
        var name = spec.name;
        delete spec.name;
        var w = {};
        sections.forEach(function (s) {
            w[s] = ((b.widgets || {})[s] || []).map(function (n) {
                if (String(n).indexOf("group:") === 0)
                    return n;
                var t = (state.widgets || {})[n];
                var settings = clone(t) || {};
                delete settings.type;
                return { type: typeOf(state, n), settings: settings };
            });
        });
        spec.widgets = w;
        return { name: name, spec: spec };
    });
    return { key: key, label: label, hint: bars.length + (bars.length === 1 ? " bar" : " bars"), custom: true, bars: bars };
}

// ── runtime layout ─────────────────────────────────────────────────────────

// does this bar draw on that output
function onScreen(bar, screenName) {
    var targets = bar.screens || ["*"];
    return targets.indexOf("*") >= 0 || targets.indexOf(screenName) >= 0;
}

// how much of each edge of an output the bars keep windows out of. Bars on one edge share one reservation, as
// deep as the deepest of them (not their sum: three bars side by side on the top edge keep one bar's room).
function reservations(bars, screenName) {
    var r = { top: 0, bottom: 0, left: 0, right: 0 };
    bars.forEach(function (b) {
        if (b.enabled === false || !onScreen(b, screenName) || b.reserve !== true || (b.visibility || "always") !== "always")
            return;
        var edge = edges.indexOf(b.edge) >= 0 ? b.edge : "top";
        var depth = (b.thickness || 34) + (b.margin || 0) + (b.margin_opposite || 0);
        r[edge] = Math.max(r[edge], depth);
    });
    return r;
}

// the stretch of its edge a bar is laid out along, in output coordinates [from, to]: the whole edge, or with
// reference = "workspace" what the bars on the two neighbouring edges leave of it
function alongRange(bar, length, reserved) {
    if ((bar.reference || "output") !== "workspace")
        return [0, length];
    var v = vertical(bar);
    var a = v ? reserved.top : reserved.left;
    var b = v ? reserved.bottom : reserved.right;
    return [a, Math.max(a, length - b)];
}

// ── corners ─────────────────────────────────────────────────────────────────

var cornerKeys = ["radius_top_left", "radius_top_right", "radius_bottom_right", "radius_bottom_left"];

// the corners of a bar's sheet that touch the screen edge (flowing into it squares them), or its inner ones
// (a full-length bar flush with the edge flows into the screen's ends instead): indices into [tl, tr, br, bl]
function edgeCornerIndices(edge) {
    return ({ top: [0, 1], bottom: [3, 2], left: [0, 3], right: [1, 2] })[edge] || [0, 1];
}
function innerCornerIndices(edge) {
    return ({ top: [3, 2], bottom: [0, 1], left: [1, 2], right: [0, 3] })[edge] || [3, 2];
}

// What each corner of a bar is drawn with, in px, [top left, top right, bottom right, bottom left]: the one place
// the sheet, its border, its blur region and its shadow take their shape from, so they always agree.
//   bar: the spec; size: { w, h } of the sheet; radiusScale: the theme's corner scale;
//   join: null or { start, end, progress } (a panel joined at the start / end side of the inner edge)
// A corner's own value wins over `radius` (left out or below 0, it follows `radius`; `radius` below 0 is half
// the thickness, a pill). Flowing into the screen edge squares the corners there. A joined panel squares the
// inner corners on its side as it grows (progress 0..1). Every radius is held to half the sheet's short side.
function cornerRadii(bar, size, radiusScale, join, touch) {
    var scale = radiusScale === undefined ? 1 : radiusScale;
    var thickness = typeof bar.thickness === "number" ? bar.thickness : 34;
    var base = typeof bar.radius === "number" && bar.radius >= 0 ? bar.radius * scale : thickness / 2;
    var c = cornerKeys.map(function (k) {
        var v = bar[k];
        return typeof v === "number" && v >= 0 ? v * scale : base;
    });
    // a concave corner is square on the sheet itself: its curve is the fillet drawn beside it
    cornerShapes(bar, touch).forEach(function (sh, i) {
        if (sh.shape !== "round")
            c[i] = 0;
    });
    if (join && join.progress > 0 && (join.start || join.end)) {
        var inner = innerCornerIndices(bar.edge);
        var horizontal = bar.edge === "top" || bar.edge === "bottom";
        var startCorner = horizontal ? (inner.indexOf(0) >= 0 ? 0 : 3) : (inner.indexOf(0) >= 0 ? 0 : 1);
        var endCorner = inner[0] === startCorner ? inner[1] : inner[0];
        if (join.start)
            c[startCorner] = c[startCorner] * (1 - join.progress);
        if (join.end)
            c[endCorner] = c[endCorner] * (1 - join.progress);
    }
    var most = Math.max(0, Math.min(size.w, size.h) / 2);
    return c.map(function (r) { return Math.max(0, Math.min(r, most)); });
}

// ── corner shapes: round, square, concave ─────────────────────────────────────
// Each corner has a shape (shape_top_left … : "concave", or left out for the usual rounded corner) and a size (its
// radius_* key, else the bar's radius). A concave corner curves inward: a fillet drawn just outside the bar joins
// it to a screen edge. So it can only be where the bar touches one —
//   · beyond the bar's end, along its own screen edge, when the bar sits flush against that edge (no margin);
//   · beside the bar's end, along the neighbouring screen edge, when that end reaches it (inner side always, the
//     outer side only with a gap to the bar's own edge — otherwise that corner is the screen's own corner).
// Where it cannot be, a concave corner is drawn square (and the editor says why). An older bar's
// concave_edge_corners (no shape_* keys) still means what it did: the edge corners, or a full-length bar's inner
// ones, concave at concave_radius.

var shapeKeys = ["shape_top_left", "shape_top_right", "shape_bottom_right", "shape_bottom_left"];
var cornerLabels = ["Top left", "Top right", "Bottom right", "Bottom left"];

// which end of the bar a corner is at: "start" (left / top) or "end"
function cornerEnd(edge, i) {
    var vert = edge === "left" || edge === "right";
    return vert ? (i === 0 || i === 1 ? "start" : "end") : (i === 0 || i === 3 ? "start" : "end");
}
// the corner's side: "outer" (on the bar's own screen edge) or "inner"
function cornerSide(edge, i) {
    return edgeCornerIndices(edge).indexOf(i) >= 0 ? "outer" : "inner";
}

// whether each end of the bar reaches the neighbouring screen edge: { start, end }. `range` is the stretch of the
// edge the bar is laid out along (alongRange) and `length` the edge's length; left out, the whole edge.
function endsTouch(bar, range, length) {
    var a = bar.anchor || "center";
    var flushOffset = (bar.offset || 0) === 0;
    var rs = range ? range[0] === 0 : true;
    var re = range && length !== undefined ? range[1] >= length : true;
    return {
        start: flushOffset && rs && (a === "fill" || a === "start"),
        end: flushOffset && re && (a === "fill" || a === "end")
    };
}

// why corner i cannot curve inward here ("" when it can)
function concaveBlocked(bar, i, touch) {
    var t = touch || endsTouch(bar);
    var end = cornerEnd(bar.edge, i), side = cornerSide(bar.edge, i);
    var margin = bar.margin || 0;
    if (t[end])
        return side === "inner" || margin > 0 ? "" : "This corner sits in the screen's own corner.";
    if (side === "outer")
        return margin === 0 ? "" : "It curves into the screen edge, so the bar needs no gap to that edge (Gap to edge 0).";
    return "Nothing to curve into: this end of the bar does not reach a screen edge.";
}

function legacyConcave(bar) {
    if (bar.concave_edge_corners !== true || (bar.margin || 0) !== 0)
        return [];
    return bar.anchor === "fill" && (bar.offset || 0) === 0 ? innerCornerIndices(bar.edge) : edgeCornerIndices(bar.edge);
}
function explicitShapes(bar) {
    return shapeKeys.some(function (k) { return bar[k] !== undefined; });
}

// every corner as it is drawn: [{ shape: "round" | "square" | "concave", size, wanted, blocked }] in tl tr br bl
// order; `wanted` is what the bar asks for, `blocked` why a concave one is drawn square instead
// sizes are as drawn: the radius keys follow the theme's corner scale (`scale`), as rounded corners always have;
// concave_radius and the half-thickness default do not (what the bars drew before per-corner shapes)
function cornerShapes(bar, touch, scale) {
    var k = scale === undefined ? 1 : scale;
    var t = touch || endsTouch(bar);
    var thickness = typeof bar.thickness === "number" ? bar.thickness : 34;
    var base = typeof bar.radius === "number" && bar.radius >= 0 ? bar.radius * k : thickness / 2;
    var concaveBase = typeof bar.concave_radius === "number" && bar.concave_radius >= 0 ? bar.concave_radius : base;
    var explicit = explicitShapes(bar);
    var legacy = explicit ? [] : legacyConcave(bar);
    return cornerKeys.map(function (key, i) {
        var own = typeof bar[key] === "number" && bar[key] >= 0 ? bar[key] * k : undefined;
        var concave = explicit ? bar[shapeKeys[i]] === "concave" : legacy.indexOf(i) >= 0;
        if (concave) {
            var size = explicit && own !== undefined ? own : concaveBase;
            var blocked = concaveBlocked(bar, i, t);
            return { shape: blocked === "" ? "concave" : "square", size: size, wanted: "concave", blocked: blocked };
        }
        var r = own !== undefined ? own : base;
        return { shape: r <= 0 ? "square" : "round", size: r, wanted: r <= 0 ? "square" : "round", blocked: "" };
    });
}

// the largest concave curve the bar draws (the room its window keeps for it)
function concaveExtent(bar, touch, radiusScale) {
    return cornerShapes(bar, touch, radiusScale).reduce(function (m, c) { return c.shape === "concave" ? Math.max(m, c.size) : m; }, 0);
}

// The fillets of the concave corners, in the bar window's coordinates: [{ x, y, r, solid, corner }] — a square
// r × r box beside the corner, `solid` the box corner that meets the bar ("tl" …), the rest curved away.
//   pill: { x, y, w, h } (the bar's sheet in its window); room: { start, end, inner, outer } (px the window has
//   beyond each end and on each side, so a curve is never cut off)
function fillets(bar, pill, room, touch, radiusScale) {
    var t = touch || endsTouch(bar);
    var edge = edges.indexOf(bar.edge) >= 0 ? bar.edge : "top";
    var vert = edge === "left" || edge === "right";
    var inward = ({ top: [0, 1], bottom: [0, -1], left: [1, 0], right: [-1, 0] })[edge];
    var along = vert ? [0, 1] : [1, 0];
    var pts = [[pill.x, pill.y], [pill.x + pill.w, pill.y], [pill.x + pill.w, pill.y + pill.h], [pill.x, pill.y + pill.h]];
    var out = [];
    cornerShapes(bar, t, radiusScale).forEach(function (c, i) {
        if (c.shape !== "concave")
            return;
        var end = cornerEnd(edge, i), side = cornerSide(edge, i);
        var endSign = end === "start" ? -1 : 1;
        var o, w, limit;
        if (t[end]) {
            // beside the end, along the neighbouring screen edge
            var sideSign = side === "inner" ? 1 : -1;
            o = [inward[0] * sideSign, inward[1] * sideSign];
            w = [-along[0] * endSign, -along[1] * endSign];
            limit = side === "inner" ? room.inner : room.outer;
        } else {
            // beyond the end, along the bar's own screen edge
            o = [along[0] * endSign, along[1] * endSign];
            w = inward;
            limit = end === "start" ? room.start : room.end;
        }
        var r = Math.max(0, Math.min(c.size, limit, Math.min(pill.w, pill.h)));
        if (r < 1)
            return;
        var p = pts[i];
        var xs = [p[0], p[0] + o[0] * r, p[0] + w[0] * r], ys = [p[1], p[1] + o[1] * r, p[1] + w[1] * r];
        var x0 = Math.min.apply(null, xs), y0 = Math.min.apply(null, ys);
        var solid = (Math.abs(p[1] - y0) < 0.01 ? "t" : "b") + (Math.abs(p[0] - x0) < 0.01 ? "l" : "r");
        out.push({ x: x0, y: y0, r: r, solid: solid, corner: i });
    });
    return out;
}

// one corner's shape: "round" | "square" | "concave". The first per-corner choice turns an older bar's
// concave_edge_corners into explicit shapes (drawn the same), so the four corners are then each the user's.
// `scale`: the theme's corner scale, so an older bar's concave sizes are written as the radii that draw them
function setCornerShape(state, id, i, shape, scale) {
    var k = scale === undefined || scale <= 0 ? 1 : scale;
    var bar = find(state, id);
    if (!bar || i < 0 || i > 3)
        return state;
    return withBar(state, id, function (b) {
        if (!explicitShapes(b)) {
            cornerShapes(b, undefined, k).forEach(function (c, n) {
                if (c.wanted === "concave") {
                    b[shapeKeys[n]] = "concave";
                    b[cornerKeys[n]] = Math.round(c.size / k * 100) / 100;
                }
            });
            delete b.concave_edge_corners;
        }
        var thickness = typeof b.thickness === "number" ? b.thickness : 34;
        if (shape === "concave") {
            b[shapeKeys[i]] = "concave";
        } else {
            delete b[shapeKeys[i]];
            if (shape === "square")
                b[cornerKeys[i]] = 0;
            else if (typeof b[cornerKeys[i]] === "number" && b[cornerKeys[i]] <= 0)
                b[cornerKeys[i]] = Math.round(thickness / 2);
        }
        // nothing concave left and no explicit shape: the keys go, the bar reads as it did
        if (!shapeKeys.some(function (k) { return b[k] !== undefined; }))
            shapeKeys.forEach(function (k) { delete b[k]; });
        return b;
    });
}
// one corner's size (px, before the theme's scale); undefined follows the bar's radius again
function setCornerSize(state, id, i, px, scale) {
    return withBar(state, id, function (b) {
        if (!explicitShapes(b) && legacyConcave(b).length > 0) {
            // keep an older bar's concave corners as they are drawn while one size changes
            var r = setCornerShape({ bars: [b], widgets: {} }, b.id, i, cornerShapes(b)[i].wanted, scale).bars[0];
            b = Object.assign({}, r);
        }
        if (px === undefined)
            delete b[cornerKeys[i]];
        else
            b[cornerKeys[i]] = Math.max(0, Math.round(px));
        return b;
    });
}

// which corners the user cannot round on this bar (it flows into the screen edge there), for Settings to say so
function squaredCorners(bar) {
    if (!(bar.concave_edge_corners === true && (bar.margin || 0) === 0))
        return [];
    return bar.anchor === "fill" && (bar.offset || 0) === 0 ? innerCornerIndices(bar.edge) : edgeCornerIndices(bar.edge);
}

// linked: one radius for every corner (no per-corner keys); independent: all four set
function cornersLinked(bar) {
    return cornerKeys.every(function (k) { return bar[k] === undefined || bar[k] < 0; });
}
// to independent: each corner starts as it is drawn now (its own value, else the radius); to linked: the radius
// becomes the top left corner's value (what the user sees first) and the per-corner keys go
function setCornersLinked(state, id, linked) {
    var bar = find(state, id);
    if (!bar)
        return state;
    return withBar(state, id, function (b) {
        var thickness = typeof b.thickness === "number" ? b.thickness : 34;
        var base = typeof b.radius === "number" && b.radius >= 0 ? b.radius : thickness / 2;
        var own = cornerKeys.map(function (k) { return typeof b[k] === "number" && b[k] >= 0 ? b[k] : base; });
        if (linked) {
            b.radius = own[0];
            cornerKeys.forEach(function (k) { delete b[k]; });
        } else {
            cornerKeys.forEach(function (k, i) { b[k] = own[i]; });
        }
        return b;
    });
}

// The room a bar's window keeps around its pill: as far as its shadow reaches, and never less than its concave
// fillets need. The two are separate on purpose: power saver pauses shadows (0 reach), and the fillets — part of
// the bar's shape, not an effect — once borrowed the shadow's room and vanished with it.
//   o: { shadows: bool (shadows on now), shadow: bool (the bar asks for one), shadowExtent, concave: bool,
//        concaveRadius }
function edgeRoom(o) {
    var shadowRoom = o.shadows && o.shadow ? Math.max(0, o.shadowExtent || 0) : 0;
    var shapeRoom = o.concave ? Math.max(0, Math.ceil(o.concaveRadius || 0)) : 0;
    return Math.max(shadowRoom, shapeRoom);
}
