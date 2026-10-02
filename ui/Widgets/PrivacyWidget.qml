import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// What is listening or watching: the microphone, the camera, a screen being shared.
BarItem {
    id: root
    readonly property var items: [
        { on: Core.micInUse, glyph: "microphone" },
        { on: Core.cameraInUse, glyph: "camera" },
        { on: Core.screenShared, glyph: "screen-share" }
    ].filter(i => i.on || opt("hide_inactive") !== true)
    shown: items.length > 0
    spacing: opt("icon_spacing") ?? 4
    Repeater {
        model: root.items
        delegate: BarGlyph {
            required property var modelData
            item: root
            name: modelData.glyph
            colour: modelData.on ? Theme.colour(root.opt("active_color") ?? "primary") : Theme.colour(root.opt("inactive_color") ?? "outline")
        }
    }
}
