import QtQuick
import qs.Common

// A quiet two-line toggle: glyph, title, state. Accent only when on.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""
    property bool on: false
    property bool more: false
    signal toggled
    signal opened

    implicitHeight: 58
    implicitWidth: 160

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusLg
        color: root.on ? Theme.accentSoft : Theme.hover
        border.width: Metrics.hairline
        border.color: root.on ? Theme.accentLine : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Motion.focus
            }
        }
    }

    Interactive {
        anchors.fill: parent
        radius: Metrics.radiusLg
        onClicked: root.toggled()
    }

    // a separate target on the right opens the full panel
    Item {
        id: moreArea
        visible: root.more
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.more ? 30 : 0

        Interactive {
            anchors.fill: parent
            anchors.margins: 4
            radius: Metrics.radiusMd
            onClicked: root.opened()
        }
        Icon {
            anchors.centerIn: parent
            name: "chevron-right"
            size: 14
            tone: "faint"
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Metrics.s4
        anchors.rightMargin: Metrics.s3 + moreArea.width
        spacing: Metrics.s3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 18
            tone: root.on ? "accent" : "muted"
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 30
            spacing: 1

            Label {
                width: parent.width
                role: "label"
                font.weight: Font.Medium
                text: root.title
            }
            Label {
                width: parent.width
                role: "caption"
                tone: "faint"
                text: root.detail
            }
        }
    }
}
