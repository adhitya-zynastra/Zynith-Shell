import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Stay awake: the screen does not sleep while it is on.
BarItem {
    id: root
    active: Core.caffeine
    BarGlyph {
        item: root
        name: Core.caffeine ? "coffee" : "coffee-off"
        colour: Core.caffeine ? Theme.accent : root.iconInk
    }
}
