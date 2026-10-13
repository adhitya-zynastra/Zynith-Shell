pragma Singleton

import QtQuick
import Quickshell
import qs.Services

// Type roles. Inter for reading, Space Grotesk for numerals and display, the Tabler font for glyphs.
Singleton {
    id: root

    readonly property FontLoader interFont: FontLoader {
        source: Paths.asset("fonts/Inter.ttf")
    }
    readonly property FontLoader groteskFont: FontLoader {
        source: Paths.asset("fonts/SpaceGrotesk.ttf")
    }
    readonly property FontLoader iconFont: FontLoader {
        source: Paths.repoAsset("fonts/noctalia-tabler.ttf")
    }

    // appearance.toml font_ui / font_display / font_mono choose others; empty keeps Zynith's own
    readonly property string bundledUi: interFont.status === FontLoader.Ready ? interFont.name : "Adwaita Sans"
    // the variable font registers its default instance as "Space Grotesk Light"; the family name keeps weights working
    readonly property string bundledDisplay: groteskFont.status === FontLoader.Ready ? "Space Grotesk" : bundledUi
    readonly property string ui: (Config.appearance.font_ui ?? "") !== "" ? Config.appearance.font_ui : bundledUi
    readonly property string display: (Config.appearance.font_display ?? "") !== "" ? Config.appearance.font_display : bundledDisplay
    readonly property string mono: (Config.appearance.font_mono ?? "") !== "" ? Config.appearance.font_mono : "JetBrains Mono"
    readonly property string icons: iconFont.status === FontLoader.Ready ? iconFont.name : "noctalia-tabler-icons"

    // pixel sizes, scaled by appearance.toml font_scale
    readonly property real scale: Math.max(0.8, Math.min(1.5, Config.appearance.font_scale ?? 1))
    readonly property int micro: Math.round(10 * scale)
    readonly property int caption: Math.round(11 * scale)
    readonly property int label: Math.round(12 * scale)
    readonly property int body: Math.round(13 * scale)
    readonly property int title: Math.round(15 * scale)
    readonly property int headline: Math.round(20 * scale)
    readonly property int display2: Math.round(32 * scale)
    readonly property int display1: Math.round(44 * scale)
    readonly property int displayXL: Math.round(96 * scale)
    // the data voice: values, units, keys, section heads — mono, uppercase, tracked, tabular
    readonly property int data: Math.round(10.5 * scale)
    readonly property real dataTracking: 1.3

    // uppercase captions are tracked out; everything else is set tight
    readonly property real tracking: 1.4
    readonly property var tabular: ({
            tnum: 1
        })
}
