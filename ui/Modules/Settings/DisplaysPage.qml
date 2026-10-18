import QtQuick
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Displays: each connected output and its orientation. niri owns the outputs; this page asks it (DisplayConfig,
// native) and changes only what it is asked to. A new orientation is tried for the session first, with a
// countdown: kept, it is written into niri's own output block (backed up and validated first); not kept — or if
// nothing answers, even a frozen UI — it goes back on its own.
Column {
    id: root
    spacing: Metrics.s5

    readonly property var outputs: DisplayConfig.outputs
    property string selected: ""
    readonly property var current: outputs.find(o => o.name === selected) ?? outputs[0] ?? null
    onOutputsChanged: if (!outputs.some(o => o.name === selected) && outputs.length > 0)
        selected = outputs[0].name
    Component.onCompleted: DisplayConfig.refresh()

    // niri turns counter-clockwise: 90 is the screen's top turned to the left (portrait, rotated left)
    readonly property var orientations: [
        { key: "normal", label: "Landscape", detail: "0°", angle: 0 },
        { key: "90", label: "Portrait, left", detail: "90°", angle: -90 },
        { key: "180", label: "Landscape, upside down", detail: "180°", angle: 180 },
        { key: "270", label: "Portrait, right", detail: "270°", angle: 90 }
    ]
    function orientationOf(t: string): var {
        return orientations.find(o => o.key === t) ?? null;
    }
    property string message: ""
    Connections {
        target: DisplayConfig
        function onApplied(output: string, ok: bool, text: string): void {
            root.message = ok ? "" : text;
        }
        function onFinished(output: string, kept: bool, text: string): void {
            root.message = kept ? "Kept. " + text : (DisplayConfig.lastError !== "" ? DisplayConfig.lastError + " — " : "") + text;
        }
    }

    PanelHeader {
        width: parent.width
        title: "Displays"
        caption: "Which way each screen faces. niri arranges the outputs; the shell follows them."
    }

    // ── the change waiting for an answer ──
    Rectangle {
        visible: DisplayConfig.pending
        width: parent.width
        height: pendingRow.implicitHeight + Metrics.s4 * 2
        radius: Metrics.radiusMd
        color: Theme.accentSoft
        border.width: 1
        border.color: Theme.accentLine
        Row {
            id: pendingRow
            x: Metrics.s4
            y: Metrics.s4
            width: parent.width - Metrics.s4 * 2
            spacing: Metrics.s4
            Column {
                width: parent.width - keep.width - undo.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    role: "title"
                    text: "Keep this orientation?"
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    role: "label"
                    tone: "muted"
                    text: DisplayConfig.pendingOutput + " is " + (root.orientationOf(DisplayConfig.pendingTransform)?.label ?? DisplayConfig.pendingTransform).toLowerCase() + ". It goes back to " + (root.orientationOf(DisplayConfig.previousTransform)?.label ?? DisplayConfig.previousTransform).toLowerCase() + " in " + DisplayConfig.secondsLeft + " s unless you keep it."
                }
            }
            Chip {
                id: keep
                objectName: "orientation-keep"
                anchors.verticalCenter: parent.verticalCenter
                icon: "check"
                text: "Keep"
                active: true
                onClicked: DisplayConfig.confirm()
            }
            Chip {
                id: undo
                objectName: "orientation-revert"
                anchors.verticalCenter: parent.verticalCenter
                icon: "arrow-back-up"
                text: "Revert (" + DisplayConfig.secondsLeft + ")"
                onClicked: DisplayConfig.revert()
            }
        }
    }

    Label {
        visible: root.message !== ""
        width: parent.width
        wrapMode: Text.Wrap
        role: "label"
        tone: DisplayConfig.lastError !== "" ? "danger" : "muted"
        text: root.message
    }

    // ── the outputs as niri places them: a small map, each screen drawn at its real shape ──
    Card {
        width: parent.width
        caption: root.outputs.length === 1 ? "Your display" : root.outputs.length + " displays"
        Label {
            visible: root.outputs.length === 0
            role: "label"
            tone: "muted"
            text: "No outputs reported — is this a niri session?"
        }
        Item {
            id: map
            visible: root.outputs.length > 0
            width: parent.width
            height: 200
            readonly property real minX: Math.min(...root.outputs.map(o => o.x))
            readonly property real minY: Math.min(...root.outputs.map(o => o.y))
            readonly property real spanW: Math.max(...root.outputs.map(o => o.x + o.width)) - minX
            readonly property real spanH: Math.max(...root.outputs.map(o => o.y + o.height)) - minY
            readonly property real k: Math.min((width - 40) / Math.max(1, spanW), (height - 20) / Math.max(1, spanH))
            Repeater {
                model: root.outputs
                delegate: Rectangle {
                    id: screenTile
                    required property var modelData
                    readonly property bool chosen: modelData.name === root.selected
                    x: (map.width - map.spanW * map.k) / 2 + (modelData.x - map.minX) * map.k
                    y: (map.height - map.spanH * map.k) / 2 + (modelData.y - map.minY) * map.k
                    width: modelData.width * map.k
                    height: modelData.height * map.k
                    radius: Metrics.radiusSm
                    color: chosen ? Theme.accentSoft : Theme.well
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Theme.accent : Theme.hairline
                    Behavior on width {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Behavior on height {
                        Anim {
                            role: "spatial"
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "label"
                            font.weight: Font.Medium
                            text: screenTile.modelData.name
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "caption"
                            numeric: true
                            tone: "muted"
                            text: screenTile.modelData.width + " × " + screenTile.modelData.height
                        }
                    }
                    // the screen's top edge, so a turned screen reads as turned
                    Rectangle {
                        readonly property real a: root.orientationOf(screenTile.modelData.transform)?.angle ?? 0
                        width: a === 0 || a === 180 ? parent.width * 0.4 : 3
                        height: a === 0 || a === 180 ? 3 : parent.height * 0.4
                        radius: 1.5
                        color: screenTile.chosen ? Theme.accent : Theme.inkFaint
                        x: a === -90 ? 4 : a === 90 ? parent.width - width - 4 : (parent.width - width) / 2
                        y: a === 0 ? 4 : a === 180 ? parent.height - height - 4 : (parent.height - height) / 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selected = screenTile.modelData.name
                    }
                }
            }
        }
        Label {
            visible: root.current !== null
            width: parent.width
            wrapMode: Text.Wrap
            role: "caption"
            tone: "faint"
            text: root.current ? [root.current.make, root.current.model].filter(s => s && s !== "Unknown").join(" ") + "  ·  " + root.current.modeWidth + " × " + root.current.modeHeight + " panel  ·  scale " + root.current.scale : ""
        }
    }

    // ── orientation ──
    Card {
        width: parent.width
        caption: "Orientation" + (root.current ? " — " + root.current.name : "")
        Flow {
            id: choices
            width: parent.width
            spacing: Metrics.s3
            readonly property real cell: (width - spacing * 3) / 4
            Repeater {
                model: root.orientations
                delegate: Item {
                    id: choice
                    required property var modelData
                    objectName: "orientation-" + modelData.key
                    readonly property bool on: root.current?.transform === modelData.key
                    readonly property bool trial: DisplayConfig.pending && DisplayConfig.pendingOutput === root.current?.name && DisplayConfig.pendingTransform === modelData.key
                    width: Math.max(130, choices.cell)
                    height: 118
                    Interactive {
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        active: choice.on
                        onClicked: if (root.current && !choice.on)
                            DisplayConfig.setTransform(root.current.name, choice.modelData.key, 15)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        color: "transparent"
                        border.width: choice.on ? 2 : 1
                        border.color: choice.on ? (choice.trial ? Theme.accent : Theme.accentLine) : Theme.hairline
                    }
                    // a little screen, turned the way this choice turns it, with its top edge marked
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Metrics.s4
                        width: 56
                        height: 56
                        Rectangle {
                            anchors.centerIn: parent
                            width: 48
                            height: 30
                            radius: 4
                            rotation: choice.modelData.angle
                            color: choice.on ? Theme.accentSoft : Theme.well
                            border.width: 1.5
                            border.color: choice.on ? Theme.accent : Theme.inkFaint
                            Behavior on rotation {
                                Anim {
                                    role: "spatial"
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 4
                                width: 18
                                height: 2.5
                                radius: 1.25
                                color: choice.on ? Theme.accent : Theme.inkMuted
                            }
                        }
                    }
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Metrics.s3
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "label"
                            font.weight: choice.on ? Font.Medium : Font.Normal
                            tone: choice.on ? "accent" : "ink"
                            text: choice.modelData.label
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            role: "caption"
                            numeric: true
                            tone: "faint"
                            text: choice.modelData.detail + (choice.trial ? "  ·  trying" : "")
                        }
                    }
                }
            }
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            role: "caption"
            tone: "faint"
            text: "A change waits " + 15 + " s for you to keep it, then goes back by itself. Kept changes are written to the output's block in niri's configuration, with a backup in ~/.config/rice-backups" + (DisplayConfig.lastBackup !== "" ? " (last: " + DisplayConfig.lastBackup.split("/").pop() + ")" : "") + "."
        }
    }
}
