import QtQuick
import qs.Common
import qs.Components
import qs.Services

Column {
    id: root

    spacing: Metrics.s5

    readonly property var blurbs: ({
            performance: "Light and immediate. Short fades, no blur, no shadows, no visualizer. For older or busy machines.",
            balanced: "The everyday setting. Compositor blur, soft shadows, measured motion, a modest visualizer.",
            enhanced: "Richer glass and depth, smoother visualizer, larger previews and more caching ahead of need.",
            max: "Everything Zynith can do, spent where it shows: deepest glass, layered shadows, the fullest motion."
        })

    PanelHeader {
        width: parent.width
        title: "Experience"
        caption: "How Zynith spends this machine"
    }

    Grid {
        width: parent.width
        columns: 2
        spacing: Metrics.s3

        Repeater {
            model: ExperiencePolicy.profiles

            delegate: Item {
                required property string modelData
                readonly property bool current: ExperiencePolicy.profile === modelData
                width: (parent.width - parent.spacing) / 2
                height: 104

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusLg
                    color: parent.current ? Theme.accentSoft : Theme.surfaceLow
                    border.width: Metrics.hairline
                    border.color: parent.current ? Theme.accentLine : Theme.hairline
                }
                Interactive {
                    anchors.fill: parent
                    radius: Metrics.radiusLg
                    onClicked: ExperiencePolicy.select(parent.modelData)
                }
                Column {
                    anchors.fill: parent
                    anchors.margins: Metrics.s4
                    spacing: Metrics.s2

                    Row {
                        spacing: Metrics.s3
                        Label {
                            role: "title"
                            text: ExperiencePolicy.labels[parent.parent.parent.modelData]
                        }
                        Label {
                            visible: ExperiencePolicy.hardwareProfile === parent.parent.parent.modelData
                            anchors.verticalCenter: parent.verticalCenter
                            role: "caption"
                            tone: "accent"
                            caps: true
                            text: "Recommended"
                        }
                    }
                    Label {
                        width: parent.width
                        role: "label"
                        tone: "muted"
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        maximumLineCount: 3
                        text: root.blurbs[parent.parent.modelData]
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Selection"

        Row {
            spacing: Metrics.s3
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: ExperiencePolicy.automatic
                onToggled: ExperiencePolicy.select(ExperiencePolicy.automatic ? ExperiencePolicy.profile : "auto")
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "body"
                text: "Follow the recommendation for this hardware (" + (ExperiencePolicy.labels[ExperiencePolicy.hardwareProfile] ?? "") + ", " + Hardware.tier + " tier)"
            }
        }
        Row {
            spacing: Metrics.s3
            opacity: ExperiencePolicy.automatic ? 1 : 0.5
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: ExperiencePolicy.adaptive
                onToggled: Config.setAdaptive(!ExperiencePolicy.adaptive)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "body"
                text: "Ease off on battery: at most Balanced, Performance when low or power saving"
                    + (ExperiencePolicy.limitedBy ? "  ·  now: " + ExperiencePolicy.labels[ExperiencePolicy.recommended] + " (" + ExperiencePolicy.limitedBy.toLowerCase() + ")" : "")
            }
        }
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
                text: "Reduce motion (any profile)"
            }
        }
    }

    Card {
        width: parent.width
        caption: "What this profile does"

        Repeater {
            model: [
                ["Animation", ExperiencePolicy.animationQuality + " · ×" + ExperiencePolicy.animationScale.toFixed(1)],
                ["Blur", ExperiencePolicy.blurQuality],
                ["Shadows", ExperiencePolicy.shadowQuality],
                ["Effects", ExperiencePolicy.effectsQuality],
                ["Visualizer", ExperiencePolicy.visualizerQuality + (ExperiencePolicy.visualizerBands > 0 ? " · " + ExperiencePolicy.visualizerBands + " bands" : "")],
                ["Wallpaper", ExperiencePolicy.wallpaperQuality + " · " + ExperiencePolicy.wallpaperTransitionMs + " ms transitions"],
                ["Thumbnails", ExperiencePolicy.thumbnailQuality + " · " + ExperiencePolicy.thumbnailSize + " px"],
                ["Background work", ExperiencePolicy.backgroundActivity + " · samplers every " + (ExperiencePolicy.updateIntervalMs / 1000) + " s"],
                ["Prefetch", ExperiencePolicy.prefetchRadius + " items ahead"]
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
            elide: Text.ElideNone
            text: "Individual values can be overridden in ~/.config/zynith/shell.json under experience.overrides."
        }
    }
}
