import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// What is playing: the cover, the title and artist (in either order, scrolling when long if asked), a
// progress line. Its gestures are its actions: by default a click opens the media panel, right-click
// plays or pauses, the wheel and thumb buttons skip.
BarItem {
    id: root
    readonly property bool artOnly: opt("album_art_only") === true
    readonly property bool showArt: !(opt("hide_album_art") === true)
    readonly property int artSize: opt("art_size") ?? 16
    readonly property string text: {
        const t = Media.title, a = opt("hide_artist") === true ? "" : Media.artist;
        if (!a)
            return t;
        return opt("artist_first") === true ? a + "  ·  " + t : t + "  ·  " + a;
    }
    shown: (Media.present || opt("hide_when_no_media") !== true) && !(vertical && !artOnly && !showArt)
    spacing: Metrics.s2
    active: PanelRouter.isOpen("media", screen?.name ?? "")

    Rectangle {
        visible: root.showArt || root.artOnly
        width: root.artSize
        height: root.artSize
        radius: Math.min(6, root.artSize / 4)
        color: Theme.well
        clip: true
        Image {
            anchors.fill: parent
            source: Media.art
            sourceSize.width: root.artSize * 2
            sourceSize.height: root.artSize * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Icon {
            anchors.centerIn: parent
            visible: Media.art === ""
            name: Media.playing ? "player-pause-filled" : "music"
            size: root.artSize * 0.6
            color: root.iconInk
        }
    }
    // the title, clipped to max_length and scrolling as asked
    Item {
        id: viewport
        visible: !root.artOnly && !root.vertical
        readonly property real natural: label.implicitWidth
        readonly property real most: root.opt("max_length") ?? 220
        readonly property real least: root.opt("min_length") ?? 80
        width: Math.max(least, Math.min(most, natural))
        height: label.implicitHeight + (progress.visible ? 4 : 0)
        clip: true
        readonly property bool scrolls: natural > width && (root.opt("title_scroll") === "always" || root.opt("title_scroll") === "on_hover" && root.hovered)
        BarText {
            id: label
            item: root
            elide: viewport.scrolls ? Text.ElideNone : Text.ElideRight
            width: viewport.scrolls ? implicitWidth : viewport.width
            text: Media.present ? root.text : "Nothing playing"
            muted: !Media.playing
            x: 0
            NumberAnimation on x {
                // only while the bar is on screen: slid away, the scroll ran the animation clock for nobody
                running: viewport.scrolls && (root.bar?.shown ?? 1) > 0
                loops: Animation.Infinite
                from: 0
                to: -(label.implicitWidth - viewport.width + 24)
                duration: Math.max(2000, (label.implicitWidth - viewport.width) * 40)
                easing.type: Easing.InOutSine
                onStopped: label.x = 0
            }
        }
        Rectangle {
            id: progress
            visible: root.opt("show_progress") === true && Media.active
            anchors.bottom: parent.bottom
            width: parent.width * (Media.active && Media.active.length > 0 ? Media.active.position / Media.active.length : 0)
            height: 2
            radius: 1
            color: root.iconInk
        }
    }
}
