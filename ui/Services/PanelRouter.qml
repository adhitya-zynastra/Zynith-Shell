pragma Singleton

import QtQuick
import Quickshell

// Which focused panel is open on which output, and where it came from. One panel per output by default:
// opening another replaces it. Panels read state from services; the router only routes.
Singleton {
    id: root

    // screen name -> { id, originX, originY, edge }
    property var openPanels: ({})

    function current(screenName: string): var {
        return openPanels[screenName] ?? null;
    }
    function isOpen(id: string, screenName: string): bool {
        return (openPanels[screenName]?.id ?? "") === id;
    }
    function open(id: string, screenName: string, origin: var): void {
        const next = Object.assign({}, openPanels);
        next[screenName] = {
            id: id,
            originX: origin?.x ?? -1,
            originY: origin?.y ?? -1,
            edge: origin?.edge ?? "top"
        };
        openPanels = next;
    }
    function close(screenName: string): void {
        if (!openPanels[screenName])
            return;
        const next = Object.assign({}, openPanels);
        delete next[screenName];
        openPanels = next;
    }
    function toggle(id: string, screenName: string, origin: var): void {
        if (isOpen(id, screenName))
            close(screenName);
        else
            open(id, screenName, origin);
    }
    function closeAll(): void {
        openPanels = {};
    }
}
