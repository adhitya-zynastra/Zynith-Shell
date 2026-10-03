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
    signal picked(string id)

    implicitHeight: row.height + indicator.height + Metrics.s2 + separator.height

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
                height: content.implicitHeight + Metrics.s3 * 2

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Metrics.radiusPlate
                    color: area.containsMouse && !tab.isCurrent ? Theme.hover : "transparent"
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                Column {
                    id: content
                    anchors.centerIn: parent
                    spacing: 3
                    Icon {
                        visible: root.showIcons
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: tab.modelData.icon ?? ""
                        size: 18
                        color: tab.isCurrent ? Theme.accent : Theme.inkMuted
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Label {
                        visible: root.showLabels
                        anchors.horizontalCenter: parent.horizontalCenter
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
        readonly property int i: root.tabs.findIndex(t => t.id === root.current)
        readonly property Item tabItem: i >= 0 ? repeater.itemAt(i) : null
        readonly property real slot: row.width / Math.max(1, root.tabs.length)
        visible: i >= 0
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
        anchors.top: indicator.bottom
        anchors.topMargin: Metrics.s1
        width: parent.width
        height: Metrics.hairline
        color: Theme.hairline
    }
}
