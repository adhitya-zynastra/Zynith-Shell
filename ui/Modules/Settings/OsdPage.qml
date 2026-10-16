import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// The on-screen display: whether Zynith shows it, where, how long, and which kinds never show.
// panels.toml [osd]; the native shell sends every event (volume, brightness, lock keys…) to it.
Column {
    id: root
    spacing: Metrics.s5

    readonly property var osd: ({
            enabled: Config.osd.enabled,
            position: Config.osd.position,
            margin: Config.osd.margin,
            duration_ms: Config.osd.durationMs,
            align: Config.osd.align,
            side_margin: Config.osd.sideMargin,
            hidden: Config.osd.hidden
        })
    readonly property var kinds: [
        { key: "volume", label: "Volume" },
        { key: "microphone", label: "Microphone" },
        { key: "brightness", label: "Brightness" },
        { key: "keyboard-layout", label: "Keyboard layout" },
        { key: "wifi", label: "Wi‑Fi" },
        { key: "bluetooth", label: "Bluetooth" },
        { key: "power-profile", label: "Power profile" },
        { key: "caffeine", label: "Stay awake" },
        { key: "nightlight", label: "Night light" },
        { key: "dnd", label: "Do not disturb" },
        { key: "lock-keys", label: "Lock keys" },
        { key: "media", label: "Track changes" },
        { key: "privacy", label: "Camera and microphone use" },
        { key: "keyboard-backlight", label: "Keyboard backlight" }
    ]

    PanelHeader {
        width: parent.width
        title: "On-screen display"
        caption: "The brief card for volume, brightness and the rest"
    }

    // who draws it: the same switch as Settings → Zynith UI (zynith.toml [surfaces] osd)
    Card {
        width: parent.width
        Label {
            role: "label"
            tone: "muted"
            text: "Drawn by"
        }
        Segmented {
            width: parent.width
            current: (Config.surfaces?.osd ?? "native") === "zynith" ? "zynith" : "native"
            options: [{ key: "zynith", label: "Zynith" }, { key: "native", label: "The native shell" }]
            onPicked: key => {
                Config.write("zynith", "surfaces.osd", key);
                CoreClient.call("surfaces-sync", () => {});
            }
        }
        Label {
            width: parent.width
            role: "micro"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: "With the native shell drawing it, its own settings apply: Settings → Shell settings → OSD."
        }
    }

    Card {
        width: parent.width
        visible: (Config.surfaces?.osd ?? "native") === "zynith"
        SchemaForm {
            width: parent.width
            schema: [
                { key: "position", label: "Where", kind: "choice", default: "bottom", options: [{ key: "top", label: "Top" }, { key: "bottom", label: "Bottom" }] },
                { key: "align", label: "Along it", kind: "choice", default: "center", options: [{ key: "left", label: "Left" }, { key: "center", label: "Centre" }, { key: "right", label: "Right" }] },
                { key: "margin", label: "From the edge", kind: "int", default: 72, from: 0, to: 400, step: 4 },
                { key: "side_margin", label: "From the side", kind: "int", default: 20, from: 0, to: 400, step: 4 },
                { key: "duration_ms", label: "Stays for (ms)", kind: "int", default: 1400, from: 400, to: 6000, step: 100 }
            ]
            valueOf: key => root.osd[key] ?? schema.find(s => s.key === key)?.default
            isSet: key => root.osd[key] !== undefined && root.osd[key] !== schema.find(s => s.key === key)?.default
            onChanged: (key, value) => Config.change("panels", "osd." + key, value, labelOf(key))
            onCleared: key => Config.change("panels", "osd." + key, undefined, labelOf(key))
        }
    }

    Card {
        width: parent.width
        caption: "Shown for"
        SchemaForm {
            width: parent.width
            // hidden kinds are stored; the chips show the ones that do show
            schema: [{ key: "shown", label: "Each kind lit here shows a card", kind: "multi", options: root.kinds }]
            valueOf: key => root.kinds.map(k => k.key).filter(k => !Array.from(root.osd.hidden ?? []).includes(k))
            onChanged: (key, value) => Config.write("panels", "osd.hidden", root.kinds.map(k => k.key).filter(k => !Array.from(value).includes(k)))
        }
    }
}
