import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Now playing, as the dashboard's lead block (Caelestia's dashboard media, Clavis/Ryoku lyrics): the record
// — the art in a disc that turns while it plays — ringed by the spectrum and by how far the song has got;
// the title set large, artist and album; a timeline you can drag; the controls; the line being sung with
// the next ones fading. Expanded (its page) the record grows and the whole lyric sheet follows the song.
// Every piece is [media] in panels.toml.
Item {
    id: root

    property var screen: null
    property bool active: true
    property bool expanded: false

    readonly property var cfg: Config.media ?? ({})
    readonly property int artSize: expanded ? (cfg.page_art_size ?? 180) : (cfg.art_size ?? 104)
    readonly property bool visualizer: (cfg.visualizer ?? true) && Spectrum.enabled
    readonly property real reach: visualizer && ring ? (cfg.visualizer_reach ?? 18) : 6
    readonly property bool showLyrics: Lyrics.enabled
    readonly property int lyricLines: Math.max(1, cfg.lyrics_lines ?? 2)
    readonly property bool present: Media.present

    implicitHeight: row.height

    // what this holds while it is on screen
    readonly property bool live: active && visible
    onLiveChanged: live ? hold() : letGo()
    Component.onCompleted: if (live)
        hold()
    Component.onDestruction: letGo()
    property bool holding: false
    function hold(): void {
        if (holding)
            return;
        holding = true;
        if (visualizer)
            Spectrum.retain();
        if (showLyrics)
            Lyrics.retain();
    }
    function letGo(): void {
        if (!holding)
            return;
        holding = false;
        if (visualizer)
            Spectrum.release();
        if (showLyrics)
            Lyrics.release();
    }
    // MPRIS does not push position: ask a few times a second while the song shows and plays
    Timer {
        running: root.live && Media.playing
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: Media.tick()
    }
    readonly property real progress: Media.length > 0 ? Math.max(0, Math.min(1, Media.position / Media.length)) : 0
    readonly property int lyricIndex: Lyrics.lineAt(Media.position)

    readonly property string vizStyle: cfg.visualizer_style ?? "both"
    readonly property bool ring: vizStyle === "ring" || vizStyle === "both"
    readonly property bool barsShown: visualizer && (vizStyle === "bars" || vizStyle === "both")
    // on the page the words get a column of their own at the right
    readonly property real lyricsWidth: expanded && showLyrics ? Math.round(width * (cfg.lyrics_column ?? 0.36)) : 0

    // side by side: the record | what is playing, the timeline, the controls, the spectrum | (page) the words
    Row {
        id: row
        width: root.width
        spacing: Metrics.s5
        readonly property real middleHeight: middle.implicitHeight
        height: Math.max(record.height, middle.implicitHeight, words.visible && root.expanded ? words.height : 0)

        Item {
            id: record
            width: root.artSize + root.reach * 2
            height: width
            anchors.verticalCenter: parent.verticalCenter

            // the spectrum, radial around the disc
            Shape {
                id: spectrum
                anchors.fill: parent
                visible: root.visualizer && root.ring && root.present
                preferredRendererType: Shape.CurveRenderer
                readonly property real c: width / 2
                readonly property real inner: root.artSize / 2 + 7
                readonly property int count: Spectrum.bandCount
                data: bars.instances
            }
            Variants {
                id: bars
                model: root.visualizer && root.ring ? Array.from({ length: Spectrum.bandCount * 2 }, (_, i) => i) : []
                ShapePath {
                    required property int modelData
                    readonly property int index: modelData
                    // mirrored: the bands climb both sides of the disc from the bottom
                    readonly property int band: index < spectrum.count ? index : spectrum.count * 2 - 1 - index
                    readonly property real value: Math.max(0.02, Math.min(1, Spectrum.values[band] ?? 0))
                    readonly property real angle: Math.PI / 2 + index * 2 * Math.PI / (spectrum.count * 2)
                    readonly property real cos: Math.cos(angle)
                    readonly property real sin: Math.sin(angle)
                    strokeWidth: Math.max(1.5, Math.PI * spectrum.inner * 2 / (spectrum.count * 2) - 2.5)
                    strokeColor: Theme.alpha(Theme.accent, 0.55 + value * 0.45)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    startX: spectrum.c + (spectrum.inner + 3) * cos
                    startY: spectrum.c + (spectrum.inner + 3) * sin
                    PathLine {
                        x: spectrum.c + (spectrum.inner + 3 + value * (root.reach - 6)) * cos
                        y: spectrum.c + (spectrum.inner + 3 + value * (root.reach - 6)) * sin
                    }
                }
            }
            // how far the song has got, as an arc just outside the disc
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.alpha(Theme.ink, 0.12)
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: record.width / 2
                        centerY: record.height / 2
                        radiusX: root.artSize / 2 + 4
                        radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 360
                    }
                }
                ShapePath {
                    strokeWidth: 2.5
                    strokeColor: Theme.accent
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: record.width / 2
                        centerY: record.height / 2
                        radiusX: root.artSize / 2 + 4
                        radiusY: radiusX
                        startAngle: -90
                        sweepAngle: 360 * root.progress
                    }
                }
            }
            // the disc
            Item {
                id: disc
                anchors.centerIn: parent
                width: root.artSize
                height: width
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.well
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: Media.art
                    readonly property int px: Math.max(ExperiencePolicy.artSize, root.artSize * 2)
                    sourceSize.width: px
                    sourceSize.height: px
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: discMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    maskEnabled: true
                    maskSource: discMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                    opacity: art.status === Image.Ready ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.contentIn * 2
                        }
                    }
                }
                // the spindle
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.max(8, root.artSize * 0.11)
                    height: width
                    radius: width / 2
                    color: Theme.alpha(Theme.base, 0.85)
                    border.width: 1
                    border.color: Theme.alpha(Theme.ink, 0.25)
                }
                Icon {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    name: "disc"
                    size: root.artSize * 0.4
                    tone: "faint"
                }
                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: Math.max(4, root.cfg.spin_seconds ?? 24) * 1000
                    loops: Animation.Infinite
                    running: (root.cfg.spin ?? true) && Media.playing && root.live && ExperiencePolicy.richEffects && !Motion.reduced
                }
            }
        }


        Column {
            id: middle
            anchors.verticalCenter: parent.verticalCenter
            width: row.width - record.width - row.spacing - (root.lyricsWidth > 0 ? root.lyricsWidth + row.spacing : 0)
            spacing: Metrics.s2

            Column {
                id: details
                width: parent.width
                spacing: Metrics.s1

                Label {
                    role: "data"
                    tone: Media.playing ? "accent" : "faint"
                    text: !root.present ? "Nothing playing" : (Media.playing ? "Now playing" : "Paused") + (Media.app !== "" ? "  ·  " + Media.app : "")
                }
                Label {
                    width: parent.width
                    role: root.expanded ? "headline" : "title"
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.present ? Media.title : "Play something"
                }
                Label {
                    width: parent.width
                    role: "label"
                    tone: "muted"
                    elide: Text.ElideRight
                    text: [Media.artist, Media.album].filter(s => s !== "").join("  ·  ")
                    visible: text !== ""
                }
                // which player, when there is more than one
                Flow {
                    visible: (root.cfg.player_chips ?? true) && Media.players.length > 1
                    width: parent.width
                    spacing: Metrics.s1
                    topPadding: Metrics.s1
                    Repeater {
                        model: Media.players
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool current: modelData === Media.active
                            width: chip.implicitWidth + Metrics.s3 * 2
                            height: 22
                            radius: 11
                            color: current ? Theme.alpha(Theme.accent, 0.18) : chipArea.containsMouse ? Theme.hover : Theme.plate
                            border.width: current ? 1 : 0
                            border.color: Theme.alpha(Theme.accent, 0.6)
                            Label {
                                id: chip
                                anchors.centerIn: parent
                                role: "micro"
                                tone: parent.current ? "accent" : "muted"
                                text: modelData.identity || "Player"
                            }
                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Media.choose(modelData)
                            }
                        }
                    }
                }
            }

            // ── the timeline ──
            Item {
                visible: root.present && Media.length > 0
                width: parent.width
                height: timeline.height + times.height + 2
                Slider {
                    id: timeline
                    width: parent.width
                    value: root.progress
                    enabled: Media.canSeek
                    onMoved: v => Media.seek(v * Media.length)
                }
                Item {
                    id: times
                    anchors.top: timeline.bottom
                    anchors.topMargin: 2
                    width: parent.width
                    height: elapsed.implicitHeight
                    Label {
                        id: elapsed
                        role: "micro"
                        numeric: true
                        tone: "faint"
                        text: Media.clock(Media.position)
                    }
                    Label {
                        anchors.right: parent.right
                        role: "micro"
                        numeric: true
                        tone: "faint"
                        text: "-" + Media.clock(Math.max(0, Media.length - Media.position))
                    }
                }
            }

            // ── the controls ──
            Row {
                visible: root.present
                spacing: Metrics.s3
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Media.canShuffle
                    icon: "arrows-shuffle"
                    iconSize: 15
                    tone: Media.shuffle ? "accent" : "faint"
                    onClicked: Media.toggleShuffle()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "player-skip-back-filled"
                    iconSize: 17
                    tone: "muted"
                    onClicked: Media.previous()
                }
                // play / pause: the one filled control
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.expanded ? 56 : 46
                    height: width
                    radius: width / 2
                    color: playArea.pressed ? Theme.mix(Theme.accent, Theme.base, 0.2) : Theme.accent
                    scale: playArea.pressed ? 0.94 : playArea.containsMouse ? 1.05 : 1
                    Behavior on scale {
                        Anim {
                            role: "spatialFast"
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: Media.playing ? "player-pause-filled" : "player-play-filled"
                        size: parent.width * 0.4
                        color: Theme.onAccent
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.toggle()
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "player-skip-forward-filled"
                    iconSize: 17
                    tone: "muted"
                    onClicked: Media.next()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Media.canLoop
                    icon: Media.loop === "track" ? "repeat-once" : "repeat"
                    iconSize: 15
                    tone: Media.loop !== "none" ? "accent" : "faint"
                    onClicked: Media.cycleLoop()
                }
            }


            // the spectrum as bars, mirrored from the middle
            Item {
                id: barStrip
                visible: root.barsShown && root.present
                width: parent.width
                height: root.expanded ? Math.round((root.cfg.bars_height ?? 26) * 1.5) : (root.cfg.bars_height ?? 26)
                readonly property int count: Math.max(8, root.cfg.bars ?? 32)
                SpectrumBars {
                    anchors.fill: parent
                    values: Spectrum.values
                    count: barStrip.count
                    mirrored: true
                    centred: true
                    gap: 0.36
                    floor: 0.08
                    colorFrom: Theme.accent
                    colorTo: Theme.colour(root.cfg.bars_color_2 ?? "tertiary")
                    gradientFromCentre: true
                    alpha: 0.45
                    alphaByLevel: 0.55
                }
            }

            // the dashboard keeps the sung line (and the next) here
            // ── the words ──
            Item {
                id: wordsCompact
                visible: root.showLyrics && root.present && !root.expanded
                width: root.expanded ? lyricsWidth : parent.width
                readonly property real lineH: root.expanded ? 30 : 22
                height: root.expanded ? Math.max(row.middleHeight, record.height) : root.lyricLines * lineH
                clip: true

                Label {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: Lyrics.lines.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    role: "caption"
                    tone: "faint"
                    text: Lyrics.searching ? "Looking for the words…" : Lyrics.status === "error" ? "Lyrics unavailable" : Lyrics.status === "none" ? "No lyrics for this song" : ""
                }
                ListView {
                    id: sheetCompact
                    anchors.fill: parent
                    visible: Lyrics.lines.length > 0
                    interactive: !Lyrics.synced
                    model: Lyrics.lines
                    currentIndex: Math.max(0, root.lyricIndex)
                    // the sung line on the middle rule (top on the dashboard), the rest fading by distance
                    preferredHighlightBegin: root.expanded ? height / 2 - wordsCompact.lineH / 2 : 0
                    preferredHighlightEnd: preferredHighlightBegin + wordsCompact.lineH
                    highlightRangeMode: Lyrics.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                    highlightMoveDuration: Motion.spatial
                    highlightMoveVelocity: -1
                    delegate: Item {
                        id: line
                        required property var modelData
                        required property int index
                        readonly property int distance: Lyrics.synced ? Math.abs(index - root.lyricIndex) : 0
                        readonly property bool sung: Lyrics.synced && index === root.lyricIndex
                        width: sheetCompact.width
                        height: wordsCompact.lineH
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            horizontalAlignment: root.expanded ? Text.AlignHCenter : Text.AlignLeft
                            elide: Text.ElideRight
                            role: line.sung ? (root.expanded ? "title" : "body") : root.expanded ? "body" : "label"
                            font.weight: line.sung ? Font.DemiBold : Font.Normal
                            color: line.sung ? Theme.accent : Theme.ink
                            opacity: Lyrics.synced ? Math.max(0.18, 1 - line.distance * 0.3) : 0.8
                            text: line.modelData.text === "" ? "♪" : line.modelData.text
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.effects
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: Lyrics.synced && Media.canSeek
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Media.seek(line.modelData.t)
                        }
                    }
                }
            }
        }

        // the page: the whole sheet, following the song
        // ── the words ──
        Item {
            id: words
            visible: root.showLyrics && root.present && root.expanded
            width: root.expanded ? lyricsWidth : parent.width
            readonly property real lineH: root.expanded ? 30 : 22
            height: root.expanded ? Math.max(row.middleHeight, record.height) : root.lyricLines * lineH
            clip: true

            Label {
                anchors.centerIn: parent
                width: parent.width
                visible: Lyrics.lines.length === 0
                horizontalAlignment: Text.AlignHCenter
                role: "caption"
                tone: "faint"
                text: Lyrics.searching ? "Looking for the words…" : Lyrics.status === "error" ? "Lyrics unavailable" : Lyrics.status === "none" ? "No lyrics for this song" : ""
            }
            ListView {
                id: sheet
                anchors.fill: parent
                visible: Lyrics.lines.length > 0
                interactive: !Lyrics.synced
                model: Lyrics.lines
                currentIndex: Math.max(0, root.lyricIndex)
                // the sung line on the middle rule (top on the dashboard), the rest fading by distance
                preferredHighlightBegin: root.expanded ? height / 2 - words.lineH / 2 : 0
                preferredHighlightEnd: preferredHighlightBegin + words.lineH
                highlightRangeMode: Lyrics.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                highlightMoveDuration: Motion.spatial
                highlightMoveVelocity: -1
                delegate: Item {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property int distance: Lyrics.synced ? Math.abs(index - root.lyricIndex) : 0
                    readonly property bool sung: Lyrics.synced && index === root.lyricIndex
                    width: sheet.width
                    height: words.lineH
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        horizontalAlignment: root.expanded ? Text.AlignHCenter : Text.AlignLeft
                        elide: Text.ElideRight
                        role: line.sung ? (root.expanded ? "title" : "body") : root.expanded ? "body" : "label"
                        font.weight: line.sung ? Font.DemiBold : Font.Normal
                        color: line.sung ? Theme.accent : Theme.ink
                        opacity: Lyrics.synced ? Math.max(0.18, 1 - line.distance * 0.3) : 0.8
                        text: line.modelData.text === "" ? "♪" : line.modelData.text
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.effects
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: Lyrics.synced && Media.canSeek
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: Media.seek(line.modelData.t)
                    }
                }
            }
        }
    }
}
