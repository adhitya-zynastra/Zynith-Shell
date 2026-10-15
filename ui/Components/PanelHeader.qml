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

        // a surface's title in the heading voice (as the Control Panel's hero); its line under it is language
        // (what this is, what state it is in), so it is read, not tracked out as data
        Label {
            width: parent.width
            role: "heading"
            font.pixelSize: Type.headline + 2
            text: root.title
        }
        Label {
            visible: root.caption !== ""
            width: parent.width
            role: "caption"
            tone: "muted"
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
