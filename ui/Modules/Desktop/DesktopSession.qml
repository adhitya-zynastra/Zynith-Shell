import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Lock, sleep, log out, restart, shut down. The last three ask for a second press.
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    readonly property bool vertical: WidgetTypes.value("session_actions", settings, "vertical") === true
    readonly property bool labels: WidgetTypes.value("session_actions", settings, "show_labels") === true
    property string armed: ""
    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = ""
    }

    implicitWidth: vertical ? 64 : 300
    implicitHeight: vertical ? 300 : 64

    Grid {
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 5
        spacing: Metrics.s2
        Repeater {
            model: Launcher.sessionActions
            delegate: Item {
                id: action
                required property var modelData
                readonly property bool confirm: ["logout", "reboot", "shutdown"].includes(modelData.id)
                readonly property bool isArmed: root.armed === modelData.id
                readonly property real side: Math.min(root.vertical ? root.width : root.width / 5 - Metrics.s2, root.vertical ? root.height / 5 - Metrics.s2 : root.height)
                width: side
                height: side
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: action.isArmed ? Theme.alpha(Theme.danger, 0.25) : area.containsMouse ? Theme.hover : Theme.alpha(Theme.base, 0.35)
                    border.width: Metrics.hairline
                    border.color: action.isArmed ? Theme.danger : Theme.hairline
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: action.modelData.glyph
                        size: action.side * (root.labels ? 0.32 : 0.42)
                        tone: action.isArmed ? "danger" : "ink"
                    }
                    Label {
                        visible: root.labels
                        anchors.horizontalCenter: parent.horizontalCenter
                        role: "micro"
                        tone: action.isArmed ? "danger" : "muted"
                        text: action.isArmed ? "Again" : action.modelData.label
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (action.confirm && !action.isArmed) {
                            root.armed = action.modelData.id;
                            disarm.restart();
                            return;
                        }
                        root.armed = "";
                        CoreClient.call("session " + action.modelData.id);
                    }
                }
            }
        }
    }
}
