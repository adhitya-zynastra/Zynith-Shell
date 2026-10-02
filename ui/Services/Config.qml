pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ~/.config/zynith/shell.json. Missing keys fall back to the defaults below; a missing file is created
// with them so the available options are visible. Only this service writes the file.
Singleton {
    id: root

    readonly property alias experience: adapter.experience
    readonly property alias bars: adapter.bars
    readonly property alias panels: adapter.panels
    readonly property alias osd: adapter.osd
    readonly property alias window: adapter.window
    readonly property alias launcher: adapter.launcher
    readonly property alias notifications: adapter.notifications
    readonly property alias wallpaper: adapter.wallpaper
    property bool loaded: false

    function setExperienceProfile(name: string): void {
        if (adapter.experience.profile === name)
            return;
        adapter.experience.profile = name;
        file.writeAdapter();
    }

    function setAdaptive(on: bool): void {
        adapter.experience.adaptive = on;
        file.writeAdapter();
    }

    function setNotificationsDnd(on: bool): void {
        adapter.notifications.dnd = on;
        file.writeAdapter();
    }

    function setReducedMotion(on: bool): void {
        adapter.experience.reducedMotion = on;
        file.writeAdapter();
    }

    // one field of one bar; the list is replaced so bindings see the change
    function updateBar(index: int, key: string, value: var): void {
        const bars = adapter.bars.slice();
        if (index < 0 || index >= bars.length)
            return;
        bars[index] = Object.assign({}, bars[index], {
            [key]: value
        });
        adapter.bars = bars;
        file.writeAdapter();
    }

    function setWindowBehaviour(behaviour: string): void {
        adapter.window.behaviour = behaviour;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: Paths.config + "/shell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loaded = true
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
            else
                console.warn("zynith: config unreadable:", FileViewError.toString(err));
            root.loaded = true;
        }
        onSaveFailed: err => console.warn("zynith: config not saved:", FileViewError.toString(err))

        JsonAdapter {
            id: adapter

            property JsonObject experience: JsonObject {
                // "auto" follows the hardware recommendation; otherwise performance | balanced | enhanced | max
                property string profile: "auto"
                // per-knob overrides on top of the profile, e.g. { "blurQuality": "off" }
                property var overrides: ({})
                property bool reducedMotion: false
                // automatic mode steps down on battery and power saving
                property bool adaptive: true
            }

            property list<var> bars: [
                {
                    id: "main",
                    edge: "top",
                    anchor: "end",
                    offset: 12,
                    margin: 8,
                    thickness: 34,
                    reserve: false,
                    layer: "top",
                    screens: ["*"],
                    widgets: {
                        start: ["workspaces"],
                        center: ["clock"],
                        end: ["media", "visualizer", "audio", "network", "battery", "quick"]
                    }
                }
            ]

            property JsonObject panels: JsonObject {
                property int width: 400
            }

            // config (niri's layout block as written) | scrolling | tiling-like; written to rice/layout.kdl
            property JsonObject window: JsonObject {
                property string behaviour: "config"
            }

            property JsonObject launcher: JsonObject {
                // command prefix for apps that run in a terminal; empty: $TERMINAL -e, else kitty
                property list<string> terminal: []
            }

            // where the Wallpaper panel looks for images ("" = ~/Pictures/wallpapers)
            property JsonObject wallpaper: JsonObject {
                property string directory: ""
            }

            property JsonObject notifications: JsonObject {
                // owning org.freedesktop.Notifications is exclusive; off while the native shell has it
                property bool server: false
                property bool dnd: false
                property int popupMs: 6000
                property int maxPopups: 4
                // kept in memory only, never written to disk
                property int historySize: 100
            }

            // off while the native shell's OSD is still the one in use
            property JsonObject osd: JsonObject {
                property bool enabled: false
                property int durationMs: 1400
                property int margin: 72
            }
        }
    }
}
