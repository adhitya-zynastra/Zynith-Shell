import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The output's (or the microphone's) level: an icon by level or muted, the percent if asked.
BarItem {
    id: root
    readonly property bool mic: opt("device") === "input"
    readonly property bool ready: mic ? Audio.micReady : Audio.ready
    readonly property real level: mic ? Audio.micVolume : Audio.volume
    readonly property bool muted: mic ? Audio.micMuted : Audio.muted
    shown: ready && !(mic && opt("hide_when_inactive") === true && !Core.micInUse)
    readonly property string glyph: muted ? ((opt("mute_glyph") || "") !== "" ? opt("mute_glyph") : (mic ? "microphone-off" : "volume-off")) : (opt("glyph") || "") !== "" ? opt("glyph") : mic ? "microphone" : Audio.glyph

    BarGlyph {
        item: root
        name: root.glyph
        colour: root.muted ? Theme.colour(root.opt("mute_color") ?? "error") : root.iconInk
    }
    BarText {
        item: root
        visible: root.vertical ? (root.bar?.readouts ?? true) && root.opt("readout") !== false : root.opt("show_label") !== false
        muted: true
        text: root.muted ? "" : Math.round(root.level * 100)
    }
}
