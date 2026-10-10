import QtQuick
import qs.Common

// One row in a panel list: glyph, title, detail, trailing text. The whole row is the target.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""
    property string trailing: ""
    property bool active: false
    property bool busy: false
    signal clicked

    implicitHeight: 44
    implicitWidth: 300

    // the current row: a tone step and an exposure mark at its edge (not an accent fill)
    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusPlate
        color: Theme.plate
        opacity: root.active ? 1 : 0
        Behavior on opacity {
            Anim {
                role: "effects"
            }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.active ? parent.height * 0.42 : 0
        radius: 1
        color: Theme.accent
        Behavior on height {
            Anim {
                role: "spatialFast"
            }
        }
    }
    Interactive {
        anchors.fill: parent
        radius: Metrics.radiusPlate
        onClicked: root.clicked()
    }

    Icon {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        tone: root.active ? "accent" : "muted"
        opacity: root.busy ? 0.4 : 1

        SequentialAnimation on opacity {
            running: root.busy && !Motion.reduced
            loops: Animation.Infinite
            NumberAnimation {
                to: 1
                duration: Motion.ms(500)
            }
            NumberAnimation {
                to: 0.35
                duration: Motion.ms(500)
            }
        }
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: Metrics.s3
        anchors.right: tail.left
        anchors.rightMargin: Metrics.s2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            role: "body"
            font.weight: root.active ? Font.Medium : Font.Normal
            text: root.title
        }
        Label {
            visible: root.detail !== ""
            width: parent.width
            role: "caption"
            tone: "faint"
            text: root.detail
        }
    }

    Label {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        role: "caption"
        tone: root.active ? "accent" : "faint"
        caps: true
        text: root.trailing
    }
}
