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
    function clock(seconds: real): string {
        const s = Math.max(0, Math.round(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    // what each control's ring reads: { value 0..1, segments (0: a continuous arc) }, or null for none; one that
    // can be set by turning the ring also carries set(value) and the number to show while turning (text)
    function readingFor(id: string): var {
        switch (id) {
        case "wifi":
            return Network.wifiEnabled ? { value: Network.connected ? Network.strength : 0, segments: 4 } : null;
        case "bluetooth":
            return Bluetooth.enabled ? { value: Math.min(1, Bluetooth.connected.length / 3), segments: 3 } : null;
        case "audio":
            return Audio.ready ? { value: Audio.muted ? 0 : Math.min(1, Audio.volume), segments: 0, set: v => Audio.setVolume(v), text: String(Math.round(Audio.volume * 100)) } : null;
        case "mic_mute":
            return Audio.micReady ? { value: Audio.micMuted ? 0 : Math.min(1, Audio.micVolume), segments: 0, set: v => Audio.setMicVolume(v), text: String(Math.round(Audio.micVolume * 100)) } : null;
        case "power_profile":
            return { value: ControlShortcuts.profile === "saver" ? 1 / 3 : ControlShortcuts.profile === "performance" ? 1 : 2 / 3, segments: 3 };
        case "system":
            return { value: System.cpu, segments: 0 };
        case "media":
            return Media.present && Media.length > 0 ? { value: Media.position / Media.length, segments: 0, set: Media.canSeek ? v => Media.seek(v * Media.length) : undefined, text: clock(Media.position) } : null;
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
                        order: slot.index
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
        property int order: 0
        readonly property bool lit: entry?.on() ?? false
        readonly property var reading: root.readingFor(entry?.id ?? "")
        readonly property bool turnable: typeof reading?.set === "function"
        // a press that travels around the ring turns it; one that stays put is a click
        property point from: Qt.point(0, 0)
        property bool turned: false
        // the panel arriving opens the lit irises one after another; leaving, they all shut together
        property bool awake: !ExperiencePolicy.stagger || Motion.spatial === 0
        Timer {
            running: root.active && !ct.awake
            interval: 140 + ct.order * 55
            onTriggered: ct.awake = true
        }
        Connections {
            target: root
            function onActiveChanged(): void {
                if (!root.active && ExperiencePolicy.stagger && Motion.spatial > 0)
                    ct.awake = false;
            }
        }
        signal pressed
        signal opened
        implicitHeight: button.height + (showLabel ? Metrics.s2 + name.implicitHeight : 0)

        // the control as an aperture: blades open over a lit core when on; the ring around reads its live value
        ApertureDial {
            id: button
            anchors.horizontalCenter: parent.horizontalCenter
            size: Math.min(ct.width, 54)
            lit: ct.lit
            awake: ct.awake
            glyph: ct.entry?.icon() ?? ""
            reading: ct.reading
            hovered: area.containsMouse
            pressed: area.pressed && !ct.turned
            turning: area.pressed && ct.turned
            Interactive {
                id: area
                anchors.fill: parent
                radius: width / 2
                preventStealing: ct.turnable
                onPressed: mouse => {
                    ct.from = Qt.point(mouse.x, mouse.y);
                    ct.turned = false;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !ct.turnable || mouse.buttons !== Qt.LeftButton)
                        return;
                    if (!ct.turned && Math.hypot(mouse.x - ct.from.x, mouse.y - ct.from.y) < 6)
                        return;
                    ct.turned = true;
                    ct.reading.set(button.valueAt(mouse.x, mouse.y));
                }
                onClicked: mouse => {
                    if (ct.turned)
                        return;
                    mouse.button === Qt.RightButton && (ct.entry?.more ?? "") !== "" ? ct.opened() : ct.pressed();
                }
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
