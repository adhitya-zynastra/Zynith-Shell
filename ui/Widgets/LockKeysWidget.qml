import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Caps, Num and Scroll Lock, each as a short tag (or its full name), lit while on; hidden when off if asked.
BarItem {
    id: root
    readonly property var keys: [
        { on: Core.capsLock, wanted: opt("show_caps_lock") !== false, short: "A", full: "Caps" },
        { on: Core.numLock, wanted: opt("show_num_lock") !== false, short: "1", full: "Num" },
        { on: Core.scrollLock, wanted: opt("show_scroll_lock") === true, short: "S", full: "Scroll" }
    ].filter(k => k.wanted && (k.on || opt("hide_when_off") !== true))
    shown: keys.length > 0
    Repeater {
        model: root.keys
        delegate: Rectangle {
            required property var modelData
            width: tag.implicitWidth + 8
            height: Metrics.icon
            radius: 4
            color: modelData.on ? Theme.accentSoft : "transparent"
            border.width: 1
            border.color: modelData.on ? Theme.accentLine : Theme.alpha(root.ink, 0.25)
            BarText {
                id: tag
                anchors.centerIn: parent
                item: root
                size: Type.micro
                color: modelData.on ? Theme.accent : Theme.alpha(root.ink, 0.45)
                text: root.opt("display") === "full" ? modelData.full : modelData.short
            }
        }
    }
}
