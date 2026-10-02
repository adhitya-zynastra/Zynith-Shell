import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    shown: Media.present && !vertical
    spacing: Metrics.s3
    onClicked: mouse => mouse.button === Qt.RightButton ? bar?.openPanel("home", root) : Media.toggle()
    onScrolled: delta => delta > 0 ? Media.previous() : Media.next()

    Icon {
        name: Media.playing ? "player-pause-filled" : "player-play-filled"
        size: 13
        tone: Media.playing ? "accent" : "muted"
    }
    Label {
        role: "label"
        tone: "muted"
        width: Math.min(implicitWidth, 180)
        text: Media.artist ? Media.title + "  ·  " + Media.artist : Media.title
    }
}
