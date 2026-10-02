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
    readonly property bool active: AudioSpectrum.active
    readonly property int consumers: AudioSpectrum.consumers

    function retain(): void {
        AudioSpectrum.retain();
    }
    function release(): void {
        AudioSpectrum.release();
    }

    readonly property Binding bands: Binding {
        target: AudioSpectrum
        property: "bands"
        value: Math.max(1, ExperiencePolicy.visualizerBands)
    }
    readonly property Binding fps: Binding {
        target: AudioSpectrum
        property: "fps"
        value: ExperiencePolicy.visualizerFps > 0 ? ExperiencePolicy.visualizerFps : 60
    }
}
