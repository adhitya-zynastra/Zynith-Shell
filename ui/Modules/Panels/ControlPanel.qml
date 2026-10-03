import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The Control Panel: quick interaction, not configuration. Built from modules in [control_panel] modules
// order; each holds what it reads only while the panel shows. The native Control Center's tabs are modules
// here too (audio, monitor, power, calendar, weather, screen_time), each with a page of its own one click in.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true
    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property int preferredWidth: cfg.width ?? 420

    // the old switch rows are the shortcut tiles now; a list that still names them gets the tiles, once
    readonly property var modules: {
        const out = [];
        for (const m of Array.from(cfg.modules ?? ["header", "shortcuts", "levels", "media", "power", "system"])) {
            const id = m === "connectivity" || m === "toggles" ? "shortcuts" : m === "screen-time" ? "screen_time" : m;
            if (!out.includes(id))
                out.push(id);
        }
        return out;
    }
    readonly property bool cards: cfg.module_style === "cards"
    // [control_panel] section_heads: each module under an indexed head (on by default)
    readonly property bool heads: cfg.section_heads !== false
    readonly property var titles: ({
            shortcuts: "Quick",
            levels: "Levels",
            audio: "Sound",
            media: "Now playing",
            monitor: "Display",
            power: "Power",
            calendar: "Calendar",
            weather: "Weather",
            screen_time: "Screen time",
            system: "System",
            notifications: "Notifications",
            clipboard: "Clipboard"
        })

    // the gap between modules is each shown module's own (below it), so a module that has nothing to show
    // takes neither room nor a gap
    readonly property real gap: cfg.spacing ?? Metrics.s5
    padding: Metrics.s5
    bottomPadding: Math.max(0, Metrics.s5 - gap)
    spacing: 0
    readonly property real inner: width - padding * 2

    function go(id: string): void {
        PanelRouter.navigate(id, screen.name);
    }
    // content settles a beat after the surface, one module after another
    function stage(i: int): real {
        if (!ExperiencePolicy.stagger)
            return visibleProgress;
        const delay = Math.min(0.5, 0.07 * i);
        return Math.max(0, Math.min(1, (visibleProgress - delay) / (1 - delay)));
    }

    // what this panel holds while it is on screen
    Hold {
        service: "system"
        when: root.active && root.modules.includes("system")
    }
    Hold {
        service: "backlight"
        when: root.active && root.modules.includes("levels")
    }
    onActiveChanged: if (active)
        Core.refresh()
    Component.onCompleted: Core.refresh()

    readonly property bool dnd: ControlShortcuts.dnd

    Repeater {
        model: root.modules

        delegate: Item {
            id: slot
            required property string modelData
            required property int index
            readonly property real progress: root.stage(index)
            // never hidden itself (a module's own visible is read here, and it would follow this one's)
            readonly property bool shown: loader.item !== null && loader.item.visible && loader.height > 0
            // a section head names it ("02  LEVELS ───"): hierarchy by type and rule, not by a box
            readonly property string title: root.titles[modelData] ?? ""
            readonly property bool headed: root.heads && title !== ""
            readonly property real headH: headed ? 18 + Metrics.s3 : 0
            width: root.inner
            height: shown ? loader.height + headH + (root.cards ? Metrics.s4 * 2 : 0) + root.gap : 0
            opacity: progress
            transform: Translate {
                y: (1 - slot.progress) * 10
            }

            // the cards style: each module on its own soft card
            Rectangle {
                visible: root.cards && slot.shown
                width: parent.width
                height: parent.height - root.gap
                radius: Metrics.radiusSurface - Metrics.s2
                color: Theme.plate
                border.width: Metrics.hairline
                border.color: Theme.hairline
            }
            SectionHead {
                visible: slot.headed && slot.shown
                x: root.cards ? Metrics.s4 : 0
                y: root.cards ? Metrics.s4 : 0
                width: parent.width - x * 2
                index: String(root.modules.filter(m => root.titles[m]).indexOf(slot.modelData) + 1).padStart(2, "0")
                title: slot.title
            }
            Loader {
                id: loader
                x: root.cards ? Metrics.s4 : 0
                y: (root.cards ? Metrics.s4 : 0) + slot.headH
                width: parent.width - x * 2
                sourceComponent: ({
                        header: header,
                        shortcuts: shortcuts,
                        levels: levels,
                        audio: audio,
                        media: media,
                        monitor: monitor,
                        power: power,
                        calendar: calendar,
                        weather: weather,
                        screen_time: screenTime,
                        system: system,
                        notifications: notifications,
                        clipboard: clipboard
                    })[slot.modelData] ?? null
            }
        }
    }

    // ── modules with files of their own ──
    Component {
        id: shortcuts
        ShortcutGrid {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: audio
        AudioModule {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: monitor
        MonitorModule {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: power
        PowerModule {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: calendar
        CalendarModule {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: weather
        WeatherModule {
            screen: root.screen
            active: root.active
        }
    }
    Component {
        id: screenTime
        ScreenTimeModule {
            screen: root.screen
            active: root.active
        }
    }

    // ── header: the time as the one big readout, the day beneath it in the data voice; who and the two
    // ways out (session, Settings) kept small and quiet at the right ──
    Component {
        id: header
        Item {
            implicitHeight: clock.implicitHeight + date.implicitHeight + Metrics.s1

            Row {
                id: clock
                spacing: 2
                Label {
                    id: hm
                    role: "display"
                    numeric: true
                    text: Qt.formatTime(Time.now, "HH:mm")
                }
                Label {
                    visible: root.cfg.header_seconds === true
                    anchors.baseline: hm.baseline
                    role: "data"
                    tone: "faint"
                    text: Qt.formatTime(Time.now, "ss")
                }
            }
            Label {
                id: date
                anchors.top: clock.bottom
                anchors.topMargin: Metrics.s1
                role: "data"
                tone: "muted"
                text: Qt.formatDate(Time.now, "ddd  ·  dd MMM") + (Power.present ? "  ·  " + Math.round(Power.level * 100) + "%" + (Power.charging ? " ⚡" : "") : "")
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Metrics.s2
                spacing: Metrics.s1
                Avatar {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 28
                }
                Item {
                    width: Metrics.s2
                    height: 1
                }
                // the session: lock, log out, restart (the native Control Center's button)
                IconButton {
                    visible: root.cfg.session_button !== false
                    icon: "power"
                    tone: "muted"
                    onClicked: Actions.run("panel session", { screen: root.screen })
                }
                IconButton {
                    icon: "settings"
                    tone: "muted"
                    onClicked: {
                        PanelRouter.close(root.screen.name);
                        Actions.run("settings-open control");
                    }
                }
            }
            Label {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s2
                anchors.bottom: date.bottom
                role: "caption"
                tone: "faint"
                text: About.realName || About.user
            }
        }
    }

    // ── levels: volume, microphone, brightness ──────────────────────────────
    Component {
        id: levels
        Column {
            spacing: Metrics.s2

            Repeater {
                // which sliders, in order: [control_panel] levels
                model: Array.from(root.cfg.levels ?? ["volume", "mic", "brightness"]).filter(k => ["volume", "mic", "brightness"].includes(k))

                delegate: Row {
                    id: level
                    required property string modelData
                    readonly property string key: modelData
                    visible: key === "volume" ? Audio.ready : key === "mic" ? Audio.micReady : Backlight.available
                    width: root.inner
                    spacing: Metrics.s3

                    readonly property real value: key === "volume" ? Audio.volume : key === "mic" ? Audio.micVolume : Backlight.value
                    readonly property bool off: key === "volume" ? Audio.muted : key === "mic" ? Audio.micMuted : false

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: level.key === "volume" ? Audio.glyph : level.key === "mic" ? (Audio.micMuted ? "microphone-off" : "microphone") : "brightness-up"
                        tone: level.off ? "faint" : "ink"
                        onClicked: level.key === "volume" ? Audio.toggleMute() : level.key === "mic" ? Audio.toggleMicMute() : root.go("monitor")
                    }
                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Metrics.control - 40 - Metrics.s3 * 2
                        value: level.value
                        opacity: level.off ? 0.5 : 1
                        onMoved: v => level.key === "volume" ? Audio.setVolume(v) : level.key === "mic" ? Audio.setMicVolume(v) : Backlight.set(v)
                    }
                    // the number opens the page: devices and apps, or every display
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        role: "data"
                        tone: levelArea.containsMouse ? "accent" : level.off ? "faint" : "muted"
                        text: level.off ? "off" : String(Math.round(level.value * 100)).padStart(3, "0")
                        MouseArea {
                            id: levelArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.go(level.key === "brightness" ? "monitor" : "audio")
                        }
                    }
                }
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
