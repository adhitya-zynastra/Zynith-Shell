pragma Singleton

import QtQuick
import Quickshell

// Every quality/cost knob in the UI comes from here. Components read `ExperiencePolicy.<knob>` and never
// branch on the profile name themselves, so tuning a profile is an edit to the table below (or a
// per-knob override in shell.json), not a search through the QML.
Singleton {
    id: root

    readonly property var profiles: ["performance", "balanced", "enhanced", "max"]
    readonly property var labels: ({
            performance: "Performance",
            balanced: "Balanced",
            enhanced: "Enhanced",
            max: "Max Experience"
        })

    readonly property string selected: Config.experience.profile
    readonly property string hardwareProfile: Hardware.recommendedProfile

    // Automatic mode also follows power: at most Balanced on battery, Performance when the battery is low
    // or power saving is on. A profile the user picked is never changed.
    readonly property bool adaptive: Config.experience.adaptive
    readonly property string limitReason: !adaptive ? "" : Power.powerSaver ? "power-saver" : Power.low ? "battery-low" : Power.onBattery ? "battery" : ""
    readonly property var limitLabels: ({
            "power-saver": "Power saver",
            "battery-low": "Battery low",
            "battery": "On battery"
        })
    readonly property string recommended: {
        if (limitReason === "power-saver" || limitReason === "battery-low")
            return "performance";
        if (limitReason === "battery" && profiles.indexOf(hardwareProfile) > profiles.indexOf("balanced"))
            return "balanced";
        return hardwareProfile;
    }
    // why automatic mode is below the hardware recommendation right now, or ""
    readonly property string limitedBy: automatic && recommended !== hardwareProfile ? limitLabels[limitReason] ?? "" : ""
    readonly property string profile: profiles.includes(selected) ? selected : recommended
    readonly property bool automatic: !profiles.includes(selected)

    readonly property var table: ({
            performance: {
                panelKeepAliveMs: 0,     // closed panels stay ready this long, hidden and idle
                animationQuality: "reduced",   // short fades, no springs, no stagger
                animationScale: 0.6,
                springs: false,
                stagger: false,
                blurQuality: "off",
                glassOpacity: 0.94,
                shadowQuality: "none",
                effectsQuality: "minimal",     // no sheen, no glow, no hover lift
                visualizerQuality: "off",
                visualizerBands: 0,
                visualizerFps: 0,
                wallpaperQuality: "fast",
                wallpaperTransitionMs: 250,
                thumbnailQuality: "low",
                thumbnailSize: 256,
                backgroundActivity: "minimal", // nothing ahead of need
                updateIntervalMs: 4000,        // samplers while something shows them
                prefetchRadius: 4,
                artSize: 96
            },
            balanced: {
                panelKeepAliveMs: 30000,     // closed panels stay ready this long, hidden and idle
                animationQuality: "standard",
                animationScale: 1.0,
                springs: true,
                stagger: true,
                blurQuality: "standard",
                glassOpacity: 0.72,
                shadowQuality: "soft",
                effectsQuality: "standard",
                visualizerQuality: "standard",
                visualizerBands: 16,
                visualizerFps: 30,
                wallpaperQuality: "standard",
                wallpaperTransitionMs: 700,
                thumbnailQuality: "standard",
                thumbnailSize: 384,
                backgroundActivity: "normal",
                updateIntervalMs: 2000,
                prefetchRadius: 16,
                artSize: 192
            },
            enhanced: {
                panelKeepAliveMs: 120000,     // closed panels stay ready this long, hidden and idle
                animationQuality: "rich",
                animationScale: 1.0,
                springs: true,
                stagger: true,
                blurQuality: "high",
                glassOpacity: 0.62,
                shadowQuality: "layered",
                effectsQuality: "rich",
                visualizerQuality: "high",
                visualizerBands: 32,
                visualizerFps: 60,
                wallpaperQuality: "high",
                wallpaperTransitionMs: 900,
                thumbnailQuality: "high",
                thumbnailSize: 512,
                backgroundActivity: "eager",
                updateIntervalMs: 1000,
                prefetchRadius: 48,
                artSize: 320
            },
            max: {
                panelKeepAliveMs: 600000,     // closed panels stay ready this long, hidden and idle
                animationQuality: "cinematic",
                animationScale: 1.1,
                springs: true,
                stagger: true,
                blurQuality: "high",
                glassOpacity: 0.55,
                shadowQuality: "layered",
                effectsQuality: "max",
                visualizerQuality: "max",
                visualizerBands: 48,
                visualizerFps: 0,              // 0 = the output's refresh rate
                wallpaperQuality: "max",
                wallpaperTransitionMs: 1100,
                thumbnailQuality: "max",
                thumbnailSize: 768,
                backgroundActivity: "eager",
                updateIntervalMs: 1000,
                prefetchRadius: 96,
                artSize: 512
            }
        })

    readonly property var effective: Object.assign({}, table[profile], Config.experience.overrides || {})

    readonly property bool reducedMotion: Config.experience.reducedMotion

    readonly property string animationQuality: effective.animationQuality
    readonly property real animationScale: reducedMotion ? 0 : effective.animationScale
    readonly property bool springs: effective.springs && !reducedMotion
    readonly property bool stagger: effective.stagger && !reducedMotion
    readonly property string blurQuality: effective.blurQuality
    readonly property bool blur: blurQuality !== "off"
    readonly property real glassOpacity: effective.glassOpacity
    readonly property string shadowQuality: effective.shadowQuality
    readonly property bool shadows: shadowQuality !== "none"
    readonly property string effectsQuality: effective.effectsQuality
    readonly property bool richEffects: effectsQuality === "rich" || effectsQuality === "max"
    readonly property string visualizerQuality: effective.visualizerQuality
    readonly property int visualizerBands: effective.visualizerBands
    readonly property int visualizerFps: effective.visualizerFps
    readonly property string wallpaperQuality: effective.wallpaperQuality
    readonly property int wallpaperTransitionMs: effective.wallpaperTransitionMs
    readonly property string thumbnailQuality: effective.thumbnailQuality
    readonly property int thumbnailSize: effective.thumbnailSize
    readonly property string backgroundActivity: effective.backgroundActivity
    readonly property int updateIntervalMs: effective.updateIntervalMs
    readonly property int prefetchRadius: effective.prefetchRadius
    readonly property int artSize: effective.artSize
    readonly property int panelKeepAliveMs: effective.panelKeepAliveMs

    function select(name: string): void {
        Config.setExperienceProfile(name === "auto" || profiles.includes(name) ? name : "auto");
    }
}
