import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Spectrum bars. Holds the spectrum only while it can actually be seen: enabled by the profile, and its
// bar on screen. Collapses during silence.
BarItem {
    id: root

    readonly property bool wanted: Spectrum.enabled && (bar?.shown ?? 1) > 0
    property bool holding: false
    readonly property int length: 64

    shown: wanted && Spectrum.active
    interactive: false
    pad: Metrics.s2

    function sync(): void {
        if (wanted && !holding) {
            Spectrum.retain();
            holding = true;
        } else if (!wanted && holding) {
            Spectrum.release();
            holding = false;
        }
    }
    onWantedChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (holding)
        Spectrum.release()

    Item {
        width: root.vertical ? root.cross - 8 : root.length
        height: root.vertical ? root.length : root.cross - 10

        Repeater {
            model: Spectrum.values.length

            delegate: Rectangle {
                required property int index
                readonly property int count: Spectrum.values.length
                readonly property real level: Math.max(0.06, Spectrum.values[index] ?? 0)
                readonly property real slot: (root.vertical ? parent.height : parent.width) / count

                x: root.vertical ? (parent.width - width) / 2 : index * slot + slot * 0.2
                y: root.vertical ? index * slot + slot * 0.2 : (parent.height - height) / 2
                width: root.vertical ? parent.width * level : slot * 0.6
                height: root.vertical ? slot * 0.6 : parent.height * level
                radius: Math.min(width, height) / 2
                color: Theme.mix(Theme.accent, Theme.ink, index / Math.max(1, count - 1) * 0.35)
                opacity: 0.55 + level * 0.45
            }
        }
    }
}
