import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Components
import qs.Services

// Settings opens on the scene: the wallpaper as a band with the person and the hour composed on it, the
// machine as one line of readouts, then every category as typeset rows under indexed heads — each saying
// where it stands now. No grid of equal cards.
Column {
    id: root

    signal navigate(string id)

    spacing: Metrics.s6

    Component.onCompleted: System.retain()
    Component.onDestruction: System.release()

    readonly property string greeting: {
        const h = Time.now.getHours();
        return h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
    }
    readonly property string firstName: (About.realName || About.user).split(/[\s.]+/).filter(p => p.length > 1)[0] ?? ""

    // ── the scene ───────────────────────────────────────────────────────────
    Item {
        id: hero
        width: parent.width
        height: 200

        Image {
            id: scene
            anchors.fill: parent
            source: Scheme.image !== "" ? (Scheme.image.startsWith("/") ? "file://" + Scheme.image : Scheme.image) : ""
            sourceSize.width: width * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle {
            id: heroMask
            anchors.fill: parent
            radius: Metrics.radiusSurface
            visible: false
            layer.enabled: true
        }
        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusSurface
            color: Theme.surfaceHigh
            visible: scene.status !== Image.Ready
        }
        MultiEffect {
            anchors.fill: parent
            source: scene
            maskEnabled: true
            maskSource: heroMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
            opacity: scene.status === Image.Ready ? 1 : 0
            Behavior on opacity {
                Anim {
                    role: "effects"
                }
            }
        }
        // the ink side of the scene: shade so the type reads on any image
        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusSurface
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Theme.alpha(Theme.base, 0.88)
                }
                GradientStop {
                    position: 0.55
                    color: Theme.alpha(Theme.base, 0.62)
                }
                GradientStop {
                    position: 1
                    color: Theme.alpha(Theme.base, 0.28)
                }
            }
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s6
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Metrics.s6
            spacing: Metrics.s5
            Avatar {
                anchors.bottom: parent.bottom
                size: 56
            }
            Column {
                anchors.bottom: parent.bottom
                spacing: 2
                Label {
                    role: "data"
                    tone: "muted"
                    text: Qt.formatDate(Time.now, "dddd  ·  dd MMMM")
                }
                Label {
                    role: "display2"
                    text: root.greeting + (root.firstName !== "" ? ", " + root.firstName : "")
                }
                Label {
                    role: "caption"
                    tone: "muted"
                    text: About.user + "  ·  " + (About.host || About.os)
                }
            }
        }
        Label {
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s6
            anchors.top: parent.top
            anchors.topMargin: Metrics.s5
            role: "display"
            numeric: true
            text: Qt.formatTime(Time.now, "HH:mm")
            style: Text.Raised
            styleColor: Theme.alpha(Theme.base, 0.35)
        }
    }

    // ── the machine, as readouts ────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: Metrics.s7
        Readout {
            caption: "CPU"
            value: Math.round(System.cpu * 100)
            unit: "%"
            size: "title"
        }
        Readout {
            caption: "Memory"
            value: (System.memUsed * System.memTotalGiB).toFixed(1)
            unit: "/ " + System.memTotalGiB.toFixed(0) + " GB"
            size: "title"
        }
        Readout {
            visible: Power.present
            caption: "Battery" + (Power.charging ? " · charging" : "")
            value: Math.round(Power.level * 100)
            unit: "%"
            size: "title"
        }
        Readout {
            caption: "Experience"
            value: ExperiencePolicy.labels[ExperiencePolicy.profile] ?? ""
            unit: ExperiencePolicy.automatic ? "auto" : ""
            size: "title"
        }
    }

    // ── every category, as typeset rows ─────────────────────────────────────
    // where each one stands now, in a phrase
    function summary(id: string): string {
        switch (id) {
        case "appearance":
            return "Tint " + Math.round((Config.appearance.tint ?? 0.35) * 100) + "%  ·  " + ((Config.appearance.accent ?? "wallpaper") === "wallpaper" ? "accent from the wallpaper" : "own accent");
        case "animation":
            return (Config.animation.style ?? "fluid") + "  ·  speed " + (Config.animation.speed ?? 1) + "×";
        case "wallpaper":
            return (Wallpapers.mode === "live" ? "Live" : "Still") + "  ·  " + (Config.wallpaper.layout ?? "carousel");
        case "experience":
            return (ExperiencePolicy.labels[ExperiencePolicy.profile] ?? "") + (ExperiencePolicy.automatic ? "  ·  automatic" : "");
        case "bars":
            return Config.bars.length + (Config.bars.length === 1 ? " bar" : " bars");
        case "widgets":
            return Config.widgets.length + " on the desktop";
        case "control":
            return (Config.controlPanel?.modules ?? []).length + " modules";
        case "launcher":
            return (Config.launcher?.layout ?? "list") + "  ·  " + (Config.launcher?.density ?? "comfortable");
        case "notifications":
            return (Config.notifications.location ?? "top-right").replace("-", " ") + (Config.notifications.dnd ? "  ·  do not disturb" : "");
        case "network":
            return Network.wifiEnabled ? (Network.name || "Not connected") : "Off";
        case "bluetooth":
            return Bluetooth.available ? Bluetooth.summary : "Unavailable";
        case "osd":
            return (Config.osd.position ?? "bottom") + "  ·  " + (Config.osd.durationMs ?? 1400) + " ms";
        case "shell":
            return "Every native setting";
        default:
            return "";
        }
    }
    readonly property var groups: {
        const out = [];
        for (const r of Routes.routes.filter(r => r.id !== "home")) {
            const name = r.group || "General";
            let g = out.find(x => x.name === name);
            if (!g) {
                g = { name: name, routes: [] };
                out.push(g);
            }
            g.routes.push(r);
        }
        return out;
    }

    Grid {
        width: parent.width
        columns: 2
        columnSpacing: Metrics.s7
        rowSpacing: Metrics.s6
        readonly property real col: (width - columnSpacing) / 2

        Repeater {
            model: root.groups
            delegate: Column {
                id: group
                required property var modelData
                required property int index
                width: parent.col
                spacing: Metrics.s1

                SectionHead {
                    width: parent.width
                    index: String(group.index + 1).padStart(2, "0")
                    title: group.modelData.name
                }
                Item {
                    width: 1
                    height: Metrics.s2
                }
                Repeater {
                    model: group.modelData.routes
                    delegate: Item {
                        id: entry
                        required property var modelData
                        width: group.width
                        height: 44

                        Rectangle {
                            anchors.fill: parent
                            radius: Metrics.radiusPlate
                            color: area.containsMouse ? Theme.plate : "transparent"
                            Behavior on color {
                                ColorAnim {}
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: area.containsMouse ? parent.height * 0.42 : 0
                            radius: 1
                            color: Theme.accent
                            Behavior on height {
                                Anim {
                                    role: "spatialFast"
                                }
                            }
                        }
                        Icon {
                            id: glyph
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.s3
                            anchors.verticalCenter: parent.verticalCenter
                            name: entry.modelData.icon
                            size: 16
                            tone: area.containsMouse ? "accent" : "muted"
                        }
                        Column {
                            anchors.left: glyph.right
                            anchors.leftMargin: Metrics.s4
                            anchors.right: arrow.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Label {
                                width: parent.width
                                role: "body"
                                text: entry.modelData.title
                            }
                            Label {
                                visible: text !== ""
                                width: parent.width
                                role: "caption"
                                tone: "faint"
                                text: root.summary(entry.modelData.id)
                            }
                        }
                        Icon {
                            id: arrow
                            anchors.right: parent.right
                            anchors.rightMargin: Metrics.s3
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-right"
                            size: 13
                            tone: "faint"
                            opacity: area.containsMouse ? 1 : 0.4
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigate(entry.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
