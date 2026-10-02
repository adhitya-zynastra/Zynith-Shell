import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Components
import qs.Services

// Now playing on the desktop: cover, title, artist and the three controls, wide or tall, scaled to the box.
// With nothing playing it says so, or hides (hide_when_no_media).
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    function opt(key: string): var {
        return WidgetTypes.value("media_player", settings, key);
    }
    readonly property bool tall: opt("layout") === "vertical"
    readonly property color ink: Theme.colour(opt("color"))
    readonly property string family: (opt("font_family") ?? "") !== "" ? opt("font_family") : Type.ui
    readonly property real unit: tall ? Math.min(width / 220, height / 300) : Math.min(width / 420, height / 120)
    visible: Media.present || opt("hide_when_no_media") !== true
    implicitWidth: 420
    implicitHeight: 120

    layer.enabled: opt("shadow") === true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.6
        shadowVerticalOffset: 2
    }

    Rectangle {
        id: art
        x: root.tall ? (root.width - width) / 2 : 0
        y: root.tall ? 0 : (root.height - height) / 2
        width: root.tall ? Math.min(root.width, root.height * 0.55) : Math.min(root.height, root.width * 0.35)
        height: width
        radius: Metrics.radiusLg * root.unit
        color: Theme.well
        clip: true
        Image {
            id: cover
            anchors.fill: parent
            source: Media.art
            sourceSize.width: 320
            sourceSize.height: 320
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity {
                Anim {
                    role: "effects"
                }
            }
        }
        Icon {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            name: "music"
            size: parent.width * 0.35
            tone: "faint"
        }
    }

    Column {
        x: root.tall ? 0 : art.width + Metrics.s4 * root.unit
        y: root.tall ? art.height + Metrics.s3 * root.unit : (root.height - height) / 2
        width: root.tall ? root.width : root.width - x
        spacing: Metrics.s1 * root.unit

        Text {
            width: parent.width
            horizontalAlignment: root.tall ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
            text: Media.present ? Media.title : "Nothing playing"
            font.family: root.family
            font.weight: Font.Medium
            font.pixelSize: Math.max(10, 17 * root.unit)
            color: root.ink
        }
        Text {
            width: parent.width
            horizontalAlignment: root.tall ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
            visible: text !== ""
            text: Media.present ? (Media.artist || Media.app) : ""
            font.family: root.family
            font.pixelSize: Math.max(9, 13 * root.unit)
            color: Theme.alpha(root.ink, 0.7)
        }
        Row {
            anchors.horizontalCenter: root.tall ? parent.horizontalCenter : undefined
            spacing: 0
            opacity: Media.present ? 1 : 0.4
            IconButton {
                size: 34 * root.unit
                icon: "player-skip-back-filled"
                iconSize: 14 * root.unit
                tone: "muted"
                onClicked: Media.previous()
            }
            IconButton {
                size: 38 * root.unit
                icon: Media.playing ? "player-pause-filled" : "player-play-filled"
                iconSize: 16 * root.unit
                onClicked: Media.toggle()
            }
            IconButton {
                size: 34 * root.unit
                icon: "player-skip-forward-filled"
                iconSize: 14 * root.unit
                tone: "muted"
                onClicked: Media.next()
            }
        }
    }
}
