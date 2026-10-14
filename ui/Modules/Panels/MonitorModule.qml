import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The displays: each one's brightness through the native brightness service (backlight or DDC/CI, as its
// [brightness] says), then night light and the palette's light or dark. DDC monitors can be looked for again.
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

    property var info: ({ available: false, displays: [] })
    readonly property var displays: (info.displays ?? []).filter(d => d.controllable)
    function read(): void {
        CoreClient.call("brightness-status", text => {
            try {
                root.info = JSON.parse(text);
            } catch (e) {}
        });
    }
    onActiveChanged: if (active)
        read()
    Component.onCompleted: read()
    // a change from a key or another surface comes back as an OSD event
    Connections {
        target: Events
        enabled: root.active
        function onOsd(c: var): void {
            if (c.kind === "brightness" && !pending.running)
                root.read();
        }
    }

    // slider moves are coalesced into one command per display per frame or two
    property var queued: ({})
    function set(id: string, v: real): void {
        const q = Object.assign({}, queued);
        q[id] = v;
        queued = q;
        pending.restart();
    }
    Timer {
        id: pending
        interval: 40
        onTriggered: {
            for (const id in root.queued)
                CoreClient.call("brightness-set " + id + " " + Math.round(root.queued[id] * 100), () => {});
            root.queued = {};
        }
    }

    spacing: Metrics.s3

    Label {
        visible: root.displays.length === 0
        role: "label"
        tone: "faint"
        text: root.info.available ? "No display here takes brightness" : "Brightness control is unavailable"
    }

    Repeater {
        model: root.displays
        delegate: Column {
            id: display
            required property var modelData
            property real value: modelData.value
            width: root.colW
            spacing: Metrics.s1

            Label {
                visible: root.displays.length > 1 || root.expanded
                width: parent.width
                role: "caption"
                tone: "faint"
                elide: Text.ElideRight
                text: display.modelData.id + (root.expanded && display.modelData.width ? "  ·  " + display.modelData.width + "×" + display.modelData.height : "")
            }
            Row {
                width: parent.width
                spacing: Metrics.s3
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.control
                    name: display.value < 0.34 ? "brightness-down" : "brightness-up"
                    tone: "muted"
                }
                Slider {
                    wheelAdjusts: true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Metrics.control - 40 - Metrics.s3 * 2
                    value: display.value
                    onMoved: v => {
                        display.value = v;
                        root.set(display.modelData.id, v);
                    }
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    role: "label"
                    numeric: true
                    tone: "muted"
                    text: Math.round(display.value * 100)
                }
            }
        }
    }

    // ── night light and the palette ──
    Row {
        width: root.colW
        spacing: Metrics.s3
        readonly property real cell: (width - spacing) / 2
        Repeater {
            model: ["nightlight", "dark_mode"]
            delegate: Tile {
                required property string modelData
                readonly property var entry: ControlShortcuts.find(modelData)
                width: parent.cell
                icon: entry.icon()
                title: entry.label()
                detail: entry.detail()
                on: entry.on()
                onToggled: entry.press()
            }
        }
    }

    Chip {
        visible: root.expanded && root.info.ddc === true
        icon: "refresh"
        text: "Look for monitors again"
        onClicked: CoreClient.call("brightness-rescan", () => root.read())
    }
}
