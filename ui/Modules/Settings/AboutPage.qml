import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "About"
        caption: "Zynith " + About.zynithVersion
    }

    Card {
        width: parent.width
        caption: "Software"

        Repeater {
            model: [["Zynith", About.zynithVersion], ["niri", About.niriVersion], ["Quickshell", About.quickshellVersion], ["Operating system", About.os], ["Kernel", About.kernel]]
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: parent.modelData[0]
                }
                Label {
                    anchors.right: parent.right
                    role: "label"
                    tone: "muted"
                    text: parent.modelData[1]
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Licenses"

        Repeater {
            model: ["Zynith is free software under the GNU GPL v3.0.", "Built on Noctalia (MIT, © 2026 noctalia-dev); its notice is kept in LICENSES/Noctalia-MIT.txt.", "UI fonts Inter and Space Grotesk: SIL Open Font License 1.1.", "Icons: Tabler Icons (MIT).", "Runs on Quickshell (LGPL-3.0 / GPL-3.0) and niri (GPL-3.0)."]
            delegate: Label {
                required property string modelData
                width: parent.width
                role: "label"
                tone: "muted"
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: modelData
            }
        }
    }
}
