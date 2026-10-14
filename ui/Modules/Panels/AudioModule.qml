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
    readonly property int pageColumns: expanded ? Math.max(1, Config.controlPanel?.page_columns ?? 2) : 1
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

    // ── on the page: every device ──
    Repeater {
        model: root.expanded ? [
            { key: "output", title: "Output", nodes: Audio.sinks, current: Audio.sink },
            { key: "input", title: "Input", nodes: Audio.sources, current: Audio.source }
        ] : []
        delegate: Column {
            id: devices
            required property var modelData
            width: root.colW
            spacing: Metrics.s2

            Label {
                role: "caption"
                tone: "faint"
                caps: true
                text: devices.modelData.title
            }
            // the default's own level
            Row {
                width: parent.width
                spacing: Metrics.s3
                visible: devices.modelData.current !== null
                readonly property bool out: devices.modelData.key === "output"
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: parent.out ? Audio.glyph : (Audio.micMuted ? "microphone-off" : "microphone")
                    onClicked: parent.out ? Audio.toggleMute() : Audio.toggleMicMute()
                }
                Slider {
                    wheelAdjusts: true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Metrics.control - 40 - Metrics.s3 * 2
                    value: parent.out ? Audio.volume : Audio.micVolume
                    opacity: (parent.out ? Audio.muted : Audio.micMuted) ? 0.5 : 1
                    onMoved: v => parent.out ? Audio.setVolume(v) : Audio.setMicVolume(v)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    role: "label"
                    numeric: true
                    tone: "muted"
                    text: Math.round((parent.out ? Audio.volume : Audio.micVolume) * 100)
                }
            }
            // the default first; past [panels] device_rows (6) the list scrolls rather than stretching the panel
            // (a network full of AirPlay receivers lists them all)
            ListView {
                id: deviceList
                width: devices.width
                readonly property int rows: Math.max(1, Config.panels?.device_rows ?? 6)
                model: [devices.modelData.current].filter(n => n !== null && devices.modelData.nodes.includes(n)).concat(devices.modelData.nodes.filter(n => n !== devices.modelData.current))
                height: count === 0 ? 0 : Math.min(contentHeight, rows * contentHeight / count)
                interactive: count > rows
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: ListRow {
                    required property var modelData
                    width: deviceList.width
                    icon: devices.modelData.key === "output" ? (modelData.properties?.["device.form-factor"] === "headphones" || modelData.properties?.["device.form-factor"] === "headset" ? "headphones" : "device-speaker") : "microphone"
                    title: Audio.nodeName(modelData)
                    active: modelData === devices.modelData.current
                    trailing: modelData === devices.modelData.current ? "Default" : ""
                    onClicked: devices.modelData.key === "output" ? Audio.setSink(modelData) : Audio.setSource(modelData)
                }
            }
            Label {
                visible: devices.modelData.nodes.length === 0
                role: "label"
                tone: "faint"
                text: devices.modelData.key === "output" ? "No output devices" : "No input devices"
            }
        }
    }

    // ── each app's level ──
    Column {
        width: root.colW
        spacing: Metrics.s2
        visible: root.apps.length > 0 || root.expanded

        Label {
            visible: root.expanded
            role: "caption"
            tone: "faint"
            caps: true
            text: "Apps"
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
