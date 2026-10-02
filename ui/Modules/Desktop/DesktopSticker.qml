import QtQuick
import qs.Common
import qs.Components
import qs.Services

// A picture of your choosing; with none chosen, a quiet frame saying so.
Item {
    id: root
    property var settings: ({})
    readonly property string path: WidgetTypes.value("sticker", settings, "image_path") ?? ""
    opacity: WidgetTypes.value("sticker", settings, "opacity") ?? 1
    implicitWidth: 240
    implicitHeight: 240

    AnimatedImage {
        anchors.fill: parent
        visible: root.path !== ""
        source: root.path !== "" ? (root.path.startsWith("/") ? "file://" + root.path : root.path) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        playing: root.path.toLowerCase().endsWith(".gif")
        smooth: true
        mipmap: true
    }
    Rectangle {
        visible: root.path === ""
        anchors.fill: parent
        radius: Metrics.radiusLg
        color: "transparent"
        border.width: 1.5
        border.color: Theme.alpha(Theme.ink, 0.3)
        Column {
            anchors.centerIn: parent
            spacing: Metrics.s2
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "photo"
                size: Math.min(root.width, root.height) * 0.2
                tone: "faint"
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                role: "caption"
                tone: "faint"
                text: "Choose an image"
            }
        }
    }
}
