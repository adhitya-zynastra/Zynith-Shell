pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// Clipboard history as the native core keeps it (encrypted at rest). This side sees short previews for the
// list, and the whole of one entry — the selected one — for the preview pane; nothing is kept once the panel
// closes. Picking an entry asks the core to put it back on the clipboard, and to paste it if asked.
Singleton {
    id: root

    property var entries: []         // [{ id, preview, mime, image, bytes, pinned, time, kind }]
    property bool loading: false
    property string error: ""

    // the selected entry, whole: { id, kind, text | image }
    property var detail: null

    // what an entry is, for filters and the preview: image | link | colour | code | text
    function classify(e: var): string {
        if (e.image)
            return "image";
        const p = (e.preview ?? "").trim();
        if (/^(https?|ftp|file):\/\/\S+$/i.test(p) || /^www\.\S+\.\S+$/i.test(p))
            return "link";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(p) || /^rgba?\(\s*\d+/i.test(p))
            return "colour";
        if (/[{};]\s*$/m.test(p) && p.includes("\n") || /^\s*(def|fn|function|class|import|#include|const|let|var)\b/m.test(p))
            return "code";
        return "text";
    }

    // the history loads while a panel shows it; the core's change events keep it current meanwhile
    property int consumers: 0
    function retain(): void {
        consumers++;
        if (consumers === 1)
            refresh();
    }
    function release(): void {
        consumers = Math.max(0, consumers - 1);
        if (consumers === 0)
            detail = null;
    }
    Connections {
        target: Events
        function onClipboard(): void {
            if (root.consumers > 0)
                coalesce.restart();
        }
    }
    Timer {
        id: coalesce
        interval: 40
        onTriggered: root.refresh()
    }

    function refresh(): void {
        if (loading)
            return;
        loading = true;
        CoreClient.call("clipboard-history 200", text => {
            loading = false;
            try {
                entries = JSON.parse(text).map(e => Object.assign(e, {
                        kind: root.classify(e)
                    }));
                error = "";
            } catch (e) {
                entries = [];
                error = text.trim() || "No answer from the core";
            }
        });
    }

    // the whole of one entry, for the preview; a newer request wins
    property string wanted: ""
    function loadDetail(entry: var): void {
        if (!entry) {
            detail = null;
            return;
        }
        if (detail?.id === entry.id)
            return;
        wanted = entry.id;
        const id = entry.id;
        if (entry.image) {
            CoreClient.call("clipboard-image " + id, text => {
                if (root.wanted !== id)
                    return;
                root.detail = text.startsWith("data:") ? { id: id, kind: "image", image: text.trim() } : { id: id, kind: "image", error: text.replace(/^error: /, "").trim() };
            });
        } else {
            CoreClient.call("clipboard-entry-text " + id, text => {
                if (root.wanted !== id)
                    return;
                root.detail = text.startsWith("error: ") ? { id: id, kind: entry.kind, text: entry.preview, error: text.slice(7).trim() } : { id: id, kind: entry.kind, text: text };
            });
        }
    }

    function select(id: string): void {
        CoreClient.call("clipboard-select " + id);
    }
    // back on the clipboard, then pasted into whatever window has the keyboard once the panel lets go of it
    function paste(entry: var): void {
        CoreClient.call("clipboard-select " + entry.id, reply => {
            if (reply.startsWith("ok"))
                CoreClient.call("clipboard-paste " + (entry.image ? "image" : "text"));
        });
    }
    function pin(id: string, on: bool): void {
        entries = entries.map(e => e.id === id ? Object.assign({}, e, {
                pinned: on
            }) : e);
        CoreClient.call("clipboard-pin " + id + " " + (on ? "on" : "off"));
    }
    function remove(id: string): void {
        entries = entries.filter(e => e.id !== id);
        if (detail?.id === id)
            detail = null;
        CoreClient.call("clipboard-remove " + id);
    }
    function clearUnpinned(): void {
        entries = entries.filter(e => e.pinned);
        CoreClient.call("clipboard-clear");
    }
    // everything, pinned included: unpin, then clear
    function clearAll(): void {
        const pinned = entries.filter(e => e.pinned).map(e => e.id);
        entries = [];
        detail = null;
        let left = pinned.length;
        if (left === 0) {
            CoreClient.call("clipboard-clear");
            return;
        }
        for (const id of pinned)
            CoreClient.call("clipboard-pin " + id + " off", () => {
                if (--left === 0)
                    CoreClient.call("clipboard-clear");
            });
    }
}
