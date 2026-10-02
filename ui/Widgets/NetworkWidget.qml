import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The connection: its strength or wired, its name if asked.
BarItem {
    id: root
    active: PanelRouter.isOpen("network", screen?.name ?? "")
    BarGlyph {
        item: root
        name: Network.glyph
        colour: Network.connected ? root.iconInk : Theme.alpha(root.iconInk, 0.45)
    }
    BarText {
        item: root
        visible: root.opt("show_label") !== false && !root.vertical && Network.name !== ""
        muted: true
        text: Network.name
    }
}
