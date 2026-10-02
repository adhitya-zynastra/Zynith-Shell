import QtQuick
import Quickshell
import Quickshell.Wayland
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// On-screen feedback for volume, mute and keyboard layout. Off by default while the native OSD runs
// (config osd.enabled); the window exists only while something is being shown.
Scope {
    id: root

    // drawn here when zynith.toml hands the OSD over (or panels.toml [osd] enabled)
    readonly property bool enabled: (Config.surfaces?.osd ?? "native") === "zynith" || Config.osd.enabled
    property string kind: ""
    property string icon: ""
    property string label: ""
    property real value: -1     // 0..1, or -1 for no gauge
    property bool showing: false
    property bool armed: false  // ignore the initial values at startup

    function show(kind: string, icon: string, label: string, value: real): void {
        if (!enabled || !armed)
            return;
        root.kind = kind;
        root.icon = icon;
        root.label = label;
        root.value = value;
        showing = true;
        hide.restart();
    }

    Timer {
        interval: 800
        running: true
        onTriggered: root.armed = true
    }
    Timer {
        id: hide
        interval: Config.osd.durationMs
        onTriggered: root.showing = false
    }

    Connections {
        target: Audio
        function onVolumeChanged(): void {
            root.show("volume", Audio.glyph, Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "", Math.min(1, Audio.volume));
        }
        function onMutedChanged(): void {
            root.show("volume", Audio.glyph, Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "", Math.min(1, Audio.volume));
        }
    }
    Connections {
        target: Audio
        function onMicMutedChanged(): void {
            root.show("mic", Audio.micMuted ? "microphone-off" : "microphone", Audio.micMuted ? "Microphone off" : "Microphone on", -1);
        }
    }
    Connections {
        target: Backlight
        function onValueChanged(): void {
            root.show("brightness", Backlight.value < 0.34 ? "brightness-down" : "brightness-up", Math.round(Backlight.value * 100) + "", Backlight.value);
        }
    }
    Connections {
        target: Workspaces
        function onKeyboardLayoutChanged(): void {
            root.show("layout", "adjustments-horizontal", Workspaces.keyboardLayout, -1);
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: perScreen
            required property var modelData

            property real presence: root.showing ? 1 : 0
            Behavior on presence {
                NumberAnimation {
                    duration: root.showing ? Motion.reveal : Motion.dismiss
                    easing.type: root.showing ? Motion.enterEasing : Motion.exitEasing
                }
            }

            LazyLoader {
                active: perScreen.presence > 0

                PanelWindow {
                    id: win
                    screen: perScreen.modelData
                    WlrLayershell.namespace: "zynith-osd"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    anchors.bottom: true
                    margins.bottom: Config.osd.margin - pad
                    color: "transparent"
                    readonly property int pad: ExperiencePolicy.shadows ? Metrics.shadowPad : 0
                    implicitWidth: card.width + pad * 2
                    implicitHeight: card.height + pad * 2
                    mask: Region {}

                    BlurRegion {
                        window: win
                        item: card
                        radius: card.radius
                    }

                    Glass {
                        id: card
                        x: win.pad
                        y: win.pad
                        width: 300
                        height: 48
                        radius: height / 2
                        raised: true
                        opacity: perScreen.presence
                        transform: Translate {
                            y: (1 - perScreen.presence) * Motion.revealOffset
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.s5
                            anchors.rightMargin: Metrics.s5
                            spacing: Metrics.s4

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.icon
                                size: 18
                            }
                            Item {
                                visible: root.value >= 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 18 - 44 - Metrics.s4 * 2
                                height: 4

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 2
                                    color: Theme.hover
                                }
                                Rectangle {
                                    width: parent.width * Math.max(0, root.value)
                                    height: parent.height
                                    radius: 2
                                    color: Theme.accent

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: Motion.focus
                                            easing.type: Motion.standardEasing
                                        }
                                    }
                                }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.value >= 0 ? 44 : parent.width - 18 - Metrics.s4
                                horizontalAlignment: root.value >= 0 ? Text.AlignRight : Text.AlignLeft
                                role: "label"
                                numeric: root.value >= 0
                                tone: "muted"
                                text: root.label
                            }
                        }
                    }
                }
            }
        }
    }
}
