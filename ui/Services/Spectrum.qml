pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// The spectrum, shaped by the Experience Profile. Consumers retain() while visible and release() when not;
// with no consumer the native side has no stream and no thread.
Singleton {
    id: root

    readonly property bool enabled: ExperiencePolicy.visualizerBands > 0
    readonly property var values: AudioSpectrum.values
    // changes only with the profile, unlike values (every frame): bind counts and colours to this
    readonly property int bandCount: AudioSpectrum.bands
    readonly property bool active: AudioSpectrum.active
    readonly property int consumers: AudioSpectrum.consumers

    // a consumer may ask for its own resolution (as each native visualizer had its own band count): the
    // analyser runs at the most any holder asks for, else at the Experience Profile's count
    property var wants: []
    readonly property int wanted: wants.length > 0 ? Math.max(...wants) : 0
    function retain(bands: int): void {
        if (bands > 0)
            wants = wants.concat([bands]);
        AudioSpectrum.retain();
    }
    function release(bands: int): void {
        if (bands > 0) {
            const i = wants.indexOf(bands);
            if (i >= 0)
                wants = wants.slice(0, i).concat(wants.slice(i + 1));
        }
        AudioSpectrum.release();
    }

    // a player saying it plays: the capture listens to every buffer (otherwise, asleep over a running output, it
    // listens in windows — AudioSpectrum)
    readonly property Binding expect: Binding {
        target: AudioSpectrum
        property: "expectSound"
        value: Media.playing
    }

    readonly property Binding bands: Binding {
        target: AudioSpectrum
        property: "bands"
        value: Math.max(1, root.wanted > 0 ? Math.min(256, root.wanted) : ExperiencePolicy.visualizerBands)
    }
    readonly property Binding fps: Binding {
        target: AudioSpectrum
        property: "fps"
        value: ExperiencePolicy.visualizerFps > 0 ? ExperiencePolicy.visualizerFps : 60
    }
}
