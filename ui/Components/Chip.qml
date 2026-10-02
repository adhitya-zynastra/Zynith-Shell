import QtQuick
import qs.Common

// A small rounded choice: a view, a filter, a category. The active one is tinted with the accent and carries
// a hairline, so a row of them reads like a tab strip without being one.
Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool active: false
    property int count: -1          // shown after the text when 0 or more
    signal clicked

    implicitHeight: 28
    implicitWidth: row.implicitWidth + Metrics.s4 * 2

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.active ? Theme.accentSoft : area.containsMouse ? Theme.hover : "transparent"
        border.width: root.active ? Metrics.hairline : 0
        border.color: Theme.accentLine

        Behavior on color {
            ColorAnimation {
                duration: Motion.focus
                easing.type: Motion.standardEasing
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.s2

        Icon {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 14
            tone: root.active ? "accent" : "muted"
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            role: "label"
            tone: root.active ? "accent" : "muted"
            font.weight: root.active ? Font.Medium : Font.Normal
            text: root.text
        }
        Label {
            visible: root.count >= 0
            anchors.verticalCenter: parent.verticalCenter
            role: "caption"
            numeric: true
            tone: "faint"
            text: root.count
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
