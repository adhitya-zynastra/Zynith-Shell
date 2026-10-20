import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Sound: where it goes, where it comes from, and each app's own level. In the Control Panel: the output and
// the first few apps ([control_panel] mixer_apps); on its own page: every device, every app, what is
// recording, and EasyEffects' profiles when it runs.
Flow {
    id: root
    // On its page the module flows into columns — top to bottom, wrapping at a height that balances them
    // ([control_panel] page_columns); in the Control Panel it is one stack, as before.
    readonly property int pageColumns: expanded ? Metrics.pageColumns(width, Config.controlPanel?.page_columns ?? 2) : 1
    readonly property real colW: pageColumns > 1 ? (width - spacing * (pageColumns - 1)) / pageColumns : width
    flow: pageColumns > 1 ? Flow.TopToBottom : Flow.LeftToRight
    height: pageColumns > 1 ? balancedHeight() : implicitHeight
    function columnsFor(h: real): int {
        let cols = 1, used = 0;
        for (const c of children) {
            if (!c.visible || c.height <= 0)
                continue;
            const need = (used > 0 ? used + spacing : 0) + c.height;
            if (need > h && used > 0) {
                cols++;
                used = c.height;
            } else {
                used = need;
            }
        }
        return cols;
    }
    function balancedHeight(): real {
        let total = 0, tallest = 0, n = 0;
        for (const c of children) {
            if (!c.visible || c.height <= 0)
                continue;
            total += c.height;
            tallest = Math.max(tallest, c.height);
            n++;
        }
        total += spacing * Math.max(0, n - 1);
        let h = Math.max(tallest, total / pageColumns);
        for (let i = 0; i < 60 && columnsFor(h) > pageColumns; i++)
            h += 12;
        return Math.ceil(h);
    }

    property var screen: null
    property bool active: true
    property bool expanded: false

    readonly property int mixerApps: Config.controlPanel?.mixer_apps ?? 3
    readonly property var apps: expanded ? Audio.playback : Audio.playback.slice(0, mixerApps)

    spacing: expanded ? Metrics.s5 : Metrics.s3

    // EasyEffects' profiles, asked for when the page opens
    property var effects: ({ available: false })
    function readEffects(): void {
        CoreClient.call("effects-status", text => {
            try {
                root.effects = JSON.parse(text);
            } catch (e) {}
        });
    }
    Component.onCompleted: if (expanded)
        readEffects()

    // ── where sound goes ──
    Item {
        visible: !root.expanded
        width: root.colW
        height: 40
        Interactive {
            anchors.fill: parent
            anchors.margins: -Metrics.s2
            radius: Metrics.radiusMd
            onClicked: PanelRouter.navigate("audio", root.screen.name)
        }
        Icon {
            id: outIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: "device-speaker"
            tone: "muted"
        }
        Column {
            anchors.left: outIcon.right
            anchors.leftMargin: Metrics.s3
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: "Output"
            }
            Label {
                width: parent.width
                role: "label"
                elide: Text.ElideRight
                text: Audio.sinkName || "No output"
            }
        }
        Icon {
            id: chevron
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-right"
            size: 14
            tone: "faint"
        }
    }

    // ── on the page: where it plays, then where else it can ──
    // Devices grouped by where they are, so six look-alike rows read as a choice: this computer, Bluetooth, the
    // displays, the network (AirPlay receivers).
    function kindOf(n: var): string {
        const name = (n?.name ?? "") + " " + (n?.description ?? "");
        if (/raop|airplay/i.test(name))
            return "network";
        if (/bluez/i.test(n?.name ?? ""))
            return "bluetooth";
        if (/hdmi|displayport|\bdp\b/i.test(name))
            return "display";
        return "here";
    }
    // which device groups are unfolded (by key), as you leave them while the page is open
    property var openGroups: ({})
    readonly property var kinds: [
        { key: "here", title: "This computer" },
        { key: "bluetooth", title: "Bluetooth" },
        { key: "display", title: "Displays" },
        { key: "network", title: "On the network" }
    ]
    function outputGlyph(n: var): string {
        const f = n?.properties?.["device.form-factor"] ?? "";
        const k = kindOf(n);
        return f === "headphones" || f === "headset" || k === "bluetooth" ? "headphones" : k === "display" ? "device-tv" : k === "network" ? "device-laptop" : "device-speaker";
    }
    function kindLabel(n: var): string {
        const f = n?.properties?.["device.form-factor"] ?? "";
        return ({ here: f === "headphones" || f === "headset" ? "Headphones" : "Built-in", bluetooth: "Bluetooth", display: "Display audio", network: "AirPlay receiver" })[kindOf(n)];
    }

    Column {
        visible: root.expanded
        width: root.colW
        spacing: Metrics.s3

        Instrument {
            width: parent.width
            icon: Audio.ready ? (Audio.muted ? "volume-off" : root.outputGlyph(Audio.sink)) : "volume-off"
            iconOn: Audio.ready && !Audio.muted
            caption: "PLAYING ON"
            title: Audio.ready ? Audio.sinkName : "No output"
            detail: !Audio.ready ? "Nothing to play on" : Audio.muted ? "Muted · click the speaker to unmute" : root.kindLabel(Audio.sink)
            value: Audio.ready ? (Audio.muted ? "Muted" : String(Math.round(Audio.volume * 100))) : ""
            unit: Audio.ready && !Audio.muted ? "%" : ""
            level: Audio.ready ? Audio.volume : -1
            dimmed: Audio.muted
            onIconClicked: Audio.toggleMute()
            onLevelMoved: v => Audio.setVolume(v)
        }

        SectionHead {
            visible: Audio.sinks.length > 1
            width: parent.width
            title: "PLAY ON"
            Label {
                role: "data"
                tone: "faint"
                text: String(Audio.sinks.length)
            }
        }
        // grouped; past [panels] device_rows the groups scroll rather than stretching the panel
        Flickable {
            id: outputs
            visible: Audio.sinks.length > 1
            width: parent.width
            readonly property int rows: Math.max(1, Config.panels?.device_rows ?? 6)
            height: Math.min(groups.implicitHeight, rows * 46 + 4 * 28)
            contentHeight: groups.implicitHeight
            interactive: contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: groups
                width: outputs.width
                spacing: Metrics.s2
                Repeater {
                    model: root.kinds.filter(k => Audio.sinks.some(n => root.kindOf(n) === k.key))
                    delegate: Column {
                        id: group
                        required property var modelData
                        readonly property var members: Audio.sinks.filter(n => root.kindOf(n) === group.modelData.key)
                        // the group playing now is open; the others fold to one line until asked for
                        readonly property bool open: root.openGroups[group.modelData.key] ?? group.members.includes(Audio.sink)
                        width: groups.width
                        spacing: 2
                        Item {
                            width: parent.width
                            height: 26
                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.s2
                                anchors.verticalCenter: parent.verticalCenter
                                role: "caption"
                                tone: "faint"
                                text: group.modelData.title + (group.open ? "" : "  ·  " + group.members.length)
                            }
                            Icon {
                                anchors.right: parent.right
                                anchors.rightMargin: Metrics.s2
                                anchors.verticalCenter: parent.verticalCenter
                                name: group.open ? "chevron-down" : "chevron-right"
                                size: 14
                                tone: "faint"
                            }
                            Interactive {
                                anchors.fill: parent
                                radius: Metrics.radiusMd
                                onClicked: {
                                    const next = Object.assign({}, root.openGroups);
                                    next[group.modelData.key] = !group.open;
                                    root.openGroups = next;
                                }
                            }
                        }
                        Repeater {
                            model: group.open ? group.members : []
                            delegate: ListRow {
                                required property var modelData
                                width: group.width
                                icon: root.outputGlyph(modelData)
                                title: Audio.nodeName(modelData)
                                active: modelData === Audio.sink
                                trailing: modelData === Audio.sink ? "Playing" : ""
                                onClicked: Audio.setSink(modelData)
                            }
                        }
                    }
                }
            }
        }
        Label {
            visible: Audio.sinks.length === 0
            role: "label"
            tone: "faint"
            text: "No output devices"
        }
    }

    // the microphone: its own level, and the others to switch to
    Column {
        visible: root.expanded
        width: root.colW
        spacing: Metrics.s3
        // apart from the device list above it in one column; level with the output in two
        topPadding: root.pageColumns > 1 ? 0 : Metrics.s3

        Instrument {
            width: parent.width
            icon: Audio.micReady && !Audio.micMuted ? "microphone" : "microphone-off"
            iconOn: Audio.micReady && !Audio.micMuted
            caption: "LISTENING WITH"
            title: Audio.micReady ? Audio.nodeName(Audio.source) : "No microphone"
            detail: !Audio.micReady ? "Nothing to record with" : Audio.micMuted ? "Muted" : Audio.recording.length > 0 ? Audio.recording.length + (Audio.recording.length === 1 ? " app is listening" : " apps are listening") : "Live"
            value: Audio.micReady ? (Audio.micMuted ? "Off" : String(Math.round(Audio.micVolume * 100))) : ""
            unit: Audio.micReady && !Audio.micMuted ? "%" : ""
            level: Audio.micReady ? Audio.micVolume : -1
            dimmed: Audio.micMuted
            onIconClicked: Audio.toggleMicMute()
            onLevelMoved: v => Audio.setMicVolume(v)
        }
        Flow {
            visible: Audio.sources.length > 1
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: Audio.sources
                delegate: Chip {
                    required property var modelData
                    icon: modelData === Audio.source ? "check" : "microphone"
                    text: Audio.nodeName(modelData)
                    active: modelData === Audio.source
                    onClicked: Audio.setSource(modelData)
                }
            }
        }
    }

    // ── each app's level ──
    Column {
        width: root.colW
        spacing: Metrics.s2
        visible: root.apps.length > 0 || root.expanded

        SectionHead {
            visible: root.expanded
            width: parent.width
            title: "APPS"
            Label {
                role: "data"
                tone: "faint"
                text: String(Audio.playback.length)
            }
        }
        Label {
            visible: root.expanded && Audio.playback.length === 0
            role: "label"
            tone: "faint"
            text: "No app is playing sound"
        }
        Repeater {
            model: root.apps
            delegate: AppLevel {
                required property var modelData
                width: root.colW
                node: modelData
            }
        }
        Label {
            visible: !root.expanded && Audio.playback.length > root.mixerApps && root.mixerApps > 0
            role: "caption"
            tone: "faint"
            text: "+" + (Audio.playback.length - root.mixerApps) + " more"
        }
    }

    // ── what is listening ──
    Column {
        visible: root.expanded && Audio.recording.length > 0
        width: root.colW
        spacing: Metrics.s2
        Label {
            role: "caption"
            tone: "faint"
            caps: true
            text: "Recording"
        }
        Repeater {
            model: root.expanded ? Audio.recording : []
            delegate: ListRow {
                required property var modelData
                width: root.colW
                icon: "microphone"
                title: Audio.appName(modelData)
                detail: Audio.streamTitle(modelData)
                PwObjectTracker {
                    objects: [modelData]
                }
            }
        }
    }

    // ── EasyEffects ──
    Repeater {
        model: root.expanded && root.effects.available ? ["output", "input"].filter(k => (root.effects[k]?.profiles ?? []).length > 0) : []
        delegate: Column {
            id: fx
            required property string modelData
            width: root.colW
            spacing: Metrics.s2
            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: "Effects · " + fx.modelData
            }
            Flow {
                width: parent.width
                spacing: Metrics.s2
                Repeater {
                    model: root.effects[fx.modelData].profiles
                    delegate: Chip {
                        required property string modelData
                        text: modelData
                        active: root.effects[fx.modelData].active === modelData
                        onClicked: CoreClient.call("effects-profile-set " + fx.modelData + " " + modelData, () => root.readEffects())
                    }
                }
            }
        }
    }

    // one app: its icon, its name and what it plays, its level
    component AppLevel: Item {
        id: app
        property var node: null
        readonly property bool muted: node?.audio?.muted ?? false
        readonly property real level: node?.audio?.volume ?? 0
        readonly property string iconPath: Quickshell.iconPath(Audio.appIcon(node), true)
        implicitHeight: 44
        // this row's stream is live while the row is
        PwObjectTracker {
            objects: [app.node]
        }

        Item {
            id: appIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.control
            height: Metrics.control
            Image {
                anchors.centerIn: parent
                visible: app.iconPath !== ""
                width: 22
                height: 22
                sourceSize.width: 44
                sourceSize.height: 44
                source: app.iconPath
                opacity: app.muted ? 0.45 : 1
                Behavior on opacity {
                    Anim {
                        role: "effects"
                    }
                }
            }
            Icon {
                anchors.centerIn: parent
                visible: app.iconPath === ""
                name: "music"
                tone: app.muted ? "faint" : "muted"
            }
            Interactive {
                anchors.fill: parent
                radius: Metrics.radiusMd
                onClicked: Audio.toggleNodeMute(app.node)
            }
        }
        Column {
            anchors.left: appIcon.right
            anchors.leftMargin: Metrics.s3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Item {
                width: parent.width
                height: appName.implicitHeight
                Label {
                    id: appName
                    width: parent.width - 40
                    role: "label"
                    elide: Text.ElideRight
                    text: Audio.appName(app.node) + (Audio.streamTitle(app.node) !== "" ? "  ·  " + Audio.streamTitle(app.node) : "")
                }
                Label {
                    anchors.right: parent.right
                    role: "caption"
                    numeric: true
                    tone: "faint"
                    text: app.muted ? "muted" : Math.round(app.level * 100)
                }
            }
            Slider {
                wheelAdjusts: true
                width: parent.width
                value: app.level
                opacity: app.muted ? 0.5 : 1
                onMoved: v => Audio.setNodeVolume(app.node, v)
            }
        }
    }
}
