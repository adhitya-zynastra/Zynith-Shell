import QtQuick
import qs.Common

// A panel's primary state, read at a glance and set in place: the thing itself as a tile (clicking it is its quick
// action — mute, off), what it is and what it is doing, its value large, and its one continuous control under them.
// Each per-icon panel leads with one (Sound: where it plays; Wi‑Fi: the connection; Displays: brightness); its
// choices follow below it.
//
//   icon, iconOn (the tile lit: on, playing), iconClicked
//   caption (data voice, above the name) · title · detail
//   value, unit (the readout; empty: none) · trailing (anything in the corner instead, a Toggle)
//   level (0..1; < 0: no slider), dimmed (the level is set but not heard: muted), levelMoved(v)
Plate {
    id: root

    property string icon: ""
    property bool iconOn: true
    property bool iconInteractive: true
    signal iconClicked
    property string caption: ""
    property string title: ""
    property string detail: ""
    property string value: ""
    property string unit: ""
    property real level: -1
    property bool dimmed: false
    property bool wheelAdjusts: true
    signal levelMoved(real v)
    default property alias trailing: corner.data

    readonly property int pad: Metrics.s4
    implicitHeight: body.implicitHeight + pad * 2

    Column {
        id: body
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: Metrics.s4

        Item {
            width: parent.width
            height: Math.max(tile.height, words.implicitHeight)

            Rectangle {
                id: tile
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: Metrics.radiusMd
                color: root.iconOn ? Theme.signalFill : Theme.well
                border.width: root.iconOn ? 1 : 0
                border.color: Theme.signalEdge
                Behavior on color {
                    ColorAnim {}
                }
                Icon {
                    anchors.centerIn: parent
                    name: root.icon
                    size: 22
                    tone: root.iconOn ? "accent" : "faint"
                }
                Interactive {
                    anchors.fill: parent
                    radius: parent.radius
                    enabled: root.iconInteractive
                    onClicked: root.iconClicked()
                }
            }
            Column {
                id: words
                anchors.left: tile.right
                anchors.leftMargin: Metrics.s4
                anchors.right: readout.left
                anchors.rightMargin: Metrics.s3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    visible: root.caption !== ""
                    role: "data"
                    tone: "faint"
                    text: root.caption
                }
                Label {
                    width: parent.width
                    role: "title"
                    elide: Text.ElideRight
                    text: root.title
                }
                Label {
                    visible: root.detail !== ""
                    width: parent.width
                    role: "caption"
                    tone: "muted"
                    elide: Text.ElideRight
                    text: root.detail
                }
            }
            Item {
                id: readout
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(number.visible ? number.implicitWidth : 0, corner.childrenRect.width)
                height: Math.max(number.visible ? number.implicitHeight : 0, corner.childrenRect.height)
                Readout {
                    id: number
                    visible: root.value !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    size: "headline"
                    value: root.value
                    unit: root.unit
                    tone: root.dimmed ? "faint" : "ink"
                }
                Item {
                    id: corner
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: childrenRect.width
                    height: childrenRect.height
                }
            }
        }

        Slider {
            visible: root.level >= 0
            width: parent.width
            wheelAdjusts: root.wheelAdjusts
            value: Math.max(0, root.level)
            opacity: root.dimmed ? 0.5 : 1
            onMoved: v => root.levelMoved(v)
        }
    }
}
