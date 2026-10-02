import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services

// Popups in the top-right corner of the output with keyboard focus, newest on top. A popup leaves after
// its timeout unless the pointer rests on it; critical ones stay until handled. No window exists while
// nothing is shown.
Scope {
    id: root

    readonly property string screenName: Quickshell.screens.find(s => s.name === Workspaces.focusedOutput)?.name ?? (Quickshell.screens[0]?.name ?? "")
    // below a top bar when there is one
    readonly property int topInset: {
        const bar = Config.bars.find(b => b.edge === "top");
        return bar ? (bar.margin ?? 0) + (bar.thickness ?? Metrics.barThickness) : 0;
    }

    LazyLoader {
        active: Notifications.popups.length > 0

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            WlrLayershell.namespace: "zynith-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                right: true
            }
            margins {
                top: Math.max(0, root.topInset + Metrics.s3 - win.pad)
                right: Math.max(0, Metrics.s3 - win.pad)
            }
            readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
            implicitWidth: 380 + pad * 2
            implicitHeight: stack.height + pad * 2

            mask: Region {
                item: stack
            }

            Column {
                id: stack
                x: win.pad
                y: win.pad
                width: 380
                spacing: Metrics.s2

                Repeater {
                    // keyed by value: a new popup does not rebuild (and restart) the others
                    model: ScriptModel {
                        values: Notifications.popups
                    }

                    delegate: Item {
                        id: slot
                        required property int modelData
                        readonly property var entry: Notifications.entry(modelData)
                        width: stack.width
                        height: entry ? card.height : 0
                        visible: entry !== null

                        // enter: slide in from the edge, fade up
                        property real shown: 0
                        Component.onCompleted: shown = 1
                        Behavior on shown {
                            NumberAnimation {
                                duration: Motion.reveal
                                easing.type: Motion.enterEasing
                            }
                        }

                        Timer {
                            running: slot.entry !== null && Notifications.timeoutFor(slot.entry) > 0 && !card.hovered
                            interval: slot.entry ? Notifications.timeoutFor(slot.entry) : 0
                            onTriggered: Notifications.hidePopup(slot.modelData)
                        }

                        // a denser sheet than panels: popups land on anything, without a blur behind them
                        Glass {
                            anchors.fill: card
                            radius: Metrics.radiusLg
                            raised: true
                            fill: Theme.alpha(Theme.surfaceMid, 0.95)
                        }
                        NotificationCard {
                            id: card
                            width: parent.width
                            entry: slot.entry ?? ({ key: -1, actions: [], appName: "", appIcon: "", image: "", summary: "", body: "", time: 0 })
                            onActivated: Notifications.hidePopup(slot.modelData)
                        }

                        opacity: shown
                        transform: Translate {
                            x: (1 - slot.shown) * 24
                        }
                    }
                }
            }
        }
    }
}
