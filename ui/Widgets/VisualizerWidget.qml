import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Spectrum bars on a bar: its length, band count, mirrored or not, from the middle or the edge, its two
// colours. Holds the spectrum only while it can be seen (profile allows it, its bar on screen); silent, it
// collapses unless asked to stay.
BarItem {
    id: root

    readonly property bool wanted: Spectrum.enabled && (bar?.shown ?? 1) > 0
    property bool holding: false
    readonly property int length: opt("width") ?? 56
    readonly property int bands: Math.max(2, opt("bands") ?? 16)
    readonly property bool mirrored: opt("mirrored") !== false
    readonly property bool reversed: opt("reversed") === true
    readonly property bool centred: opt("centered") !== false
    readonly property color from: Theme.colour(settings.color_1 ?? settings.color ?? "primary")
    readonly property color to: Theme.colour(opt("color_2") ?? "primary")

    shown: wanted && (Spectrum.active || opt("show_when_idle") === true)
    interactive: opt("interactive") === true
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

    // the analyser's bands, stretched to this widget's count
    function level(i: int): real {
        const values = Spectrum.values;
        const n = values.length;
        if (n === 0)
            return 0;
        let t = mirrored ? Math.abs((i + 0.5) / bands * 2 - 1) : (i + 0.5) / bands;
        if (reversed)
            t = 1 - t;
        const x = t * (n - 1);
        const a = Math.floor(x), b = Math.min(n - 1, a + 1);
        return values[a] + (values[b] - values[a]) * (x - a);
    }

    Item {
        width: root.vertical ? root.cross - 8 : root.length
        height: root.vertical ? root.length : root.cross - 10

        Repeater {
            model: root.bands
            delegate: Rectangle {
                required property int index
                readonly property real v: Math.max(0.06, root.level(index))
                readonly property real slot: (root.vertical ? parent.height : parent.width) / root.bands
                readonly property real across: root.vertical ? parent.width : parent.height

                x: root.vertical ? (root.centred ? (parent.width - width) / 2 : 0) : index * slot + slot * 0.2
                y: root.vertical ? index * slot + slot * 0.2 : (root.centred ? (parent.height - height) / 2 : parent.height - height)
                width: root.vertical ? across * v : slot * 0.6
                height: root.vertical ? slot * 0.6 : across * v
                radius: Math.min(width, height) / 2
                color: Theme.mix(root.from, root.to, index / Math.max(1, root.bands - 1))
                opacity: 0.55 + v * 0.45
            }
        }
    }
}
