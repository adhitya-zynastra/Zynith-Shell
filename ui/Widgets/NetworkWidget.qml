import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    onClicked: bar?.openPanel("home", root)

    Icon {
        name: Network.glyph
        tone: Network.connected ? "ink" : "faint"
    }
    Label {
        visible: root.hovered && !root.vertical && Network.name !== ""
        role: "label"
        tone: "muted"
        text: Network.name
    }
}
