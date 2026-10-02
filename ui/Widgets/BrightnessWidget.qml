import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Zynith.Native

// The screen's brightness; the level shows if asked. Scrolling changes it (its actions).
BarItem {
    id: root
    shown: Backlight.available
    Component.onCompleted: Backlight.retain()
    Component.onDestruction: Backlight.release()
    BarGlyph {
        item: root
        name: Backlight.value < 0.34 ? "brightness-down" : "brightness-up"
    }
    BarText {
        item: root
        visible: root.opt("show_label") !== false && !root.vertical
        muted: true
        text: Math.round(Backlight.value * 100)
    }
}
