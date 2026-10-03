import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services

// While niri's overview is open, a quiet readout at the top of each screen: which workspace of how many,
// what has focus, the time. niri stays the authority for windows and workspaces; this only reads them.
// [window] overview_companion (on by default).
Scope {
    id: root
    readonly property bool on: Config.window?.overview_companion !== false && Workspaces.overviewOpen

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData
            property real shown: root.on ? 1 : 0
            Behavior on shown {
                Anim {
                    role: root.on ? "enter" : "exit"
                }
            }
            readonly property var sets: Workspaces.forScreen(modelData)
            readonly property int at: sets.findIndex(w => w.active)

            LazyLoader {
                active: perScreen.shown > 0.01
                PanelWindow {
                    screen: perScreen.modelData
                    WlrLayershell.namespace: "zynith-overview"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    anchors.top: true
                    margins.top: Metrics.s6
                    implicitWidth: line.implicitWidth + Metrics.s6 * 2
                    implicitHeight: 40
                    color: "transparent"
                    mask: Region {}

                    Row {
                        id: line
                        anchors.centerIn: parent
                        spacing: Metrics.s5
                        opacity: perScreen.shown
                        transform: Translate {
                            y: (1 - perScreen.shown) * -10
                        }
                        Label {
                            role: "data"
                            tone: "accent"
                            text: perScreen.at >= 0 ? String(perScreen.at + 1).padStart(2, "0") + " / " + String(perScreen.sets.length).padStart(2, "0") : ""
                            style: Text.Raised
                            styleColor: Theme.alpha(Theme.base, 0.6)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 1
                            color: Theme.alpha(Theme.ink, 0.35)
                        }
                        Label {
                            role: "data"
                            tone: "ink"
                            text: Workspaces.focusedWindow?.title ? (Workspaces.focusedWindow.appId || "").split(".").pop() : "Desktop"
                            style: Text.Raised
                            styleColor: Theme.alpha(Theme.base, 0.6)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 1
                            color: Theme.alpha(Theme.ink, 0.35)
                        }
                        Label {
                            role: "data"
                            tone: "muted"
                            text: Qt.formatTime(Time.now, "HH:mm")
                            style: Text.Raised
                            styleColor: Theme.alpha(Theme.base, 0.6)
                        }
                    }
                }
            }
        }
    }
}
