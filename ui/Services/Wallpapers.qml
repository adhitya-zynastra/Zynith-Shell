pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common

// What can be shown as a wallpaper and what is shown now. The native shell owns the one WallpaperState
// (desktop, overview, lock and palette all follow it) and the live library; this side lists and asks.
//
// Every view is derived from state held here: switching between Installed, Favourites, Recent and Collection
// filters what is already loaded, so it shows at once and never waits on a reload. The shell says when its
// state changed (Events.wallpaper); the library and images load when a browser first wants them.
Singleton {
    id: root

    readonly property string directory: Config.wallpaper.directory || (Paths.home + "/Pictures/wallpapers")

    // ── static ───────────────────────────────────────────────────────────────
    property var images: []          // [{ path, name, folder, mtime }]
    property var favorites: []       // absolute paths, the shell's static favourites
    property string current: ""      // the static wallpaper (the default output)
    property bool scanning: false
    readonly property var folders: {
        const seen = {};
        for (const i of images)
            if (i.folder !== "")
                seen[i.folder] = (seen[i.folder] ?? 0) + 1;
        return Object.keys(seen).sort((a, b) => a.localeCompare(b)).map(f => ({
                    name: f,
                    count: seen[f]
                }));
    }

    // ── live ─────────────────────────────────────────────────────────────────
    property string mode: "static"   // static | live
    property string liveCurrent: ""
    property string livePending: ""
    property var liveItems: ({})     // id -> { id, title, kind, preview, renderable, updated }
    property var liveFavorites: []
    property var liveCollection: []
    property var liveRecent: []
    property var carousel: ({
            enabled: false,
            interval: 300,
            order: "sequential"
        })
    property bool discovering: false
    property string problem: ""
    property string error: ""
    readonly property int unsupported: Object.values(liveItems).filter(i => !i.renderable).length

    // where the browser was left: source images | live, the view of each, the sort; touched once the source
    // was picked by hand (until then the browser opens on whatever is showing)
    property var browse: ({
            source: "images",
            imageView: "all",
            liveView: "installed",
            sort: "newest",
            output: "",
            touched: false
        })
    // counts answers from the shell, so a browser can act on the first one after opening
    property int synced: 0

    // ── views ────────────────────────────────────────────────────────────────
    // static: all | favorites | recent | folder:<name>   live: installed | favorites | recent | collection
    function imagesFor(view: string, query: string, sort: string): var {
        let list;
        if (view === "favorites") {
            const byPath = {};
            for (const i of images)
                byPath[i.path] = i;
            list = favorites.map(p => byPath[p] ?? describe(p, 0));
        } else if (view === "recent") {
            const byPath = {};
            for (const i of images)
                byPath[i.path] = i;
            list = state.recent.map(p => byPath[p]).filter(i => i !== undefined);
        } else if (view.startsWith("folder:")) {
            const folder = view.slice(7);
            list = images.filter(i => i.folder === folder);
        } else {
            list = images.slice();
        }
        const q = query.trim().toLowerCase();
        if (q !== "")
            list = list.filter(i => i.name.toLowerCase().includes(q) || i.folder.toLowerCase().includes(q));
        if (view !== "recent" && view !== "favorites")
            list = sorted(list, sort, i => i.name, i => i.mtime);
        return list;
    }

    function liveFor(view: string, query: string, sort: string): var {
        const pick = ids => ids.map(id => liveItems[id]).filter(i => i !== undefined && i.renderable);
        let list;
        switch (view) {
        case "favorites":
            list = pick(liveFavorites);
            break;
        case "recent":
            list = pick(liveRecent);
            break;
        case "collection":
            list = pick(liveCollection);
            break;
        default:
            list = Object.values(liveItems).filter(i => i.renderable);
            list = sorted(list, sort, i => i.title, i => i.updated);
        }
        const q = query.trim().toLowerCase();
        if (q !== "")
            list = list.filter(i => i.title.toLowerCase().includes(q) || i.id.includes(q));
        return list;
    }

    function sorted(list: var, sort: string, name: var, time: var): var {
        switch (sort) {
        case "newest":
            return list.sort((a, b) => time(b) - time(a));
        case "oldest":
            return list.sort((a, b) => time(a) - time(b));
        case "za":
            return list.sort((a, b) => name(b).localeCompare(name(a)));
        default:
            return list.sort((a, b) => name(a).localeCompare(name(b)));
        }
    }

    function describe(path: string, mtime: real): var {
        const rel = path.startsWith(directory + "/") ? path.slice(directory.length + 1) : path.split("/").pop();
        const parts = rel.split("/");
        return {
            path: path,
            name: parts[parts.length - 1].replace(/\.[^.]+$/, ""),
            folder: parts.length > 1 ? parts[0] : "",
            mtime: mtime
        };
    }

    // ── loading ──────────────────────────────────────────────────────────────
    // a browser asks while it is open; the shell's change events keep it current meanwhile
    property int consumers: 0
    function retain(): void {
        consumers++;
        if (consumers === 1) {
            // the list stays from the first scan (the refresh button rescans), so a browser opens on it at once
            if (images.length === 0 && !scanning)
                rescan();
            sync();
        }
    }
    function release(): void {
        consumers = Math.max(0, consumers - 1);
    }
    // a one-off reader (the launcher): loads once, then keeps what it has
    function ensure(): void {
        if (images.length === 0 && !scanning)
            rescan();
        if (Object.keys(liveItems).length === 0)
            sync();
    }

    function rescan(): void {
        scanning = true;
        files.running = false;
        files.running = true;
    }

    // one answer for everything the shell holds; several change events in a burst become one sync
    function sync(): void {
        syncCoalesce.restart();
    }
    Timer {
        id: syncCoalesce
        interval: 16
        onTriggered: {
            CoreClient.call("wallpaper-get", text => root.current = text.trim());
            CoreClient.call("wallpaper-favorites", text => {
                try {
                    root.favorites = JSON.parse(text);
                } catch (e) {}
            });
            CoreClient.call("wallpaper-live-library", text => {
                let d;
                try {
                    d = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const items = {};
                for (const i of d.items)
                    items[i.id] = i;
                root.liveItems = items;
                root.mode = d.mode;
                root.liveCurrent = d.current;
                root.livePending = d.pending;
                root.liveFavorites = d.favorites;
                root.liveCollection = d.collection;
                root.liveRecent = d.recent;
                root.carousel = d.carousel;
                root.discovering = d.discovering;
                root.problem = d.problem;
                root.error = d.error;
                root.synced++;
            });
        }
    }

    Connections {
        target: Events
        function onWallpaper(): void {
            if (root.consumers > 0)
                root.sync();
        }
    }

    // ── actions (state changes here first, so the browser answers at once; the shell's event confirms) ──
    function applyImage(path: string): void {
        current = path;
        mode = "static";
        rememberRecent(path);
        CoreClient.call("wallpaper-set " + path, reply => {
            if (reply.startsWith("ok"))
                CoreClient.call("wallpaper-live-stop");
            else
                console.warn("zynith: wallpaper not set:", reply.trim());
        });
    }
    function applyImageOn(output: string, path: string): void {
        rememberRecent(path);
        CoreClient.call("wallpaper-set " + output + " " + path);
    }
    function applyLive(id: string): void {
        livePending = id;
        mode = "live";
        CoreClient.call("wallpaper-live-set " + id, reply => {
            if (!reply.startsWith("ok")) {
                root.error = reply.replace(/^error: /, "").trim();
                root.sync();
            }
        });
    }
    function stopLive(): void {
        mode = "static";
        CoreClient.call("wallpaper-live-stop");
    }
    function toggleFavorite(path: string): void {
        const on = !favorites.includes(path);
        favorites = on ? [path].concat(favorites) : favorites.filter(p => p !== path);
        CoreClient.call("wallpaper-favorite " + (on ? "add " : "remove ") + path);
    }
    function toggleLiveFavorite(id: string): void {
        const on = !liveFavorites.includes(id);
        liveFavorites = on ? [id].concat(liveFavorites) : liveFavorites.filter(i => i !== id);
        CoreClient.call("wallpaper-live-favorite " + (on ? "add " : "remove ") + id);
    }
    function toggleCollection(id: string): void {
        const on = !liveCollection.includes(id);
        liveCollection = on ? liveCollection.concat([id]) : liveCollection.filter(i => i !== id);
        CoreClient.call("wallpaper-live-collection " + (on ? "add " : "remove ") + id);
    }
    function setCarousel(enabled: bool, interval: int, order: string): void {
        carousel = {
            enabled: enabled,
            interval: interval,
            order: order
        };
        CoreClient.call("wallpaper-live-carousel " + (enabled ? "on " : "off ") + interval + " " + order, reply => {
            if (!reply.startsWith("ok")) {
                root.error = reply.replace(/^error: /, "").trim();
                root.sync();
            }
        });
    }
    function nextLive(): void {
        CoreClient.call("wallpaper-live-next");
    }
    function random(): void {
        if (images.length > 0)
            applyImage(images[Math.floor(Math.random() * images.length)].path);
    }

    // images picked here recently; the shell keeps no such list for static wallpapers
    function rememberRecent(path: string): void {
        state.recent = [path].concat(state.recent.filter(p => p !== path)).slice(0, 24);
        stateFile.writeAdapter();
    }
    FileView {
        id: stateFile
        path: Paths.state + "/wallpapers.json"
        printErrors: false
        JsonAdapter {
            id: state
            property var recent: []
        }
    }

    Process {
        id: files
        command: ["find", "-L", root.directory, "-maxdepth", "4", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")", "-printf", "%T@\t%p\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.images = text.split("\n").filter(l => l !== "").map(l => {
                    const tab = l.indexOf("\t");
                    return root.describe(l.slice(tab + 1), parseFloat(l.slice(0, tab)) * 1000);
                });
                root.scanning = false;
            }
        }
    }
}
