pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native

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
        CoreClient.call("status", text => {
            try {
                const d = JSON.parse(text);
                if (d.caffeine === undefined)
                    return; // an older shell without these fields
                caffeine = d.caffeine;
                nightlight = d.nightlight.enabled;
                nightlightForced = d.nightlight.forced;
                nightlightActive = d.nightlight.active;
                dnd = d.dnd;
                known = true;
            } catch (e) {}
        });
    }

    function run(args: var): void {
        CoreClient.call(args.join(" "), () => settle.restart());
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

    // the shell says when one of them changed (its OSD events), wherever it was changed from
    Connections {
        target: Events
        function onOsd(c: var): void {
            if (["caffeine", "nightlight", "dnd", "power-profile"].includes(c.kind))
                root.refresh();
            else if (c.kind === "lock-keys")
                root.readLeds();
            else if (c.kind === "privacy")
                root.notePrivacy(c);
        }
    }
    Component.onCompleted: {
        refresh();
        findLeds.running = true;
    }

    // ── lock keys: the keyboard's LEDs ──
    property bool capsLock: false
    property bool numLock: false
    property bool scrollLock: false
    property var ledPaths: ({})
    Process {
        id: findLeds
        command: ["sh", "-c", "for k in capslock numlock scrolllock; do p=$(ls -d /sys/class/leds/*::$k 2>/dev/null | head -1); echo \"$k $p\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = {};
                for (const line of text.trim().split("\n")) {
                    const [k, p] = line.split(" ");
                    if (p)
                        paths[k] = p + "/brightness";
                }
                root.ledPaths = paths;
                root.readLeds();
            }
        }
    }
    function readLeds(): void {
        capsView.reload();
        numView.reload();
        scrollView.reload();
    }
    FileView {
        id: capsView
        path: root.ledPaths.capslock ?? ""
        printErrors: false
        onLoaded: root.capsLock = parseInt(text()) > 0
    }
    FileView {
        id: numView
        path: root.ledPaths.numlock ?? ""
        printErrors: false
        onLoaded: root.numLock = parseInt(text()) > 0
    }
    FileView {
        id: scrollView
        path: root.ledPaths.scrolllock ?? ""
        printErrors: false
        onLoaded: root.scrollLock = parseInt(text()) > 0
    }

    // ── privacy: what is in use, from the shell's privacy events ──
    property bool micInUse: false
    property bool cameraInUse: false
    property bool screenShared: false
    function notePrivacy(c: var): void {
        const on = !c.inactive;
        if ((c.icon ?? "").startsWith("microphone"))
            micInUse = on;
        else if ((c.icon ?? "").startsWith("camera"))
            cameraInUse = on;
        else if ((c.icon ?? "").startsWith("screen-share"))
            screenShared = on;
    }
}
