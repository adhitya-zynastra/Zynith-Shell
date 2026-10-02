import QtQuick
import qs.Common
import qs.Components
import qs.Services

// niri lays windows out as scrollable columns. "Tiling-like" tunes those columns to share the screen;
// it does not turn niri into a master/stack tiler, and nothing resizes windows behind your back.
Column {
    id: root

    spacing: Metrics.s5

    readonly property var choices: [
        {
            key: "scrolling",
            title: "Scrolling",
            text: "Windows open beside each other on an endless strip and the view scrolls to them. niri's own way."
        },
        {
            key: "tiling-like",
            title: "Tiling-like",
            text: "New columns open at half the screen, with ⅓ · ½ · ⅔ · full presets and expand / center actions. Existing windows are never resized when one opens; a third column still scrolls."
        }
    ]

    PanelHeader {
        width: parent.width
        title: "Window behaviour"
        caption: "Applied through generated niri configuration"
    }

    Repeater {
        model: root.choices

        delegate: Item {
            required property var modelData
            readonly property bool current: Config.window.behaviour === modelData.key
            width: root.width
            height: 84

            Rectangle {
                anchors.fill: parent
                radius: Metrics.radiusLg
                color: parent.current ? Theme.accentSoft : Theme.surfaceLow
                border.width: Metrics.hairline
                border.color: parent.current ? Theme.accentLine : Theme.hairline
            }
            Interactive {
                anchors.fill: parent
                radius: Metrics.radiusLg
                onClicked: Config.setWindowBehaviour(parent.modelData.key)
            }
            Column {
                anchors.fill: parent
                anchors.margins: Metrics.s4
                spacing: Metrics.s1
                Label {
                    role: "title"
                    text: parent.parent.modelData.title
                }
                Label {
                    width: parent.width
                    role: "label"
                    tone: "muted"
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    text: parent.parent.modelData.text
                }
            }
        }
    }

    Label {
        width: root.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        text: "The choice is stored now; the native shell writes ~/.config/niri/rice/layout.kdl from it (validated with niri validate, applied by niri's live reload). Until that generator ships, this records your preference only."
    }
}
