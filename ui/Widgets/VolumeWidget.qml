import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Zynith.Native

// The output's (or the microphone's) level: an icon by level or muted, the percent if asked.
BarItem {
    id: root
    readonly property bool mic: opt("device") === "input"
    readonly property bool ready: mic ? Audio.micReady : Audio.ready
    readonly property real level: mic ? Audio.micVolume : Audio.volume
    readonly property bool muted: mic ? Audio.micMuted : Audio.muted
    shown: ready && !(mic && opt("hide_when_inactive") === true && !Core.micInUse)
    // effects_profile_glyphs (native): an icon for the EasyEffects profile in use, asked of the native shell
    // only while a table is set
    readonly property var profileGlyphs: opt("effects_profile_glyphs") ?? ({})
    readonly property bool watchesProfile: Object.keys(profileGlyphs).length > 0
    property string effectsProfile: ""
    function readProfile(): void {
        CoreClient.call("effects-status", text => {
            try {
                const d = JSON.parse(text);
                root.effectsProfile = (root.mic ? d.input?.active : d.output?.active) ?? "";
            } catch (e) {}
        });
    }
    Timer {
        running: root.watchesProfile && root.shown
        interval: Math.max(2000, ExperiencePolicy.updateIntervalMs)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readProfile()
    }
    readonly property string profileGlyph: effectsProfile !== "" ? (profileGlyphs[effectsProfile] ?? "") : ""
    readonly property string glyph: muted ? ((opt("mute_glyph") || "") !== "" ? opt("mute_glyph") : (mic ? "microphone-off" : "volume-off")) : profileGlyph !== "" ? profileGlyph : (opt("glyph") || "") !== "" ? opt("glyph") : mic ? "microphone" : Audio.glyph

    BarGlyph {
        item: root
        name: root.glyph
        colour: root.muted ? Theme.colour(root.opt("mute_color") ?? "error") : root.iconInk
    }
    BarText {
        item: root
        visible: root.vertical ? (root.bar?.readouts ?? false) && root.opt("readout") !== false : root.opt("show_label") !== false
        muted: true
        text: root.muted ? "" : Math.round(root.level * 100)
    }
}
