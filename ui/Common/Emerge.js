.pragma library

// How a panel emerges from the component that opened it, and goes back into it: the island's motion. The panel
// starts as a capsule the size of the icon, sitting on the bar's inner edge where the icon is, and grows into its
// card — along the bar a beat before it deepens, its corners relaxing from a capsule's to the surface's — on a
// spring that settles without bouncing. Closing runs the same path back. Every value is a function of the
// progress alone, so an interrupted open or close reverses from wherever it is. Pure: PanelSurface draws it,
// tools/tests/tst_emerge.qml tests it.

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

// a critically damped spring from 0 to 1 (no overshoot), normalised to end exactly at 1
function spring(t) {
    var x = clamp(t, 0, 1), k = 7.5;
    var raw = 1 - (1 + k * x) * Math.exp(-k * x);
    var end = 1 - (1 + k) * Math.exp(-k);
    return raw / end;
}

// the capsule a panel starts as: the icon's span along the bar, a little depth, on the card's bar-side edge
//   edge: the bar's edge ("top" | "bottom" | "left" | "right"); origin: the icon's centre { x, y } on screen;
//   span: the icon's length along the bar; card: where the panel ends up { x, y, w, h }
function seed(edge, origin, span, card) {
    var s = Math.max(24, span || 32);
    var d = 26;   // its depth: a capsule, not a line
    var horizontal = edge === "top" || edge === "bottom";
    if (horizontal) {
        var x = clamp(origin.x - s / 2, card.x, card.x + card.w - s);
        return { x: x, y: edge === "top" ? card.y : card.y + card.h - d, w: s, h: d };
    }
    var y = clamp(origin.y - s / 2, card.y, card.y + card.h - s);
    return { x: edge === "left" ? card.x : card.x + card.w - d, y: y, w: d, h: s };
}

// the shape at progress p (0 = the capsule, 1 = the card): { x, y, w, h, radius, content }
//   radius: the card's corner radius at rest; content: how far the page has faded in (it waits for the shape)
function frame(p, from, to, radius, edge) {
    var horizontal = edge === "top" || edge === "bottom";
    // along the bar first, then the depth, slightly behind
    var ga = spring(p / 0.82);
    var gd = spring((p - 0.06) / 0.94);
    var gx = horizontal ? ga : gd, gy = horizontal ? gd : ga;
    var lerp = function (a, b, g) { return a + (b - a) * g; };
    var x = lerp(from.x, to.x, gx), w = lerp(from.w, to.w, gx);
    var y = lerp(from.y, to.y, gy), h = lerp(from.h, to.h, gy);
    var capsule = Math.min(from.w, from.h) / 2;
    var r = lerp(capsule, radius, spring(p));
    return {
        x: x, y: y, w: w, h: h,
        radius: Math.min(r, Math.min(w, h) / 2),
        content: clamp((p - 0.42) / 0.5, 0, 1)
    };
}
