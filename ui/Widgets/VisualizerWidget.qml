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
    property int holding: 0
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

    readonly property bool square: (opt("bar_style") ?? "square") !== "rounded"
    function sync(): void {
        const want = wanted ? bands : 0;
        if (want === holding)
            return;
        if (holding > 0)
            Spectrum.release(holding);
        if (want > 0)
            Spectrum.retain(want);
        holding = want;
    }
    onWantedChanged: sync()
    onBandsChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (holding > 0)
        Spectrum.release(holding)


    // one scene-graph node for every bar (Zynith.Native SpectrumBars)
    SpectrumBars {
        width: root.vertical ? root.cross - 8 : root.length
        height: root.vertical ? root.length : root.cross - 10
        vertical: root.vertical
        values: Spectrum.values
        // as the native bar visualizer: mirrored shows each band twice
        count: root.mirrored ? root.bands * 2 : root.bands
        mirrored: root.mirrored
        reversed: root.reversed
        centred: root.centred
        square: root.square
        gap: root.square ? 1 / 3 : 0.4
        floor: root.square ? 0 : 0.06
        minLength: root.square ? 1 : 2
        smoothing: root.opt("smoothing") ?? 60
        colorFrom: root.from
        colorTo: root.to
        alpha: root.square ? 1 : 0.55
        alphaByLevel: root.square ? 0 : 0.45
    }
}
