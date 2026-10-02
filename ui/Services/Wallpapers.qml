pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// What can be shown as a wallpaper and what is shown now. The native shell owns the one WallpaperState
// (desktop, overview, lock and palette all follow it); this side lists and asks. Lists load when the panel
// opens, never in the background.
Singleton {
    id: root

    readonly property string directory: Config.wallpaper.directory || (Paths.home + "/Pictures/wallpapers")
    property var images: []        // absolute paths
    property var live: []          // [{ id, title, kind, preview, favorite, current }]
    property string current: ""    // the static wallpaper
    property string mode: "static" // static | live
    property string liveCurrent: ""
    property bool loading: false

    function refresh(): void {
        loading = true;
        if (!files.running)
            files.running = true;
        if (!status.running)
            status.running = true;
        if (!liveList.running)
            liveList.running = true;
        if (!currentPath.running)
            currentPath.running = true;
    }

    // a static choice also ends a live wallpaper, so the desktop shows what was picked
    function applyImage(path: string): void {
        current = path;
        mode = "static";
        Quickshell.execDetached(["sh", "-c", "\"$0\" msg wallpaper-set \"$1\" && \"$0\" msg wallpaper-live-stop >/dev/null", Paths.core, path]);
    }
    function applyLive(id: string): void {
        liveCurrent = id;
        mode = "live";
        Quickshell.execDetached([Paths.core, "msg", "wallpaper-live-set", id]);
    }

    Process {
        id: files
        command: ["find", "-L", root.directory, "-maxdepth", "4", "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.images = text.split("\n").filter(l => l !== "").sort((a, b) => a.localeCompare(b));
                root.loading = false;
            }
        }
    }
    Process {
        id: currentPath
        command: [Paths.core, "msg", "wallpaper-get"]
        stdout: StdioCollector {
            onStreamFinished: root.current = text.trim()
        }
    }
    Process {
        id: status
        command: [Paths.core, "msg", "wallpaper-live-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.mode = d.mode === "live" ? "live" : "static";
                    root.liveCurrent = d.current ?? "";
                } catch (e) {}
            }
        }
    }
    Process {
        id: liveList
        command: [Paths.core, "msg", "wallpaper-live-list", "collection"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.live = JSON.parse(text);
                } catch (e) {
                    root.live = [];
                }
            }
        }
    }
}
