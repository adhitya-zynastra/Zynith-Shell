pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// Clipboard history as the native core keeps it (encrypted at rest). This side only ever sees short
// previews; picking an entry asks the core to put it back on the clipboard.
Singleton {
    id: root

    property var entries: []
    property bool loading: false
    property string error: ""

    function refresh(): void {
        if (loading)
            return;
        loading = true;
        CoreClient.call("clipboard-history 60", text => {
            loading = false;
            try {
                entries = JSON.parse(text);
                error = "";
            } catch (e) {
                entries = [];
                error = text.trim() || "No answer from the core";
            }
        });
    }

    function select(id: string): void {
        CoreClient.call("clipboard-select " + id);
    }
    function remove(id: string): void {
        entries = entries.filter(e => e.id !== id);
        CoreClient.call("clipboard-remove " + id);
    }
    function clearUnpinned(): void {
        entries = entries.filter(e => e.pinned);
        CoreClient.call("clipboard-clear");
    }
}
