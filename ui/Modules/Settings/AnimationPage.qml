import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// One speed for the whole desktop, as Ryoku keeps one tempo: the Zynith UI (animation.toml speed, which
// multiplies durations) and the native shell with niri's windows (shell.animation.speed, which multiplies pace)
// move together from this one control; reduce motion stops both. The window animations' own shape stays below.
Column {
    id: root
    spacing: Metrics.s5

    // pace: 2 = twice as fast; the UI's duration multiplier is its inverse
    readonly property real pace: 1 / Math.max(0.25, Number(Config.animation?.speed ?? 1))
    function setPace(v: real): void {
        const p = Math.max(0.25, Math.min(4, Math.round(v * 20) / 20));
        Config.write("animation", "speed", Number((1 / p).toFixed(3)));
        CoreClient.call("settings-set " + JSON.stringify({ path: ["shell", "animation", "speed"], value: p }));
    }
    function setReduced(on: bool): void {
        Config.setReducedMotion(on);
        CoreClient.call("settings-set " + JSON.stringify({ path: ["shell", "animation", "enabled"], value: !on }));
    }

    PanelHeader {
        width: parent.width
        title: "Animations"
        caption: "How fast things move, everywhere at once"
    }

    Card {
        width: parent.width
        caption: "Motion"

        SettingRow {
            title: "Animation speed"
            detail: "Panels, bars, the lock screen and window movement"
            controlWidth: 260
            Row {
                width: parent.width
                spacing: Metrics.s3
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56 - Metrics.s3
                    // 0.25× … 3×
                    value: (root.pace - 0.25) / 2.75
                    onMoved: v => root.setPace(0.25 + v * 2.75)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    horizontalAlignment: Text.AlignRight
                    role: "label"
                    numeric: true
                    tone: "muted"
                    text: root.pace.toFixed(2) + "×"
                }
            }
        }
        SettingChoice {
            title: "Feel"
            detail: "How motion eases in and out"
            domain: "animation"
            key: "style"
            options: [{ key: "fluid", label: "Fluid" }, { key: "crisp", label: "Crisp" }, { key: "calm", label: "Calm" }]
        }
        SettingRow {
            title: "Reduce motion"
            detail: "Changes happen at once, without movement"
            controlWidth: 44
            Toggle {
                anchors.right: parent.right
                checked: Config.experience.reducedMotion === true
                onToggled: root.setReduced(!(Config.experience.reducedMotion === true))
            }
        }
    }

    Card {
        width: parent.width
        caption: "Panels"
        SettingToggle {
            title: "Join the bar"
            detail: "A panel opened from a bar grows out of it as one surface"
            domain: "panels"
            key: "panels.attach"
        }
        SettingChoice {
            title: "When one panel becomes another"
            domain: "panels"
            key: "panels.switch"
            options: [{ key: "morph", label: "It reshapes" }, { key: "fade", label: "It fades" }, { key: "none", label: "At once" }]
        }
    }
}
