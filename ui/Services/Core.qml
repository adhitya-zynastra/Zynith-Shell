pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Toggles the native shell still owns (night light, stay awake, its notification Do Not Disturb), read from
// its status and changed through its IPC. Asked when something shows them, never on a timer.
Singleton {
    id: root

    property bool known: false
    property bool caffeine: false
    property bool nightlight: false
    property bool nightlightForced: false
    property bool nightlightActive: false
    property bool dnd: false

    function refresh(): void {
        if (!status.running)
            status.running = true;
    }

    function run(args: var): void {
        Quickshell.execDetached([Paths.core, "msg"].concat(args));
        settle.restart();
    }
    function toggleCaffeine(): void {
        caffeine = !caffeine;
        run(["caffeine-toggle"]);
    }
    function toggleNightlight(): void {
        nightlight = !nightlight;
        run(["nightlight-toggle"]);
    }
    function setDnd(on: bool): void {
        dnd = on;
        run(["notification-dnd-set", on ? "on" : "off"]);
    }

    // read back what the shell made of it
    Timer {
        id: settle
        interval: 300
        onTriggered: root.refresh()
    }

    Process {
        id: status
        command: [Paths.core, "msg", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.caffeine === undefined)
                        return; // an older shell without these fields
                    root.caffeine = d.caffeine;
                    root.nightlight = d.nightlight.enabled;
                    root.nightlightForced = d.nightlight.forced;
                    root.nightlightActive = d.nightlight.active;
                    root.dnd = d.dnd;
                    root.known = true;
                } catch (e) {}
            }
        }
    }
}
