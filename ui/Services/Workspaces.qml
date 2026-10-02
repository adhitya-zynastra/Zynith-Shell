pragma Singleton

import QtQuick
import Quickshell
import Quickshell.WindowManager

// Workspaces per output through ext-workspace, which niri implements. niri-only data (columns, overview)
// will come from the native niri model later.
Singleton {
    id: root

    function forScreen(screen: var): var {
        const projections = WindowManager.windowsetProjections;
        for (const p of projections) {
            if (screen && p.screens.some(s => s.name === screen.name))
                return p.windowsets.filter(w => w.shouldDisplay);
        }
        return WindowManager.windowsets.filter(w => w.shouldDisplay);
    }
}
