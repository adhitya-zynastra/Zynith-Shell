import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Now playing on the desktop: cover, title, artist and the three controls. Hidden with nothing playing.
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    visible: Media.present || !(settings.hide_when_no_media ?? true)
    implicitWidth: 340
    implicitHeight: 92

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusXl
        color: Theme.alpha(Theme.pal(root.settings.background_color ?? "surface"), root.settings.background_opacity ?? 0.42)
        border.width: Theme.hairlineWidth
        border.color: Theme.hairline
    }
    Rectangle {
        id: art
        x: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - Metrics.s3 * 2
        height: width
        radius: Metrics.radiusLg
        color: Theme.well
        clip: true
        Image {
            anchors.fill: parent
            source: Media.art
            sourceSize.width: 160
            sourceSize.height: 160
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    Column {
        anchors.left: art.right
        anchors.leftMargin: Metrics.s4
        anchors.right: parent.right
        anchors.rightMargin: Metrics.s4
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.s1
        Label {
            width: parent.width
            role: "body"
            font.family: root.settings.font_family ?? Type.ui
            font.weight: Font.Medium
            text: Media.title
        }
        Label {
            width: parent.width
            role: "label"
            tone: "muted"
            font.family: root.settings.font_family ?? Type.ui
            text: Media.artist || Media.app
        }
        Row {
            spacing: 0
            IconButton {
                icon: "player-skip-back-filled"
                iconSize: 13
                tone: "muted"
                onClicked: Media.previous()
            }
            IconButton {
                icon: Media.playing ? "player-pause-filled" : "player-play-filled"
                iconSize: 14
                onClicked: Media.toggle()
            }
            IconButton {
                icon: "player-skip-forward-filled"
                iconSize: 13
                tone: "muted"
                onClicked: Media.next()
            }
        }
    }
}
