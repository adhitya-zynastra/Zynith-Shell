import QtQuick
import qs.Common

// Title row for focused panels: back (when there is somewhere to go back to), title, optional trailing item.
Item {
    id: root

    property string title: ""
    property string caption: ""
    property bool canGoBack: false
    default property alias trailing: trail.data
    signal back

    implicitHeight: 34
    implicitWidth: 300

    IconButton {
        id: backButton
        visible: root.canGoBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon: "chevron-left"
        tone: "muted"
        onClicked: root.back()
    }

    Column {
        anchors.left: root.canGoBack ? backButton.right : parent.left
        anchors.leftMargin: root.canGoBack ? Metrics.s2 : 0
        anchors.right: trail.left
        anchors.verticalCenter: parent.verticalCenter

        Label {
            width: parent.width
            role: "headline"
            text: root.title
        }
        Label {
            visible: root.caption !== ""
            width: parent.width
            role: "caption"
            tone: "faint"
            caps: true
            text: root.caption
        }
    }

    Row {
        id: trail
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.s2
    }
}
