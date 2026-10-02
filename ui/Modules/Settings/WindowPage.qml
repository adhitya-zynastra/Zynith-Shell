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
            key: "config",
            title: "As configured",
            text: "The layout block in niri's config.kdl applies exactly as written. Zynith adds nothing."
        },
        {
            key: "scrolling",
            title: "Scrolling",
            text: "Windows open at the width they ask for on an endless strip; the view scrolls, centring the focused window when it does not fit."
        },
        {
            key: "tiling-like",
            title: "Tiling-like",
            text: "New windows take half the screen, so two share it side by side, with ⅓ · ½ · ⅔ · full presets. Existing windows are never resized when one opens; a third window still scrolls. niri has no master/stack tiling."
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
        tone: WindowBehaviour.status !== "" || !WindowBehaviour.included ? "accent" : "faint"
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        text: WindowBehaviour.status !== "" ? "Not applied: " + WindowBehaviour.status
            : !WindowBehaviour.included ? "niri's config.kdl does not include rice/layout.kdl, so the choice has no effect yet. Add  include \"rice/layout.kdl\"  after its layout block."
            : "Written to ~/.config/niri/rice/layout.kdl after niri has validated it; niri applies it at once. Windows already open keep their size."
    }
}
