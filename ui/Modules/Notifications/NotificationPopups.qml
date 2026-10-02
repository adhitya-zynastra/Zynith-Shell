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
    // top-right | top-left | top-center | bottom-right | bottom-left | bottom-center
    readonly property string location: Config.notifications.location ?? "top-right"
    readonly property bool atTop: !location.startsWith("bottom")
    readonly property string side: location.endsWith("left") ? "left" : location.endsWith("center") ? "center" : "right"
    readonly property bool compact: Config.notifications.density === "compact"
    readonly property int cardWidth: compact ? 340 : 380
    // clear of any always-visible bar on the edges the stack touches
    function inset(edge: string): int {
        let most = 0;
        for (const bar of Config.bars) {
            if (bar.edge === edge && (bar.visibility ?? "always") === "always")
                most = Math.max(most, (bar.margin ?? 0) + (bar.thickness ?? Metrics.barThickness));
        }
        return most;
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
                top: root.atTop
                bottom: !root.atTop
                left: root.side === "left"
                right: root.side === "right"
            }
            margins {
                top: Math.max(0, root.inset("top") + Metrics.s3 - win.pad)
                bottom: Math.max(0, root.inset("bottom") + Metrics.s3 - win.pad)
                left: Math.max(0, root.inset("left") + Metrics.s3 - win.pad)
                right: Math.max(0, root.inset("right") + Metrics.s3 - win.pad)
            }
            readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
            implicitWidth: root.cardWidth + pad * 2
            implicitHeight: stack.height + pad * 2

            mask: Region {
                item: stack
            }

            Column {
                id: stack
                x: win.pad
                y: win.pad
                width: root.cardWidth
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
                            compact: root.compact
                            entry: slot.entry ?? ({ key: -1, actions: [], appName: "", appIcon: "", image: "", summary: "", body: "", time: 0 })
                            onActivated: Notifications.hidePopup(slot.modelData)
                        }

                        opacity: shown
                        transform: Translate {
                            x: root.side === "center" ? 0 : (1 - slot.shown) * (root.side === "left" ? -24 : 24)
                            y: root.side === "center" ? (1 - slot.shown) * (root.atTop ? -16 : 16) : 0
                        }
                    }
                }
            }
        }
    }
}
