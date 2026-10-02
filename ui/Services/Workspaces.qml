pragma Singleton

import QtQuick
import Quickshell
import Quickshell.WindowManager
import Zynith.Native

// Workspaces per output. Under niri the native model (with window counts and overview state) is the
// source; ext-workspace covers other compositors. Entries: { key, active, urgent, windows, activate() }.
Singleton {
    id: root

    readonly property bool niri: NiriState.connected
    readonly property bool overviewOpen: NiriState.overviewOpen
    readonly property var focusedWindow: NiriState.focusedWindow
    readonly property string keyboardLayout: NiriState.keyboardLayout
    // the output holding the focused workspace ("" outside niri)
    readonly property string focusedOutput: NiriState.workspaces.find(w => w.focused)?.output ?? ""

    // the workspaces on this screen's output (all of them when `all`)
    function forScreen(screen: var, all: bool): var {
        const name = screen?.name ?? "";
        if (niri) {
            return NiriState.workspaces.filter(w => all || w.output === name).map(w => ({
                        key: w.id,
                        idx: w.idx,
                        name: w.name ?? "",
                        output: w.output,
                        active: w.active,
                        focused: w.focused,
                        urgent: w.urgent,
                        windows: w.windows,
                        activate: () => NiriState.focusWorkspace(w.id)
                    }));
        }
        for (const p of WindowManager.windowsetProjections) {
            if (p.screens.some(s => s.name === name))
                return p.windowsets.filter(w => w.shouldDisplay).map(w => ({
                            key: w.id,
                            active: w.active,
                            urgent: w.urgent,
                            windows: -1,
                            activate: () => w.activate()
                        }));
        }
        return [];
    }

    // the active workspace on this output has windows (drives smart auto-hide)
    function occupied(screenName: string): bool {
        if (!niri)
            return true;
        const w = NiriState.workspaces.find(w => w.output === screenName && w.active);
        return w ? w.windows > 0 : false;
    }
}
