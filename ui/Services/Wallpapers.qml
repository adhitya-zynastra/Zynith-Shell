pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
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
        CoreClient.call("wallpaper-get", text => current = text.trim());
        CoreClient.call("wallpaper-live-status", text => {
            try {
                const d = JSON.parse(text);
                mode = d.mode === "live" ? "live" : "static";
                liveCurrent = d.current ?? "";
            } catch (e) {}
        });
        CoreClient.call("wallpaper-live-list collection", text => {
            try {
                live = JSON.parse(text);
            } catch (e) {
                live = [];
            }
        });
    }

    // a static choice also ends a live wallpaper, so the desktop shows what was picked
    function applyImage(path: string): void {
        current = path;
        mode = "static";
        CoreClient.call("wallpaper-set " + path, reply => {
            if (reply.startsWith("ok"))
                CoreClient.call("wallpaper-live-stop");
            else
                console.warn("zynith: wallpaper not set:", reply.trim());
        });
    }
    function applyLive(id: string): void {
        liveCurrent = id;
        mode = "live";
        CoreClient.call("wallpaper-live-set " + id);
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
}
