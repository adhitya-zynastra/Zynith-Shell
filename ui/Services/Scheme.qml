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

    // the colours shown: while the palette changes (a new wallpaper), every surface blends from the old one
    // to the new over a beat instead of snapping. [animation] palette_ms sets how long (0: at once).
    property var target: Fallback.colors
    property var previous: Fallback.colors
    property real blend: 1
    readonly property var colors: blend >= 1 ? target : mixed(previous, target, blend)
    readonly property var fallback: Fallback.colors
    function mixed(a: var, b: var, t: real): var {
        const out = {};
        for (const k in b) {
            const from = a[k] !== undefined ? Qt.color(a[k]) : Qt.color(b[k]);
            const to = Qt.color(b[k]);
            out[k] = Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
        }
        return out;
    }
    function setColors(next: var): void {
        if (JSON.stringify(next) === JSON.stringify(target))
            return;
        const ms = Config.animation?.palette_ms ?? 650;
        // the first palette, or no motion: at once
        if (!live || ms <= 0 || Motion.reduced) {
            target = next;
            blend = 1;
            return;
        }
        previous = colors;
        target = next;
        crossfade.duration = Math.round(ms * Motion.scale);
        crossfade.restart();
    }
    NumberAnimation {
        id: crossfade
        target: root
        property: "blend"
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
    }
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
                root.setColors(Object.assign({}, root.fallback, data.colors));
                root.mode = data.mode || "dark";
                root.image = data.image || "";
                root.live = true;
            } catch (e) {
                console.warn("zynith: palette.json unreadable:", e);
            }
        }
    }
}
