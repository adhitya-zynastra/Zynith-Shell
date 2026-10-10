import QtQuick
import Zynith.Native
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


    // one scene-graph node for every bar (Zynith.Native SpectrumBars)
    SpectrumBars {
        width: root.vertical ? root.cross - 8 : root.length
        height: root.vertical ? root.length : root.cross - 10
        vertical: root.vertical
        values: Spectrum.values
        count: root.bands
        mirrored: root.mirrored
        reversed: root.reversed
        centred: root.centred
        gap: 0.4
        floor: 0.06
        colorFrom: root.from
        colorTo: root.to
        alpha: 0.55
        alphaByLevel: 0.45
    }
}
