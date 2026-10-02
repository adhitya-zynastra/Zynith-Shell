pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Clipboard history as the native core keeps it (encrypted at rest). This side only ever sees short
// previews; picking an entry asks the core to put it back on the clipboard.
Singleton {
    id: root

    property var entries: []
    property bool loading: false
    property string error: ""

    function refresh(): void {
        if (list.running)
            return;
        loading = true;
        list.running = true;
    }

    function select(id: string): void {
        run(["clipboard-select", id]);
    }
    function remove(id: string): void {
        entries = entries.filter(e => e.id !== id);
        run(["clipboard-remove", id]);
    }
    function clearUnpinned(): void {
        entries = entries.filter(e => e.pinned);
        run(["clipboard-clear"]);
    }

    function run(args: var): void {
        Quickshell.execDetached([Paths.core, "msg"].concat(args));
    }

    Process {
        id: list
        command: [Paths.core, "msg", "clipboard-history", "60"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    root.entries = JSON.parse(text);
                    root.error = "";
                } catch (e) {
                    root.entries = [];
                    root.error = text.trim() || "No answer from the core";
                }
            }
        }
    }
}
