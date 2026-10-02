.pragma library

// A small arithmetic evaluator for the launcher: numbers, + - * / % ^, parentheses, unary minus, the usual
// functions and pi/e. Parsed by hand, so typed text is never run as code. Returns a number, or null.

var FUNCS = {
    sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil, exp: Math.exp,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: Math.log10, log2: Math.log2
};
var CONSTS = { pi: Math.PI, e: Math.E, tau: 2 * Math.PI };

function tokenize(s) {
    var tokens = [], i = 0;
    while (i < s.length) {
        var c = s[i];
        if (c === " " || c === "\t") { i++; continue; }
        if ((c >= "0" && c <= "9") || c === ".") {
            var j = i;
            while (j < s.length && ((s[j] >= "0" && s[j] <= "9") || s[j] === "." || s[j] === "_")) j++;
            if (j < s.length && (s[j] === "e" || s[j] === "E") && /[0-9+-]/.test(s[j + 1] || "")) {
                j += 2;
                while (j < s.length && s[j] >= "0" && s[j] <= "9") j++;
            }
            var n = Number(s.slice(i, j).replace(/_/g, ""));
            if (isNaN(n)) return null;
            tokens.push({ t: "num", v: n });
            i = j;
            continue;
        }
        if (/[a-z]/i.test(c)) {
            var k = i;
            while (k < s.length && /[a-z0-9]/i.test(s[k])) k++;
            tokens.push({ t: "id", v: s.slice(i, k).toLowerCase() });
            i = k;
            continue;
        }
        if ("+-*/%^()×÷,".indexOf(c) >= 0) {
            tokens.push({ t: "op", v: c === "×" ? "*" : c === "÷" ? "/" : c });
            i++;
            continue;
        }
        return null;
    }
    return tokens;
}

function evaluate(text) {
    var tokens = tokenize(text);
    if (!tokens || tokens.length === 0) return null;
    var pos = 0;
    function peek() { return tokens[pos]; }
    function take(v) { if (tokens[pos] && tokens[pos].v === v) { pos++; return true; } return false; }

    function primary() {
        var tk = tokens[pos++];
        if (!tk) throw "end";
        if (tk.t === "num") return tk.v;
        if (tk.t === "op" && tk.v === "(") {
            var v = expr();
            if (!take(")")) throw "paren";
            return v;
        }
        if (tk.t === "id") {
            if (CONSTS.hasOwnProperty(tk.v)) return CONSTS[tk.v];
            if (FUNCS.hasOwnProperty(tk.v)) {
                if (!take("(")) throw "call";
                var a = expr();
                if (!take(")")) throw "paren";
                return FUNCS[tk.v](a);
            }
        }
        throw "token";
    }
    function unary() {
        if (take("-")) return -unary();
        if (take("+")) return unary();
        return power();
    }
    function power() {
        var base = primary();
        if (take("^")) return Math.pow(base, unary());
        return base;
    }
    function term() {
        var v = unary();
        for (;;) {
            if (take("*")) v *= unary();
            else if (take("/")) v /= unary();
            else if (take("%")) v %= unary();
            else return v;
        }
    }
    function expr() {
        var v = term();
        for (;;) {
            if (take("+")) v += term();
            else if (take("-")) v -= term();
            else return v;
        }
    }
    try {
        var result = expr();
        if (pos !== tokens.length || !isFinite(result)) return null;
        return result;
    } catch (e) {
        return null;
    }
}

// something worth calculating: an operator or a function, not just a bare number
function looksLikeMath(text) {
    return /[0-9)]\s*[-+*/%^×÷]\s*[-(0-9a-z.]/i.test(text) || /^(sqrt|sin|cos|tan|ln|log|abs|exp)\s*\(/i.test(text.trim());
}

function format(n) {
    if (Math.abs(n) >= 1e15 || (Math.abs(n) < 1e-6 && n !== 0)) return n.toExponential(6);
    return String(Math.round(n * 1e10) / 1e10);
}
