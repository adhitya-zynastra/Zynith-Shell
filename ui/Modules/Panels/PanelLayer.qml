import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services

Scope {
    id: root

    required property var modelData
    readonly property string screenName: modelData.name

    readonly property var entry: PanelRouter.openPanels[screenName] ?? null
    // what is drawn: the open entry, or the last one while it animates out
    property var shown: null
    property bool closing: false
    readonly property bool present: shown !== null

    // A warm (closed, kept-alive) window is reused for whichever panel opens next. It is shown only after it has taken
    // the new panel's size (`mapped` follows `shown` one call later, within the same pass of the event loop): a warm
    // window mapped first and resized after kept the old size at the compositor (the wallpaper browser after the
    // session menu stayed 432 px wide). That used to be avoided by throwing the warm window away whenever another panel
    // opened — a whole new window and page, ~40 ms more before the first frame.
    property bool mapped: false
    onShownChanged: {
        if (shown === null)
            mapped = false;
        else if (!mapped)
            Qt.callLater(() => root.mapped = root.shown !== null);
    }
    onEntryChanged: {
        if (entry) {
            // shown before the warm timer stops, or the loader sees neither for an instant and drops the window
            closing = false;
            shown = entry;
            cool.stop();
        } else if (shown) {
            closing = true;
        }
    }

    function finishClose(): void {
        if (closing) {
            // a bare panel (the wallpaper browser) is never kept warm: hidden, its content stops being bare,
            // the window shrank, and shown again it kept that size (432 px). It reopens on a fresh window.
            const wasBare = surface.item?.bare ?? false;
            // warm first: cleared the other way round, the loader saw neither present nor warm for an instant and
            // destroyed the window, then built an unused new one — nothing was ever kept warm
            if (ExperiencePolicy.panelKeepAliveMs > 0 && !wasBare)
                cool.restart();
            // hidden before `closing` clears: a surface whose close is taken back re-enters, and a warm one must not
            shown = null;
            closing = false;
        }
    }

    // After closing, the windows stay alive but unmapped for a while, so reopening skips surface
    // creation. Hidden panels do no work (they follow `active`).
    property bool warm: cool.running
    Timer {
        id: cool
        interval: ExperiencePolicy.panelKeepAliveMs
    }

    // A hover-opened panel closes a moment after the pointer has left it and what opened it.
    readonly property bool transientIdle: (entry?.transient ?? false) && (entry?.closeOnLeave ?? true) && !PanelRouter.held(screenName)
    Timer {
        interval: Math.max(0, root.entry?.closeDelay ?? 300)
        running: root.transientIdle
        onTriggered: if (PanelRouter.current(root.screenName)?.transient)
            PanelRouter.close(root.screenName)
    }

    // Clicks outside the panel close it. A hover-opened panel has none: it closes on leaving, and a catcher
    // over the bars would take the pointer from the icon that opened it. Transparent unless the profile dims the desktop behind a panel.
    //
    // Kept, like the panel's window: shown and hidden with each pinned panel, the catcher was a new full-screen window
    // every time (Quickshell destroys a hidden one), ~30 ms of every click- or key-opened panel before its first frame
    // (warm Sound panel 82-93 ms with it, 60 without). Once a pinned panel has used it, it stays mapped for as long as
    // the panel's window is kept (present or warm): transparent, with no input region, while nothing is pinned.
    // Hover-only use never creates it.
    readonly property bool catching: present && !(shown?.transient ?? false) && !(shown?.preview ?? false)
    property bool catcherKept: false
    onCatchingChanged: if (catching)
        catcherKept = true
    readonly property bool hostAlive: present || warm
    onHostAliveChanged: if (!hostAlive)
        catcherKept = false

    LazyLoader {
        active: root.present || root.warm

        PanelWindow {
            id: catcherWin
            visible: root.catching || root.catcherKept
            screen: root.modelData
            WlrLayershell.namespace: "zynith-panel-catcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: root.catching && ExperiencePolicy.richEffects && !root.closing ? Theme.scrim : "transparent"

            // The bars are not part of it: a click on another bar icon reaches that icon, which opens its panel in
            // this surface (a morph). The catcher lay over the bars, so that click closed the panel and the hover
            // opened the other one afresh — a close and a reopen where a switch was meant.
            readonly property var barRects: Object.keys(PanelRouter.bars).filter(k => k.endsWith("@" + root.screenName) && !PanelRouter.bars[k].hidden).map(k => PanelRouter.bars[k].bar)
            function hole(i: int): var {
                return barRects[i] ?? [0, 0, 0, 0];
            }
            // nothing pinned: no input at all, clicks reach what is under it
            mask: Region {
                x: 0
                y: 0
                width: root.catching ? catcherWin.width : 0
                height: root.catching ? catcherWin.height : 0
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(0)[0]; y: catcherWin.hole(0)[1]; width: catcherWin.hole(0)[2]; height: catcherWin.hole(0)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(1)[0]; y: catcherWin.hole(1)[1]; width: catcherWin.hole(1)[2]; height: catcherWin.hole(1)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(2)[0]; y: catcherWin.hole(2)[1]; width: catcherWin.hole(2)[2]; height: catcherWin.hole(2)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(3)[0]; y: catcherWin.hole(3)[1]; width: catcherWin.hole(3)[2]; height: catcherWin.hole(3)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(4)[0]; y: catcherWin.hole(4)[1]; width: catcherWin.hole(4)[2]; height: catcherWin.hole(4)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(5)[0]; y: catcherWin.hole(5)[1]; width: catcherWin.hole(5)[2]; height: catcherWin.hole(5)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(6)[0]; y: catcherWin.hole(6)[1]; width: catcherWin.hole(6)[2]; height: catcherWin.hole(6)[3] }
                Region { intersection: Intersection.Subtract; x: catcherWin.hole(7)[0]; y: catcherWin.hole(7)[1]; width: catcherWin.hole(7)[2]; height: catcherWin.hole(7)[3] }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Motion.reveal
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: if (root.catching)
                    PanelRouter.close(root.screenName)
            }
        }
    }

    LazyLoader {
        id: surface
        active: root.present || root.warm

        PanelSurface {
            visible: root.mapped
            screen: root.modelData
            entry: root.shown
            closing: root.closing
            onDismissed: root.finishClose()
        }
    }
}
