import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Night light: on, off, or forced on.
BarItem {
    id: root
    active: Core.nightlight
    BarGlyph {
        item: root
        name: Core.nightlightForced ? "moon-stars" : Core.nightlight ? "moon" : "moon-off"
        colour: Core.nightlight ? Theme.accent : root.iconInk
    }
}
