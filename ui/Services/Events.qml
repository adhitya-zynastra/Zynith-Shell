pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// What the native shell tells the UI as it happens (`event <name> [payload]` on the command socket), so
// nothing here polls for it. Each event says only that something changed; the listener asks for the state.
Singleton {
    id: root

    // the session lock, as the native shell holds it
    property bool locked: false

    signal wallpaper
    signal clipboard
    signal launcher
    signal osd(var content)

    function dispatch(args: string): void {
        const space = args.indexOf(" ");
        const name = space < 0 ? args : args.slice(0, space);
        const payload = space < 0 ? "" : args.slice(space + 1);
        switch (name) {
        case "wallpaper":
            wallpaper();
            break;
        case "clipboard":
            clipboard();
            break;
        case "launcher":
            launcher();
            break;
        case "lock":
            locked = payload === "on";
            break;
        case "panel":
            {
                // the native shell hands over a panel Zynith draws: "toggle|open <id> [context]"
                const verb = payload.split(" ")[0];
                Actions.run((verb === "open" ? "panel-open " : "panel-toggle ") + payload.slice(verb.length + 1), {});
                break;
            }
        case "osd":
            try {
                osd(JSON.parse(payload));
            } catch (e) {
                console.warn("zynith: unreadable osd event");
            }
            break;
        }
    }

    // the lock may have been taken before this UI started
    Component.onCompleted: CoreClient.call("status", text => {
        try {
            root.locked = JSON.parse(text).locked === true;
        } catch (e) {}
    })
}
