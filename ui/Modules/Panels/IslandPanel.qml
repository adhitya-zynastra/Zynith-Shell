import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The island opened: the thing it shows, with what you can do about it. It grows out of the island in the bar
// (PanelSurface: the same drop as every panel), so it reads as the island taking a larger shape, not a window
// appearing. Several things at once: a chip each, to switch.
Item {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    readonly property Item blurItem: null
    readonly property int preferredWidth: 380
    implicitHeight: col.implicitHeight

    readonly property var a: Island.primary
    readonly property string kind: a?.kind ?? "idle"

    // the progress line moves only while the island is open (MPRIS does not push the position)
    Timer {
        running: root.active && root.kind === "media" && Media.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: Media.tick()
    }

    Column {
        id: col
        width: parent.width
        spacing: Metrics.s4

        // ── several things at once: pick one ──
        Flow {
            visible: Island.ordered.length > 1
            width: parent.width
            spacing: Metrics.s1
            Repeater {
                model: Island.ordered
                delegate: Chip {
                    required property var modelData
                    icon: ({ media: "music", notification: "bell", device: "headphones", power: "plug-connected" })[modelData.kind] ?? "point-filled"
                    text: ({ media: "Music", notification: modelData.data.app || "Notification", device: "Sound", power: "Power" })[modelData.kind] ?? modelData.kind
                    active: modelData.id === root.a?.id
                    onClicked: Island.pick(modelData.id)
                }
            }
        }

        // ── nothing happening ──
        Column {
            visible: root.kind === "idle"
            width: parent.width
            spacing: Metrics.s1
            Label {
                role: "display"
                numeric: true
                text: Qt.formatTime(Time.now, "HH:mm")
            }
            Label {
                role: "label"
                tone: "muted"
                text: Qt.formatDate(Time.now, "dddd · d MMMM")
            }
            Label {
                role: "caption"
                tone: "faint"
                text: "Nothing is happening. Music, new notifications and changes to your sound or charger show here."
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }

        // ── music ──
        Item {
            visible: root.kind === "media"
            width: parent.width
            height: visible ? 168 : 0
            Rectangle {
                id: art
                width: 96
                height: 96
                radius: Metrics.radiusMd
                color: Theme.well
                clip: true
                Image {
                    anchors.fill: parent
                    source: Media.art
                    sourceSize.width: 192
                    sourceSize.height: 192
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Icon {
                    visible: Media.art === ""
                    anchors.centerIn: parent
                    name: "music"
                    size: 32
                    tone: "faint"
                }
            }
            Column {
                x: art.width + Metrics.s4
                width: parent.width - x
                spacing: 2
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    role: "title"
                    text: Media.title || "Playing"
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    role: "label"
                    tone: "muted"
                    text: Media.artist
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    role: "caption"
                    tone: "faint"
                    text: Media.app
                }
            }
            // where it is in the track
            Column {
                y: art.height + Metrics.s3
                width: parent.width
                spacing: 2
                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.well
                    Rectangle {
                        width: parent.width * (Media.length > 0 ? Math.min(1, Media.position / Media.length) : 0)
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                Item {
                    width: parent.width
                    height: 16
                    Label {
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
                        text: Media.clock(Media.length)
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: Metrics.s4
                IconButton {
                    icon: "player-skip-back-filled"
                    onClicked: Media.previous()
                }
                IconButton {
                    objectName: "island-play"
                    icon: Media.playing ? "player-pause-filled" : "player-play-filled"
                    active: true
                    onClicked: Media.toggle()
                }
                IconButton {
                    icon: "player-skip-forward-filled"
                    onClicked: Media.next()
                }
            }
        }

        // ── a notification: the card, with its actions and reply ──
        Loader {
            width: parent.width
            active: root.kind === "notification" && Notifications.entry(root.a.data.key) !== null
            visible: active
            sourceComponent: NotificationCard {
                width: parent?.width ?? 380
                entry: Notifications.entry(root.a.data.key)
                onActivated: Island.drop(root.a.id)
            }
        }

        // ── the sound moved: where it goes now, and the other places it can go ──
        Column {
            visible: root.kind === "device"
            width: parent.width
            spacing: Metrics.s3
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                role: "title"
                text: "Sound now plays through " + (root.a?.data?.name ?? "")
            }
            Slider {
                width: parent.width
                value: Audio.volume
                onMoved: v => Audio.setVolume(v)
                onCommitted: v => Audio.setVolume(v)
            }
            Repeater {
                model: Audio.sinks
                delegate: Chip {
                    required property var modelData
                    icon: Audio.sink === modelData ? "check" : "device-speaker"
                    text: Audio.nodeName(modelData)
                    active: Audio.sink === modelData
                    onClicked: Audio.setSink(modelData)
                }
            }
        }

        // ── power ──
        Row {
            visible: root.kind === "power"
            spacing: Metrics.s4
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Power.glyph
                size: 32
                tone: "accent"
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    role: "title"
                    text: (Power.charging ? "Charging" : "On battery") + " · " + Math.round(Power.level * 100) + "%"
                }
                Label {
                    role: "caption"
                    tone: "muted"
                    text: Power.charging ? "Plugged in" : "Unplugged"
                }
            }
        }

        // put it away
        Row {
            visible: root.a !== null
            spacing: Metrics.s2
            Chip {
                objectName: "island-dismiss"
                icon: "x"
                text: root.kind === "notification" ? "Dismiss" : "Put away"
                onClicked: Island.dismiss(root.a.id)
            }
        }
    }
}
