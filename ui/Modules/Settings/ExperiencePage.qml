import QtQuick
import qs.Common
import qs.Components
import qs.Services

// What the shell spends, and never how it looks: the look is Appearance → Surface style. One choice (follow power,
// or always save), what that means right now, and whether blur and shadows may pause while power is short.
Column {
    id: root

    spacing: Metrics.s5

    PanelHeader {
        width: parent.width
        title: "Performance"
        caption: "What the shell spends on this machine — never how it looks"
    }

    Card {
        width: parent.width
        caption: "The shell's own work"
        Column {
            width: parent.width
            spacing: Metrics.s4
            Segmented {
                width: Math.min(parent.width, 420)
                options: [{ key: "auto", label: "Follow power" }, { key: "save", label: "Always save" }]
                current: ExperiencePolicy.efficiency
                onPicked: key => ExperiencePolicy.setEfficiency(key)
            }
            Label {
                width: parent.width
                role: "body"
                tone: "muted"
                wrapMode: Text.WordWrap
                text: ExperiencePolicy.efficiency === "save" ? "Previews stay small, the visualizer modest and background work slow, plugged in or not." : "Everything at its best while plugged in; previews, the visualizer and background work ease off on battery, and further with power saver."
            }
            Row {
                spacing: Metrics.s3
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "caption"
                    caps: true
                    tone: "faint"
                    text: "Right now"
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "label"
                    tone: ExperiencePolicy.level === "full" ? "ink" : "accent"
                    text: ExperiencePolicy.levelLabels[ExperiencePolicy.level] + (ExperiencePolicy.limitedBy !== "" ? "  ·  " + ExperiencePolicy.limitedBy : "")
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "When power is short"
        Row {
            width: parent.width
            spacing: Metrics.s3
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: Config.experience.easeEffects !== false
                onToggled: Config.setEaseEffects(Config.experience.easeEffects === false)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                role: "body"
                wrapMode: Text.WordWrap
                text: "Pause blur and shadows while power saver is on or the battery is low. Your surface style stays chosen, and they come back as soon as power does."
            }
        }
        Label {
            visible: Material.pausedText !== ""
            width: parent.width
            role: "caption"
            tone: "accent"
            wrapMode: Text.WordWrap
            text: Material.pausedText
        }
    }

    Card {
        width: parent.width
        caption: "Motion"
        Row {
            spacing: Metrics.s3
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: ExperiencePolicy.reducedMotion
                onToggled: Config.setReducedMotion(!ExperiencePolicy.reducedMotion)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "body"
                text: "Reduce motion"
            }
        }
    }

    Card {
        width: parent.width
        caption: "What that means now"
        Repeater {
            model: [
                ["Visualizer", ExperiencePolicy.visualizerBands > 0 ? ExperiencePolicy.visualizerBands + " bands" : "off"],
                ["Previews", ExperiencePolicy.thumbnailSize + " px" + (ExperiencePolicy.richEffects ? ", animated" : ", still")],
                ["Panels kept warm", ExperiencePolicy.panelKeepAliveMs > 0 ? Math.round(ExperiencePolicy.panelKeepAliveMs / 1000) + " s" : "no"],
                ["Background work", "every " + (ExperiencePolicy.updateIntervalMs / 1000) + " s"]
            ]
            delegate: Item {
                required property var modelData
                width: parent.width
                height: 20
                Label {
                    role: "caption"
                    tone: "faint"
                    caps: true
                    text: parent.modelData[0]
                }
                Label {
                    anchors.right: parent.right
                    role: "label"
                    tone: "muted"
                    text: parent.modelData[1]
                }
            }
        }
        Label {
            width: parent.width
            role: "caption"
            tone: "faint"
            wrapMode: Text.WordWrap
            text: "Single values can be set in ~/.config/zynith/experience.toml under [overrides]."
        }
    }
}
