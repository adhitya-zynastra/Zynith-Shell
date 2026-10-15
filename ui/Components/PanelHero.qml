import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Common
import qs.Services

// The Control Panel's hero: the wallpaper as a band across the top of the card (as the grid wallpaper
// browser's preview), with who you are as the main thing on it — the picture large, the name in display
// type, the machine under it — and the hour, the day and the weather at the other end. Everything shown is
// [control_panel] hero_*: height, which pieces, the shade.
Item {
    id: root

    property bool active: true
    readonly property var cfg: Config.controlPanel ?? ({})
    // hero_style: card (the wallpaper as an inset, rounded card, clear but for a shade under the type, as the
    // native Control Center's home) | band (full-bleed across the top of the panel)
    readonly property bool card: (cfg.hero_style ?? "card") === "card"
    readonly property real inset: card ? Metrics.s3 : 0
    readonly property real radius: card ? Metrics.radiusSurface - Metrics.s1 : Metrics.radiusSurface
    readonly property bool showClock: cfg.hero_clock ?? true
    readonly property bool showWeather: cfg.hero_weather ?? true
    readonly property bool showDetails: cfg.hero_details ?? true
    readonly property int avatarSize: cfg.hero_avatar_size ?? 64
    // narrow (a page, a small screen): the details step aside so nothing overlaps
    readonly property bool narrow: width < 820
    // how dark the band is under the type, 0 – 1
    readonly property real shade: Math.max(0, Math.min(1, cfg.hero_shade ?? 0.7))

    implicitHeight: cfg.hero_height ?? 150

    Hold {
        service: "weather"
        when: root.active && root.showWeather
    }

    // how long the machine has been up (read when shown, then each minute while it is)
    property real uptime: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptime = Number(text().split(" ")[0]) || 0
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.active && root.showDetails
        triggeredOnStart: true
        onTriggered: uptimeFile.reload()
    }
    function since(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return "up " + (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m";
    }

    // ── the wallpaper, rounded at the top with the card, square where it meets the content ──
    Item {
        id: band
        anchors.fill: parent
        anchors.margins: root.inset
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bandMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceHigh
        }
        Image {
            id: picture
            anchors.fill: parent
            source: Scheme.image !== "" ? (Scheme.image.startsWith("/") ? "file://" + Scheme.image : Scheme.image) : ""
            sourceSize.width: width * 1.5
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            // a slow drift while the panel is open: the picture breathes rather than sits
            scale: 1.06
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.contentIn * 2
                }
            }
            SequentialAnimation on x {
                running: root.active && ExperiencePolicy.richEffects && !Motion.reduced && (root.cfg.hero_drift ?? true)
                loops: Animation.Infinite
                NumberAnimation {
                    from: -8
                    to: 8
                    duration: Motion.ms(14000)
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 8
                    to: -8
                    duration: Motion.ms(14000)
                    easing.type: Easing.InOutSine
                }
            }
        }
        // the shade: dark under the type at the bottom left, the picture clear at the top right
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Theme.alpha(Theme.base, root.card ? 0 : root.shade * 0.15)
                }
                GradientStop {
                    position: root.card ? 0.45 : 0.55
                    color: Theme.alpha(Theme.base, root.card ? root.shade * 0.08 : root.shade * 0.45)
                }
                GradientStop {
                    position: 1
                    color: Theme.alpha(Theme.base, root.shade)
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Theme.alpha(Theme.base, root.shade * (root.card ? 0.35 : 0.55))
                }
                GradientStop {
                    position: 0.6
                    color: "transparent"
                }
            }
        }
    }
    Rectangle {
        id: bandMask
        anchors.fill: band
        visible: false
        layer.enabled: true
        radius: root.radius
        // the band's bottom meets the content square; the card is rounded all round
        Rectangle {
            visible: !root.card
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.radius
        }
    }

    // ── who ──
    Row {
        anchors.left: parent.left
        anchors.leftMargin: Metrics.s6 + root.inset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.s5 + (root.card ? Metrics.s1 : 0)
        spacing: Metrics.s5

        // the picture, ringed in the accent
        Item {
            width: root.avatarSize + 6
            height: width
            anchors.bottom: parent.bottom
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.alpha(Theme.accent, 0.85)
            }
            Avatar {
                anchors.centerIn: parent
                size: root.avatarSize
            }
        }
        Column {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: 2
            Label {
                role: "data"
                tone: "accent"
                text: {
                    const h = Time.now.getHours();
                    return h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
                }
            }
            Label {
                role: "display2"
                font.weight: Font.Medium
                text: About.displayName
                style: Text.Raised
                styleColor: Theme.alpha(Theme.base, 0.3)
            }
            Label {
                visible: root.showDetails && !root.narrow
                role: "caption"
                tone: "muted"
                text: [About.user + "@" + (About.host || "localhost"), About.os, root.uptime > 0 ? root.since(root.uptime) : ""].filter(s => s !== "").join("  ·  ")
            }
        }
    }

    // ── when, and what it is like out ──
    Column {
        anchors.right: parent.right
        anchors.rightMargin: Metrics.s6 + root.inset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.s5 + (root.card ? Metrics.s1 : 0)
        spacing: 2
        Label {
            visible: root.showClock
            anchors.right: parent.right
            role: root.narrow ? "headline" : "display"
            numeric: true
            text: Qt.formatTime(Time.now, "HH:mm")
            style: Text.Raised
            styleColor: Theme.alpha(Theme.base, 0.3)
        }
        Row {
            anchors.right: parent.right
            spacing: Metrics.s3
            Row {
                visible: root.showWeather && Weather.valid
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s1
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Weather.glyph(Weather.data.current?.code ?? 0, Weather.data.current?.isDay ?? true)
                    size: 15
                    tone: "accent"
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "data"
                    text: Math.round(Weather.data.current?.temperature ?? 0) + (Weather.data.unit ?? "°")
                }
            }
            Label {
                visible: root.showClock
                anchors.verticalCenter: parent.verticalCenter
                role: "data"
                tone: "muted"
                text: Qt.formatDate(Time.now, "dddd  ·  dd MMMM")
            }
        }
    }
}
