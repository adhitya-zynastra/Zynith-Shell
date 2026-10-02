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
    property bool loaded: false

    function setExperienceProfile(name: string): void {
        if (adapter.experience.profile === name)
            return;
        adapter.experience.profile = name;
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

            // off while the native shell's OSD is still the one in use
            property JsonObject osd: JsonObject {
                property bool enabled: false
                property int durationMs: 1400
                property int margin: 72
            }
        }
    }
}
