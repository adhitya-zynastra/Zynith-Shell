import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    shown: Power.present
    onClicked: bar?.openPanel("home", root)

    Icon {
        name: Power.glyph
        tone: Power.level < 0.15 && !Power.charging ? "accent" : "ink"
    }
    Label {
        visible: !root.vertical
        role: "label"
        numeric: true
        tone: "muted"
        text: Math.round(Power.level * 100)
    }
}
