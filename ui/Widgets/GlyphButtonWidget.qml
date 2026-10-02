import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// A button that is a glyph (or your picture) and maybe a label: launcher, Control Panel, clipboard,
// wallpaper, screenshot, settings, session and your own buttons. What it does is its actions.
BarItem {
    id: root
    readonly property string label: opt("label") ?? ""
    active: {
        const panel = ({ launcher: "launcher", "control-center": "control", clipboard: "clipboard", wallpaper: "wallpaper", session: "session" })[type];
        return panel !== undefined && PanelRouter.isOpen(panel, screen?.name ?? "");
    }
    BarGlyph {
        item: root
        name: root.opt("glyph") || (BarWidgetTypes.find(root.type)?.glyph ?? "circle")
        size: Metrics.icon + 1
    }
    BarText {
        item: root
        visible: root.label !== "" && !root.vertical
        text: root.label
    }
}
