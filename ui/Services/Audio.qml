pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default output and input. Reads and writes go through PipeWire; nothing is cached here.
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null

    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false
    readonly property string sinkName: ready ? (sink.nickname || sink.description || sink.name) : ""

    readonly property bool micReady: source !== null && source.ready && source.audio !== null
    readonly property real micVolume: micReady ? source.audio.volume : 0
    readonly property bool micMuted: micReady ? source.audio.muted : true

    readonly property string glyph: !ready || muted || volume <= 0.001 ? "volume-off" : volume < 0.34 ? "volume-3" : volume < 0.67 ? "volume-2" : "volume"

    function setVolume(v: real): void {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(1.5, v));
    }
    function nudge(delta: real): void {
        setVolume(volume + delta);
    }
    function toggleMute(): void {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function setMicVolume(v: real): void {
        if (micReady)
            source.audio.volume = Math.max(0, Math.min(1.5, v));
    }
    function toggleMicMute(): void {
        if (micReady)
            source.audio.muted = !source.audio.muted;
    }

    // PipeWire node properties are only live while tracked.
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
}
