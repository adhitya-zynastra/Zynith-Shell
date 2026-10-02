pragma Singleton

import QtQuick
import Quickshell

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

    readonly property string ui: interFont.status === FontLoader.Ready ? interFont.name : "Adwaita Sans"
    readonly property string display: groteskFont.status === FontLoader.Ready ? groteskFont.name : ui
    readonly property string mono: "JetBrains Mono"
    readonly property string icons: iconFont.status === FontLoader.Ready ? iconFont.name : "noctalia-tabler-icons"

    // pixel sizes
    readonly property int micro: 10
    readonly property int caption: 11
    readonly property int label: 12
    readonly property int body: 13
    readonly property int title: 15
    readonly property int headline: 20
    readonly property int display1: 44

    // uppercase captions are tracked out; everything else is set tight
    readonly property real tracking: 1.4
    readonly property var tabular: ({
            tnum: 1
        })
}
