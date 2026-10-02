import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services

// A focused panel: placed beside the widget that opened it, grows out of the bar edge, leaves faster
// than it arrived. The content is chosen by panel id.
PanelWindow {
    id: win

    required property var entry
    property bool closing: false
    signal dismissed

    readonly property string edge: entry?.edge ?? "top"
    readonly property int panelWidth: Config.panels.width
    readonly property real cardHeight: content.implicitHeight
    readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad + 6 : 0
    readonly property int gap: Metrics.s3
    readonly property int screenMargin: Metrics.s3
    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real ox: (entry?.originX ?? -1) >= 0 ? entry.originX : sw - panelWidth / 2 - screenMargin
    readonly property real oy: (entry?.originY ?? -1) >= 0 ? entry.originY : 0
    readonly property real extent: entry?.extent ?? 42

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    // the card's rectangle on screen
    readonly property real cardX: edge === "left" ? extent + gap : edge === "right" ? sw - extent - gap - panelWidth : clamp(ox - panelWidth / 2, screenMargin, sw - panelWidth - screenMargin)
    readonly property real cardY: edge === "top" ? extent + gap : edge === "bottom" ? sh - extent - gap - cardHeight : clamp(oy - cardHeight / 2, screenMargin, sh - cardHeight - screenMargin)
    readonly property real winX: Math.max(0, cardX - pad)
    readonly property real winY: Math.max(0, cardY - pad)

    WlrLayershell.namespace: "zynith-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors {
        top: true
        left: true
    }
    margins {
        left: winX
        top: winY
    }
    implicitWidth: cardX - winX + panelWidth + pad
    implicitHeight: cardY - winY + cardHeight + pad

    mask: Region {
        item: card
    }

    BlurRegion {
        window: win
        item: card
        radius: Metrics.radiusXl
    }

    // 0 = gone, 1 = in place
    property real revealed: 0

    NumberAnimation {
        id: enter
        target: win
        property: "revealed"
        to: 1
        duration: Motion.reveal
        easing.type: Motion.enterEasing
    }
    NumberAnimation {
        id: leave
        target: win
        property: "revealed"
        to: 0
        duration: Motion.dismiss
        easing.type: Motion.exitEasing
        onFinished: win.dismissed()
    }
    Component.onCompleted: enter.start()
    onClosingChanged: {
        if (closing) {
            enter.stop();
            leave.start();
        } else {
            leave.stop();
            enter.start();
        }
    }

    Glass {
        id: card

        x: win.cardX - win.winX
        y: win.cardY - win.winY
        width: win.panelWidth
        height: win.cardHeight
        radius: Metrics.radiusXl
        raised: true
        opacity: win.revealed

        // grow from the bar side, a few pixels of travel
        readonly property real travel: (1 - win.revealed) * Motion.revealOffset
        transform: [
            Scale {
                origin.x: win.edge === "left" ? 0 : win.edge === "right" ? card.width : win.ox - win.cardX
                origin.y: win.edge === "top" ? 0 : win.edge === "bottom" ? card.height : win.oy - win.cardY
                xScale: Motion.revealScale + (1 - Motion.revealScale) * win.revealed
                yScale: Motion.revealScale + (1 - Motion.revealScale) * win.revealed
            },
            Translate {
                x: win.edge === "left" ? -card.travel : win.edge === "right" ? card.travel : 0
                y: win.edge === "top" ? -card.travel : win.edge === "bottom" ? card.travel : 0
            }
        ]

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: PanelRouter.close(win.screen.name)
        }

        PanelContent {
            id: content

            width: parent.width
            panelId: win.entry?.id ?? ""
            screen: win.screen
            visibleProgress: win.revealed
        }
    }
}
