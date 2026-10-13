import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The Control Panel: quick interaction, not configuration. Built from the sections [control_panel] columns
// names (ControlSections: the catalogue, defaults, validation); each holds what it reads only while the panel
// shows, and one whose service this machine lacks takes no room. The native Control Center's tabs are modules
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

    // which sections show and where: one list, [control_panel] columns (ControlSections owns the catalogue,
    // the defaults and the validation); the column layout reads the same sections one after another
    readonly property var columns: ControlSections.arrangement(cfg)
    readonly property var weights: ControlSections.weights(columns, cfg.column_widths)
    readonly property real weightSum: weights.reduce((a, b) => a + b, 0)
    // every section shown, in reading order (numbers the section heads)
    readonly property var order: ControlSections.flat(columns)
    // cards: each module on its own soft plate (the dashboard's default, as Caelestia's blocks)
    readonly property string moduleStyle: cfg.module_style ?? "auto"
    // on the connected tab sheet, the sheet is the plate: sections sit on it bare (no box inside a box)
    property bool onSheet: false
    // how far in the sheet stands from the card (the page pads from the sheet's edge, not the card's)
    property real sheetInset: 0
    readonly property bool cards: !onSheet && (moduleStyle === "cards" || (moduleStyle === "auto" && dashboard))
    // [control_panel] section_heads: each module under an indexed head (on by default)
    readonly property bool heads: cfg.section_heads === true || ((cfg.section_heads ?? "auto") === "auto" && !dashboard)
    // the gap between modules is each shown module's own (below it), so a module that has nothing to show
    // takes neither room nor a gap
    readonly property real gap: cfg.spacing ?? Metrics.s5
    padding: sheetInset + Metrics.s5
    // the sheet has no inset at its top (the current tab joins it there)
    topPadding: Metrics.s5
    bottomPadding: sheetInset + Math.max(0, Metrics.s5 - gap)
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
        when: root.active && (root.order.includes("levels") || root.order.includes("brightness"))
    }
    onActiveChanged: if (active)
        Core.refresh()
    Component.onCompleted: Core.refresh()

    readonly property bool dnd: ControlShortcuts.dnd

    // ── the column layout ──
    Repeater {
        model: root.dashboard ? [] : root.order
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
                clipboard: clipboard,
                about: about,
                volume: volume,
                microphone: microphone,
                brightness: brightness,
                network: network,
                bluetooth: bluetooth,
                session: session,
                profile: profile
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
        readonly property string title: ControlSections.title(moduleId)
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
            index: String(slot.host.order.filter(m => ControlSections.title(m) !== "").indexOf(slot.moduleId) + 1).padStart(2, "0")
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

    // ── levels: volume, microphone, brightness — together, or each a section of its own ──
    component LevelRow: Row {
        id: level
        property var host: null   // the panel (an inline component does not see the file's ids)
        property string key: "volume"
        visible: key === "volume" ? Audio.ready : key === "mic" ? Audio.micReady : Backlight.available
        spacing: Metrics.s3

        readonly property real value: key === "volume" ? Audio.volume : key === "mic" ? Audio.micVolume : Backlight.value
        readonly property bool off: key === "volume" ? Audio.muted : key === "mic" ? Audio.micMuted : false

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: level.key === "volume" ? Audio.glyph : level.key === "mic" ? (Audio.micMuted ? "microphone-off" : "microphone") : "brightness-up"
            tone: level.off ? "faint" : "ink"
            onClicked: level.key === "volume" ? Audio.toggleMute() : level.key === "mic" ? Audio.toggleMicMute() : level.host.go("monitor")
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
                onClicked: level.host.go(level.key === "brightness" ? "monitor" : "audio")
            }
        }
    }
    Component {
        id: levels
        Column {
            spacing: Metrics.s2
            Repeater {
                // which sliders, in order: [control_panel] levels
                model: Array.from(root.cfg.levels ?? ["volume", "mic", "brightness"]).filter(k => ["volume", "mic", "brightness"].includes(k))
                delegate: LevelRow {
                    required property string modelData
                    host: root
                    key: modelData
                    width: parent?.width ?? 0
                }
            }
        }
    }
    Component {
        id: volume
        LevelRow {
            host: root
            key: "volume"
        }
    }
    Component {
        id: microphone
        LevelRow {
            host: root
            key: "mic"
        }
    }
    Component {
        id: brightness
        LevelRow {
            host: root
            key: "brightness"
        }
    }

    // ── a service in one line: its state, a switch, the row opens its page ──
    component StateRow: Item {
        id: srow
        property var host: null
        property string icon: ""
        property string title: ""
        property string detail: ""
        property bool on: false
        property string page: ""
        signal switched
        implicitHeight: 44
        Interactive {
            anchors.fill: parent
            anchors.rightMargin: sw.width + Metrics.s3
            radius: Metrics.radiusMd
            onClicked: srow.host.go(srow.page)
        }
        Icon {
            id: sicon
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            name: srow.icon
            size: 18
            tone: srow.on ? "accent" : "muted"
        }
        Column {
            anchors.left: sicon.right
            anchors.leftMargin: Metrics.s3
            anchors.right: sw.left
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Label {
                width: parent.width
                role: "body"
                elide: Text.ElideRight
                text: srow.title
            }
            Label {
                width: parent.width
                visible: text !== ""
                role: "label"
                tone: "faint"
                elide: Text.ElideRight
                text: srow.detail
            }
        }
        Toggle {
            id: sw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: srow.on
            onToggled: srow.switched()
        }
    }

    // ── Wi‑Fi ──
    Component {
        id: network
        StateRow {
            host: root
            visible: Network.available && Network.hasWifi
            icon: Network.glyph
            title: !Network.wifiEnabled ? "Wi‑Fi off" : Network.connected ? Network.name : "Not connected"
            detail: !Network.wifiEnabled ? "" : Network.connected ? (Network.wired ? "Ethernet" : Math.round(Network.strength * 100) + "% signal") + (Network.vpn !== "" ? "  ·  VPN " + Network.vpn : "") : "Choose a network"
            on: Network.wifiEnabled
            page: "network"
            onSwitched: Network.setWifiEnabled(!Network.wifiEnabled)
        }
    }

    // ── Bluetooth ──
    Component {
        id: bluetooth
        StateRow {
            host: root
            visible: Bluetooth.available
            icon: Bluetooth.enabled ? (Bluetooth.connected.length > 0 ? "bluetooth-connected" : "bluetooth") : "bluetooth-off"
            title: Bluetooth.enabled ? "Bluetooth" : "Bluetooth off"
            detail: Bluetooth.enabled ? (Bluetooth.connected.length === 0 ? "No devices connected" : Bluetooth.connected.map(d => d.name).join(", ")) : ""
            on: Bluetooth.enabled
            page: "bluetooth"
            onSwitched: Bluetooth.setEnabled(!Bluetooth.enabled)
        }
    }

    // ── power actions: the session menu's, in a row; the ones that end the session ask twice ──
    Component {
        id: session
        Item {
            id: sess
            implicitHeight: 56
            readonly property var known: ({
                    lock: { label: "Lock", icon: "lock", confirm: false },
                    suspend: { label: "Sleep", icon: "zzz", confirm: false },
                    hibernate: { label: "Hibernate", icon: "snowflake", confirm: true },
                    logout: { label: "Log out", icon: "logout", confirm: true },
                    reboot: { label: "Restart", icon: "refresh", confirm: true },
                    shutdown: { label: "Shut down", icon: "power", confirm: true }
                })
            // [panels] session_actions, as the session menu
            readonly property var actions: Array.from(Config.panels?.session_actions ?? ["lock", "suspend", "logout", "reboot", "shutdown"]).filter(id => known[id] !== undefined)
            property string armed: ""
            Timer {
                id: disarm
                interval: 4000
                onTriggered: sess.armed = ""
            }
            // the same request the session menu sends; the native shell carries it out (the lock is its own)
            function run(id: string): void {
                if (known[id].confirm && armed !== id) {
                    armed = id;
                    disarm.restart();
                    return;
                }
                armed = "";
                PanelRouter.close(root.screen.name);
                CoreClient.call("session " + id);
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.s2
                Repeater {
                    model: sess.actions
                    delegate: Column {
                        id: act
                        required property string modelData
                        readonly property bool armed: sess.armed === modelData
                        width: Math.min(64, (sess.width - Metrics.s2 * (sess.actions.length - 1)) / Math.max(1, sess.actions.length))
                        spacing: Metrics.s1
                        IconButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: sess.known[act.modelData].icon
                            tone: act.armed ? "danger" : "ink"
                            active: act.armed
                            onClicked: sess.run(act.modelData)
                        }
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            role: "micro"
                            tone: act.armed ? "danger" : "muted"
                            elide: Text.ElideRight
                            text: act.armed ? "Again" : sess.known[act.modelData].label
                        }
                    }
                }
            }
        }
    }

    // ── the Experience profile: automatic, or one picked ──
    Component {
        id: profile
        Column {
            spacing: Metrics.s2
            // chips that wrap: the names stay whole in a narrow column
            Flow {
                width: parent.width
                spacing: Metrics.s1
                Repeater {
                    model: ["auto"].concat(ExperiencePolicy.profiles)
                    delegate: Chip {
                        required property string modelData
                        text: modelData === "auto" ? "Auto" : ExperiencePolicy.labels[modelData]
                        active: modelData === "auto" ? ExperiencePolicy.automatic : !ExperiencePolicy.automatic && ExperiencePolicy.profile === modelData
                        onClicked: ExperiencePolicy.select(modelData)
                    }
                }
            }
            Label {
                width: parent.width
                role: "label"
                tone: "faint"
                elide: Text.ElideRight
                text: (ExperiencePolicy.automatic ? "Now " + ExperiencePolicy.labels[ExperiencePolicy.profile] : "Picked by you") + (ExperiencePolicy.limitedBy !== "" ? "  ·  held back: " + ExperiencePolicy.limitedBy : "")
            }
        }
    }

    // ── system info: who, which machine, which system, how long up ──
    Component {
        id: about
        Item {
            id: info
            implicitHeight: Math.max(44, infoText.implicitHeight)
            property real uptime: 0
            FileView {
                id: uptimeFile
                path: "/proc/uptime"
                onLoaded: info.uptime = Number(text().split(" ")[0]) || 0
            }
            // read when shown, then each minute while the panel is
            Timer {
                interval: 60000
                repeat: true
                running: root.active
                onTriggered: uptimeFile.reload()
            }
            readonly property string since: {
                const t = Math.floor(uptime / 60), d = Math.floor(t / 1440), h = Math.floor(t % 1440 / 60), m = t % 60;
                return uptime <= 0 ? "" : "up " + (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m";
            }
            Avatar {
                id: infoAvatar
                anchors.verticalCenter: parent.verticalCenter
                size: 40
            }
            Column {
                id: infoText
                anchors.left: infoAvatar.right
                anchors.leftMargin: Metrics.s3
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Label {
                    width: parent.width
                    role: "body"
                    elide: Text.ElideRight
                    text: (About.realName || About.user) + "  ·  " + About.user + "@" + (About.host || "localhost")
                }
                Label {
                    width: parent.width
                    role: "label"
                    tone: "faint"
                    elide: Text.ElideRight
                    text: [About.os, About.kernel, info.since].filter(t => t !== "").join("  ·  ")
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

    // ── notifications: Do not disturb, and the latest ones ──
    Component {
        id: notifications
        Column {
            spacing: Metrics.s1
            StateRow {
                host: root
                width: parent.width
                icon: root.dnd ? "bell-off" : "bell"
                title: "Do not disturb"
                detail: root.dnd ? "Popups held back" : Notifications.unread > 0 ? Notifications.unread + " waiting" : "Off"
                on: root.dnd
                page: "notifications"
                onSwitched: ControlShortcuts.setDnd(!root.dnd)
            }
            Repeater {
                model: Notifications.serving ? Notifications.history.slice(0, 3) : []
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
