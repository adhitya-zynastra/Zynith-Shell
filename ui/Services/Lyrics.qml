pragma Singleton

import QtQuick
import Quickshell

// The words of the playing song, from lrclib.net (the provider Clavis and Ryoku use), synced to the line
// when the source has timings. Asked only while a view that shows lyrics is on screen (retain/release), once
// per track, kept for the session. [media] lyrics = false (or provider = "none") never asks anyone; the
// request carries the artist, title, album and length — nothing else.
Singleton {
    id: root

    readonly property var cfg: Config.media ?? ({})
    readonly property bool enabled: (cfg.lyrics ?? true) && (cfg.lyrics_provider ?? "lrclib") === "lrclib"
    property int consumers: 0
    function retain(): void {
        consumers++;
    }
    function release(): void {
        consumers = Math.max(0, consumers - 1);
    }

    // [{ t: seconds, text }] when synced; plain lines with t = -1 otherwise
    property var lines: []
    property bool synced: false
    // idle | searching | found | none | error | off
    property string status: "idle"
    readonly property bool searching: status === "searching"

    readonly property string key: [Media.artist, Media.title, Media.album, Math.round(Media.length)].join("␟")
    property string loadedKey: ""
    property var cache: ({})

    readonly property bool wanted: consumers > 0 && Media.present
    onWantedChanged: fetch()
    onKeyChanged: fetch()
    onEnabledChanged: fetch()

    function show(entry: var): void {
        lines = entry?.lines ?? [];
        synced = entry?.synced ?? false;
        status = entry ? (lines.length > 0 ? "found" : "none") : "idle";
    }
    function fetch(): void {
        if (!enabled) {
            show(null);
            status = "off";
            return;
        }
        if (!wanted || key === loadedKey)
            return;
        loadedKey = key;
        if (cache[key] !== undefined)
            return show(cache[key]);
        show(null);
        status = "searching";
        const q = "artist_name=" + encodeURIComponent(Media.artist) + "&track_name=" + encodeURIComponent(Media.title) + (Media.album !== "" ? "&album_name=" + encodeURIComponent(Media.album) : "") + (Media.length > 0 ? "&duration=" + Math.round(Media.length) : "");
        const asked = key;
        request("https://lrclib.net/api/get?" + q, (code, body) => {
            if (asked !== root.key)
                return;
            if (code === 200)
                return root.take(asked, body);
            // no exact match (the album or length differ): the best search hit
            root.request("https://lrclib.net/api/search?track_name=" + encodeURIComponent(Media.title) + "&artist_name=" + encodeURIComponent(Media.artist), (c2, b2) => {
                if (asked !== root.key)
                    return;
                if (c2 !== 200)
                    return root.fail(asked, c2);
                try {
                    const hits = JSON.parse(b2);
                    const hit = hits.find(h => h.syncedLyrics) ?? hits.find(h => h.plainLyrics) ?? null;
                    root.take(asked, hit ? JSON.stringify(hit) : "{}");
                } catch (e) {
                    root.fail(asked, -1);
                }
            });
        });
    }
    function request(url: string, done: var): void {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState === XMLHttpRequest.DONE)
                done(x.status, x.responseText);
        };
        x.open("GET", url);
        x.send();
    }
    function fail(k: string, code: int): void {
        cache[k] = { lines: [], synced: false };
        status = code === 404 || code === 200 ? "none" : "error";
        lines = [];
    }
    function take(k: string, body: string): void {
        let d = {};
        try {
            d = JSON.parse(body);
        } catch (e) {}
        const entry = { lines: [], synced: false };
        if (d.syncedLyrics) {
            for (const raw of d.syncedLyrics.split("\n")) {
                const m = raw.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/);
                if (m)
                    entry.lines.push({ t: Number(m[1]) * 60 + Number(m[2]), text: m[3].trim() });
            }
            entry.synced = entry.lines.length > 0;
        }
        if (!entry.synced && d.plainLyrics)
            entry.lines = d.plainLyrics.split("\n").map(l => ({ t: -1, text: l.trim() }));
        cache[k] = entry;
        show(entry);
    }

    // the line being sung at `position` seconds (-1 before the first)
    function lineAt(position: real): int {
        if (!synced)
            return -1;
        let lo = 0, hi = lines.length - 1, found = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lines[mid].t <= position + 0.15) {
                found = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return found;
    }
}
