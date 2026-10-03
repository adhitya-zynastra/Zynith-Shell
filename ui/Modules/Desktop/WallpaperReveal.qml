import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// A new wallpaper arrives as a circle growing out of where it was chosen (the card in the browser), over
// the old one, under every window — then the native wallpaper, which has changed underneath meanwhile,
// takes over. [wallpaper] reveal: circle (default) · none. Lasts wallpaper.reveal_ms (≈ 550, the
// measured reference).
Scope {
    id: root

    readonly property var job: Wallpapers.reveal
    readonly property bool on: (Config.wallpaper?.reveal ?? "circle") !== "none" && !Motion.reduced

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: perScreen
            required property var modelData
            // this screen shows it when the change is for every screen or for this one
            readonly property bool mine: root.on && root.job !== null && (root.job.output === "" || root.job.output === modelData.name)

            LazyLoader {
                active: perScreen.mine

                PanelWindow {
                    id: win
                    screen: perScreen.modelData
                    WlrLayershell.namespace: "zynith-wallpaper-reveal"
                    WlrLayershell.layer: WlrLayer.Background
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    mask: Region {}

                    // where the circle starts, in this screen's coordinates (the centre when unknown)
                    readonly property real ox: (root.job?.x ?? -1) >= 0 ? root.job.x - (screen?.x ?? 0) : width / 2
                    readonly property real oy: (root.job?.y ?? -1) >= 0 ? root.job.y - (screen?.y ?? 0) : height / 2
                    // far enough to cover the furthest corner
                    readonly property real reach: Math.hypot(Math.max(ox, width - ox), Math.max(oy, height - oy))

                    property real grow: 0
                    property real fade: 1
                    SequentialAnimation {
                        id: play
                        running: false
                        PropertyAction {
                            target: win
                            property: "fade"
                            value: 1
                        }
                        NumberAnimation {
                            target: win
                            property: "grow"
                            from: 0
                            to: 1
                            duration: Math.round((Config.wallpaper?.reveal_ms ?? 550) * Motion.scale)
                            easing.type: Easing.OutQuad
                        }
                        // the native wallpaper has its new image by now: hand over
                        PauseAnimation {
                            duration: 250
                        }
                        NumberAnimation {
                            target: win
                            property: "fade"
                            to: 0
                            duration: Motion.dismiss
                            easing.type: Easing.InQuad
                        }
                        ScriptAction {
                            script: Wallpapers.reveal = null
                        }
                    }

                    Image {
                        id: next
                        anchors.fill: parent
                        source: root.job ? "file://" + root.job.path : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: win.width
                        sourceSize.height: win.height
                        asynchronous: true
                        visible: false
                        // the circle starts once the image is ready, so it never reveals nothing
                        onStatusChanged: if (status === Image.Ready)
                            play.restart()
                        // an image that will not load: nothing to show, let go
                        Component.onCompleted: if (status === Image.Error)
                            Wallpapers.reveal = null
                    }
                    Item {
                        id: circle
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle {
                            readonly property real r: win.reach * win.grow
                            x: win.ox - r
                            y: win.oy - r
                            width: r * 2
                            height: r * 2
                            radius: r
                            color: "white"
                        }
                    }
                    MultiEffect {
                        id: shown
                        anchors.fill: parent
                        Component.onCompleted: PanelRouter.barItems["reveal@" + (win.screen?.name ?? "")] = shown
                        source: next
                        maskEnabled: true
                        maskSource: circle
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.08
                        opacity: win.fade
                    }
                }
            }
        }
    }
}
