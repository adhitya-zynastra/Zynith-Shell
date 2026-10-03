import QtQuick
import Quickshell
import Quickshell.Services.UPower
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
    readonly property color tint: warn ? Theme.colour(opt("warning_color") ?? "error") : mode === "graphic" ? root.ink : root.iconInk
    shown: Power.present && !(opt("hide_when_plugged") === true && !Power.onBattery) && !(opt("hide_when_full") === true && level >= 0.995)

    BarGlyph {
        item: root
        visible: root.mode === "glyph"
        name: Power.glyph
        colour: root.tint
    }
    // the gauge, drawn as the native one: a body of the foreground at 30 %, filled with the foreground (the
    // warning colour when low), its terminal on the far end (on top when vertical), 22 × 14 at 14 px text;
    // under it (beside it, horizontally) a bolt while charging, a plug when held or full
    readonly property real gaugeScale: root.sizeScale
    readonly property string stateGlyph: !Power.present ? "" : Power.device.state === UPowerDeviceState.Charging ? "bolt-filled" : Power.device.state === UPowerDeviceState.FullyCharged || Power.device.state === UPowerDeviceState.PendingCharge ? "plug-filled" : ""
    Grid {
        visible: root.mode === "graphic"
        columns: root.vertical ? 1 : 2
        spacing: 2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Item {
            readonly property real bodyLong: 22
            readonly property real bodyShort: 14
            readonly property real term: 2.5
            width: root.vertical ? bodyShort : bodyLong + term
            height: root.vertical ? bodyLong + term : bodyShort
            Rectangle {
                id: body
                x: 0
                y: root.vertical ? parent.term : 0
                width: root.vertical ? parent.bodyShort : parent.bodyLong
                height: root.vertical ? parent.bodyLong : parent.bodyShort
                radius: 3
                color: Theme.alpha(root.tint, 0.3)
                Rectangle {
                    readonly property real fraction: Math.max(0, Math.min(1, root.level))
                    x: 0
                    y: root.vertical ? parent.height - height : 0
                    width: root.vertical ? parent.width : parent.width * fraction
                    height: root.vertical ? parent.height * fraction : parent.height
                    radius: 3
                    color: root.tint
                    Behavior on height {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Behavior on width {
                        Anim {
                            role: "spatial"
                        }
                    }
                }
            }
            Rectangle {
                x: root.vertical ? (parent.bodyShort - 7) / 2 : parent.bodyLong
                y: root.vertical ? 0 : (parent.bodyShort - 7) / 2
                width: root.vertical ? 7 : parent.term
                height: root.vertical ? parent.term : 7
                radius: 1.5
                color: Theme.alpha(root.tint, 0.3)
            }
        }
        Icon {
            visible: root.stateGlyph !== ""
            name: root.stateGlyph
            size: 13
            color: root.tint
        }
    }
    BarText {
        item: root
        visible: root.vertical ? (root.bar?.readouts ?? false) && root.opt("readout") !== false : root.opt("show_label") !== false
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
