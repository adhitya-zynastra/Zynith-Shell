import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The shortcut tiles. Which and in what order: [control_panel] shortcuts; how big: shortcut_size (compact
// round buttons · regular two-line tiles · wide rows), shortcut_columns, shortcut_labels, and tile_sizes for a
// regular tile that spans its row. A tile's chevron (or a right click) opens what it summarises in place.
Item {
    id: root

    property var screen: null
    property bool active: true

    readonly property var cfg: Config.controlPanel ?? ({})
    readonly property var entries: Array.from(cfg.shortcuts ?? []).map(id => ControlShortcuts.find(id)).filter(e => ControlShortcuts.available(e))
    // the dashboard's columns are narrow: its own size (dashboard_shortcut_size), else shortcut_size
    readonly property bool onDashboard: (cfg.layout ?? "dashboard") === "dashboard"
    readonly property string size: onDashboard ? (cfg.dashboard_shortcut_size ?? cfg.shortcut_size ?? "compact") : (cfg.shortcut_size ?? "regular")
    readonly property int columns: (cfg.shortcut_columns ?? 0) > 0 ? cfg.shortcut_columns : size === "compact" ? 4 : size === "wide" ? 1 : 2
    readonly property bool labels: cfg.shortcut_labels !== false
    readonly property real gap: Metrics.s3
    readonly property real cell: (width - gap * (columns - 1)) / columns

    implicitHeight: flow.implicitHeight
    visible: entries.length > 0

    // pages drawn in place within the Control Panel, and surfaces of their own
    readonly property var pages: ["network", "bluetooth", "notifications", "media", "system", "audio", "power", "monitor", "calendar", "weather", "screen-time"]

    function go(target: string): void {
        if (target === "")
            return;
        if (pages.includes(target))
            PanelRouter.navigate(target, screen.name);
        else if (/^[a-z-]+$/.test(target) && ["launcher", "clipboard", "wallpaper", "session"].includes(target))
            Actions.run("panel " + target, { screen: root.screen });
        else
            Actions.run(target, { screen: root.screen });
    }
    function press(entry: var): void {
        if (typeof entry.press === "function") {
            entry.press();
            if (entry.closes)
                PanelRouter.close(screen.name);
        } else {
            go(entry.press);
        }
    }
    // what each control's ring reads: { value 0..1, segments (0: a continuous arc) }, or null for none
    function readingFor(id: string): var {
        switch (id) {
        case "wifi":
            return Network.wifiEnabled ? { value: Network.connected ? Network.strength : 0, segments: 4 } : null;
        case "bluetooth":
            return Bluetooth.enabled ? { value: Math.min(1, Bluetooth.connected.length / 3), segments: 3 } : null;
        case "audio":
            return Audio.ready ? { value: Audio.muted ? 0 : Math.min(1, Audio.volume), segments: 0 } : null;
        case "mic_mute":
            return Audio.micReady ? { value: Audio.micMuted ? 0 : Math.min(1, Audio.micVolume), segments: 0 } : null;
        case "power_profile":
            return { value: ControlShortcuts.profile === "saver" ? 1 / 3 : ControlShortcuts.profile === "performance" ? 1 : 2 / 3, segments: 3 };
        case "system":
            return { value: System.cpu, segments: 0 };
        case "media":
            return Media.present && Media.length > 0 ? { value: Media.position / Media.length, segments: 0 } : null;
        case "screen_time":
            return ScreenTime.enabled ? { value: Math.min(1, ScreenTime.total / (8 * 3600)), segments: 0 } : null;
        }
        return null;
    }

    function more(entry: var): void {
        go(entry.more ?? "");
    }

    Flow {
        id: flow
        width: root.width
        spacing: root.gap

        Repeater {
            model: root.entries

            delegate: Loader {
                id: slot
                required property var modelData
                required property int index
                readonly property bool span: root.size === "regular" && (root.cfg.tile_sizes ?? {})[modelData.id] === "wide"
                width: span ? root.width : root.cell
                sourceComponent: root.size === "compact" ? compactTile : wideTile

                // a tile keeps what it reads awake while the panel shows
                Hold {
                    service: slot.modelData.needs ?? ""
                    when: root.active
                }

                Component {
                    id: wideTile
                    Tile {
                        width: slot.width
                        icon: slot.modelData.icon()
                        title: slot.modelData.label()
                        detail: root.size === "wide" || slot.span || root.labels ? slot.modelData.detail() : ""
                        on: slot.modelData.on()
                        more: (slot.modelData.more ?? "") !== ""
                        onToggled: root.press(slot.modelData)
                        onOpened: root.more(slot.modelData)
                    }
                }
                Component {
                    id: compactTile
                    CompactTile {
                        width: slot.width
                        entry: slot.modelData
                        showLabel: root.labels
                        onPressed: root.press(slot.modelData)
                        onOpened: root.more(slot.modelData)
                    }
                }
            }
        }
    }

    // a round button with its name under it; a right click opens its page
    component CompactTile: Item {
        id: ct
        property var entry: null
        property bool showLabel: true
        readonly property bool lit: entry?.on() ?? false
        signal pressed
        signal opened
        implicitHeight: button.height + (showLabel ? Metrics.s2 + name.implicitHeight : 0)

        // the control as an aperture: blades open over a lit core when on; the ring around reads its live value
        ApertureDial {
            id: button
            anchors.horizontalCenter: parent.horizontalCenter
            size: Math.min(ct.width, 54)
            lit: ct.lit
            glyph: ct.entry?.icon() ?? ""
            reading: root.readingFor(ct.entry?.id ?? "")
            hovered: area.containsMouse
            pressed: area.pressed
            Interactive {
                id: area
                anchors.fill: parent
                radius: width / 2
                onClicked: mouse => mouse.button === Qt.RightButton && (ct.entry?.more ?? "") !== "" ? ct.opened() : ct.pressed()
            }
        }
        Label {
            id: name
            visible: ct.showLabel
            anchors.top: button.bottom
            anchors.topMargin: Metrics.s2
            width: ct.width
            horizontalAlignment: Text.AlignHCenter
            role: "caption"
            tone: ct.lit ? "ink" : "muted"
            // a name too long for the cell ("Do not disturb") takes a second line rather than losing its end
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            lineHeight: 0.92
            elide: Text.ElideRight
            text: ct.entry?.label() ?? ""
        }
    }
}
