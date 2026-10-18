import QtQuick
import qs.Common
import qs.Components
import qs.Services
import "../../Common/BarModel.js" as BarModel

// The bar's four corners, picked on a drawing of the bar against the screen edges it touches. Each corner is
// rounded, square or concave — concave curves the corner inward, into a screen edge (BarModel.cornerShapes: where
// there is no edge to curve into it cannot be, and this says why and offers the change that makes it possible).
// Sizes preview on the real bar while dragged and are written when let go.
Column {
    id: corners

    required property var page
    readonly property var bar: page.bar ?? ({})
    readonly property string barId: page.barId
    property int corner: -1
    readonly property var touch: BarModel.endsTouch(bar)
    readonly property real scale: Metrics.radiusScale
    readonly property var shapes: BarModel.cornerShapes(bar, touch, scale)
    readonly property real thickness: bar.thickness ?? 34
    spacing: Metrics.s4

    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        role: "caption"
        tone: "muted"
        text: corners.corner < 0 ? "Click a corner of the bar to shape it." : "Shaping the " + BarModel.cornerLabels[corners.corner].toLowerCase() + " corner. Click another corner, or the same one to finish."
    }

    // ── the drawing ──
    Rectangle {
        id: stage
        width: parent.width
        height: 230
        radius: Metrics.radiusLg
        color: Theme.surfaceLow
        border.width: 1
        border.color: Theme.hairline
        clip: true

        readonly property bool vert: corners.bar.edge === "left" || corners.bar.edge === "right"
        readonly property string edge: corners.bar.edge ?? "top"
        // the bar drawn larger than life: its thickness 52 px, its length most of the stage
        readonly property real tk: 52
        readonly property real f: tk / corners.thickness
        readonly property real span: vert ? height : width
        readonly property real gap: (corners.bar.margin ?? 0) > 0 ? Math.max(12, (corners.bar.margin ?? 0) * f) : 0
        readonly property bool fill: corners.bar.anchor === "fill"
        readonly property real len: fill || (corners.touch.start && corners.touch.end) ? span : span * 0.62
        readonly property real a0: corners.touch.start ? 0 : corners.touch.end ? span - len : corners.bar.anchor === "start" ? 34 : corners.bar.anchor === "end" ? span - len - 34 : (span - len) / 2
        readonly property real c0: edge === "top" ? gap : edge === "bottom" ? height - gap - tk : edge === "left" ? gap : width - gap - tk
        readonly property var pill: vert ? { x: c0, y: a0, w: tk, h: len } : { x: a0, y: c0, w: len, h: tk }
        readonly property var radii: BarModel.cornerRadii(corners.bar, { w: pill.w / f, h: pill.h / f }, corners.scale, null, corners.touch).map(v => v * f)
        readonly property var curves: BarModel.fillets(corners.bar, { x: pill.x / f, y: pill.y / f, w: pill.w / f, h: pill.h / f }, { start: 9999, end: 9999, inner: 9999, outer: 9999 }, corners.touch, corners.scale)
        readonly property var points: [[pill.x, pill.y], [pill.x + pill.w, pill.y], [pill.x + pill.w, pill.y + pill.h], [pill.x, pill.y + pill.h]]

        // the screen's edges in view: the bar's own, and those its ends reach
        Repeater {
            model: ["top", "bottom", "left", "right"].filter(e => e === stage.edge || (stage.vert ? (e === "top" && corners.touch.start) || (e === "bottom" && corners.touch.end) : (e === "left" && corners.touch.start) || (e === "right" && corners.touch.end)))
            delegate: Rectangle {
                required property string modelData
                color: Theme.inkFaint
                x: modelData === "right" ? stage.width - 4 : 0
                y: modelData === "bottom" ? stage.height - 4 : 0
                width: modelData === "left" || modelData === "right" ? 4 : stage.width
                height: modelData === "top" || modelData === "bottom" ? 4 : stage.height
            }
        }
        Label {
            x: stage.vert ? (stage.edge === "left" ? stage.width - width - Metrics.s3 : Metrics.s3) : (stage.width - width) / 2
            y: stage.vert ? (stage.height - height) / 2 : (stage.edge === "top" ? stage.height - height - Metrics.s3 : Metrics.s3)
            role: "micro"
            caps: true
            tone: "faint"
            text: "screen edge " + (stage.edge === "top" ? "↑" : stage.edge === "bottom" ? "↓" : stage.edge === "left" ? "←" : "→")
        }
        // the bar
        Rectangle {
            x: stage.pill.x
            y: stage.pill.y
            width: stage.pill.w
            height: stage.pill.h
            color: Theme.accentSoft
            border.width: 1
            border.color: Theme.accentLine
            topLeftRadius: stage.radii[0]
            topRightRadius: stage.radii[1]
            bottomRightRadius: stage.radii[2]
            bottomLeftRadius: stage.radii[3]
            Behavior on topLeftRadius {
                Anim {
                    role: "spatialFast"
                }
            }
            Behavior on topRightRadius {
                Anim {
                    role: "spatialFast"
                }
            }
            Behavior on bottomRightRadius {
                Anim {
                    role: "spatialFast"
                }
            }
            Behavior on bottomLeftRadius {
                Anim {
                    role: "spatialFast"
                }
            }
        }
        Repeater {
            model: stage.curves
            delegate: ConcaveCorner {
                required property var modelData
                x: modelData.x * stage.f
                y: modelData.y * stage.f
                r: Math.max(1, modelData.r * stage.f)
                solid: modelData.solid
                fill: Theme.accentSoft
            }
        }
        // the four corners, to click
        Repeater {
            model: 4
            delegate: Item {
                id: handle
                required property int index
                readonly property var p: stage.points[index]
                readonly property bool chosen: corners.corner === index
                readonly property var sh: corners.shapes[index]
                objectName: "corner-" + index
                // inside the bar, off its very corner, so a click never lands on the screen edge
                x: p[0] - width / 2 + (index === 0 || index === 3 ? 14 : -14)
                y: p[1] - height / 2 + (index === 0 || index === 1 ? 14 : -14)
                width: 26
                height: 26
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: handle.chosen ? Theme.accent : handleArea.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                    border.width: 2
                    border.color: Theme.accent
                }
                Icon {
                    anchors.centerIn: parent
                    name: handle.sh.wanted === "concave" ? "arrow-down-right" : handle.sh.shape === "square" ? "border-corner-square" : "border-corner-rounded"
                    size: 12
                    tone: handle.chosen ? "onAccent" : "accent"
                    rotation: handle.sh.wanted === "concave" ? [180, 270, 0, 90][handle.index] : [0, 90, 180, 270][handle.index]
                }
                MouseArea {
                    id: handleArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: corners.corner = corners.corner === handle.index ? -1 : handle.index
                }
            }
        }
    }

    // ── the chosen corner ──
    Column {
        visible: corners.corner >= 0
        width: parent.width
        spacing: Metrics.s3
        readonly property var sh: corners.corner >= 0 ? corners.shapes[corners.corner] : null
        readonly property string blocked: corners.corner >= 0 ? BarModel.concaveBlocked(corners.bar, corners.corner, corners.touch) : ""
        Row {
            spacing: Metrics.s2
            Repeater {
                model: [{ key: "round", label: "Rounded", hint: "A soft outward curve" }, { key: "square", label: "Square", hint: "A sharp corner" }, { key: "concave", label: "Concave", hint: "Curves inward, into the screen edge" }]
                delegate: ShapeChoice {
                    required property var modelData
                    kind: modelData.key
                    label: modelData.label
                    hint: modelData.hint
                    current: parent.parent.sh?.wanted ?? "round"
                    possible: modelData.key !== "concave" || parent.parent.blocked === ""
                }
            }
        }
        // why a concave corner cannot be here, and the change that makes it possible
        Rectangle {
            visible: parent.blocked !== ""
            width: parent.width
            height: whyCol.implicitHeight + Metrics.s3 * 2
            radius: Metrics.radiusMd
            color: Theme.plate
            Column {
                id: whyCol
                x: Metrics.s3
                y: Metrics.s3
                width: parent.width - Metrics.s3 * 2
                spacing: Metrics.s2
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    role: "caption"
                    tone: "muted"
                    text: "Concave here: " + parent.parent.parent.blocked + (parent.parent.parent.sh?.wanted === "concave" ? " Until then it is drawn square." : "")
                }
                Flow {
                    width: parent.width
                    spacing: Metrics.s2
                    readonly property string side: corners.corner >= 0 ? BarModel.cornerSide(corners.bar.edge, corners.corner) : ""
                    readonly property string end: corners.corner >= 0 ? BarModel.cornerEnd(corners.bar.edge, corners.corner) : ""
                    Chip {
                        visible: parent.side === "outer" && (corners.bar.margin ?? 0) > 0 && !corners.touch[parent.end]
                        objectName: "fix-no-gap"
                        icon: "arrow-bar-to-up"
                        text: "Put the bar against its edge (no gap)"
                        onClicked: BarEdits.setKey(corners.barId, "margin", 0)
                    }
                    Chip {
                        visible: parent.side === "inner" && !corners.touch[parent.end]
                        objectName: "fix-reach-end"
                        icon: "arrows-horizontal"
                        text: corners.bar.anchor === "fill" || corners.bar.anchor === parent.end ? "Move it to the very end of the edge" : "Make it full length"
                        onClicked: corners.bar.anchor === "fill" || corners.bar.anchor === parent.end ? BarEdits.setKey(corners.barId, "offset", 0) : BarEdits.place(corners.barId, corners.bar.edge, "fill")
                    }
                    Chip {
                        visible: parent.side === "outer" && corners.touch[parent.end] && (corners.bar.margin ?? 0) === 0
                        objectName: "fix-gap"
                        icon: "arrow-bar-down"
                        text: "Leave a gap to its edge"
                        onClicked: BarEdits.setKey(corners.barId, "margin", 8)
                    }
                }
            }
        }
        // its size
        Item {
            visible: parent.sh !== null && parent.sh.wanted !== "square"
            width: parent.width
            height: 32
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 90
                role: "label"
                tone: "muted"
                text: parent.parent.sh?.wanted === "concave" ? "Curve size" : "Roundness"
            }
            Slider {
                id: sizeSlider
                objectName: "corner-size"
                x: 90
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 90 - 96
                readonly property real most: Math.max(4, parent.parent.sh?.wanted === "concave" ? 48 : corners.thickness / 2)
                readonly property string key: BarModel.cornerKeys[Math.max(0, corners.corner)]
                // the slider speaks the radius key (before the theme's scale)
                value: Math.min(1, (parent.parent.sh?.size ?? 0) / corners.scale / most)
                step: 1 / most
                onMoved: v => BarEdits.preview(corners.barId, key, Math.round(v * most))
                onCommitted: v => {
                    BarEdits.setCornerSize(corners.barId, corners.corner, Math.round(v * most));
                    BarEdits.endPreview(corners.barId, key, Math.round(v * most), false);
                }
                onCanceled: BarEdits.endPreview(corners.barId, key, undefined, true)
            }
            Label {
                anchors.right: resetSize.left
                anchors.rightMargin: Metrics.s2
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                numeric: true
                tone: "muted"
                text: Math.round(sizeSlider.value * sizeSlider.most) + " px"
            }
            IconButton {
                id: resetSize
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: 26
                iconSize: 13
                icon: "restore"
                tone: "muted"
                enabled: corners.bar[sizeSlider.key] !== undefined
                onClicked: BarEdits.setCornerSize(corners.barId, corners.corner, undefined)
            }
        }
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Chip {
                icon: "copy"
                text: "Same for all four corners"
                onClicked: {
                    const sh = parent.parent.sh;
                    for (let i = 0; i < 4; i++)
                        if (i !== corners.corner && (sh.wanted !== "concave" || BarModel.concaveBlocked(corners.bar, i, corners.touch) === ""))
                            BarEdits.setCornerShape(corners.barId, i, sh.wanted);
                }
            }
        }
    }

    // one shape to pick, drawn
    component ShapeChoice: Rectangle {
        id: choice
        property string kind
        property string label
        property string hint
        property string current
        property bool possible: true
        readonly property bool on: current === kind
        objectName: "corner-shape-" + kind
        width: 120
        height: 92
        radius: Metrics.radiusMd
        color: on ? Theme.accentSoft : choiceArea.containsMouse && possible ? Theme.hover : Theme.plate
        border.width: on ? 2 : 0
        border.color: Theme.accent
        opacity: possible || on ? 1 : 0.55
        // the corner, drawn: a screen edge on top, the corner below it
        Item {
            x: (parent.width - 44) / 2
            y: 10
            width: 44
            height: 34
            Rectangle {
                width: parent.width
                height: 3
                color: Theme.inkFaint
                visible: choice.kind === "concave"
            }
            Rectangle {
                x: 14
                y: choice.kind === "concave" ? 3 : 6
                width: 30
                height: 28
                color: Theme.accent
                topLeftRadius: choice.kind === "round" ? 14 : 0
            }
            ConcaveCorner {
                visible: choice.kind === "concave"
                x: 2
                y: 3
                r: 12
                solid: "tr"
                fill: Theme.accent
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 50
            role: "label"
            tone: choice.on ? "accent" : "ink"
            text: choice.label
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 68
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            role: "micro"
            tone: "faint"
            text: choice.hint
        }
        MouseArea {
            id: choiceArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: choice.possible ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (corners.corner >= 0)
                BarEdits.setCornerShape(corners.barId, corners.corner, choice.kind)
        }
    }
}
