import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

// The user's picture in a circle, or their initial when there is none.
Item {
    id: root

    property int size: 44
    property string source: About.avatar
    property string name: About.displayName

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.well
        border.width: 1
        border.color: Theme.hairline
    }
    Image {
        id: picture
        anchors.fill: parent
        source: root.source
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    Rectangle {
        id: circle
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: picture.status === Image.Ready
        source: picture
        maskEnabled: true
        maskSource: circle
    }
    Label {
        anchors.centerIn: parent
        visible: picture.status !== Image.Ready
        role: root.size >= 40 ? "title" : "body"
        text: root.name.charAt(0).toUpperCase()
    }
}
