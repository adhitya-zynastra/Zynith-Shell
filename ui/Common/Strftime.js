.pragma library

// "{:%H}" / "%H:%M" (the native widgets' strftime) → a Qt date format, so layouts carry over unchanged.
var MAP = { H: "HH", I: "hh", M: "mm", S: "ss", p: "AP", d: "dd", e: "d", m: "MM", y: "yy", Y: "yyyy",
            a: "ddd", A: "dddd", b: "MMM", B: "MMMM", j: "", "%": "%" };

function toQt(fmt) {
    var f = String(fmt || "%H:%M").replace(/^\{:/, "").replace(/\}$/, "");
    var out = "", literal = "";
    for (var i = 0; i < f.length; i++) {
        if (f[i] === "%" && i + 1 < f.length) {
            if (literal) { out += "'" + literal.replace(/'/g, "''") + "'"; literal = ""; }
            out += MAP[f[i + 1]] !== undefined ? MAP[f[i + 1]] : "";
            i++;
        } else {
            literal += f[i];
        }
    }
    if (literal) out += "'" + literal.replace(/'/g, "''") + "'";
    return out;
}
