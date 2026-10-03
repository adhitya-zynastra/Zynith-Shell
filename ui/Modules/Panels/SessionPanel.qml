import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Leave, lock or power off. The native shell carries out each action (locking stays on its secure path);
// anything that ends the session asks once more before it happens. Keys 1–5 pick an action.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    readonly property int preferredWidth: 520
    // in the middle of the screen
    readonly property real preferredTop: -1

    property string armed: ""
    onActiveChanged: if (active) {
        armed = "";
        keys.forceActiveFocus();
    }
    Component.onCompleted: keys.forceActiveFocus()

    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock", confirm: false },
        { id: "suspend", label: "Sleep", icon: "zzz", confirm: false },
        { id: "logout", label: "Log out", icon: "logout", confirm: true },
        { id: "reboot", label: "Restart", icon: "refresh", confirm: true },
        { id: "shutdown", label: "Shut down", icon: "power", confirm: true }
    ]

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
        interval: 4000
        onTriggered: root.armed = ""
    }

    padding: Metrics.s6
    spacing: Metrics.s5
    readonly property real inner: width - padding * 2

    Item {
        id: keys
        width: root.inner
        height: title.implicitHeight
        focus: true
        Keys.onEscapePressed: PanelRouter.close(root.screen.name)
        Keys.onPressed: event => {
            const n = event.key - Qt.Key_1;
            if (n >= 0 && n < root.actions.length) {
                root.run(root.actions[n]);
                event.accepted = true;
            }
        }

        Label {
            id: title
            role: "headline"
            text: root.armed ? "Press again to " + (root.actions.find(a => a.id === root.armed)?.label ?? "").toLowerCase() : "Session"
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
        width: root.inner
        spacing: Metrics.s3

        Repeater {
            model: root.actions

            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool armed: root.armed === modelData.id
                width: (root.inner - Metrics.s3 * (root.actions.length - 1)) / root.actions.length
                height: 96

                Rectangle {
                    anchors.fill: parent
                    radius: Metrics.radiusLg
                    color: tile.armed ? Theme.alpha(Theme.danger, 0.18) : area.containsMouse ? Theme.hover : Theme.well
                    border.width: tile.armed ? 1 : 0
                    border.color: Theme.alpha(Theme.danger, 0.6)

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.focus
                        }
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
