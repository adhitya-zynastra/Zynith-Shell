import QtQuick
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The controls reached for many times a day: levels, a few switches, the power profile. Brightness is
// re-read only while this panel is on screen.
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

    property bool holding: false
    function sync(): void {
        if (active && !holding) {
            Backlight.retain();
            Core.refresh();
            holding = true;
        } else if (!active && holding) {
            Backlight.release();
            holding = false;
        }
    }
    onActiveChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (holding)
        Backlight.release()

    function go(id: string): void {
        PanelRouter.navigate(id, screen.name);
    }

    // DND belongs to whichever notification server is running
    readonly property bool dnd: Notifications.serving ? Notifications.dnd : Core.dnd
    function setDnd(on: bool): void {
        if (Notifications.serving)
            Notifications.setDnd(on);
        else
            Core.setDnd(on);
    }

    PanelHeader {
        width: root.inner
        title: "Quick settings"
        canGoBack: root.canGoBack
        onBack: root.back()
    }

    // ── levels ──────────────────────────────────────────────────────────────
    Column {
        width: root.inner
        spacing: Metrics.s3

        Repeater {
            model: [
                {
                    key: "volume",
                    shown: Audio.ready
                },
                {
                    key: "mic",
                    shown: Audio.micReady
                },
                {
                    key: "brightness",
                    shown: Backlight.available
                }
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

    // ── switches ────────────────────────────────────────────────────────────
    Grid {
        width: root.inner
        columns: 2
        columnSpacing: Metrics.s3
        rowSpacing: Metrics.s3
        readonly property real cell: (width - columnSpacing) / 2

        Tile {
            width: parent.cell
            icon: Network.glyph
            title: "Wi‑Fi"
            detail: !Network.wifiEnabled ? "Off" : Network.name || "Not connected"
            on: Network.wifiEnabled
            more: true
            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
            onOpened: root.go("network")
        }
        Tile {
            width: parent.cell
            icon: Bluetooth.enabled ? (Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth") : "bluetooth-off"
            title: "Bluetooth"
            detail: Bluetooth.available ? Bluetooth.summary : "Unavailable"
            on: Bluetooth.enabled
            more: true
            onToggled: Bluetooth.setEnabled(!Bluetooth.enabled)
            onOpened: root.go("bluetooth")
        }
        Tile {
            width: parent.cell
            icon: root.dnd ? "bell-off" : "bell"
            title: "Do not disturb"
            detail: root.dnd ? "Popups held back" : "Off"
            on: root.dnd
            onToggled: root.setDnd(!root.dnd)
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

    // ── power profile ───────────────────────────────────────────────────────
    Column {
        width: root.inner
        spacing: Metrics.s3

        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Power"
        }
        Segmented {
            width: parent.width
            current: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
            options: PowerProfiles.hasPerformanceProfile ? [
                {
                    key: "saver",
                    label: "Power saver"
                },
                {
                    key: "balanced",
                    label: "Balanced"
                },
                {
                    key: "performance",
                    label: "Performance"
                }
            ] : [
                {
                    key: "saver",
                    label: "Power saver"
                },
                {
                    key: "balanced",
                    label: "Balanced"
                }
            ]
            onPicked: key => PowerProfiles.profile = key === "saver" ? PowerProfile.PowerSaver : key === "performance" ? PowerProfile.Performance : PowerProfile.Balanced
        }
    }
}
