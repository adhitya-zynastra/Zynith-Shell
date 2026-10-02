import QtQuick
import qs.Common
import qs.Services

// The spectrum across its box: mirrored around the middle or rising from one edge. It holds the spectrum
// only while it exists and the profile allows a visualizer; silent, it hides unless asked not to.
Item {
    id: root
    property var settings: ({})
    readonly property int bars: Math.max(4, settings.bands ?? 48)
    readonly property bool mirrored: settings.mirrored ?? true
    readonly property bool reversed: settings.reversed ?? false
    readonly property color from: Theme.pal(settings.color ?? "primary")
    readonly property color to: Theme.pal(settings.color_2 ?? "secondary")

    readonly property bool wanted: Spectrum.enabled
    property bool holding: false
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

    visible: wanted && (Spectrum.active || (settings.show_when_idle ?? false))

    // the analyser's bands, stretched to this widget's bar count
    function level(i: int): real {
        const values = Spectrum.values;
        const n = values.length;
        if (n === 0)
            return 0;
        let t = mirrored ? Math.abs((i + 0.5) / bars * 2 - 1) : (i + 0.5) / bars;
        if (reversed)
            t = 1 - t;
        const x = t * (n - 1);
        const a = Math.floor(x), b = Math.min(n - 1, a + 1);
        return values[a] + (values[b] - values[a]) * (x - a);
    }

    Row {
        anchors.fill: parent
        spacing: Math.max(1, root.width / root.bars * 0.3)
        Repeater {
            model: root.bars
            delegate: Item {
                required property int index
                width: (root.width - parent.spacing * (root.bars - 1)) / root.bars
                height: root.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(2, parent.height * root.level(parent.index))
                    radius: width / 2
                    color: Theme.mix(root.from, root.to, parent.index / root.bars)
                    opacity: 0.85
                }
            }
        }
    }
}
