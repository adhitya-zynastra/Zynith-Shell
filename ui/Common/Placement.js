.pragma library

// Where a desktop widget sits on a screen of (W, H), from its stored centre and box in its reference
// resolution. "free" scales position and size with the screen (the native default); an anchored widget keeps
// its distance to that edge or corner and keeps its size (scaled evenly, never stretched).
// Returns { x, y, width, height, s }: top-left, size in screen pixels, and the even scale.
function place(w, g, W, H) {
    var ref = w.reference || [W, H];
    var rw = ref[0] || W, rh = ref[1] || H;
    var sx = W / rw, sy = H / rh, s = Math.min(sx, sy);
    var anchor = (w.settings && w.settings.anchor) || "free";
    var width, height, cx, cy;
    if (anchor === "free") {
        width = g.width * sx;
        height = g.height * sy;
        cx = g.cx * sx;
        cy = g.cy * sy;
    } else {
        width = g.width * s;
        height = g.height * s;
        var left = anchor.indexOf("left") >= 0, right = anchor.indexOf("right") >= 0;
        var top = anchor.indexOf("top") >= 0, bottom = anchor.indexOf("bottom") >= 0;
        cx = left ? g.cx * s : right ? W - (rw - g.cx) * s : W / 2 + (g.cx - rw / 2) * s;
        cy = top ? g.cy * s : bottom ? H - (rh - g.cy) * s : H / 2 + (g.cy - rh / 2) * s;
    }
    return { x: cx - width / 2, y: cy - height / 2, width: width, height: height, s: s };
}
