pragma Singleton

import QtQuick
import Quickshell

// What the UI may spend: panel keep-alive, visualizer bands and rate, thumbnail sizes, prefetch, sampling rates,
// decorative motion. It never decides how a surface looks — that is Material (Glass / Solid / Blur), the user's
// choice. The four Experience Profiles that once decided both are gone.
//
// The level follows power, not a picked profile:
//   full     plugged in (as far as the hardware recommends)
//   saving   on battery, or always when the user asked to save power (experience.toml efficiency = "save")
//   minimal  power saver on, or the battery low
// Under real pressure (power saver, battery low) Material may pause blur and shadows for the moment, and says so;
// the user's style is never rewritten. experience.toml [overrides] still sets single knobs.
Singleton {
    id: root

    readonly property var levels: ["minimal", "saving", "full"]
    readonly property var levelLabels: ({
            minimal: "Minimal",
            saving: "Saving power",
            full: "Full"
        })

    // "auto" (follow power) | "save" (spend little even when plugged in)
    readonly property string efficiency: Config.experience.efficiency === "save" ? "save" : "auto"
    function setEfficiency(name: string): void {
        Config.setEfficiency(name === "save" ? "save" : "auto");
    }

    // genuine pressure: the user or the battery asked for less
    readonly property string pressure: Power.powerSaver ? "power-saver" : Power.low ? "battery-low" : ""
    readonly property var pressureLabels: ({
            "power-saver": "Power saver",
            "battery-low": "Battery low",
            "battery": "On battery"
        })
    // a weak machine starts lower when plugged in (Hardware's own reading of the CPU, memory and GPU)
    readonly property bool modestHardware: Hardware.recommendedProfile === "performance"
    readonly property string level: pressure !== "" ? "minimal" : efficiency === "save" || Power.onBattery || modestHardware ? "saving" : "full"
    // why the level is below full right now, in words ("" when it is full)
    readonly property string limitedBy: pressure !== "" ? pressureLabels[pressure] : efficiency === "save" ? "Saving power" : Power.onBattery ? pressureLabels["battery"] : modestHardware ? "This hardware" : ""

    // Material reads this: blur and shadows pause while power is genuinely short (never because of a preference),
    // unless the user keeps them (experience.toml ease_effects = false)
    readonly property bool easeEffects: pressure !== "" && Config.experience.easeEffects !== false

    readonly property var table: ({
            minimal: {
                panelKeepAliveMs: 0,
                richEffects: false,           // animated previews, the spinning record, hero drift, the scrim
                visualizerQuality: "off",
                visualizerBands: 0,
                visualizerFps: 0,
                wallpaperQuality: "fast",
                thumbnailQuality: "low",
                thumbnailSize: 256,
                backgroundActivity: "minimal",
                updateIntervalMs: 4000,
                prefetchRadius: 4,
                artSize: 96
            },
            saving: {
                panelKeepAliveMs: 30000,
                richEffects: false,
                visualizerQuality: "standard",
                visualizerBands: 16,
                visualizerFps: 30,
                wallpaperQuality: "standard",
                thumbnailQuality: "standard",
                thumbnailSize: 384,
                backgroundActivity: "normal",
                updateIntervalMs: 2000,
                prefetchRadius: 16,
                artSize: 192
            },
            full: {
                panelKeepAliveMs: 120000,
                richEffects: true,
                visualizerQuality: "high",
                visualizerBands: 32,
                visualizerFps: 60,
                wallpaperQuality: "high",
                thumbnailQuality: "high",
                thumbnailSize: 512,
                backgroundActivity: "eager",
                updateIntervalMs: 1000,
                prefetchRadius: 48,
                artSize: 320
            }
        })

    readonly property var effective: Object.assign({}, table[level], Config.experience.overrides || {})

    // motion is the user's (Settings → Animation): reduce motion turns the decorative parts off, power does not
    readonly property bool reducedMotion: Config.experience.reducedMotion
    readonly property real animationScale: reducedMotion ? 0 : 1
    readonly property bool springs: !reducedMotion
    readonly property bool stagger: !reducedMotion

    readonly property bool richEffects: effective.richEffects === true && !reducedMotion
    readonly property string visualizerQuality: effective.visualizerQuality
    readonly property int visualizerBands: effective.visualizerBands
    readonly property int visualizerFps: effective.visualizerFps
    readonly property string wallpaperQuality: effective.wallpaperQuality
    readonly property string thumbnailQuality: effective.thumbnailQuality
    readonly property int thumbnailSize: effective.thumbnailSize
    readonly property string backgroundActivity: effective.backgroundActivity
    readonly property int updateIntervalMs: effective.updateIntervalMs
    readonly property int prefetchRadius: effective.prefetchRadius
    readonly property int artSize: effective.artSize
    readonly property int panelKeepAliveMs: effective.panelKeepAliveMs
}
