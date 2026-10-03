import QtQuick
import qs.Common
import qs.Services

// A row of tabs across the top of a surface, with one indicator that slides to the current tab (Caelestia's
// dashboard tabs). Which tabs and in what order is the caller's (from config); each is { id, label, icon }.
Item {
    id: root

    property var tabs: []
    property string current: ""
    property bool showIcons: true
    property bool showLabels: true
    // stacked (icon over label, an underline that slides) | inline (icon beside label, a pill that slides)
    property string style: "inline"
    readonly property bool inline: style === "inline"
    signal picked(string id)

    implicitHeight: inline ? row.height : row.height + indicator.height + Metrics.s2 + separator.height

    // inline: the pill under the current tab, sliding between them
    Rectangle {
        id: pill
        visible: root.inline && indicator.i >= 0
        x: indicator.i * indicator.slot + 3
        width: indicator.slot - 6
        height: row.height
        radius: height / 2
        color: Theme.alpha(Theme.accent, 0.16)
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.35)
        Behavior on x {
            Anim {
                role: "spatial"
            }
        }
    }

    Row {
        id: row
        width: parent.width
        Repeater {
            id: repeater
            model: root.tabs
            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool isCurrent: modelData.id === root.current
                readonly property real contentWidth: content.implicitWidth
                width: row.width / Math.max(1, root.tabs.length)
                height: root.inline ? 34 : content.implicitHeight + Metrics.s3 * 2

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: area.containsMouse && !tab.isCurrent ? Theme.hover : "transparent"
                    radius: root.inline ? height / 2 : Metrics.radiusPlate
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                Grid {
                    id: content
                    anchors.centerIn: parent
                    columns: root.inline ? 2 : 1
                    spacing: root.inline ? Metrics.s2 : 3
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Icon {
                        visible: root.showIcons
                        name: tab.modelData.icon ?? ""
                        size: root.inline ? 15 : 18
                        color: tab.isCurrent ? Theme.accent : Theme.inkMuted
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Label {
                        visible: root.showLabels
                        role: "label"
                        tone: tab.isCurrent ? "accent" : "muted"
                        text: tab.modelData.label ?? tab.modelData.id
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(tab.modelData.id)
                }
            }
        }
    }

    // the indicator: as wide as the current tab's content, sliding between tabs
    Rectangle {
        id: indicator
        visible: !root.inline && i >= 0
        readonly property int i: root.tabs.findIndex(t => t.id === root.current)
        readonly property Item tabItem: i >= 0 ? repeater.itemAt(i) : null
        readonly property real slot: row.width / Math.max(1, root.tabs.length)
        anchors.top: row.bottom
        anchors.topMargin: Metrics.s1
        width: tabItem ? Math.max(24, tabItem.contentWidth) : 0
        height: 3
        radius: 1.5
        x: i * slot + (slot - width) / 2
        color: Theme.accent
        Behavior on x {
            Anim {
                role: "spatial"
            }
        }
        Behavior on width {
            Anim {
                role: "spatial"
            }
        }
    }
    Rectangle {
        id: separator
        visible: !root.inline
        anchors.top: indicator.bottom
        anchors.topMargin: Metrics.s1
        width: parent.width
        height: Metrics.hairline
        color: Theme.hairline
    }
}
