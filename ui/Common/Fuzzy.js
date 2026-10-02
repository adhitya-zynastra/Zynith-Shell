.pragma library

// How well `q` (lower case) matches `text`; 0 is no match. A whole-name prefix beats the start of a later
// word, then initials ("vsc"), then a substring, then letters in order. `loose` allows the last kind.
function score(q, text, loose) {
    if (!text || !q)
        return 0;
    const t = text.toLowerCase();
    if (t === q)
        return 1000;
    if (t.startsWith(q))
        return 800 - Math.min(t.length - q.length, 100);
    const words = t.split(/[\s\-_.]+/).filter(w => w.length > 0);
    for (let i = 1; i < words.length; i++) {
        if (words[i].startsWith(q))
            return 600 - i * 10;
    }
    if (q.length >= 2 && words.length >= q.length && words.map(w => w[0]).join("").startsWith(q))
        return 550;
    const at = t.indexOf(q);
    if (at >= 0)
        return 400 - Math.min(at, 100);
    if (!loose)
        return 0;
    let from = 0, last = -1, gaps = 0;
    for (const c of q) {
        const k = t.indexOf(c, from);
        if (k < 0)
            return 0;
        if (last >= 0)
            gaps += k - last - 1;
        last = k;
        from = k + 1;
    }
    return Math.max(1, 200 - gaps * 8);
}
