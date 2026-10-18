import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import "../../Common/BarModel.js" as BarModel

// Where the bar is and how big: its screen edge and its place along it (pictures, not words), then its sizes —
// each previews on the real bar while dragged, and each can go back to its default on its own.
Column {
    id: pos

    required property var page
    readonly property var bar: page.bar ?? ({})
    readonly property bool vertical: bar.edge === "left" || bar.edge === "right"
    spacing: Metrics.s5

    Row {
        spacing: Metrics.s6
        // the edge: a screen with four sides to click
        Column {
            spacing: Metrics.s2
            Label {
                role: "micro"
                caps: true
                tone: "faint"
                text: "Screen edge"
            }
            Item {
                width: 150
                height: 100
                Rectangle {
                    x: 22
                    y: 18
                    width: 106
                    height: 64
                    radius: Metrics.radiusSm
                    color: Theme.surfaceLow
                    border.width: 1
                    border.color: Theme.hairline
                }
                Repeater {
                    model: BarModel.edges
                    delegate: Rectangle {
                        id: edgeCell
                        required property string modelData
                        readonly property bool on: pos.bar.edge === modelData
                        readonly property bool v: modelData === "left" || modelData === "right"
                        objectName: "edge-" + modelData
                        x: modelData === "left" ? 2 : modelData === "right" ? 132 : 22
                        y: modelData === "top" ? 0 : modelData === "bottom" ? 86 : 18
                        width: v ? 16 : 106
                        height: v ? 64 : 14
                        radius: 5
                        color: on ? Theme.accent : edgeArea.containsMouse ? Theme.accentLine : Theme.plate
                        MouseArea {
                            id: edgeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarEdits.place(pos.page.barId, edgeCell.modelData, pos.bar.anchor ?? "center")
                        }
                    }
                }
            }
        }
        // the place along it
        Column {
            spacing: Metrics.s2
            Label {
                role: "micro"
                caps: true
                tone: "faint"
                text: "Along the edge"
            }
            Row {
                spacing: Metrics.s2
                Repeater {
                    model: BarModel.anchors
                    delegate: Rectangle {
                        id: anchorCell
                        required property string modelData
                        readonly property bool on: pos.bar.anchor === modelData
                        objectName: "anchor-" + modelData
                        width: 84
                        height: 100
                        radius: Metrics.radiusMd
                        color: on ? Theme.accentSoft : anchorArea.containsMouse ? Theme.hover : Theme.plate
                        border.width: on ? 2 : 0
                        border.color: Theme.accent
                        // a little screen with the bar where this puts it
                        Rectangle {
                            x: 12
                            y: 10
                            width: 60
                            height: 40
                            radius: 4
                            color: Theme.surfaceLow
                            border.width: 1
                            border.color: Theme.hairline
                            Rectangle {
                                readonly property real len: anchorCell.modelData === "fill" ? 1 : 0.4
                                readonly property real t: 5
                                readonly property real along: anchorCell.modelData === "start" || anchorCell.modelData === "fill" ? 0 : anchorCell.modelData === "end" ? 1 - len : (1 - len) / 2
                                color: anchorCell.on ? Theme.accent : Theme.inkMuted
                                radius: 2
                                x: pos.vertical ? (pos.bar.edge === "left" ? 2 : parent.width - t - 2) : 2 + along * (parent.width - 4)
                                y: pos.vertical ? 2 + along * (parent.height - 4) : (pos.bar.edge === "top" ? 2 : parent.height - t - 2)
                                width: pos.vertical ? t : len * (parent.width - 4)
                                height: pos.vertical ? len * (parent.height - 4) : t
                            }
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 60
                            role: "label"
                            tone: anchorCell.on ? "accent" : "ink"
                            text: anchorCell.modelData === "fill" ? "Full length" : anchorCell.modelData === "center" ? "Centre" : pos.vertical ? (anchorCell.modelData === "start" ? "Top" : "Bottom") : (anchorCell.modelData === "start" ? "Left" : "Right")
                        }
                        MouseArea {
                            id: anchorArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarEdits.place(pos.page.barId, pos.bar.edge ?? "top", anchorCell.modelData)
                        }
                    }
                }
            }
        }
    }

    SchemaForm {
        width: parent.width
        advanced: "hide"
        schema: [
            { key: "thickness", label: "Thickness", hint: "How deep the bar is, from the screen edge in", kind: "int", default: 34, from: 20, to: 96, step: 1 },
            { key: "length", label: "Length", hint: "0 fits what it holds", kind: "int", default: 0, from: 0, to: 3840, step: 10, when: { anchor: ["start", "center", "end"] } },
            { key: "margin", label: "Gap to the edge", hint: "0 puts it against the screen edge (needed for concave corners there)", kind: "int", default: 0, from: 0, to: 64, step: 1 },
            { key: "offset", label: pos.bar.anchor === "fill" ? "Room at both ends" : "Distance from the " + (pos.bar.anchor === "end" ? (pos.vertical ? "bottom" : "right") : (pos.vertical ? "top" : "left")), kind: "int", default: 0, from: 0, to: 1200, step: 2, when: { anchor: ["start", "end", "fill"] } },
            { key: "padding", label: "Room inside its ends", kind: "int", default: 12, from: 0, to: 40, step: 1 },
            { key: "spacing", label: "Space between components", hint: "-1 follows the theme", kind: "int", default: -1, from: -1, to: 24, step: 1 }
        ]
        valueOf: key => pos.bar[key] ?? schema.find(s => s.key === key)?.default
        isSet: key => pos.bar[key] !== undefined
        shows: spec => !spec.when || Object.entries(spec.when).every(([k, v]) => v.includes(pos.bar[k] ?? "center"))
        onChanged: (key, value) => BarEdits.setKey(pos.page.barId, key, value)
        onCleared: key => BarEdits.setKey(pos.page.barId, key, undefined)
        commitOnRelease: true
        onPreviewed: (key, value) => BarEdits.preview(pos.page.barId, key, value)
        onPreviewEnded: (key, value, canceled) => BarEdits.endPreview(pos.page.barId, key, value, canceled)
    }

    // which displays it is on
    Column {
        visible: Quickshell.screens.length > 1
        width: parent.width
        spacing: Metrics.s2
        Label {
            role: "micro"
            caps: true
            tone: "faint"
            text: "Displays"
        }
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Chip {
                text: "Every display"
                active: (pos.bar.screens ?? ["*"]).includes("*")
                onClicked: BarEdits.setKey(pos.page.barId, "screens", ["*"])
            }
            Repeater {
                model: Quickshell.screens
                delegate: Chip {
                    required property var modelData
                    readonly property var list: (pos.bar.screens ?? ["*"]).filter(s => s !== "*")
                    text: modelData.name
                    active: list.includes(modelData.name)
                    onClicked: {
                        const next = active ? list.filter(s => s !== modelData.name) : list.concat([modelData.name]);
                        BarEdits.setKey(pos.page.barId, "screens", next.length > 0 ? next : ["*"]);
                    }
                }
            }
        }
    }
}
