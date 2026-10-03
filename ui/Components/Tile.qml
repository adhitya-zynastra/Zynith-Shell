import QtQuick
import qs.Common

// A quiet two-line toggle: glyph, title, state. Accent only when on. A right click, or the chevron when
// there is one, opens what it summarises (the native Control Center's right click).
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

    // a press gives a little
    scale: main.pressed ? 0.97 : 1
    Glide on scale {
        epsilon: 0.001
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusLg
        color: root.on ? Theme.accentSoft : Theme.hover
        border.width: Metrics.hairline
        border.color: root.on ? Theme.accentLine : "transparent"

        Behavior on color {
            ColorAnim {}
        }
        Behavior on border.color {
            ColorAnim {}
        }
    }

    Interactive {
        id: main
        anchors.fill: parent
        radius: Metrics.radiusLg
        onClicked: mouse => mouse.button === Qt.RightButton && root.more ? root.opened() : root.toggled()
    }

    // a separate target on the right opens the full page
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
        anchors.leftMargin: Metrics.s3
        anchors.rightMargin: Metrics.s3 + moreArea.width
        spacing: Metrics.s3

        // the glyph on a badge that fills with the accent when on
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: root.on ? Metrics.radiusMd : 17
            color: root.on ? Theme.accent : Theme.well
            Behavior on color {
                ColorAnim {}
            }
            Behavior on radius {
                Anim {
                    role: "spatialFast"
                }
            }
            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: 17
                color: root.on ? Theme.onAccent : Theme.inkMuted
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 34 - Metrics.s3
            spacing: 1

            Label {
                width: parent.width
                role: "label"
                font.weight: Font.Medium
                elide: Text.ElideRight
                text: root.title
            }
            Label {
                visible: text !== ""
                width: parent.width
                role: "caption"
                tone: "faint"
                elide: Text.ElideRight
                text: root.detail
            }
        }
    }
}
