import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The battery: an icon or a small gauge, the percent, time left or rate; hidden when plugged in or full if
// asked, and in the warning colour below the threshold.
BarItem {
    id: root
    readonly property string mode: opt("display_mode") ?? "glyph"
    readonly property real level: Power.level
    readonly property bool warn: !Power.charging && (opt("warning_threshold") ?? 0) > 0 && level * 100 <= (opt("warning_threshold") ?? 0)
    readonly property color tint: warn ? Theme.colour(opt("warning_color") ?? "error") : root.iconInk
    shown: Power.present && !(opt("hide_when_plugged") === true && !Power.onBattery) && !(opt("hide_when_full") === true && level >= 0.995)

    BarGlyph {
        item: root
        visible: root.mode === "glyph"
        name: Power.glyph
        colour: root.tint
    }
    // the gauge: a small battery that fills
    Item {
        visible: root.mode === "graphic"
        width: root.vertical ? 12 : 22
        height: root.vertical ? 22 : 12
        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: root.vertical ? 0 : 2
            anchors.topMargin: root.vertical ? 2 : 0
            radius: 3
            color: "transparent"
            border.width: 1.5
            border.color: Theme.alpha(root.tint, 0.8)
            Rectangle {
                x: 2.5
                y: root.vertical ? parent.height - height - 2.5 : 2.5
                width: root.vertical ? parent.width - 5 : Math.max(1, (parent.width - 5) * root.level)
                height: root.vertical ? Math.max(1, (parent.height - 5) * root.level) : parent.height - 5
                radius: 1.5
                color: Power.charging ? Theme.accent : root.tint
                Behavior on width {
                    Anim {
                        role: "spatialFast"
                    }
                }
            }
        }
        Rectangle {
            visible: !root.vertical
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: 5
            radius: 1
            color: Theme.alpha(root.tint, 0.8)
        }
    }
    BarText {
        item: root
        visible: root.opt("show_label") !== false && !root.vertical
        muted: true
        color: root.warn ? root.tint : Theme.alpha(root.ink, 0.7)
        text: {
            const what = root.opt("label_content") ?? "percent";
            const d = Power.device;
            if (what === "time" && d) {
                const s = Power.charging ? d.timeToFull : d.timeToEmpty;
                return s > 0 ? Math.floor(s / 3600) + ":" + String(Math.floor(s % 3600 / 60)).padStart(2, "0") : Math.round(root.level * 100) + "%";
            }
            if (what === "rate" && d)
                return Math.abs(d.changeRate).toFixed(1) + " W";
            return Math.round(root.level * 100) + "%";
        }
    }
}
