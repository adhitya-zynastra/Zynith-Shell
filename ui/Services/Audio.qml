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

    // as the native glyphs: muted or 0 % → off, under 40 % → low, else high
    readonly property string glyph: !ready || muted || Math.round(volume * 100) === 0 ? "volume-off" : volume < 0.4 ? "volume-2" : "volume"

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

    // ── devices and apps (the Audio module and page) ──
    // hardware outputs and inputs, and what apps are playing or recording
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    // app streams by direction; Zynith's own (the spectrum's capture) is not an app to mix. Only what the
    // registry gives unbound is read here (type, name): reading a bound property in these lists would loop.
    readonly property var playback: Pipewire.nodes.values.filter(n => n.audio && n.type === PwNodeType.AudioOutStream && n.name !== "zynith-spectrum")
    readonly property var recording: Pipewire.nodes.values.filter(n => n.audio && n.type === PwNodeType.AudioInStream && n.name !== "zynith-spectrum")

    function nodeName(n: PwNode): string {
        return n ? (n.nickname || n.description || n.name) : "";
    }
    // an app stream: who it is and what it plays
    function appName(n: PwNode): string {
        const p = n?.properties ?? {};
        return p["application.name"] || p["application.process.binary"] || n?.description || n?.name || "App";
    }
    function appIcon(n: PwNode): string {
        const p = n?.properties ?? {};
        return p["application.icon-name"] || p["application.process.binary"] || "";
    }
    function streamTitle(n: PwNode): string {
        const p = n?.properties ?? {};
        return p["media.title"] || p["media.name"] || "";
    }
    function setSink(n: PwNode): void {
        Pipewire.preferredDefaultAudioSink = n;
    }
    function setSource(n: PwNode): void {
        Pipewire.preferredDefaultAudioSource = n;
    }
    function setNodeVolume(n: PwNode, v: real): void {
        if (n?.ready && n.audio)
            n.audio.volume = Math.max(0, Math.min(1.5, v));
    }
    function toggleNodeMute(n: PwNode): void {
        if (n?.ready && n.audio)
            n.audio.muted = !n.audio.muted;
    }

    // PipeWire node properties are only live while tracked: the defaults here, an app's stream by the row
    // that shows it (tracking every node at once crashed Quickshell's PipeWire binding)
    PwObjectTracker {
        objects: [root.sink, root.source]
    }

}
