import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Settings opens on a picture of the machine and the person using it, not a list.
Column {
    id: root

    signal navigate(string id)

    spacing: Metrics.s5

    Component.onCompleted: System.retain()
    Component.onDestruction: System.release()

    // ── who ─────────────────────────────────────────────────────────────────
    Row {
        spacing: Metrics.s5

        Rectangle {
            width: 72
            height: 72
            radius: 36
            color: Theme.hover
            clip: true

            Image {
                id: avatar
                anchors.fill: parent
                source: About.avatar
                sourceSize.width: 144
                sourceSize.height: 144
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Label {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                role: "headline"
                tone: "muted"
                text: (About.realName || "?").charAt(0).toUpperCase()
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Label {
                role: "headline"
                text: About.realName
            }
            Label {
                role: "body"
                tone: "muted"
                text: About.user + "  ·  " + (About.host || About.os)
            }
        }
    }

    // ── now ─────────────────────────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: Metrics.s4

        Card {
            width: (parent.width - parent.spacing) / 2
            caption: "Date & time"

            Label {
                role: "display"
                numeric: true
                text: Qt.formatTime(Time.now, "HH:mm")
            }
            Label {
                role: "body"
                tone: "muted"
                text: Qt.formatDate(Time.now, "dddd, d MMMM yyyy") + (About.timezone ? "  ·  " + About.timezone : "")
            }
        }

        Card {
            width: (parent.width - parent.spacing) / 2
            caption: "Status"

            Meter {
                width: parent.width
                label: "CPU"
                value: System.cpu
            }
            Meter {
                width: parent.width
                label: "Memory"
                value: System.memUsed
                readout: (System.memUsed * System.memTotalGiB).toFixed(1) + " / " + System.memTotalGiB.toFixed(0) + " GB"
            }
            Meter {
                visible: Power.present
                width: parent.width
                label: Power.charging ? "Battery · charging" : "Battery"
                value: Power.level
            }
            Label {
                role: "label"
                tone: "muted"
                text: (Network.connected ? Network.name : "Offline") + "  ·  Bluetooth " + Bluetooth.summary.toLowerCase()
            }
        }
    }

    // ── system / software ───────────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: Metrics.s4

        Card {
            width: (parent.width - parent.spacing) / 2
            caption: "System"

            Repeater {
                model: [About.os, Hardware.cpuModel + " · " + Hardware.cpuThreads + " threads", Hardware.memGiB.toFixed(0) + " GB memory", Hardware.gpuSummary, "Linux " + About.kernel]
                delegate: Label {
                    required property string modelData
                    role: "label"
                    tone: "muted"
                    text: modelData
                }
            }
        }

        Card {
            width: (parent.width - parent.spacing) / 2
            caption: "Software"

            Repeater {
                model: ["Zynith " + About.zynithVersion, "niri " + About.niriVersion, "Quickshell " + About.quickshellVersion, "Experience: " + (ExperiencePolicy.labels[ExperiencePolicy.profile] ?? "") + (ExperiencePolicy.automatic ? " · auto" : "")]
                delegate: Label {
                    required property string modelData
                    role: "label"
                    tone: "muted"
                    text: modelData
                }
            }
        }
    }

    // ── categories ──────────────────────────────────────────────────────────
    Grid {
        width: parent.width
        columns: 3
        spacing: Metrics.s3

        Repeater {
            model: Routes.routes.filter(r => r.id !== "home")

            delegate: Item {
                required property var modelData
                width: (parent.width - parent.spacing * 2) / 3
                height: 64

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusLg
                    color: Theme.surfaceLow
                    border.width: Metrics.hairline
                    border.color: Theme.hairline
                }
                Interactive {
                    anchors.fill: parent
                    radius: Metrics.radiusLg
                    onClicked: root.navigate(parent.modelData.id)
                }
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: parent.parent.modelData.icon
                        tone: "accent"
                        size: 18
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            role: "body"
                            font.weight: Font.Medium
                            text: parent.parent.parent.modelData.title
                        }
                        Label {
                            role: "caption"
                            tone: "faint"
                            text: parent.parent.parent.modelData.group
                        }
                    }
                }
            }
        }
    }
}
