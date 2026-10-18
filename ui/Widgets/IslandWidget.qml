import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The Zynith Island, as it sits in a bar: one living object that takes the shape of what is happening — the music
// playing, a notification arriving, the sound moving to headphones, the charger going in — and rests small when
// nothing is. The bar places it (any bar, any region, any edge); Services/Island knows what is happening; this
// draws it. Click to open it (the island panel grows out of it), right-click to put away what it shows, scroll to
// switch between things happening at once.
//
// On a vertical bar it is a column: the picture or icon, and below it a bubble for the next thing waiting.
BarItem {
    id: root

    readonly property var a: Island.primary
    readonly property var b: Island.secondary
    readonly property string idle: opt("idle") ?? "time"
    readonly property string motion: Motion.reduced ? "off" : (opt("motion") ?? "full")
    readonly property bool plainStyle: (opt("style") ?? "capsule") === "plain"
    readonly property real most: Math.max(120, opt("max_width") ?? 300)
    shown: a !== null || idle !== "hidden"
    active: PanelRouter.isOpen("island", screen?.name ?? "")

    // this island counts (the service works only while one exists) and says how it wants to be
    readonly property string instanceId: name + "@" + (screen?.name ?? "") + ":" + (bar?.spec?.id ?? "")
    Component.onCompleted: Island.retain(instanceId, settings)
    Component.onDestruction: Island.release(instanceId)
    onSettingsChanged: Island.retain(instanceId, settings)

    // what it shows now; a change of activity cross-fades while the shape morphs
    property var shownA: a
    onAChanged: {
        if ((a?.id ?? "") === (shownA?.id ?? "")) {
            shownA = a;
            return;
        }
        if (motion === "off") {
            shownA = a;
            return;
        }
        swap.restart();
    }
    SequentialAnimation {
        id: swap
        NumberAnimation {
            target: face
            property: "opacity"
            to: 0
            duration: root.motion === "subtle" ? 60 : 90
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: root.shownA = root.a
        }
        NumberAnimation {
            target: face
            property: "opacity"
            to: 1
            duration: root.motion === "subtle" ? 100 : 160
            easing.type: Easing.OutQuad
        }
    }

    readonly property real unit: Math.round(22 * sizeScale)
    readonly property string kind: shownA?.kind ?? "idle"
    readonly property string title: {
        const d = shownA?.data ?? {};
        switch (kind) {
        case "media":
            return d.title || d.app || "Playing";
        case "notification":
            return d.summary !== "" ? d.summary : (d.app || "Notification");
        case "device":
            return d.name;
        case "power":
            return (d.charging ? "Charging" : "On battery") + " · " + Math.round((d.level ?? 0) * 100) + "%";
        default:
            return idle === "time" ? Qt.formatTime(Time.now, "HH:mm") : "";
        }
    }
    readonly property string glyph: ({
            media: shownA?.data?.playing ? "player-play-filled" : "player-pause-filled",
            notification: "bell-ringing",
            device: shownA?.data?.icon ?? "volume",
            power: shownA?.data?.charging ? "plug-connected" : "battery-2"
        })[kind] ?? ""

    // ── the island's own shape: a capsule in the bar, as wide (or, on a vertical bar, tall) as what it holds ──
    Item {
        id: pill
        readonly property real thick: Math.max(root.unit + 8, (root.vertical ? (root.bar?.thickness ?? 34) : (root.bar?.thickness ?? 34)) - 8)
        readonly property real wantAlong: root.vertical ? (root.kind === "idle" ? (root.idle === "dot" ? 12 : thick) : thick + (root.b ? 18 : 0)) : root.kind === "idle" ? (root.idle === "dot" ? 18 : Math.min(root.most, clock.implicitWidth + 20)) : Math.min(root.most, content.implicitWidth + 20 + (root.b ? 26 : 0))
        implicitWidth: root.vertical ? thick : wantAlong
        implicitHeight: root.vertical ? wantAlong : thick
        width: implicitWidth
        height: implicitHeight
        Behavior on implicitWidth {
            enabled: root.motion !== "off" && !root.vertical
            NumberAnimation {
                duration: root.motion === "subtle" ? 160 : 320
                easing.type: Easing.OutBack
                easing.overshoot: root.motion === "subtle" ? 0.6 : 1.4
            }
        }
        Behavior on implicitHeight {
            enabled: root.motion !== "off" && root.vertical
            NumberAnimation {
                duration: root.motion === "subtle" ? 160 : 320
                easing.type: Easing.OutBack
                easing.overshoot: root.motion === "subtle" ? 0.6 : 1.4
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.plainStyle && !(root.kind === "idle" && root.idle === "time")
            radius: Math.min(width, height) / 2
            color: Theme.alpha(Theme.base, 0.92)
            border.width: root.active ? 1 : 0
            border.color: Theme.accentLine
        }
        clip: true

        Item {
            id: face
            anchors.fill: parent

            // idle: the time, or a quiet dot
            Label {
                id: clock
                visible: root.kind === "idle" && root.idle === "time"
                anchors.centerIn: parent
                role: "label"
                numeric: true
                color: root.ink
                text: root.title
                rotation: 0
            }
            Rectangle {
                visible: root.kind === "idle" && root.idle === "dot"
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: root.iconInk
                opacity: 0.6
            }

            // an activity: horizontal — picture, words, state; vertical — the picture alone
            Row {
                id: content
                visible: root.kind !== "idle" && !root.vertical
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s2
                Leading {
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.most - root.unit - 70)
                    elide: Text.ElideRight
                    role: "label"
                    color: root.ink
                    text: root.title
                }
                Icon {
                    visible: root.kind === "media"
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.glyph
                    size: Math.round(root.unit * 0.6)
                    color: root.iconInk
                }
            }
            Leading {
                visible: root.kind !== "idle" && root.vertical
                anchors.horizontalCenter: parent.horizontalCenter
                y: (pill.thick - height) / 2
            }
            // the next thing waiting, as a small bubble
            Rectangle {
                visible: root.b !== null && root.kind !== "idle"
                width: 18
                height: 18
                radius: 9
                color: Theme.accentSoft
                x: root.vertical ? (parent.width - width) / 2 : parent.width - width - 6
                y: root.vertical ? parent.height - height - 4 : (parent.height - height) / 2
                Icon {
                    anchors.centerIn: parent
                    name: ({ media: "music", notification: "bell", device: "headphones", power: "plug-connected" })[root.b?.kind ?? ""] ?? "point-filled"
                    size: 11
                    tone: "accent"
                }
            }
        }
    }

    // the picture of an activity: the album art, the app's icon, or the glyph
    component Leading: Rectangle {
        readonly property string art: root.kind === "media" ? (root.shownA?.data?.art ?? "") : ""
        readonly property string appIcon: root.kind === "notification" ? (root.shownA?.data?.icon ?? "") : ""
        width: root.unit
        height: root.unit
        radius: root.kind === "media" ? Math.round(root.unit / 4) : root.unit / 2
        color: art !== "" ? Theme.well : "transparent"
        clip: true
        Image {
            visible: parent.art !== ""
            anchors.fill: parent
            source: parent.art
            sourceSize.width: root.unit * 2
            sourceSize.height: root.unit * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Image {
            id: appImage
            visible: parent.appIcon !== "" && status === Image.Ready
            anchors.fill: parent
            anchors.margins: 1
            source: parent.appIcon
            sourceSize.width: root.unit * 2
            sourceSize.height: root.unit * 2
            asynchronous: true
        }
        Icon {
            visible: parent.art === "" && appImage.status !== Image.Ready
            anchors.centerIn: parent
            name: root.glyph
            size: Math.round(root.unit * 0.72)
            color: root.kind === "notification" ? Theme.accent : root.iconInk
        }
    }
}
