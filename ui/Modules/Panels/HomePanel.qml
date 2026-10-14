import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Home: what time it is, what is playing, the few controls used all day, and how Zynith is spending
// the machine. Everything here is read from services; the panel holds no state of its own.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1

    function go(id: string): void {
        PanelRouter.navigate(id, screen.name);
    }

    padding: Metrics.s6
    spacing: Metrics.s5


    // the sampler runs only while this panel is on screen
    property bool active: true
    property bool holding: false
    function syncSampler(): void {
        if (active && !holding) {
            System.retain();
            holding = true;
        } else if (!active && holding) {
            System.release();
            holding = false;
        }
    }
    onActiveChanged: syncSampler()
    Component.onCompleted: syncSampler()
    Component.onDestruction: if (holding)
        System.release()

    readonly property real inner: width - padding * 2

    // content settles a beat after the surface (content-reveal)
    function stage(i: int): real {
        if (!ExperiencePolicy.stagger)
            return visibleProgress;
        const delay = 0.12 * i;
        return Math.max(0, Math.min(1, (visibleProgress - delay) / (1 - delay)));
    }

    // ── time ────────────────────────────────────────────────────────────────
    Item {
        width: root.inner
        height: clock.implicitHeight + date.implicitHeight
        opacity: root.stage(0)

        Label {
            id: clock
            role: "display"
            numeric: true
            text: Qt.formatTime(Time.now, "HH:mm")
        }
        Label {
            id: date
            anchors.top: clock.bottom
            role: "caption"
            tone: "faint"
            caps: true
            text: Qt.formatDate(Time.now, "dddd  ·  d MMMM")
        }
        Label {
            anchors.right: parent.right
            anchors.bottom: date.bottom
            role: "caption"
            tone: "faint"
            caps: true
            text: Power.present ? Math.round(Power.level * 100) + "%" + (Power.charging ? "  ·  charging" : "") : ""
        }
    }

    // ── now playing ─────────────────────────────────────────────────────────
    Item {
        visible: Media.present
        width: root.inner
        height: 64
        opacity: root.stage(1)

        Interactive {
            anchors.fill: parent
            anchors.rightMargin: 120
            anchors.margins: -Metrics.s2
            radius: Metrics.radiusLg
            onClicked: root.go("media")
        }

        Rectangle {
            id: art
            width: 64
            height: 64
            radius: Metrics.radiusMd
            color: Theme.hover
            clip: true

            Image {
                anchors.fill: parent
                source: Media.art
                sourceSize.width: ExperiencePolicy.artSize
                sourceSize.height: ExperiencePolicy.artSize
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
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
                name: "music"
                tone: "faint"
                size: 22
            }
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: Metrics.s4
            anchors.right: controls.left
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Label {
                width: parent.width
                role: "body"
                font.weight: Font.Medium
                text: Media.title
            }
            Label {
                width: parent.width
                role: "label"
                tone: "muted"
                text: Media.artist || Media.app
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            IconButton {
                icon: "player-skip-back-filled"
                iconSize: 14
                tone: "muted"
                onClicked: Media.previous()
            }
            IconButton {
                icon: Media.playing ? "player-pause-filled" : "player-play-filled"
                size: 36
                iconSize: 16
                active: Media.playing
                onClicked: Media.toggle()
            }
            IconButton {
                icon: "player-skip-forward-filled"
                iconSize: 14
                tone: "muted"
                onClicked: Media.next()
            }
        }
    }

    // ── volume ──────────────────────────────────────────────────────────────
    Row {
        width: root.inner
        spacing: Metrics.s3
        opacity: root.stage(2)

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: Audio.glyph
            tone: Audio.muted ? "faint" : "ink"
            onClicked: Audio.toggleMute()
        }
        Slider {
            wheelAdjusts: true
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 30 - 40 - Metrics.s3 * 2
            value: Audio.volume
            onMoved: v => Audio.setVolume(v)
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            role: "label"
            numeric: true
            tone: "muted"
            text: Math.round(Audio.volume * 100)
        }
    }

    // ── connectivity ────────────────────────────────────────────────────────
    Row {
        width: root.inner
        spacing: Metrics.s3
        opacity: root.stage(3)

        Tile {
            width: (parent.width - parent.spacing) / 2
            icon: Network.glyph
            title: "Wi‑Fi"
            detail: !Network.wifiEnabled ? "Off" : Network.name || "Not connected"
            on: Network.wifiEnabled
            more: true
            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
            onOpened: root.go("network")
        }
        Tile {
            width: (parent.width - parent.spacing) / 2
            icon: Bluetooth.enabled ? (Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth") : "bluetooth-off"
            title: "Bluetooth"
            detail: Bluetooth.available ? Bluetooth.summary : "Unavailable"
            on: Bluetooth.enabled
            more: true
            onToggled: Bluetooth.setEnabled(!Bluetooth.enabled)
            onOpened: root.go("bluetooth")
        }
    }

    // ── system ──────────────────────────────────────────────────────────────
    Item {
        width: root.inner
        height: systemRow.implicitHeight
        opacity: root.stage(4)

        Interactive {
            anchors.fill: parent
            anchors.margins: -Metrics.s2
            radius: Metrics.radiusMd
            onClicked: root.go("system")
        }

        Row {
            id: systemRow
            width: parent.width
            spacing: Metrics.s5

            Meter {
                width: (parent.width - parent.spacing) / 2
                label: "CPU"
                value: System.cpu
            }
            Meter {
                width: (parent.width - parent.spacing) / 2
                label: "Memory"
                value: System.memUsed
                readout: (System.memUsed * System.memTotalGiB).toFixed(1) + " / " + System.memTotalGiB.toFixed(0) + " GB"
            }
        }
    }

    // ── experience ──────────────────────────────────────────────────────────
    Column {
        width: root.inner
        spacing: Metrics.s3
        opacity: root.stage(5)

        Item {
            width: parent.width
            height: 16

            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: "Experience"
            }
            Label {
                anchors.right: parent.right
                role: "caption"
                tone: ExperiencePolicy.automatic ? "accent" : "faint"
                caps: true
                text: !ExperiencePolicy.automatic ? "Manual  ·  set auto" : ExperiencePolicy.limitedBy ? "Auto  ·  " + ExperiencePolicy.limitedBy : "Auto"

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ExperiencePolicy.select("auto")
                }
            }
        }

        Segmented {
            width: parent.width
            current: ExperiencePolicy.profile
            options: [
                {
                    key: "performance",
                    label: "Performance"
                },
                {
                    key: "balanced",
                    label: "Balanced"
                },
                {
                    key: "enhanced",
                    label: "Enhanced"
                },
                {
                    key: "max",
                    label: "Max"
                }
            ]
            onPicked: key => ExperiencePolicy.select(key)
        }

        Label {
            width: parent.width
            role: "caption"
            tone: "faint"
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: (Hardware.cpuModel || "CPU") + "  ·  " + Hardware.memGiB.toFixed(0) + " GB  ·  " + Hardware.gpuSummary
                + "\nRecommended: " + (ExperiencePolicy.labels[ExperiencePolicy.hardwareProfile] ?? "")
        }
    }
}
