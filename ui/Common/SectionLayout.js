.pragma library

// The Control Panel's arrangement as data: columns, each a list of section ids top to bottom. Pure functions
// (no services), shared by Services/ControlSections.qml and the Settings editor, tested by
// tools/tests/tst_section_layout.qml. Every edit returns a new arrangement; none changes its input.

var maxColumns = 4;

// older names for the same sections
function canonical(id) {
    var s = String(id);
    return s === "connectivity" || s === "toggles" ? "shortcuts" : s === "screen-time" ? "screen_time" : s === "mic" ? "microphone" : s;
}

// as written → known ids, each once, no empty columns, at most maxColumns (the extra ones join the last)
// (a lone string is a one-section column; an empty list stays empty: everything off is a choice)
function validate(given, known, fallback) {
    if (given === undefined || given === null)
        return fallback;
    var seen = [];
    var out = [];
    var cols = Array.from(given);
    for (var c = 0; c < cols.length; c++) {
        var raw = typeof cols[c] === "string" ? [cols[c]] : Array.from(cols[c] || []);
        var list = [];
        for (var i = 0; i < raw.length; i++) {
            var id = canonical(raw[i]);
            if (known.indexOf(id) >= 0 && seen.indexOf(id) < 0) {
                seen.push(id);
                list.push(id);
            }
        }
        if (list.length > 0)
            out.push(list);
    }
    if (out.length > maxColumns) {
        var tail = out.splice(maxColumns - 1);
        out.push(tail.reduce(function (a, b) { return a.concat(b); }, []));
    }
    return out;
}

// what a [control_panel] table asks for: its columns; before those were ever written, a column layout's
// retired `modules` list; else the fallback
function arrangement(cfg, known, fallback) {
    if (cfg && cfg.columns !== undefined)
        return validate(cfg.columns, known, fallback);
    if (cfg && (cfg.layout || "dashboard") === "column" && cfg.modules !== undefined)
        return validate([cfg.modules], known, fallback);
    return fallback;
}

function flat(columns) {
    return columns.reduce(function (all, c) { return all.concat(c); }, []);
}

// a weight per column: missing or not positive = 1, kept within 0.2 – 5
function weights(columns, given) {
    var list = Array.from(given || []);
    return columns.map(function (c, i) {
        var w = Number(list[i]);
        return w > 0 ? Math.max(0.2, Math.min(5, w)) : 1;
    });
}

function copy(columns) {
    return columns.map(function (c) { return c.slice(); });
}
function where(columns, id) {
    for (var c = 0; c < columns.length; c++) {
        var r = columns[c].indexOf(id);
        if (r >= 0)
            return { c: c, r: r };
    }
    return null;
}

// up or down within its column, and on into the neighbouring column at either end. In reading order
// (`flat`: the column layout, one list) it changes places with the section before or after it instead, so the
// list always moves by one and every column keeps its size.
function step(columns, id, by, flatOrder) {
    var at = where(columns, id);
    if (!at)
        return columns;
    var cols = copy(columns);
    if (flatOrder) {
        var order = flat(columns);
        var k = order.indexOf(id) + by;
        if (k < 0 || k >= order.length)
            return columns;
        var other = where(columns, order[k]);
        cols[at.c][at.r] = order[k];
        cols[other.c][other.r] = id;
        return cols;
    }
    var col = cols[at.c];
    var j = at.r + by;
    if (j >= 0 && j < col.length) {
        col.splice(at.r, 1);
        col.splice(j, 0, id);
    } else if (by < 0 && at.c > 0) {
        col.splice(at.r, 1);
        cols[at.c - 1].push(id);
    } else if (by > 0 && at.c < cols.length - 1) {
        col.splice(at.r, 1);
        cols[at.c + 1].unshift(id);
    } else {
        return columns;
    }
    return cols.filter(function (c) { return c.length > 0; });
}

// { columns, weights }: the edit, and the weights following their columns (a column that empties takes its
// weight with it; a new one gets 1)
function reweigh(before, w, cols) {
    var kept = [];
    var kw = [];
    for (var i = 0; i < cols.length; i++) {
        if (cols[i].length === 0)
            continue;
        kept.push(cols[i]);
        kw.push(i < w.length ? w[i] : 1);
    }
    return { columns: kept, weights: kw };
}

// to the column beside it (a new one past the last, up to maxColumns)
function shift(columns, w, id, by) {
    var at = where(columns, id);
    if (!at)
        return { columns: columns, weights: w };
    var target = at.c + by;
    if (target < 0 || (target >= columns.length && columns.length >= maxColumns))
        return { columns: columns, weights: w };
    var cols = copy(columns);
    cols[at.c].splice(at.r, 1);
    if (target >= cols.length)
        cols.push([]);
    cols[target].push(id);
    return reweigh(columns, w, cols);
}

function hide(columns, w, id) {
    var cols = copy(columns).map(function (c) { return c.filter(function (m) { return m !== id; }); });
    return reweigh(columns, w, cols);
}

// onto the shortest column (a column of its own when there is none)
function show(columns, id) {
    if (where(columns, id))
        return columns;
    var cols = copy(columns);
    if (cols.length === 0)
        cols.push([]);
    var best = 0;
    for (var c = 1; c < cols.length; c++)
        if (cols[c].length < cols[best].length)
            best = c;
    cols[best].push(id);
    return cols;
}
