import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Scroll for brightness; the level shows while hovered (and is only read while it shows).
BarItem {
    id: root

    shown: Backlight.available
    onClicked: bar?.openPanel("control", root)
    onScrolled: delta => Backlight.set(Backlight.value + (delta > 0 ? 0.05 : -0.05))
    onHoveredChanged: hovered ? Backlight.retain() : Backlight.release()
    Component.onDestruction: if (hovered)
        Backlight.release()

    Icon {
        name: Backlight.value < 0.34 ? "brightness-down" : "brightness-up"
    }
    Label {
        visible: root.hovered && !root.vertical
        role: "label"
        numeric: true
        tone: "muted"
        text: Math.round(Backlight.value * 100)
    }
}
