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
    // [control_panel] layout: dashboard (modules in columns side by side, wide and short — Caelestia's
    // dashboard) | column (one tall column, the earlier look)
    readonly property bool dashboard: (cfg.layout ?? "dashboard") === "dashboard"
    readonly property int preferredWidth: dashboard ? (cfg.dashboard_width ?? 1080) : (cfg.width ?? 420)

    function canonical(m: string): string {
        return m === "connectivity" || m === "toggles" ? "shortcuts" : m === "screen-time" ? "screen_time" : m;
    }
    // the old switch rows are the shortcut tiles now; a list that still names them gets the tiles, once
    function dedupe(list: var, seen: var): var {
        const out = [];
        for (const m of Array.from(list ?? [])) {
            const id = canonical(String(m));
            if (!seen.includes(id)) {
                seen.push(id);
                out.push(id);
            }
        }
        return out;
    }
    readonly property var modules: dedupe(cfg.modules ?? ["header", "shortcuts", "levels", "media", "power", "system"], [])
    // [control_panel] columns: the dashboard's columns, each a list of modules top to bottom
    readonly property var columns: {
        const seen = [];
        const given = Array.from(cfg.columns ?? [["media"], ["shortcuts", "levels"], ["weather"]]);
        return given.map(c => dedupe(typeof c === "string" ? [c] : Array.from(c), seen)).filter(c => c.length > 0);
    }
    // [control_panel] column_widths: a weight per column (missing or 0 = 1)
    readonly property var weights: columns.map((c, i) => Math.max(0.1, Number((cfg.column_widths ?? [])[i] ?? 1) || 1))
    readonly property real weightSum: weights.reduce((a, b) => a + b, 0)
    // every module shown, in reading order (numbers the section heads)
    readonly property var order: dashboard ? columns.reduce((all, c) => all.concat(c), []) : modules
    // cards: each module on its own soft plate (the dashboard's default, as Caelestia's blocks)
    readonly property string moduleStyle: cfg.module_style ?? "auto"
    readonly property bool cards: moduleStyle === "cards" || (moduleStyle === "auto" && dashboard)
    // [control_panel] section_heads: each module under an indexed head (on by default)
    readonly property bool heads: cfg.section_heads === true || ((cfg.section_heads ?? "auto") === "auto" && !dashboard)
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
        when: root.active && root.order.includes("system")
    }
    Hold {
        service: "backlight"
        when: root.active && root.order.includes("levels")
    }
    onActiveChanged: if (active)
        Core.refresh()
    Component.onCompleted: Core.refresh()

    readonly property bool dnd: ControlShortcuts.dnd

    // ── the column layout ──
    Repeater {
        model: root.dashboard ? [] : root.modules
        delegate: Slot {
            required property string modelData
            required property int index
            host: root
            moduleId: modelData
            order: index
            width: root.inner
        }
    }

    // ── the dashboard layout: columns side by side, each module on its plate ──
    Row {
        id: dash
        visible: root.dashboard
        width: root.inner
        spacing: root.gap
        readonly property real share: (width - spacing * Math.max(0, root.columns.length - 1)) / Math.max(0.1, root.weightSum)
        Repeater {
            model: root.dashboard ? root.columns : []
            delegate: Column {
                id: column
                required property var modelData
                required property int index
                width: dash.share * (root.weights[index] ?? 1)
                Repeater {
                    model: column.modelData
                    delegate: Slot {
                        required property string modelData
                        host: root
                        moduleId: modelData
                        order: root.order.indexOf(modelData)
                        width: column.width
                    }
                }
            }
        }
    }

    function componentFor(id: string): Component {
        return ({
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
            })[id] ?? null;
    }

    // one module where it sits: its head, its plate, the module itself
    component Slot: Item {
        id: slot
        property var host: null
        property string moduleId: ""
        property int order: 0
        readonly property real progress: host.stage(order)
        // never hidden itself (a module's own visible is read here, and it would follow this one's)
        readonly property bool shown: loader.item !== null && loader.item.visible && loader.height > 0
        // a section head names it ("02  LEVELS ───"): hierarchy by type and rule, not by a box
        readonly property string title: host.titles[moduleId] ?? ""
        readonly property bool headed: host.heads && title !== ""
        readonly property real headH: headed ? 18 + Metrics.s3 : 0
        readonly property real inset: host.cards ? Metrics.s4 : 0
        height: shown ? loader.height + headH + inset * 2 + host.gap : 0
        opacity: progress
        transform: Translate {
            y: (1 - slot.progress) * 10
        }

        Rectangle {
            visible: slot.host.cards && slot.shown
            width: parent.width
            height: parent.height - slot.host.gap
            radius: Metrics.radiusSurface - Metrics.s2
            color: Theme.plate
            border.width: Metrics.hairline
            border.color: Theme.hairline
        }
        SectionHead {
            visible: slot.headed && slot.shown
            x: slot.inset
            y: slot.inset
            width: parent.width - x * 2
            index: String(slot.host.order.filter(m => slot.host.titles[m]).indexOf(slot.moduleId) + 1).padStart(2, "0")
            title: slot.title
        }
        Loader {
            id: loader
            x: slot.inset
            y: slot.inset + slot.headH
            width: parent.width - x * 2
            sourceComponent: slot.host.componentFor(slot.moduleId)
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
                // only where it fits beside the date
                visible: parent.width - date.implicitWidth - Metrics.s4 >= implicitWidth
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
                    width: parent?.width ?? 0
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

    // ── media: now playing, with the spectrum, the timeline and the words ──
    Component {
        id: media
        MediaModule {
            screen: root.screen
            active: root.active
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
            // side by side where there is room, stacked in a narrow column
            Grid {
                id: systemRow
                width: parent.width
                columns: width >= 320 ? 2 : 1
                columnSpacing: Metrics.s5
                rowSpacing: Metrics.s3
                readonly property real cell: columns === 2 ? (width - columnSpacing) / 2 : width
                Meter {
                    width: systemRow.cell
                    label: "CPU"
                    value: System.cpu
                }
                Meter {
                    width: systemRow.cell
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
                    width: parent?.width ?? 0
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
                    width: parent?.width ?? 0
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
