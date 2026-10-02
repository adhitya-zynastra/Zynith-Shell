import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Scroll for volume, click to mute. The level shows while hovered.
BarItem {
    id: root

    shown: Audio.ready
    onClicked: mouse => mouse.button === Qt.RightButton ? bar?.openPanel("home", root) : Audio.toggleMute()
    onScrolled: delta => Audio.nudge(delta > 0 ? 0.05 : -0.05)

    Icon {
        name: Audio.glyph
        tone: Audio.muted ? "faint" : "ink"
    }
    Label {
        visible: root.hovered && !root.vertical
        role: "label"
        numeric: true
        tone: "muted"
        text: Math.round(Audio.volume * 100)
    }
}
