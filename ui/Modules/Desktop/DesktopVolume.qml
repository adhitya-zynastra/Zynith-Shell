import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The output's or microphone's level, settable from the desktop: the icon mutes, the track sets.
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    function opt(key: string): var {
        return WidgetTypes.value("volume", settings, key);
    }
    readonly property bool mic: opt("device") === "input"
    readonly property bool compact: opt("layout") === "compact"
    readonly property real level: mic ? Audio.micVolume : Audio.volume
    readonly property bool muted: mic ? Audio.micMuted : Audio.muted
    readonly property color tint: Theme.colour(opt("color"))

    implicitWidth: 300
    implicitHeight: 64

    Row {
        anchors.fill: parent
        anchors.leftMargin: Metrics.s3
        anchors.rightMargin: Metrics.s3
        spacing: Metrics.s3
        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            size: Math.min(40, root.height * 0.8)
            iconSize: size * 0.5
            icon: root.mic ? (root.muted ? "microphone-off" : "microphone") : Audio.glyph
            active: !root.muted
            onClicked: root.mic ? Audio.toggleMicMute() : Audio.toggleMute()
        }
        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - parent.spacing * 2 - Math.min(40, root.height * 0.8) - (root.compact ? 0 : 44)
            value: Math.min(1, root.level)
            onMoved: v => root.mic ? Audio.setMicVolume(v) : Audio.setVolume(v)
        }
        Label {
            visible: !root.compact
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            horizontalAlignment: Text.AlignRight
            role: "label"
            numeric: true
            color: root.tint
            text: root.muted ? "—" : Math.round(root.level * 100) + "%"
        }
    }
}
