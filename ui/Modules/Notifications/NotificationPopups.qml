import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Common
import qs.Components
import qs.Services

// Popups, newest nearest the corner. A popup arrives on the spatial curve from its edge, leaves sliding the
// way it came (or the way it was swiped), and the stack closes up behind it. Its time runs out along a thin
// line that stops while the pointer rests on it; critical and resident ones stay until handled. Beyond
// max_popups the rest wait, and say so. No window exists while nothing is shown.
Scope {
    id: root

    readonly property string screenName: {
        const wanted = Config.notifications.monitor ?? "focused";
        if (wanted === "primary")
            return Quickshell.screens[0]?.name ?? "";
        const named = Quickshell.screens.find(s => s.name === wanted);
        if (named)
            return named.name;
        return Quickshell.screens.find(s => s.name === Workspaces.focusedOutput)?.name ?? (Quickshell.screens[0]?.name ?? "");
    }
    // top-right | top-left | top-center | bottom-right | bottom-left | bottom-center
    readonly property string location: Config.notifications.location ?? "top-right"
    readonly property bool atTop: !location.startsWith("bottom")
    readonly property string side: location.endsWith("left") ? "left" : location.endsWith("center") ? "center" : "right"
    readonly property bool compact: Config.notifications.density === "compact"
    readonly property int cardWidth: compact ? 340 : 384
    // clear of any always-visible bar on the edges the stack touches
    function inset(edge: string): int {
        let most = 0;
        for (const bar of Config.bars) {
            if (bar.edge === edge && (bar.visibility ?? "always") === "always")
                most = Math.max(most, (bar.margin ?? 0) + (bar.thickness ?? Metrics.barThickness));
        }
        return most;
    }

    // the window outlives the last popup by its exit, so the exit is seen
    property bool lingering: false
    Connections {
        target: Notifications
        function onPopupsChanged(): void {
            if (Notifications.popups.length === 0) {
                root.lingering = true;
                linger.restart();
            }
        }
    }
    Timer {
        id: linger
        interval: Motion.exit + 60
        onTriggered: root.lingering = false
    }

    LazyLoader {
        active: Notifications.popups.length > 0 || root.lingering

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            WlrLayershell.namespace: "zynith-notifications"
            WlrLayershell.layer: Config.notifications.layer === "top" ? WlrLayer.Top : WlrLayer.Overlay
            // a popup with a reply field can take the keyboard when clicked; otherwise popups never do
            WlrLayershell.keyboardFocus: Notifications.popups.some(k => (Notifications.entry(k)?.reply ?? "") !== "") ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: root.atTop
                bottom: !root.atTop
                left: root.side === "left"
                right: root.side === "right"
            }
            margins {
                top: Math.max(0, root.inset("top") + Config.notifications.marginY - win.pad)
                bottom: Math.max(0, root.inset("bottom") + Config.notifications.marginY - win.pad)
                left: Math.max(0, root.inset("left") + Config.notifications.marginX - win.pad)
                right: Math.max(0, root.inset("right") + Config.notifications.marginX - win.pad)
            }
            readonly property int pad: Material.shadows ? Metrics.shadowPad + 8 : 0
            implicitWidth: root.cardWidth + pad * 2 + 40
            implicitHeight: Math.max(1, list.contentHeight + waiting.height + pad * 2 + 8)

            mask: Region {
                item: list
                Region {
                    item: waiting
                }
            }
            // the compositor blurs behind the stack only, not the window's margins
            BlurRegion {
                window: win
                item: list
                radius: Metrics.radiusLg
            }

            ListView {
                id: list
                // a reply field takes the keyboard while it is being used
                property bool typing: false
                x: win.pad + (root.side === "left" ? 0 : 40)
                y: win.pad + (root.atTop ? 0 : waiting.height)
                width: root.cardWidth
                height: contentHeight
                interactive: false
                spacing: Metrics.s2
                verticalLayoutDirection: root.atTop ? ListView.TopToBottom : ListView.BottomToTop

                model: ScriptModel {
                    values: Notifications.popups
                }

                add: Transition {
                    ParallelAnimation {
                        Anim {
                            property: "opacity"
                            from: 0
                            to: 1
                            role: "effects"
                        }
                        Anim {
                            property: "x"
                            from: root.side === "left" ? -48 : root.side === "right" ? 48 : 0
                            to: 0
                            role: "spatial"
                        }
                        Anim {
                            property: "scale"
                            from: 0.92
                            to: 1
                            role: "spatial"
                        }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        Anim {
                            property: "opacity"
                            to: 0
                            role: "exit"
                        }
                        Anim {
                            property: "x"
                            to: root.side === "left" ? -root.cardWidth * 0.5 : root.cardWidth * 0.5
                            role: "exit"
                        }
                    }
                }
                displaced: Transition {
                    Anim {
                        property: "y"
                        role: "spatial"
                    }
                    Anim {
                        properties: "opacity,scale"
                        to: 1
                        role: "effects"
                    }
                }

                delegate: Item {
                    id: slot
                    required property int modelData
                    readonly property var entry: Notifications.entry(modelData)
                    readonly property int timeout: entry ? Notifications.timeoutFor(entry) : 0
                    width: list.width
                    height: entry ? card.height : 0
                    visible: entry !== null

                    // the swipe: the card follows the pointer sideways; far or fast enough closes it
                    property real dragX: 0
                    DragHandler {
                        id: swipe
                        target: null
                        xAxis.enabled: true
                        yAxis.enabled: false
                        onTranslationChanged: slot.dragX = translation.x
                        onActiveChanged: if (!active) {
                            const far = Math.abs(slot.dragX) > slot.width * 0.35 || Math.abs(centroid.velocity.x) > 900;
                            if (far) {
                                flingOut.to = slot.dragX > 0 ? slot.width * 1.2 : -slot.width * 1.2;
                                flingOut.start();
                            } else {
                                settle.start();
                            }
                        }
                    }
                    Anim {
                        id: settle
                        target: slot
                        property: "dragX"
                        to: 0
                        role: "spatialFast"
                    }
                    SequentialAnimation {
                        id: flingOut
                        property real to: 0
                        Anim {
                            target: slot
                            property: "dragX"
                            to: flingOut.to
                            role: "exit"
                        }
                        ScriptAction {
                            script: Notifications.close(slot.modelData)
                        }
                    }

                    // time left, as a line along the bottom; it stops while the pointer rests on the card
                    property real remaining: 1
                    NumberAnimation on remaining {
                        id: countdown
                        running: slot.timeout > 0
                        paused: running && (card.hovered || swipe.active || list.typing)
                        from: 1
                        to: 0
                        duration: slot.timeout
                        onFinished: Notifications.hidePopup(slot.modelData)
                    }

                    Item {
                        id: sheet
                        width: parent.width
                        height: card.height
                        x: slot.dragX
                        opacity: 1 - Math.min(0.7, Math.abs(slot.dragX) / slot.width)

                        // a denser sheet than panels: popups land on anything
                        Glass {
                            anchors.fill: parent
                            radius: Metrics.radiusLg
                            raised: true
                            fill: Theme.alpha(Theme.surfaceMid, 0.95)
                        }
                        NotificationCard {
                            id: card
                            width: parent.width
                            compact: root.compact
                            popup: true
                            entry: slot.entry ?? ({ key: -1, actions: [], appName: "", appIcon: "", image: "", summary: "", body: "", time: 0, progress: -1, reply: "" })
                            onActivated: Notifications.hidePopup(slot.modelData)
                            onTypingChanged: list.typing = typing
                        }
                        Rectangle {
                            visible: slot.timeout > 0
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.radiusLg
                            width: (parent.width - Metrics.radiusLg * 2) * slot.remaining
                            height: 2
                            radius: 1
                            color: Theme.alpha(Theme.accent, 0.55)
                        }
                    }
                }
            }

            // the rest of a burst, waiting their turn
            Rectangle {
                id: waiting
                visible: Notifications.queue.length > 0
                x: win.pad + (root.side === "left" ? 0 : 40) + (root.side === "right" ? root.cardWidth - width : root.side === "center" ? (root.cardWidth - width) / 2 : 0)
                y: root.atTop ? list.y + list.contentHeight + Metrics.s2 : win.pad
                width: waitingLabel.implicitWidth + Metrics.s5 * 2
                height: visible ? 26 : 0
                radius: 13
                color: Theme.alpha(Theme.surfaceMid, 0.95)
                border.width: Metrics.hairline
                border.color: Theme.hairline
                Label {
                    id: waitingLabel
                    anchors.centerIn: parent
                    role: "caption"
                    tone: "muted"
                    text: "+" + Notifications.queue.length + " waiting"
                }
                Behavior on y {
                    Anim {
                        role: "spatial"
                    }
                }
            }
        }
    }
}
