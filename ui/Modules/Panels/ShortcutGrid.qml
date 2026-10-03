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
    readonly property string size: cfg.shortcut_size ?? "regular"
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

        Rectangle {
            id: button
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(ct.width, 56)
            height: width
            radius: ct.lit ? Metrics.radiusLg : width / 2
            color: ct.lit ? Theme.accent : Theme.hover
            border.width: Metrics.hairline
            border.color: ct.lit ? "transparent" : Theme.hairline
            scale: area.pressed ? 0.92 : area.containsMouse ? 1.04 : 1
            Glide on scale {
                epsilon: 0.001
            }
            Behavior on color {
                ColorAnim {}
            }
            Behavior on radius {
                Anim {
                    role: "spatialFast"
                }
            }
            Icon {
                anchors.centerIn: parent
                name: ct.entry?.icon() ?? ""
                size: 20
                color: ct.lit ? Theme.onAccent : Theme.ink
            }
            Interactive {
                id: area
                anchors.fill: parent
                radius: parent.radius
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
            elide: Text.ElideRight
            text: ct.entry?.label() ?? ""
        }
    }
}
