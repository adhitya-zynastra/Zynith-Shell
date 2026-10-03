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

    onEntryChanged: {
        if (entry) {
            closing = false;
            shown = entry;
        } else if (shown) {
            closing = true;
        }
    }

    function finishClose(): void {
        if (closing) {
            closing = false;
            shown = null;
            if (ExperiencePolicy.panelKeepAliveMs > 0)
                cool.restart();
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
    LazyLoader {
        active: root.present || root.warm

        PanelWindow {
            visible: root.present && !(root.shown?.transient ?? false)
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
            color: ExperiencePolicy.richEffects && !root.closing ? Theme.scrim : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Motion.reveal
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: PanelRouter.close(root.screenName)
            }
        }
    }

    LazyLoader {
        active: root.present || root.warm

        PanelSurface {
            visible: root.present
            screen: root.modelData
            entry: root.shown
            closing: root.closing
            onDismissed: root.finishClose()
        }
    }
}
