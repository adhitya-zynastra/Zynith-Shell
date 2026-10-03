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
        name: Backlight.value < 0.4 ? "brightness-down-filled" : "brightness-up-filled"
    }
    BarText {
        item: root
        visible: root.vertical ? (root.bar?.readouts ?? false) && root.opt("readout") !== false : root.opt("show_label") !== false
        muted: true
        text: Math.round(Backlight.value * 100)
    }
}
