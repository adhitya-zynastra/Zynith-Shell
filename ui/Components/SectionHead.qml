import QtQuick
import qs.Common

// A section's head: an index, its name in the data voice, and a hairline running to the edge
// ("01  SOUND ─────────"). Hierarchy by type and rule, not by a box around the section.
Item {
    id: root
    property string index: ""
    property string title: ""
    default property alias trailing: trail.data
    implicitHeight: 18
    implicitWidth: 240

    Row {
        id: lead
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.s3
        Label {
            visible: root.index !== ""
            role: "data"
            tone: "faint"
            text: root.index
        }
        Label {
            role: "data"
            tone: "muted"
            text: root.title
        }
    }
    Rectangle {
        anchors.left: lead.right
        anchors.leftMargin: Metrics.s3
        anchors.right: trail.left
        anchors.rightMargin: trail.children.length > 0 ? Metrics.s3 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.rule
    }
    Row {
        id: trail
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.s2
    }
}
