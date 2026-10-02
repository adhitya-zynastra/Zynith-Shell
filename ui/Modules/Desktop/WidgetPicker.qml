import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Every kind of desktop widget, each shown live with its defaults; a click places one in the middle of the
// screen. The cards arrive one after another.
Item {
    id: root
    signal picked(string type)

    // the desktop behind dims a little more while choosing
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.base, 0.35 * card.p)
        TapHandler {
            onTapped: Desktop.picking = false
        }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, grid.cellWidth * 4 + Metrics.s5 * 2)
        height: header.height + grid.height + Metrics.s5 * 3
        radius: Metrics.radiusXl
        raised: true
        property real p: 0
        Component.onCompleted: p = 1
        Behavior on p {
            Anim {
                role: "spatial"
            }
        }
        opacity: Math.min(1, p * 1.4)
        scale: 0.94 + 0.06 * p

        TapHandler {}
        Column {
            x: Metrics.s5
            y: Metrics.s5
            width: parent.width - Metrics.s5 * 2
            spacing: Metrics.s4

            Item {
                id: header
                width: parent.width
                height: 32
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "headline"
                    font.weight: Font.Light
                    text: "Add a widget"
                }
                Label {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    tone: "faint"
                    text: "Esc closes"
                }
            }

            Grid {
                id: grid
                readonly property real cellWidth: 196
                columns: Math.max(2, Math.floor(parent.width / cellWidth))
                spacing: Metrics.s3

                Repeater {
                    model: WidgetTypes.types
                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        width: grid.cellWidth - Metrics.s3
                        height: 168
                        // one after another
                        readonly property real arrive: Math.max(0, Math.min(1, (card.p - index * 0.04) / 0.6))
                        opacity: arrive
                        transform: Translate {
                            y: (1 - tile.arrive) * 14
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusLg
                            color: area.containsMouse ? Theme.hover : Theme.well
                            border.width: Metrics.hairline
                            border.color: area.containsMouse ? Theme.accentLine : Theme.hairline
                            Behavior on color {
                                ColorAnim {}
                            }
                        }
                        // the widget itself, at its default size, scaled into the tile
                        Item {
                            id: stage
                            x: Metrics.s3
                            y: Metrics.s3
                            width: parent.width - Metrics.s3 * 2
                            height: parent.height - 44
                            clip: true
                            WidgetView {
                                readonly property real fit: Math.min(stage.width / width, stage.height / height, 1)
                                width: tile.modelData.size[0]
                                height: tile.modelData.size[1]
                                anchors.centerIn: parent
                                scale: fit
                                enabled: false
                                preview: true
                                // drawn at full size, then scaled as a texture: no colour fringes on small text
                                layer.enabled: true
                                layer.smooth: true
                                spec: ({
                                        type: tile.modelData.type,
                                        settings: {}
                                    })
                            }
                        }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.s4
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Metrics.s3
                            spacing: Metrics.s2
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: tile.modelData.icon
                                size: 14
                                tone: area.containsMouse ? "accent" : "muted"
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "label"
                                font.weight: Font.Medium
                                text: tile.modelData.label
                            }
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.picked(tile.modelData.type)
                        }
                    }
                }
            }
        }
    }
}
