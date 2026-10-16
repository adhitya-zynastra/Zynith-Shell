.pragma library
// The water-drop entrance: one silhouette as a function of progress t (0 → 1), from a pool on the bar edge to the
// panel's own shape. Phases (the same function run backwards is the exit, and an interrupted one reverses from
// wherever it is, because nothing depends on anything but t):
//   pool    0.00–0.20  a shallow bead gathers on the edge where the panel was asked for, held by two menisci
//   drop    0.20–0.50  it draws itself in to a round drop that hangs from a thinning neck
//   swell   0.50–1.00  the drop swells into the panel; the neck widens to the whole joint and is gone into it
// A floating panel (not joined to its bar) has no neck: the bead forms on its near side and swells.
//
// The path's subpaths overlap where the neck enters the head: draw it with ShapePath.WindingFill.
// Geometry is worked out in edge space — x along the edge the panel grows from, y away from it — and handed back
// in the card's own coordinates, so one rule serves all four edges.
//   g: { edge: top|bottom|left|right, attached, ox (where it was asked for, along the edge, card-local),
//        along (the card's length along the edge), depth (its size away from the edge),
//        corners: [tl, tr, br, bl] the card's final radii, radius (the card's radius) }
//   → { path (SVG, card-local), head: { x, y, w, h, r }, neck: { x, y, w, h } | null (card-local boxes, inside the
//       silhouette: for the blur and the input region), bounds: { x, y, w, h }, content (0..1: how far the page
//       inside has arrived), join (0..1: the fillets beside the panel), phase }

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}
function lerp(a, b, t) {
    return a + (b - a) * t;
}
function part(t, a, b) {
    return clamp((t - a) / (b - a), 0, 1);
}
function outCubic(t) {
    return 1 - Math.pow(1 - t, 3);
}
function inOutSine(t) {
    return -(Math.cos(Math.PI * t) - 1) / 2;
}
// the swell: eases in and settles (smootherstep), no overshoot and no jump at its start
function swell(t) {
    return t * t * t * (t * (6 * t - 15) + 10);
}
function smooth(t) {
    return t * t * (3 - 2 * t);
}

// edge-space radii [nearStart, nearEnd, farEnd, farStart] from the card's [tl, tr, br, bl]
function edgeCorners(edge, c) {
    if (edge === "bottom")
        return [c[3], c[2], c[1], c[0]];
    if (edge === "left")
        return [c[0], c[3], c[2], c[1]];
    if (edge === "right")
        return [c[1], c[2], c[3], c[0]];
    return [c[0], c[1], c[2], c[3]];
}

function shape(t, g) {
    t = clamp(t, 0, 1);
    var along = Math.max(1, g.along), depth = Math.max(1, g.depth);
    var attached = g.attached === true;
    var R0 = g.radius > 0 ? g.radius : 16;
    var fin = edgeCorners(g.edge, g.corners || [R0, R0, R0, R0]);

    var tA = outCubic(part(t, 0, 0.2));
    var tB = inOutSine(part(t, 0.2, 0.5));
    var tC = swell(part(t, 0.5, 1));

    // sizes, kept in proportion to the panel and never past it
    var poolW = clamp(along * 0.22, 44, 120);
    var poolH = clamp(depth * 0.05, 7, 12);
    var dropR = clamp(Math.min(along, depth) * 0.11, 14, 32);
    var neckL = attached ? clamp(depth * 0.16, 12, 40) : 0;
    poolW = Math.min(poolW, along);
    dropR = Math.min(dropR, along / 2, (depth - neckL) / 2);
    // where it forms: as close to where it was asked for as keeps the pool, the drop and their menisci inside
    var reach = Math.max(poolW / 2, dropR) + 10;
    var ox = reach * 2 < along ? clamp(g.ox, reach, along - reach) : along / 2;

    // the head: a rounded rect in edge space, x0..x1 along, y0..y1 away, radii [nS, nE, fE, fS]
    var hx0, hx1, hy0, hy1, rad;
    // the pool: flat on the edge (its near corners square on the bar), as wide as poolW, rising poolH
    var pw = poolW * tA, ph = poolH * tA;
    if (!attached)
        pw = ph * 2; // a floating bead starts round
    var pool = {
        x0: ox - pw / 2,
        x1: ox + pw / 2,
        y0: 0,
        y1: ph,
        r: [attached ? 0 : ph / 2, attached ? 0 : ph / 2, Math.min(ph, pw / 2), Math.min(ph, pw / 2)]
    };
    // the drop: round, hanging at the end of the neck
    var drop = {
        x0: ox - dropR,
        x1: ox + dropR,
        y0: neckL,
        y1: neckL + 2 * dropR,
        r: [dropR, dropR, dropR, dropR]
    };
    // the panel
    var card = {
        x0: 0,
        x1: along,
        y0: 0,
        y1: depth,
        r: fin
    };
    var a, b, k;
    if (t <= 0.5) {
        a = pool;
        b = drop;
        k = tB;
    } else {
        a = drop;
        b = card;
        k = tC;
    }
    hx0 = lerp(a.x0, b.x0, k);
    hx1 = lerp(a.x1, b.x1, k);
    hy0 = lerp(a.y0, b.y0, k);
    hy1 = lerp(a.y1, b.y1, k);
    rad = [0, 1, 2, 3].map(function (i) {
        return lerp(a.r[i], b.r[i], k);
    });
    var hw = Math.max(0, hx1 - hx0), hh = Math.max(0, hy1 - hy0);
    rad = rad.map(function (r) {
        return clamp(r, 0, Math.min(hw, hh) / 2);
    });

    // the neck (attached only): from the edge to the head's near side, its foot wider than its waist
    var neck = null;
    if (attached && hy0 > 0.5) {
        var foot = t <= 0.5 ? lerp(poolW, dropR * 1.5, tB) : lerp(dropR * 1.5, along, tC);
        var waist = t <= 0.5 ? lerp(poolW, dropR * 0.6, tB) : lerp(dropR * 0.6, along, tC);
        neck = { foot: Math.min(foot, along), waist: Math.min(waist, hw), y: hy0 };
    }
    // the menisci where the bead or neck meets the edge: grow with the pool, give way to the joint's own fillets
    var men = attached ? (t <= 0.5 ? lerp(0, 9, tA) : lerp(9, 0, part(t, 0.5, 0.85))) : 0;
    var footW = neck ? neck.foot : hw;
    var footX = neck ? clamp((hx0 + hx1) / 2 - footW / 2, 0, along - footW) : hx0;
    men = Math.min(men, footX, along - (footX + footW), (neck ? hy0 : hh));
    men = Math.max(0, men);

    // ── the path, card-local ──
    var map = mapper(g.edge, along, depth);
    function P(x, y) {
        var p = map(x, y);
        return p[0].toFixed(2) + " " + p[1].toFixed(2);
    }
    var d = "";
    // head: rounded rect, corners going round from the near-start one
    if (hw > 0.3 && hh > 0.3) {
        var nS = rad[0], nE = rad[1], fE = rad[2], fS = rad[3];
        // corners as circular arcs (cubic, k = 0.5523), so a drop is round rather than a squircle
        var K = 0.5523;
        d += "M " + P(hx0 + nS, hy0) + " L " + P(hx1 - nE, hy0)
            + " C " + P(hx1 - nE + nE * K, hy0) + " " + P(hx1, hy0 + nE - nE * K) + " " + P(hx1, hy0 + nE)
            + " L " + P(hx1, hy1 - fE)
            + " C " + P(hx1, hy1 - fE + fE * K) + " " + P(hx1 - fE + fE * K, hy1) + " " + P(hx1 - fE, hy1)
            + " L " + P(hx0 + fS, hy1)
            + " C " + P(hx0 + fS - fS * K, hy1) + " " + P(hx0, hy1 - fS + fS * K) + " " + P(hx0, hy1 - fS)
            + " L " + P(hx0, hy0 + nS)
            + " C " + P(hx0, hy0 + nS - nS * K) + " " + P(hx0 + nS - nS * K, hy0) + " " + P(hx0 + nS, hy0) + " Z ";
    }
    // neck: its foot on the edge, sides drawing in to the waist where it enters the head (2 px into it, no seam)
    if (neck) {
        var fx0 = footX, fx1 = footX + footW;
        var c = (hx0 + hx1) / 2;
        var wx0 = c - neck.waist / 2, wx1 = c + neck.waist / 2, wy = neck.y + Math.min(2, hh / 2);
        d += "M " + P(fx0, 0) + " L " + P(fx1, 0) + " C " + P(fx1, wy * 0.55) + " " + P(wx1, wy * 0.45) + " " + P(wx1, wy) + " L " + P(wx0, wy) + " C " + P(wx0, wy * 0.45) + " " + P(fx0, wy * 0.55) + " " + P(fx0, 0) + " Z ";
    }
    // menisci: the square beside the foot less a quarter circle (a quadratic, close enough at these sizes)
    if (men > 0.3) {
        var l = footX, r = footX + footW;
        d += "M " + P(l - men, 0) + " L " + P(l, 0) + " L " + P(l, men) + " Q " + P(l, 0) + " " + P(l - men, 0) + " Z ";
        d += "M " + P(r, 0) + " L " + P(r + men, 0) + " Q " + P(r, 0) + " " + P(r, men) + " Z ";
    }

    // boxes inside the silhouette, card-local: the head (with its smallest radius) and the neck at its waist
    var headBox = box(map, hx0, hy0, hx1, hy1);
    headBox.r = Math.min.apply(null, rad);
    var neckBox = neck ? box(map, (hx0 + hx1) / 2 - neck.waist / 2, 0, (hx0 + hx1) / 2 + neck.waist / 2, neck.y + 1) : null;
    var bx0 = Math.min(hx0, neck ? footX - men : hx0), bx1 = Math.max(hx1, neck ? footX + footW + men : hx1);
    var bounds = box(map, bx0, 0, bx1, Math.max(hy1, 0));

    return {
        path: d,
        head: headBox,
        neck: neckBox,
        bounds: bounds,
        content: smooth(part(t, 0.55, 0.92)),
        join: smooth(part(t, 0.82, 1)),
        phase: t < 0.2 ? "pool" : t < 0.5 ? "drop" : t < 1 ? "swell" : "rest"
    };
}

// edge space (x along, y away from the edge) → card-local (u right, v down)
function mapper(edge, along, depth) {
    if (edge === "bottom")
        return function (x, y) {
            return [x, depth - y];
        };
    if (edge === "left")
        return function (x, y) {
            return [y, x];
        };
    if (edge === "right")
        return function (x, y) {
            return [depth - y, x];
        };
    return function (x, y) {
        return [x, y];
    };
}
function box(map, x0, y0, x1, y1) {
    var a = map(x0, y0), b = map(x1, y1);
    var x = Math.min(a[0], b[0]), y = Math.min(a[1], b[1]);
    return { x: x, y: y, w: Math.abs(b[0] - a[0]), h: Math.abs(b[1] - a[1]) };
}
