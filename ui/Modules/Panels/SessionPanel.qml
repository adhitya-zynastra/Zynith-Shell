import QtQuick
import QtQuick.Shapes
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Leave, lock or power off. The native shell carries out each action (locking stays on its secure path);
// anything that ends the session asks once more before it happens. Keys 1–n pick an action, Esc leaves.
//
// [panels] session_style: orbs (the native shell's modal session menu: no card, a row of round glyphs with
// their names, floating over the dimmed desktop) | card (the actions in a panel card). [panels]
// session_actions picks which actions and in what order.
Item {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true

    readonly property var cfg: Config.panels ?? ({})
    readonly property bool orbs: (cfg.session_style ?? "orbs") !== "card"
    // orbs draw their own surfaces over the dimmed desktop (a bare panel); the card is a panel like the rest
    readonly property bool bare: orbs
    readonly property Item blurItem: null
    readonly property int preferredWidth: 520
    readonly property real preferredTop: -1   // in the middle of the screen

    readonly property var known: ({
            lock: { label: "Lock", icon: "lock", confirm: false },
            suspend: { label: "Sleep", icon: "zzz", confirm: false },
            hibernate: { label: "Hibernate", icon: "snowflake", confirm: true },
            logout: { label: "Log out", icon: "logout", confirm: true },
            reboot: { label: "Restart", icon: "refresh", confirm: true },
            shutdown: { label: "Shut down", icon: "power", confirm: true }
        })
    readonly property var actions: Array.from(cfg.session_actions ?? ["lock", "suspend", "logout", "reboot", "shutdown"]).filter(id => known[id] !== undefined).map(id => Object.assign({ id: id }, known[id]))

    property string armed: ""
    readonly property int confirmMs: 4000
    onActiveChanged: if (active) {
        armed = "";
        keys.forceActiveFocus();
    }
    Component.onCompleted: keys.forceActiveFocus()

    function run(action: var): void {
        if (action.confirm && armed !== action.id) {
            armed = action.id;
            disarm.restart();
            return;
        }
        PanelRouter.close(screen.name);
        CoreClient.call("session " + action.id);
    }
    Timer {
        id: disarm
        interval: root.confirmMs
        onTriggered: root.armed = ""
    }
    readonly property string prompt: armed ? "Press again to " + (actions.find(a => a.id === armed)?.label ?? "").toLowerCase() : ""

    implicitWidth: preferredWidth
    implicitHeight: orbs ? (screen?.height ?? 1080) : cardColumn.implicitHeight

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: root.armed ? (root.armed = "") : PanelRouter.close(root.screen.name)
        Keys.onPressed: event => {
            const n = event.key - Qt.Key_1;
            if (n >= 0 && n < root.actions.length) {
                root.run(root.actions[n]);
                event.accepted = true;
            }
        }
    }

    // ── orbs: the native modal menu ──
    Item {
        visible: root.orbs
        anchors.fill: parent

        // a click on the dimmed desktop leaves
        MouseArea {
            anchors.fill: parent
            onClicked: PanelRouter.close(root.screen.name)
        }

        Column {
            anchors.centerIn: parent
            spacing: Metrics.s6

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                role: "display2"
                numeric: true
                opacity: Motion.ease("standardDecel", root.visibleProgress)
                text: Qt.formatTime(Time.now, "HH:mm")
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.s6
                Repeater {
                    model: root.actions
                    delegate: Orb {
                        required property var modelData
                        required property int index
                        action: modelData
                        number: index + 1
                        // each settles in a moment after the one before
                        arrive: Math.max(0, Math.min(1, (root.visibleProgress - index * 0.06) / 0.7))
                    }
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                role: "label"
                tone: root.armed ? "danger" : "faint"
                opacity: Motion.ease("standardDecel", root.visibleProgress)
                text: root.armed ? root.prompt : "Esc to stay"
            }
        }
    }

    component Orb: Column {
        id: orb
        property var action
        property int number
        property real arrive: 1
        readonly property bool armed: root.armed === action.id
        spacing: Metrics.s3
        opacity: Motion.ease("standardDecel", arrive)
        transform: Translate {
            y: (1 - Motion.ease("emphasizedDecel", orb.arrive)) * 18
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76
            height: 76
            Glass {
                anchors.fill: parent
                radius: width / 2
                raised: true
                fill: orb.armed ? Theme.alpha(Theme.danger, 0.22) : orbArea.containsMouse ? Theme.alpha(Theme.accent, 0.28) : Theme.glass
                Behavior on fill {
                    ColorAnim {}
                }
            }
            // the confirm window running out, round the armed orb
            Shape {
                visible: orb.armed
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.danger
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 38
                        centerY: 38
                        radiusX: 37
                        radiusY: 37
                        startAngle: -90
                        sweepAngle: 360 * orb.remain
                    }
                }
            }
            Icon {
                anchors.centerIn: parent
                name: orb.action.icon
                size: 26
                tone: orb.armed ? "danger" : orbArea.containsMouse ? "accent" : "ink"
            }
            MouseArea {
                id: orbArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.run(orb.action)
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            role: "label"
            tone: orb.armed ? "danger" : "muted"
            text: orb.action.label
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            role: "micro"
            tone: "faint"
            text: orb.number
        }
        // how much of the confirm window is left (1 → 0)
        property real remain: 1
        NumberAnimation on remain {
            running: orb.armed
            from: 1
            to: 0
            duration: root.confirmMs
        }
        onArmedChanged: if (!armed)
            remain = 1
    }

    // ── card: the actions in a panel card ──
    Column {
        id: cardColumn
        visible: !root.orbs
        width: root.preferredWidth
        padding: Metrics.s6
        spacing: Metrics.s5
        readonly property real inner: width - padding * 2

        Item {
            width: cardColumn.inner
            height: title.implicitHeight
            Label {
                id: title
                role: "headline"
                text: root.armed ? root.prompt : "Session"
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: title.verticalCenter
                role: "caption"
                tone: "faint"
                caps: true
                text: Qt.formatTime(Time.now, "HH:mm")
            }
        }
        Row {
            width: cardColumn.inner
            spacing: Metrics.s3
            Repeater {
                model: root.actions
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool armed: root.armed === modelData.id
                    width: (cardColumn.inner - Metrics.s3 * (root.actions.length - 1)) / Math.max(1, root.actions.length)
                    height: 96
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusLg
                        color: tile.armed ? Theme.alpha(Theme.danger, 0.18) : area.containsMouse ? Theme.hover : Theme.well
                        border.width: tile.armed ? 1 : 0
                        border.color: Theme.alpha(Theme.danger, 0.6)
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: Metrics.s3
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: tile.modelData.icon
                            size: 22
                            tone: tile.armed ? "danger" : "ink"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "label"
                            tone: "muted"
                            text: tile.modelData.label
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "micro"
                            tone: "faint"
                            text: tile.index + 1
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.run(tile.modelData)
                    }
                }
            }
        }
    }
}
