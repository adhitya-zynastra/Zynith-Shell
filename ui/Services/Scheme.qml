pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/FallbackPalette.js" as Fallback

// The wallpaper-derived colour scheme (not named Palette: that is a QtQuick type and would shadow this). The native theme engine renders it to
// ~/.local/state/zynith/palette.json (templates/palette.json, a user template); this only reads it.
Singleton {
    id: root

    property var colors: Fallback.colors
    readonly property var fallback: Fallback.colors
    property string mode: "dark"
    property string image: ""
    property bool live: false

    // A file that does not exist yet cannot be watched; until the theme engine first writes it, look
    // again now and then. Once it exists, changes arrive through the watch.
    Timer {
        id: retry
        interval: 15000
        onTriggered: paletteFile.reload()
    }

    FileView {
        id: paletteFile
        path: Paths.state + "/palette.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: retry.restart()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.schema !== 1 || !data.colors)
                    return;
                root.colors = Object.assign({}, root.fallback, data.colors);
                root.mode = data.mode || "dark";
                root.image = data.image || "";
                root.live = true;
            } catch (e) {
                console.warn("zynith: palette.json unreadable:", e);
            }
        }
    }
}
