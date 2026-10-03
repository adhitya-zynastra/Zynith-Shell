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

    // a neutral plate; on, its edge takes the accent as light (Optics: never a painted tile)
    Plate {
        anchors.fill: parent
        radius: Metrics.radiusPlate
    }
    // on: a breath of the accent in the face and an exposure mark on the leading edge — light, not paint,
    // so a panel with several things on is still calm
    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusPlate
        color: Theme.signalFill
        opacity: root.on ? 1 : 0
        Behavior on opacity {
            Anim {
                role: "effects"
            }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.on ? parent.height * 0.42 : 0
        radius: 1
        color: Theme.accent
        Behavior on height {
            Anim {
                role: "spatialFast"
            }
        }
    }

    Interactive {
        id: main
        anchors.fill: parent
        radius: Metrics.radiusPlate
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

        // the glyph: the accent's when on, quiet otherwise
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: 18
                color: root.on ? Theme.accent : Theme.inkMuted
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
                tone: root.on ? "muted" : "faint"
                elide: Text.ElideRight
                text: root.detail
            }
        }
    }
}
