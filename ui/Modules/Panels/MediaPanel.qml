import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Components
import qs.Services

Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true

    padding: Metrics.s6
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2
    readonly property var player: Media.active

    // MPRIS does not push position; refresh it once a second while this panel shows a playing track
    Timer {
        running: root.active && root.player !== null && Media.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.player.positionChanged()
    }

    PanelHeader {
        width: root.inner
        title: "Now playing"
        caption: Media.app
        canGoBack: root.canGoBack
        onBack: root.back()
    }

    Rectangle {
        width: root.inner
        height: width
        radius: Metrics.radiusLg
        color: Theme.hover
        clip: true
        visible: Media.present

        Image {
            anchors.fill: parent
            source: Media.art
            sourceSize.width: ExperiencePolicy.artSize * 2
            sourceSize.height: ExperiencePolicy.artSize * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.contentIn
                }
            }
        }
        Icon {
            anchors.centerIn: parent
            visible: Media.art === ""
            name: "disc"
            size: 48
            tone: "faint"
        }
    }

    Column {
        width: root.inner
        spacing: 2
        visible: Media.present

        Label {
            width: parent.width
            role: "title"
            text: Media.title
        }
        Label {
            width: parent.width
            role: "body"
            tone: "muted"
            text: [Media.artist, root.player?.trackAlbum ?? ""].filter(s => s).join("  ·  ")
        }
    }

    // progress
    Column {
        width: root.inner
        spacing: Metrics.s2
        visible: Media.present && (root.player?.lengthSupported ?? false) && root.player.length > 0

        Slider {
            width: parent.width
            value: root.player ? root.player.position / Math.max(1, root.player.length) : 0
            onMoved: v => {
                if (root.player?.canSeek)
                    root.player.position = v * root.player.length;
            }
        }
        Item {
            width: parent.width
            height: 14

            function clock(s: real): string {
                s = Math.max(0, Math.floor(s));
                return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
            }
            Label {
                role: "caption"
                numeric: true
                tone: "faint"
                text: parent.clock(root.player?.position ?? 0)
            }
            Label {
                anchors.right: parent.right
                role: "caption"
                numeric: true
                tone: "faint"
                text: parent.clock(root.player?.length ?? 0)
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Metrics.s4
        visible: Media.present

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "player-skip-back-filled"
            enabled: root.player?.canGoPrevious ?? false
            onClicked: Media.previous()
        }
        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            size: 48
            iconSize: 22
            icon: Media.playing ? "player-pause-filled" : "player-play-filled"
            active: true
            onClicked: Media.toggle()
        }
        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "player-skip-forward-filled"
            enabled: root.player?.canGoNext ?? false
            onClicked: Media.next()
        }
    }

    // other players, when there is more than one
    Column {
        width: root.inner
        spacing: Metrics.s1
        visible: Media.players.length > 1

        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Players"
        }
        Repeater {
            model: Media.players

            delegate: ListRow {
                required property MprisPlayer modelData
                width: root.inner
                icon: modelData.isPlaying ? "player-play-filled" : "music"
                title: modelData.identity
                detail: modelData.trackTitle
                active: modelData === root.player
                onClicked: Media.last = modelData
            }
        }
    }

    Label {
        visible: !Media.present
        width: root.inner
        role: "body"
        tone: "faint"
        text: "Nothing is playing."
    }
}
