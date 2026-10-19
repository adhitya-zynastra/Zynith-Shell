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

    // An open panel in the stack's corner (the Control Panel under its bar, say): the popups sit just past it
    // rather than over its heading — below it for a stack at the top, above it at the bottom. A hover peek is
    // left alone (it is gone in a moment), as is a panel that would leave the stack no room.
    readonly property var panel: {
        const entry = PanelRouter.openPanels[screenName];
        const r = PanelRouter.rects[screenName];
        return entry && !entry.transient && r && r.h > 0 ? r : null;
    }
    function dodge(edge: string, base: int): int {
        const scr = Quickshell.screens.find(s => s.name === root.screenName);
        if (!panel || !scr)
            return base;
        const sw = scr.width, sh = scr.height, px = panel.x - scr.x, py = panel.y - scr.y;
        const mx = Config.notifications.marginX, inL = inset("left") + mx, inR = inset("right") + mx;
        const lo = side === "left" ? inL : side === "right" ? sw - inR - cardWidth : (sw - cardWidth) / 2;
        if (px >= lo + cardWidth || px + panel.w <= lo)
            return base;
        const gap = Metrics.s4;
        if (edge === "top" && atTop && py < base + 160) {
            const below = py + panel.h + gap;
            return sh - below > 240 ? Math.max(base, below) : base;
        }
        if (edge === "bottom" && !atTop && py + panel.h > sh - base - 160) {
            const above = sh - py + gap;
            return sh - above > 240 ? Math.max(base, above) : base;
        }
        return base;
    }

    // the window outlives the last popup by its exit, so the exit is seen — only when there was one: the list is
    // also re-set while already empty (opening the notification centre does), and lingering then created an empty
    // window just to destroy it, a ~100 ms stall of the GUI thread in the middle of the centre's entrance
    property bool lingering: false
    property int lastCount: 0
    Connections {
        target: Notifications
        function onPopupsChanged(): void {
            const n = Notifications.popups.length;
            if (n === 0 && root.lastCount > 0) {
                root.lingering = true;
                linger.restart();
            }
            root.lastCount = n;
        }
    }
    Timer {
        id: linger
        interval: Motion.exit + 60
        onTriggered: root.lingering = false
    }

    LazyLoader {
        // an island that takes notifications is where they appear instead (Services/Island)
        active: (Notifications.popups.length > 0 || root.lingering) && !Island.takesNotifications

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
                top: Math.max(0, root.dodge("top", root.inset("top") + Config.notifications.marginY) - win.pad)
                bottom: Math.max(0, root.dodge("bottom", root.inset("bottom") + Config.notifications.marginY) - win.pad)
                left: root.side === "left" ? 0 : Math.max(0, root.inset("left") + Config.notifications.marginX - win.pad)
                right: root.side === "right" ? 0 : Math.max(0, root.inset("right") + Config.notifications.marginX - win.pad)
            }
            readonly property int pad: Material.shadows ? Metrics.shadowPad + 8 : 0
            // On the side the stack sits against, the window reaches the screen's edge and the margin is room inside
            // it: a card swiped that way leaves through the screen's edge. Ending short of it, the window cut a swiped
            // card off square at its own edge.
            readonly property int sideRoom: root.side === "right" ? Math.max(0, root.inset("right") + Config.notifications.marginX - pad) : root.side === "left" ? Math.max(0, root.inset("left") + Config.notifications.marginX - pad) : 0
            implicitWidth: root.cardWidth + pad * 2 + 40 + sideRoom
            implicitHeight: Math.max(1, list.contentHeight + waiting.height + pad * 2 + 8)
            readonly property var state: ({ top: anchors.top, bottom: anchors.bottom, left: anchors.left, right: anchors.right, marginTop: margins.top, marginBottom: margins.bottom, marginLeft: margins.left, marginRight: margins.right, layer: Config.notifications.layer, cardWidth: root.cardWidth, height: implicitHeight, cards: list.count, screen: screen?.name ?? "" })
            onStateChanged: Ipc.report("notifications", state)
            Component.onCompleted: Ipc.report("notifications", state)

            mask: Region {
                item: list
                Region {
                    item: waiting
                }
            }
            // the compositor's backdrop behind each card, not behind the stack as one block (that showed in the gaps
            // between cards) nor the window's margins
            property var cards: []
            // only the cards at rest (Components/MaterialSettle): a card that slides in, is pushed along, or is
            // swiped would leave its region behind it (a frosted patch where it was) or run ahead of it
            readonly property bool listMoving: arriving.running || leaving.running || pushed.running
            BlurRegion {
                window: win
                items: win.cards.filter(c => c.settled)
                radius: Metrics.radiusSurface
            }

            ListView {
                id: list
                // for diagnostics: the cards' own pixels (zynith-ui ipc captureBar notifications@<screen> <png>)
                Component.onCompleted: PanelRouter.barItems["notifications@" + (win.screen?.name ?? "")] = list
                // a reply field takes the keyboard while it is being used
                property bool typing: false
                x: win.pad + (root.side === "left" ? win.sideRoom : 40)
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
                    id: arriving
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
                    id: leaving
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
                    id: pushed
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
                    // its backdrop region follows the delegate, which is what the list moves (a region on the sheet
                    // inside stayed where the card first appeared when newer cards pushed it along)
                    Component.onCompleted: win.cards = win.cards.concat([slot])
                    Component.onDestruction: win.cards = win.cards.filter(c => c !== slot)

                    // the material in motion: no backdrop while the list moves it or it is being swiped
                    MaterialSettle {
                        id: cardSettle
                        moving: win.listMoving || slot.dragX !== 0
                    }
                    readonly property bool settled: cardSettle.settled
                    onSettledChanged: win.cards = win.cards.slice()

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

                        // the material's raised tier (denser than panels: popups land on anything)
                        Glass {
                            anchors.fill: parent
                            radius: Metrics.radiusSurface
                            raised: true
                            fill: Theme.alpha(Theme.surfaceHigh, cardSettle.alpha(Material.raisedAlpha))
                            easeFill: cardSettle.frost === 0
                            // Glass in motion carries the wallpaper itself (MaterialSettle): where the card is now
                            still: cardSettle.still
                            standIn: cardSettle.standIn
                            screenSize: Qt.size(win.screen?.width ?? 1920, win.screen?.height ?? 1080)
                            screenX: (win.anchors.left ? win.margins.left : win.anchors.right ? screenSize.width - win.margins.right - win.implicitWidth : (screenSize.width - win.implicitWidth) / 2) + list.x + slot.x + sheet.x
                            screenY: (win.anchors.top ? win.margins.top : screenSize.height - win.margins.bottom - win.implicitHeight) + list.y + slot.y - list.contentY
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
                            anchors.leftMargin: Metrics.radiusSurface
                            width: (parent.width - Metrics.radiusSurface * 2) * slot.remaining
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
                x: list.x + (root.side === "right" ? root.cardWidth - width : root.side === "center" ? (root.cardWidth - width) / 2 : 0)
                y: root.atTop ? list.y + list.contentHeight + Metrics.s2 : win.pad
                width: waitingLabel.implicitWidth + Metrics.s5 * 2
                height: visible ? 26 : 0
                radius: height / 2
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
