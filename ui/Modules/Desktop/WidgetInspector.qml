import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Components
import qs.Services

// The selected desktop widget's settings, drawn from its kind's schema (WidgetTypes): every setting the native
// editor offered, in the same keys, plus exact geometry. Changes write through Desktop, so they can be undone.
Item {
    id: root

    required property var widget
    property string side: "right"
    property real screenW: 1920
    property real screenH: 1080
    // the widget's box on screen: the card sits beside it (right if there is room, else left), level with it, kept
    // on screen; without one, at the side's edge
    property var near: null
    readonly property real gap: 24
    // the card, for the editor (a press on it is the inspector's, never the canvas's)
    readonly property Item cardItem: card
    readonly property string type: WidgetTypes.canonical(widget?.type ?? "")
    readonly property var settings: widget?.settings ?? ({})
    readonly property var schema: WidgetTypes.schema(type)

    Glass {
        id: card
        width: 360
        height: Math.min(parent.height - 160, column.implicitHeight + Metrics.s5 * 2)
        readonly property bool fitsRight: root.near !== null && root.near.x + root.near.width + root.gap + width <= parent.width - 32
        readonly property bool fitsLeft: root.near !== null && root.near.x - root.gap - width >= 32
        readonly property string placedSide: fitsRight ? "right" : fitsLeft ? "left" : root.side
        x: fitsRight ? root.near.x + root.near.width + root.gap : fitsLeft ? root.near.x - root.gap - width : (root.side === "right" ? parent.width - width - 32 : 32)
        y: root.near !== null ? Math.max(24, Math.min(parent.height - height - 24, root.near.y + root.near.height / 2 - height / 2)) : (parent.height - height) / 2
        radius: Metrics.radiusXl
        raised: true

        // arrives from its side
        property real p: 0
        Component.onCompleted: p = 1
        Behavior on p {
            Anim {
                role: "spatial"
            }
        }
        opacity: p
        transform: Translate {
            x: (1 - card.p) * (card.placedSide === "right" ? 40 : -40)
        }

        TapHandler {}
        Flickable {
            anchors.fill: parent
            anchors.margins: Metrics.s5
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: column
                width: parent.width
                spacing: Metrics.s4

                // who
                Row {
                    spacing: Metrics.s3
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: Theme.accentSoft
                        Icon {
                            anchors.centerIn: parent
                            name: WidgetTypes.find(root.type)?.icon ?? "apps"
                            size: 17
                            tone: "accent"
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            role: "title"
                            text: WidgetTypes.find(root.type)?.label ?? root.type
                        }
                        Label {
                            role: "caption"
                            tone: "faint"
                            text: (root.widget?.output || "every screen") + "  ·  " + (root.widget?.id ?? "")
                        }
                    }
                }

                // where, exactly
                Grid {
                    columns: 5
                    spacing: Metrics.s2
                    Repeater {
                        model: [
                            { key: "cx", label: "X" },
                            { key: "cy", label: "Y" },
                            { key: "width", label: "W" },
                            { key: "height", label: "H" },
                            { key: "rotation", label: "°" }
                        ]
                        delegate: Column {
                            required property var modelData
                            spacing: 2
                            Label {
                                role: "micro"
                                tone: "faint"
                                text: modelData.label
                            }
                            NumberField {
                                width: 58
                                value: modelData.key === "rotation" ? Math.round((root.widget?.rotation ?? 0) * 180 / Math.PI) : Math.round(root.widget?.[modelData.key] ?? 0)
                                onCommitted: v => Desktop.patch([root.widget.id], {
                                        [modelData.key]: modelData.key === "rotation" ? v * Math.PI / 180 : v
                                    })
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.hairline
                }

                // the kind's own settings, then the common ones
                Repeater {
                    model: root.schema
                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property bool shown: WidgetTypes.visible(root.type, modelData, root.settings)
                        readonly property var value: WidgetTypes.value(root.type, root.settings, modelData.key)
                        width: column.width
                        height: shown ? control.implicitHeight + label.implicitHeight + Metrics.s1 : 0
                        visible: shown
                        clip: true

                        function set(v: var): void {
                            Desktop.setSetting(root.widget.id, row.modelData.key, v);
                        }

                        Label {
                            id: label
                            role: "label"
                            tone: "muted"
                            visible: row.modelData.kind !== "toggle"
                            text: row.modelData.label
                        }
                        Loader {
                            id: control
                            anchors.top: row.modelData.kind === "toggle" ? parent.top : label.bottom
                            anchors.topMargin: row.modelData.kind === "toggle" ? 0 : Metrics.s1
                            width: parent.width
                            sourceComponent: ({
                                    toggle: toggleControl,
                                    choice: choiceControl,
                                    select: selectControl,
                                    slider: sliderControl,
                                    int: sliderControl,
                                    text: textControl,
                                    colour: colourControl,
                                    font: fontControl,
                                    image: imageControl,
                                    glyph: glyphControl
                                })[row.modelData.kind] ?? textControl
                            onLoaded: {
                                item.spec = Qt.binding(() => row.modelData);
                                item.val = Qt.binding(() => row.value);
                                // the widget's id and the key, not the row: a change rebuilds the rows, and a control
                                // still holding the old one failed ("set is not a function") and lost the change
                                const id = root.widget.id, key = row.modelData.key;
                                item.apply = v => Desktop.setSetting(id, key, v);
                            }
                        }
                    }
                }

                Chip {
                    icon: "refresh"
                    text: "Reset to defaults"
                    onClicked: Desktop.resetSettings(root.widget.id)
                }
            }
        }
    }

    // ── controls, one per kind of setting ──────────────────────────────────────
    Component {
        id: toggleControl
        Item {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            implicitHeight: 28
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                text: ctl.spec.label
            }
            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: ctl.val === true
                onToggled: ctl.apply(!checked)
            }
        }
    }
    Component {
        id: choiceControl
        Segmented {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            implicitHeight: 32
            options: ctl.spec.options
            current: String(ctl.val)
            onPicked: key => ctl.apply(key)
        }
    }
    Component {
        id: selectControl
        Flow {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 4
            Repeater {
                model: ctl.spec.options
                delegate: Chip {
                    required property var modelData
                    text: modelData.label
                    active: String(ctl.val) === modelData.key
                    onClicked: ctl.apply(modelData.key)
                }
            }
        }
    }
    Component {
        id: sliderControl
        Row {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: Metrics.s3
            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 52 - Metrics.s3
                value: ((ctl.val ?? ctl.spec.from) - ctl.spec.from) / (ctl.spec.to - ctl.spec.from)
                onMoved: v => {
                    const raw = ctl.spec.from + v * (ctl.spec.to - ctl.spec.from);
                    ctl.apply(Math.round(raw / ctl.spec.step) * ctl.spec.step);
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 52
                horizontalAlignment: Text.AlignRight
                role: "label"
                numeric: true
                tone: "muted"
                text: ctl.spec.kind === "int" ? Math.round(ctl.val ?? 0) : Number(ctl.val ?? 0).toFixed(ctl.spec.step < 0.1 ? 2 : 1)
            }
        }
    }
    Component {
        id: textControl
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 2
            Field {
                width: parent.width
                text: ctl.val ?? ""
                onCommitted: t => ctl.apply(t)
            }
            Label {
                visible: (ctl.spec.hint ?? "") !== ""
                role: "micro"
                tone: "faint"
                text: ctl.spec.hint ?? ""
            }
        }
    }
    Component {
        id: colourControl
        Flow {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 6
            Repeater {
                model: WidgetTypes.colourRoles
                delegate: Rectangle {
                    required property var modelData
                    width: 26
                    height: 26
                    radius: 13
                    color: Theme.pal(modelData)
                    border.width: ctl.val === modelData ? 2.5 : 1
                    border.color: ctl.val === modelData ? Theme.accent : Theme.hairline
                    scale: swatch.containsMouse ? 1.12 : 1
                    Glide on scale {
                        epsilon: 0.001
                    }
                    MouseArea {
                        id: swatch
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ctl.apply(modelData)
                    }
                }
            }
            // a colour of your own: #rrggbb
            Field {
                width: 92
                placeholder: "#hex"
                text: String(ctl.val ?? "").startsWith("#") ? ctl.val : ""
                onCommitted: t => {
                    if (/^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(t.trim()))
                        ctl.apply(t.trim());
                }
            }
        }
    }
    Component {
        id: fontControl
        // a family picked from the installed ones (Components/FontPicker)
        FontPicker {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            value: val ?? ""
            fallback: spec.placeholder ?? spec.default ?? "The interface font"
            onPicked: family => ctl.apply(family)
        }
    }
    Component {
        id: imageControl
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 4
            Row {
                width: parent.width
                spacing: Metrics.s2
                Field {
                    width: parent.width - pick.width - Metrics.s2
                    placeholder: "/path/to/image.png"
                    text: ctl.val ?? ""
                    onCommitted: t => ctl.apply(t)
                }
                Chip {
                    id: pick
                    icon: "folder"
                    text: "Choose"
                    onClicked: chooser.running = true
                }
            }
            Process {
                id: chooser
                command: ["zenity", "--file-selection", "--title=Choose an image", "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.svg"]
                stdout: StdioCollector {
                    onStreamFinished: if (text.trim() !== "")
                        ctl.apply(text.trim())
                }
            }
        }
    }
    Component {
        id: glyphControl
        Flow {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 4
            Repeater {
                model: ["heart", "star", "rocket", "music", "terminal", "world", "camera", "settings", "power", "home", "bolt", "moon", "sun", "coffee", "folder", "photo", "message", "bell"].filter(g => Icons.has(g))
                delegate: Rectangle {
                    required property var modelData
                    width: 30
                    height: 30
                    radius: 8
                    color: ctl.val === modelData ? Theme.accentSoft : glyphArea.containsMouse ? Theme.hover : "transparent"
                    border.width: ctl.val === modelData ? 1 : 0
                    border.color: Theme.accentLine
                    Icon {
                        anchors.centerIn: parent
                        name: modelData
                        size: 15
                        tone: ctl.val === modelData ? "accent" : "ink"
                    }
                    MouseArea {
                        id: glyphArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ctl.apply(modelData)
                    }
                }
            }
        }
    }

    // a text field that commits on Enter or when it loses focus
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder: ""
        signal committed(string text)
        signal edited(string text)
        implicitHeight: 32
        height: 32
        radius: 10
        color: Theme.well
        border.width: Metrics.hairline
        border.color: input.activeFocus ? Theme.accentLine : Theme.hairline
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Metrics.s3
            anchors.rightMargin: Metrics.s3
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            font.family: Type.ui
            font.pixelSize: Type.label
            clip: true
            onTextEdited: field.edited(text)
            onEditingFinished: field.committed(text)
            Label {
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                tone: "faint"
                text: field.placeholder
            }
        }
    }
    component NumberField: Rectangle {
        id: num
        property real value: 0
        signal committed(real value)
        height: 30
        radius: 8
        color: Theme.well
        border.width: Metrics.hairline
        border.color: numInput.activeFocus ? Theme.accentLine : Theme.hairline
        TextInput {
            id: numInput
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignRight
            color: Theme.ink
            font.family: Type.display
            font.pixelSize: Type.label
            font.features: Type.tabular
            text: String(num.value)
            validator: DoubleValidator {}
            onEditingFinished: {
                const v = parseFloat(text);
                if (!isNaN(v))
                    num.committed(v);
            }
        }
    }
}
