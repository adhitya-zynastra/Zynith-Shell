import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The Control Panel: quick interaction, not configuration. Built from modules whose order is
// panels.toml [control_panel] modules; each module holds what it needs only while the panel shows.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true
    readonly property int preferredWidth: Config.controlPanel?.width ?? 420

    readonly property var modules: Config.controlPanel?.modules ?? ["header", "levels", "connectivity", "toggles", "media", "power", "system"]

    padding: Metrics.s5
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2

    function go(id: string): void {
        PanelRouter.navigate(id, screen.name);
    }
    // content settles a beat after the surface
    function stage(i: int): real {
        if (!ExperiencePolicy.stagger)
            return visibleProgress;
        const delay = Math.min(0.5, 0.08 * i);
        return Math.max(0, Math.min(1, (visibleProgress - delay) / (1 - delay)));
    }

    // what this panel holds while it is on screen
    property bool holding: false
    function sync(): void {
        const needs = active;
        if (needs && !holding) {
            System.retain();
            Backlight.retain();
            Core.refresh();
            holding = true;
        } else if (!needs && holding) {
            System.release();
            Backlight.release();
            holding = false;
        }
    }
    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (holding) {
        System.release();
        Backlight.release();
    }

    // DND belongs to whichever notification server runs
    readonly property bool dnd: Notifications.serving ? Notifications.dnd : Core.dnd
    function setDnd(on: bool): void {
        if (Notifications.serving)
            Notifications.setDnd(on);
        else
            Core.setDnd(on);
    }

    Repeater {
        model: root.modules

        delegate: Loader {
            required property string modelData
            required property int index
            width: root.inner
            opacity: root.stage(index)
            sourceComponent: ({
                    header: header,
                    levels: levels,
                    connectivity: connectivity,
                    toggles: toggles,
                    media: media,
                    power: power,
                    system: system,
                    notifications: notifications,
                    clipboard: clipboard
                })[modelData] ?? null
        }
    }

    // ── header: who, when ───────────────────────────────────────────────────
    Component {
        id: header
        Item {
            implicitHeight: 52

            Avatar {
                id: avatarFrame
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 44
            }
            Column {
                anchors.left: avatarFrame.right
                anchors.leftMargin: Metrics.s4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    role: "title"
                    text: About.realName || About.user
                }
                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: Qt.formatDate(Time.now, "dddd  ·  d MMMM") + (Power.present ? "  ·  " + Math.round(Power.level * 100) + "%" : "")
                }
            }
            Label {
                id: headerClock
                anchors.right: settingsButton.left
                anchors.rightMargin: Metrics.s2
                anchors.verticalCenter: parent.verticalCenter
                role: "display2"
                numeric: true
                text: Qt.formatTime(Time.now, "HH:mm")
            }
            IconButton {
                id: settingsButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "settings"
                tone: "muted"
                onClicked: {
                    PanelRouter.close(root.screen.name);
                    Quickshell.execDetached([Quickshell.shellPath("zynith-ui"), "settings"]);
                }
            }
        }
    }

    // ── levels: volume, microphone, brightness ──────────────────────────────
    Component {
        id: levels
        Column {
            spacing: Metrics.s2

            Repeater {
                model: [
                    { key: "volume", shown: Audio.ready },
                    { key: "mic", shown: Audio.micReady },
                    { key: "brightness", shown: Backlight.available }
                ]

                delegate: Row {
                    id: level
                    required property var modelData
                    readonly property string key: modelData.key
                    visible: modelData.shown
                    width: root.inner
                    spacing: Metrics.s3

                    readonly property real value: key === "volume" ? Audio.volume : key === "mic" ? Audio.micVolume : Backlight.value
                    readonly property bool off: key === "volume" ? Audio.muted : key === "mic" ? Audio.micMuted : false

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: level.key === "volume" ? Audio.glyph : level.key === "mic" ? (Audio.micMuted ? "microphone-off" : "microphone") : "brightness-up"
                        tone: level.off ? "faint" : "ink"
                        onClicked: level.key === "volume" ? Audio.toggleMute() : level.key === "mic" ? Audio.toggleMicMute() : undefined
                    }
                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Metrics.control - 40 - Metrics.s3 * 2
                        value: level.value
                        opacity: level.off ? 0.5 : 1
                        onMoved: v => level.key === "volume" ? Audio.setVolume(v) : level.key === "mic" ? Audio.setMicVolume(v) : Backlight.set(v)
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        role: "label"
                        numeric: true
                        tone: "muted"
                        text: Math.round(level.value * 100)
                    }
                }
            }
        }
    }

    // ── connectivity ────────────────────────────────────────────────────────
    Component {
        id: connectivity
        Row {
            spacing: Metrics.s3
            Tile {
                width: (root.inner - Metrics.s3) / 2
                icon: Network.glyph
                title: "Wi‑Fi"
                detail: !Network.wifiEnabled ? "Off" : Network.name || "Not connected"
                on: Network.wifiEnabled
                more: true
                onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
                onOpened: root.go("network")
            }
            Tile {
                width: (root.inner - Metrics.s3) / 2
                icon: Bluetooth.enabled ? (Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth") : "bluetooth-off"
                title: "Bluetooth"
                detail: Bluetooth.available ? Bluetooth.summary : "Unavailable"
                on: Bluetooth.enabled
                more: true
                onToggled: Bluetooth.setEnabled(!Bluetooth.enabled)
                onOpened: root.go("bluetooth")
            }
        }
    }

    // ── switches ────────────────────────────────────────────────────────────
    Component {
        id: toggles
        Grid {
            columns: 2
            columnSpacing: Metrics.s3
            rowSpacing: Metrics.s3
            readonly property real cell: (root.inner - columnSpacing) / 2

            Tile {
                width: parent.cell
                icon: root.dnd ? "bell-off" : "bell"
                title: "Do not disturb"
                detail: root.dnd ? "Popups held back" : Notifications.unread > 0 ? Notifications.unread + " waiting" : "Off"
                on: root.dnd
                more: Notifications.serving
                onToggled: root.setDnd(!root.dnd)
                onOpened: root.go("notifications")
            }
            Tile {
                width: parent.cell
                icon: "sunset-2"
                title: "Night light"
                detail: !Core.known ? "…" : Core.nightlightForced ? "On now" : Core.nightlight ? (Core.nightlightActive ? "On · scheduled" : "Scheduled") : "Off"
                on: Core.nightlight || Core.nightlightForced
                onToggled: Core.toggleNightlight()
            }
            Tile {
                width: parent.cell
                icon: "coffee"
                title: "Stay awake"
                detail: !Core.known ? "…" : Core.caffeine ? "Screen stays on" : "Off"
                on: Core.caffeine
                onToggled: Core.toggleCaffeine()
            }
            Tile {
                width: parent.cell
                icon: Audio.micMuted ? "microphone-off" : "microphone"
                title: "Microphone"
                detail: !Audio.micReady ? "None" : Audio.micMuted ? "Muted" : "Live"
                on: Audio.micReady && !Audio.micMuted
                onToggled: Audio.toggleMicMute()
            }
        }
    }

    // ── media ───────────────────────────────────────────────────────────────
    Component {
        id: media
        Item {
            visible: Media.present
            implicitHeight: Media.present ? 64 : 0

            Interactive {
                anchors.fill: parent
                anchors.rightMargin: 116
                anchors.margins: -Metrics.s2
                radius: Metrics.radiusLg
                onClicked: root.go("media")
            }
            Rectangle {
                id: art
                width: 64
                height: 64
                radius: Metrics.radiusMd
                color: Theme.well
                clip: true
                Image {
                    anchors.fill: parent
                    source: Media.art
                    sourceSize.width: ExperiencePolicy.artSize
                    sourceSize.height: ExperiencePolicy.artSize
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
    }

    // ── power: the system profile and Zynith's Experience profile ───────────
    Component {
        id: power
        Column {
            spacing: Metrics.s3

            Item {
                width: root.inner
                height: 16
                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: "Power"
                }
                Label {
                    anchors.right: parent.right
                    role: "caption"
                    caps: true
                    tone: ExperiencePolicy.automatic ? "accent" : "faint"
                    text: "Experience · " + (ExperiencePolicy.labels[ExperiencePolicy.profile] ?? "") + (ExperiencePolicy.automatic ? " · auto" : "")
                }
            }
            Segmented {
                width: root.inner
                current: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
                options: PowerProfiles.hasPerformanceProfile ? [{ key: "saver", label: "Saver" }, { key: "balanced", label: "Balanced" }, { key: "performance", label: "Performance" }] : [{ key: "saver", label: "Saver" }, { key: "balanced", label: "Balanced" }]
                onPicked: key => PowerProfiles.profile = key === "saver" ? PowerProfile.PowerSaver : key === "performance" ? PowerProfile.Performance : PowerProfile.Balanced
            }
        }
    }

    // ── system ──────────────────────────────────────────────────────────────
    Component {
        id: system
        Item {
            implicitHeight: systemRow.implicitHeight
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
    }

    // ── the latest notifications ────────────────────────────────────────────
    Component {
        id: notifications
        Column {
            visible: Notifications.serving && Notifications.history.length > 0
            spacing: Metrics.s1
            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: "Notifications"
            }
            Repeater {
                model: Notifications.history.slice(0, 3)
                delegate: NotificationCard {
                    required property var modelData
                    width: root.inner
                    compact: true
                    entry: modelData
                }
            }
        }
    }

    // ── the latest clipboard entries ────────────────────────────────────────
    Component {
        id: clipboard
        Column {
            spacing: Metrics.s1
            Component.onCompleted: Clipboard.refresh()
            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: "Clipboard"
            }
            Repeater {
                model: Clipboard.entries.slice(0, 3)
                delegate: ListRow {
                    required property var modelData
                    width: root.inner
                    icon: modelData.image ? "photo" : "clipboard-list"
                    title: modelData.image ? "Image" : modelData.preview.replace(/\s+/g, " ").trim()
                    onClicked: {
                        Clipboard.select(modelData.id);
                        PanelRouter.close(root.screen.name);
                    }
                }
            }
        }
    }
}
