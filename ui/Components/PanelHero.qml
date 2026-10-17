import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Io
import qs.Common
import qs.Services

// The Control Panel's hero: the wallpaper as a band across the top of the card (as the grid wallpaper
// browser's preview), with who you are as the main thing on it — the picture large, the name in display
// type, the machine under it — and the hour, the day and the weather at the other end. Everything shown is
// [control_panel] hero_*: height, which pieces, the shade.
//
// On a page other than the dashboard the hero is that page's heading (heading: { eyebrow, title, detail,
// value, unit, caption }; null shows who you are). The connected tab rises out of the page's sheet into the
// band through a groove cut in the picture (notch*), so the tab, the page and its heading read as one piece.
Item {
    id: root

    property var heading: null
    property string headingKey: ""
    // +1 / -1: the way the tabs travelled (the old heading leaves that way, the new one comes from the other)
    property int direction: 0
    property bool animate: true
    // room at the bottom that the tabs take (the type sits above it)
    property real bottomRoom: 0
    // the groove: where the tab rises into the band (this item's coordinates); none when notchRight <= notchLeft
    property real notchLeft: 0
    property real notchRight: 0
    property real notchTop: 0
    property real notchRadius: Metrics.radiusPlate
    // the picture's own rounding where the groove opens out of its bottom edge
    property real notchMouth: Metrics.s3
    // the card's top corners [left, right]: a full-bleed band follows them (square where an attached card meets
    // its bar), an inset card keeps its own
    property var topCorners: [radius, radius]

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
    // narrow: the picture no larger than the type beside it can carry
    readonly property int avatarSize: Math.min(cfg.hero_avatar_size ?? 64, narrow ? 52 : 1000)
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
        // the wallpaper, changing with the palette (a new one cross-fades in as the colours do)
        WallpaperImage {
            id: picture
            anchors.fill: parent
            opacity: ready ? 1 : 0
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
    // the band's outline: rounded at the top (and at the bottom as a card), with the groove where a tab rises
    Shape {
        id: bandMask
        anchors.fill: band
        visible: false
        layer.enabled: true
        preferredRendererType: Shape.CurveRenderer
        function f(n: real): string {
            return Number(n).toFixed(2);
        }
        function arc(r: real, sweep: int, x: real, y: real): string {
            return r > 0.01 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y);
        }
        readonly property string outline: {
            const W = width, H = height;
            if (W <= 0 || H <= 0)
                return "";
            const Rt = Math.min(root.radius, W / 2, H / 2);
            const Rl = root.card ? Rt : Math.min(root.topCorners[0] ?? Rt, W / 2, H / 2);
            const Rr = root.card ? Rt : Math.min(root.topCorners[1] ?? Rt, W / 2, H / 2);
            const Rb = root.card ? Rt : 0;
            let p = "M 0 " + f(Rl) + arc(Rl, 1, Rl, 0) + " L " + f(W - Rr) + " 0" + arc(Rr, 1, W, Rr) + " L " + f(W) + " " + f(H - Rb) + arc(Rb, 1, W - Rb, H);
            const a = root.notchLeft - root.inset, b = root.notchRight - root.inset, top = root.notchTop - root.inset;
            if (b - a > 1 && top < H - 1 && a > Rb && b < W - Rb) {
                const m = Math.max(0, Math.min(root.notchMouth, a - Rb, W - Rb - b, (H - top) / 2));
                const r = Math.max(0, Math.min(root.notchRadius, (b - a) / 2, (H - top) / 2));
                p += " L " + f(b + m) + " " + f(H) + arc(m, 1, b, H - m);
                p += " L " + f(b) + " " + f(top + r) + arc(r, 0, b - r, top);
                p += " L " + f(a + r) + " " + f(top) + arc(r, 0, a, top + r);
                p += " L " + f(a) + " " + f(H - m) + arc(m, 1, a - m, H);
            }
            p += " L " + f(Rb) + " " + f(H) + arc(Rb, 1, 0, H - Rb) + " Z";
            return p;
        }
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: "white"
            PathSvg {
                path: bandMask.outline
            }
        }
    }

    // ── what the hero says: who you are (the dashboard) or the page's heading. On a change the old one leaves
    // the way the tabs travelled and the new one arrives from the other side: one axis with the tab and the page.
    property int front: 0
    property var frozen: null
    property bool frozenWho: true
    readonly property real travel: Metrics.s7 * 2
    onHeadingKeyChanged: {
        const was = slots[front];
        frozen = was.who ? null : JSON.parse(JSON.stringify(was.content ?? {}));
        frozenWho = was.who;
        front = 1 - front;
        const now = slots[front], gone = slots[1 - front];
        // interrupted: the heading that was arriving leaves from where it got to, not from full view
        const midway = swap.running;
        swap.stop();
        if (!animate || direction === 0 || Motion.reduced) {
            now.x = 0;
            now.opacity = 1;
            gone.opacity = 0;
            return;
        }
        if (!midway) {
            gone.x = 0;
            gone.opacity = 1;
        }
        now.x = direction * travel;
        now.opacity = 0;
        swap.start();
    }
    readonly property var slots: [slotA, slotB]
    ParallelAnimation {
        id: swap
        NumberAnimation {
            target: root.slots[1 - root.front]
            property: "x"
            to: -root.direction * root.travel
            duration: Motion.spatialFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spatialFastCurve
        }
        NumberAnimation {
            target: root.slots[1 - root.front]
            property: "opacity"
            to: 0
            duration: Motion.contentOut * 0.8
            easing.type: Motion.exitEasing
        }
        NumberAnimation {
            target: root.slots[root.front]
            property: "x"
            to: 0
            duration: Motion.spatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spatialCurve
        }
        // the new heading shows once the old one has mostly gone: never two lines of type over each other
        SequentialAnimation {
            PauseAnimation {
                duration: Motion.contentOut * 0.8
            }
            NumberAnimation {
                target: root.slots[root.front]
                property: "opacity"
                to: 1
                duration: Motion.contentIn + 60
                easing.type: Motion.enterEasing
            }
        }
    }
    Item {
        id: slotA
        anchors.fill: parent
        readonly property bool isFront: root.front === 0
        readonly property bool who: isFront ? root.heading === null : root.frozenWho
        readonly property var content: isFront ? root.heading : root.frozen
        visible: opacity > 0.01
        Loader {
            anchors.fill: parent
            sourceComponent: slotA.who ? identity : pageHeading
            onLoaded: if (item.slot !== undefined)
                item.slot = slotA
        }
    }
    Item {
        id: slotB
        anchors.fill: parent
        opacity: 0
        readonly property bool isFront: root.front === 1
        readonly property bool who: isFront ? root.heading === null : root.frozenWho
        readonly property var content: isFront ? root.heading : root.frozen
        visible: opacity > 0.01
        Loader {
            anchors.fill: parent
            sourceComponent: slotB.who ? identity : pageHeading
            onLoaded: if (item.slot !== undefined)
                item.slot = slotB
        }
    }
    Component {
        id: pageHeading
        HeroHeading {
            property Item slot: null
            anchors.fill: parent
            anchors.leftMargin: Metrics.s6 + root.inset
            anchors.rightMargin: Metrics.s6 + root.inset
            narrow: root.narrow
            bottomRoom: Metrics.s5 + (root.card ? Metrics.s1 : 0) + root.bottomRoom
            heading: slot?.content ?? ({})
        }
    }

    Component {
        id: identity
        Item {
            anchors.fill: parent

            // ── who ──
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.s6 + root.inset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.s5 + (root.card ? Metrics.s1 : 0) + root.bottomRoom
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
                        // narrow: the name gives way to the clock on its right
                        width: root.narrow ? Math.min(implicitWidth, root.width - root.avatarSize - clockColumn.width - Metrics.s6 * 3 - Metrics.s5 - root.inset * 2) : implicitWidth
                        role: root.narrow ? "headline" : "display2"
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
                    // narrow: the day, under the name, where the details would be
                    Label {
                        visible: root.narrow && root.showClock
                        role: "data"
                        tone: "muted"
                        text: Qt.formatDate(Time.now, "ddd  ·  dd MMM")
                    }
                }
            }

            // ── when, and what it is like out (narrow: the hour alone) ──
            Column {
                id: clockColumn
                anchors.right: parent.right
                anchors.rightMargin: Metrics.s6 + root.inset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.s5 + (root.card ? Metrics.s1 : 0) + root.bottomRoom
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
                    visible: !root.narrow
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
    }
}
