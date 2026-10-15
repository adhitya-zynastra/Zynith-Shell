pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common
import "../Common/MaterialModel.js" as Model

// The one place that decides what Zynith's surfaces are made of: Glass, Solid or Blur (Settings → Appearance →
// Surface style), at the strength the user chose. Theme, Glass, BlurRegion and every surface read it; no
// component picks its own opacity, blur or depth. The numbers are Common/MaterialModel.js (tested).
//
// Blur is the compositor's: Zynith asks niri to blur behind a surface (ext-background-effect) and niri's strength
// comes from the native shell's [shell.glass] blur_strength (written to ~/.config/niri/rice/glass.kdl). Whether
// that is in place is read, not assumed (blurAvailable); when it is not, Settings says so and the Blur style
// draws a denser tint instead of pretending.
Singleton {
    id: root

    readonly property var look: Config.appearance
    readonly property string style: Model.styles.indexOf(look.surface_style) >= 0 ? look.surface_style : "glass"
    readonly property real glassStrength: Model.clamp01(look.glass_strength ?? 0.5)
    readonly property real blurStrength: Model.clamp01(look.blur_strength ?? 0.5)
    readonly property var levels: Model.levels

    // niri, with the shell's blur block in place
    readonly property bool onNiri: Workspaces.niri
    property bool blurBlock: false
    readonly property bool blurAvailable: onNiri && blurBlock
    FileView {
        path: Paths.home + "/.config/niri/rice/glass.kdl"
        watchChanges: true
        printErrors: false
        onLoaded: root.blurBlock = /(^|\n)\s*blur\s*\{/.test(text())
        onLoadFailed: root.blurBlock = false
        onFileChanged: reload()
    }

    readonly property var resolved: Model.resolve(style, glassStrength, blurStrength, {
        blurAvailable: blurAvailable,
        easeEffects: ExperiencePolicy.easeEffects
    })
    // what surfaces read
    readonly property bool blur: resolved.blur
    readonly property real fillAlpha: resolved.fillAlpha
    readonly property real raisedAlpha: resolved.raisedAlpha
    readonly property real edgeAlpha: resolved.edgeAlpha
    readonly property real sheenAlpha: resolved.sheenAlpha
    readonly property real wellAlpha: resolved.wellAlpha
    readonly property bool shadows: resolved.shadows
    readonly property real shadowDepth: resolved.shadowDepth
    readonly property bool solid: style === "solid"
    // what is set aside for now, and why (for Settings to say plainly)
    readonly property var paused: resolved.paused
    readonly property string pausedText: paused.includes("blur-unavailable") ? (onNiri ? "No blur here: niri's blur block is missing from rice/glass.kdl" : "No blur here: the compositor does not offer it") : paused.includes("blur") || paused.includes("shadows") ? "Blur and shadows paused for now: " + ExperiencePolicy.limitedBy.toLowerCase() : ""
    function levelOf(strength: real): string {
        return Model.levelOf(strength);
    }

    // writers (Settings): each is one key of appearance.toml; Blur Strength also sets niri's blur
    function setStyle(name: string): void {
        Config.setAppearance("surface_style", Model.styles.indexOf(name) >= 0 ? name : "glass");
    }
    function setGlassStrength(v: real): void {
        Config.setAppearance("glass_strength", Math.round(Model.clamp01(v) * 100) / 100);
    }
    function setBlurStrength(v: real): void {
        Config.setAppearance("blur_strength", Math.round(Model.clamp01(v) * 100) / 100);
    }

    // niri follows the style (only the shell process writes, and only on a change): its global blur strength
    // (Glass: the faintest, Blur: the chosen strength; niri has one blur, and only one style is in use) through the
    // native shell's [shell.glass] blur_strength, and whether the backdrop is the wallpaper (xray, Glass) or what is
    // really behind (Blur) through rice/materials.kdl, which NiriConfig validates before installing.
    readonly property int nativeBlurStrength: resolved.nativeBlurStrength
    readonly property string backdrop: resolved.backdrop
    property int sentBlurStrength: -1
    property bool sendsNative: false
    onNativeBlurStrengthChanged: sendNative()
    onBackdropChanged: sendNative()
    onSendsNativeChanged: sendNative()
    function sendNative(): void {
        if (!sendsNative || !Config.loaded)
            return;
        if (nativeBlurStrength >= 0 && nativeBlurStrength !== sentBlurStrength) {
            sentBlurStrength = nativeBlurStrength;
            CoreClient.call("settings-set " + JSON.stringify({
                path: ["shell", "glass", "blur_strength"],
                value: nativeBlurStrength
            }));
        }
        if (onNiri)
            NiriConfig.apply("materials", Model.niriFragment(backdrop));
    }
    readonly property bool niriRulesIncluded: NiriConfig.isIncluded("materials")
    readonly property Connections whenLoaded: Connections {
        target: Config
        function onLoadedChanged(): void {
            root.sendNative();
        }
    }
    Component.onCompleted: Qt.callLater(sendNative)
}
