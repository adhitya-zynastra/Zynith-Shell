import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Every bar is an edge, an anchor along it, and a visibility rule. Changes apply live.
Column {
    id: root

    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Bars"
        caption: Config.bars.length + (Config.bars.length === 1 ? " bar" : " bars")
    }

    Repeater {
        model: Config.bars

        delegate: Card {
            id: card
            required property var modelData
            required property int index
            width: root.width
            caption: modelData.id ?? ("bar " + index)

            Repeater {
                model: [
                    {
                        key: "edge",
                        label: "Edge",
                        options: ["top", "bottom", "left", "right"]
                    },
                    {
                        key: "anchor",
                        label: "Anchor",
                        options: ["start", "center", "end", "fill"]
                    },
                    {
                        key: "visibility",
                        label: "Visibility",
                        options: ["always", "smart", "autohide"]
                    }
                ]
                delegate: Row {
                    required property var modelData
                    width: card.width - Metrics.s5 * 2
                    spacing: Metrics.s4

                    Label {
                        width: 90
                        anchors.verticalCenter: parent.verticalCenter
                        role: "caption"
                        tone: "faint"
                        caps: true
                        text: parent.modelData.label
                    }
                    Segmented {
                        width: parent.width - 90 - Metrics.s4
                        current: card.modelData[parent.modelData.key] ?? (parent.modelData.key === "visibility" ? "always" : parent.modelData.key === "anchor" ? "center" : "top")
                        options: parent.modelData.options.map(o => ({
                                    key: o,
                                    label: o.charAt(0).toUpperCase() + o.slice(1)
                                }))
                        onPicked: key => Config.updateBar(card.index, parent.modelData.key, key)
                    }
                }
            }

            Label {
                width: parent.width
                role: "caption"
                tone: "faint"
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: "Widgets: " + ["start", "center", "end"].map(s => (card.modelData.widgets?.[s] ?? []).join(", ") || "—").join("  |  ")
            }
        }
    }
}
