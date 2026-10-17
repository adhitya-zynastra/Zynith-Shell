import QtQuick
import Quickshell
import Quickshell.Wayland
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// On-screen feedback. Volume, microphone, brightness and the keyboard layout are watched here; everything
// else the native shell notices — Wi-Fi, Bluetooth, power profile, caffeine, night light, Do Not Disturb, lock
// keys, track changes, the camera or microphone in use, keyboard backlight — arrives as its OSD event
// (Events.osd), with the native [osd.kinds] filters already applied. The window exists only while showing.
Scope {
    id: root

    readonly property bool enabled: (Config.surfaces?.osd ?? "native") === "zynith" || Config.osd.enabled
    // kinds watched here; the native shell's events for these are ignored so nothing shows twice
    readonly property var ownKinds: ["volume", "microphone", "brightness", "keyboard-layout"]

    property string kind: ""
    property string title: ""
    property string icon: ""
    property string label: ""
    property real value: -1     // 0..1 (up to 1.5 for boosted volume), or -1 for no gauge
    property bool inactive: false
    property bool showing: false
    property int pulse: 0       // bumps on every update, for the icon's small acknowledgement
    property bool armed: false  // ignore the initial values at startup

    function show(kind: string, title: string, icon: string, label: string, value: real, inactive: bool): void {
        if (!enabled || !armed || Config.osd.hidden.includes(kind) || Events.locked)
            return;
        root.kind = kind;
        root.title = title;
        root.icon = Icons.has(icon) ? icon : (glyphs[icon] ?? "adjustments");
        root.label = label;
        root.value = value;
        root.inactive = inactive;
        pulse++;
        showing = true;
        hide.restart();
    }

    // the native shell's glyph names that are not Tabler's
    readonly property var glyphs: ({
            "caffeine-on": "coffee",
            "caffeine-off": "coffee-off",
            "nightlight-on": "moon",
            "nightlight-forced": "moon-stars",
            "nightlight-off": "moon-off",
            "capslock": "arrow-big-up-line",
            "numlock": "numbers",
            "scrolllock": "arrows-sort",
            "power-saver": "leaf",
            "balanced": "scale",
            "performance": "gauge"
        })
    readonly property var titles: ({
            "keyboard-backlight": "Keyboard light",
            "lock-keys": "",
            "media": "Now playing",
            "privacy": "In use",
            "power-profile": "Power"
        })

    Timer {
        interval: 800
        running: true
        onTriggered: root.armed = true
    }
    Timer {
        id: hide
        interval: root.kind === "media" ? Math.max(Config.osd.durationMs, 2600) : Config.osd.durationMs
        onTriggered: root.showing = false
    }

    Connections {
        target: Audio
        function onVolumeChanged(): void {
            root.showVolume();
        }
        function onMutedChanged(): void {
            root.showVolume();
        }
        function onMicMutedChanged(): void {
            root.show("microphone", "", Audio.micMuted ? "microphone-off" : "microphone", Audio.micMuted ? "Microphone off" : "Microphone on", -1, Audio.micMuted);
        }
    }
    function showVolume(): void {
        show("volume", "Volume", Audio.glyph, Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "", Audio.muted ? 0 : Audio.volume, Audio.muted);
    }
    Connections {
        target: Backlight
        function onValueChanged(): void {
            root.show("brightness", "Brightness", Backlight.value < 0.34 ? "brightness-down" : "brightness-up", Math.round(Backlight.value * 100) + "", Backlight.value, false);
        }
    }
    Connections {
        target: Workspaces
        function onKeyboardLayoutChanged(): void {
            root.show("keyboard-layout", "", "keyboard", Workspaces.keyboardLayout, -1, false);
        }
    }
    // a test card (zynith-ui ipc osd <kind>), shown like any other
    Connections {
        target: Ipc
        function onOsdProbe(kind: string): void {
            root.show(kind, "Probe", "adjustments", "50", 0.5, false);
        }
    }
    Connections {
        target: Events
        function onOsd(c: var): void {
            if (root.ownKinds.includes(c.kind))
                return;
            root.show(c.kind, root.titles[c.kind] ?? c.title ?? "", c.icon, c.value, c.showProgress ? c.progress : -1, c.inactive);
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: perScreen
            required property var modelData

            // leaving, the card condenses first (MaterialSettle), then fades: `gone` lets the fade start
            property bool gone: true
            property real presence: root.showing || !gone ? 1 : 0
            Connections {
                target: root
                function onShowingChanged(): void {
                    if (root.showing) {
                        perScreen.gone = false;
                        perScreen.settle?.cancel();
                    } else if (perScreen.settle) {
                        perScreen.settle.condense(() => perScreen.gone = true);
                    } else {
                        perScreen.gone = true;
                    }
                }
            }
            property var settle: null
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
                    readonly property bool top: Config.osd.position === "top"
                    WlrLayershell.namespace: "zynith-osd"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    anchors.bottom: !top
                    anchors.top: top
                    anchors.left: Config.osd.align === "left"
                    anchors.right: Config.osd.align === "right"
                    margins.bottom: Config.osd.margin - pad
                    margins.top: Config.osd.margin - pad
                    margins.left: Math.max(0, Config.osd.sideMargin - pad)
                    margins.right: Math.max(0, Config.osd.sideMargin - pad)
                    color: "transparent"
                    readonly property int pad: Material.shadows ? Metrics.shadowPad + 8 : 0
                    implicitWidth: 360 + pad * 2
                    implicitHeight: card.height + pad * 2
                    mask: Region {}

                    readonly property var state: ({ top: anchors.top, bottom: anchors.bottom, left: anchors.left, right: anchors.right, marginTop: margins.top, marginBottom: margins.bottom, marginLeft: margins.left, marginRight: margins.right, pad: pad, width: implicitWidth, height: implicitHeight, hideMs: hide.interval, screen: screen?.name ?? "" })
                    onStateChanged: Ipc.report("osd", state)
                    Component.onCompleted: Ipc.report("osd", state)

                    // the material in motion (Components/MaterialSettle): the backdrop only while the card rests —
                    // not while it fades or slides in or out, nor while it reshapes (a gauge and a plain card)
                    MaterialSettle {
                        id: settle
                        moving: perScreen.presence < 0.999 || cardWidth.running || cardHeight.running
                        Component.onCompleted: perScreen.settle = settle
                        Component.onDestruction: if (perScreen.settle === settle)
                            perScreen.settle = null
                    }
                    BlurRegion {
                        window: win
                        item: settle.settled ? card : null
                        radius: card.radius
                    }

                    Glass {
                        id: card
                        // for diagnostics: its own pixels (zynith-ui ipc captureBar osd@<screen> <png>)
                        Component.onCompleted: PanelRouter.barItems["osd@" + (win.screen?.name ?? "")] = card
                        readonly property bool gauge: root.value >= 0
                        x: win.pad + (360 - width) / 2
                        y: win.pad
                        // the notification's anatomy, as a readout: a glyph tile, the kind in the data voice, the
                        // level in display numerals over its meter; a lens like every card, not a pill
                        width: gauge ? 320 : Math.min(360, Math.max(200, content.implicitWidth + Metrics.s4 * 2))
                        height: gauge ? 64 : 52
                        radius: Metrics.radiusSurface
                        raised: true
                        fill: Theme.alpha(Theme.sheetTone, settle.alpha(Theme.glassAlpha))
                        easeFill: settle.frost === 0
                        opacity: perScreen.presence
                        transform: Translate {
                            y: (1 - perScreen.presence) * Motion.revealOffset * (win.top ? -1 : 1)
                        }

                        Behavior on width {
                            NumberAnimation {
                                id: cardWidth
                                duration: Motion.morph
                                easing.type: Motion.standardEasing
                            }
                        }
                        Behavior on height {
                            NumberAnimation {
                                id: cardHeight
                                duration: Motion.morph
                                easing.type: Motion.standardEasing
                            }
                        }

                        Row {
                            id: content
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.s4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Metrics.s4

                            // the glyph on a plate, as a notification's: lit when on, quiet when off
                            Rectangle {
                                id: disc
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                height: width
                                radius: Metrics.radiusPlate
                                color: Theme.plate
                                border.width: root.inactive ? 0 : Metrics.hairline
                                border.color: Theme.signalEdge

                                Icon {
                                    id: glyph
                                    anchors.centerIn: parent
                                    name: root.icon
                                    size: 18
                                    tone: root.inactive ? "faint" : "accent"
                                }
                                // a small acknowledgement on every change
                                SequentialAnimation {
                                    id: tick
                                    NumberAnimation {
                                        target: disc
                                        property: "scale"
                                        to: 1.06
                                        duration: Motion.focus / 2
                                        easing.type: Motion.enterEasing
                                    }
                                    NumberAnimation {
                                        target: disc
                                        property: "scale"
                                        to: 1
                                        duration: Motion.focus
                                        easing.type: Motion.standardEasing
                                    }
                                }
                                Connections {
                                    target: root
                                    function onPulseChanged(): void {
                                        if (!Motion.reduced)
                                            tick.restart();
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: card.gauge ? 4 : 1
                                width: card.gauge ? card.width - disc.width - Metrics.s4 * 3 : implicitWidth

                                // title and value on one line for gauges; the message alone otherwise
                                Item {
                                    visible: card.gauge
                                    width: parent.width
                                    height: reading.implicitHeight
                                    Label {
                                        id: kindLabel
                                        anchors.left: parent.left
                                        // on the readout's baseline (the readout sits in a row, so by offset)
                                        y: reading.baselineOffset - baselineOffset
                                        role: "data"
                                        tone: "muted"
                                        text: root.title
                                    }
                                    // the level: display numerals, the unit set smaller
                                    Row {
                                        anchors.right: parent.right
                                        spacing: 1
                                        Label {
                                            id: reading
                                            role: "headline"
                                            numeric: true
                                            font.weight: Font.Light
                                            tone: root.value > 1 ? "danger" : "ink"
                                            text: /^\d+%?$/.test(root.label) ? String(parseInt(root.label)) : root.label
                                        }
                                        Label {
                                            visible: /^\d+%$/.test(root.label) || (/^\d+$/.test(root.label) && root.value >= 0)
                                            y: reading.baselineOffset - baselineOffset
                                            role: "caption"
                                            tone: "muted"
                                            text: "%"
                                        }
                                    }
                                }
                                Item {
                                    visible: card.gauge
                                    width: parent.width
                                    height: 3

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: Theme.rule
                                    }
                                    Rectangle {
                                        id: fill
                                        width: parent.width * Math.min(1, Math.max(0, root.value))
                                        height: parent.height
                                        radius: 2
                                        color: root.inactive ? Theme.inkFaint : Theme.alpha(Theme.ink, 0.82)
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Motion.focus
                                                easing.type: Motion.standardEasing
                                            }
                                        }
                                    }
                                    // the level's head: a small mark of light where it stands
                                    Rectangle {
                                        visible: !root.inactive
                                        x: Math.max(0, fill.width - 1)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 2
                                        height: 9
                                        radius: 1
                                        color: Theme.accent
                                    }
                                    // past 100 %: the boost shows over the full bar in the warning colour
                                    Rectangle {
                                        visible: root.value > 1
                                        anchors.right: parent.right
                                        width: parent.width * Math.min(1, (root.value - 1) * 2)
                                        height: parent.height
                                        radius: 3
                                        color: Theme.warning
                                        opacity: 0.85
                                    }
                                }
                                Label {
                                    visible: !card.gauge && root.title !== ""
                                    role: "data"
                                    tone: "faint"
                                    text: root.title
                                }
                                Label {
                                    visible: !card.gauge
                                    width: Math.min(implicitWidth, 360 - disc.width - Metrics.s4 * 4)
                                    role: "label"
                                    tone: root.inactive ? "muted" : "ink"
                                    text: root.label
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
