import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// A form drawn from a settings schema ({ key, label, kind, default, options, from, to, step, when, hint }):
// one control per setting, shown only while its `when` holds. `valueOf(key)` gives the current value,
// `shows(spec)` whether a setting applies, and every change is reported as changed(key, value).
// Kinds: toggle choice select slider int text colour font image glyph list.
Column {
    id: root

    property var schema: []
    property var valueOf: key => undefined
    property var shows: spec => true
    // a setting that is unset shows its default but marks itself as following it
    property var isSet: key => false
    signal changed(string key, var value)
    signal cleared(string key)

    spacing: Metrics.s4

    Repeater {
        model: root.schema
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool shown: root.shows(modelData)
            readonly property var value: root.valueOf(modelData.key)
            width: root.width
            height: shown ? column.implicitHeight : 0
            visible: shown
            opacity: shown ? 1 : 0
            Behavior on opacity {
                Anim {
                    role: "effects"
                }
            }

            Column {
                id: column
                width: parent.width
                spacing: Metrics.s1

                Item {
                    visible: row.modelData.kind !== "toggle"
                    width: parent.width
                    height: 18
                    Label {
                        role: "label"
                        tone: "muted"
                        text: row.modelData.label
                    }
                    // back to the default
                    Label {
                        visible: root.isSet(row.modelData.key)
                        anchors.right: parent.right
                        role: "micro"
                        tone: resetArea.containsMouse ? "accent" : "faint"
                        text: "default"
                        MouseArea {
                            id: resetArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cleared(row.modelData.key)
                        }
                    }
                }
                Loader {
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
                            glyph: glyphControl,
                            list: listControl
                        })[row.modelData.kind] ?? textControl
                    onLoaded: {
                        item.spec = Qt.binding(() => row.modelData);
                        item.val = Qt.binding(() => row.value);
                        item.apply = v => root.changed(row.modelData.key, v);
                    }
                }
                Label {
                    visible: (row.modelData.hint ?? "") !== "" && row.modelData.kind !== "text"
                    width: parent.width
                    role: "micro"
                    tone: "faint"
                    wrapMode: Text.WordWrap
                    text: row.modelData.hint ?? ""
                }
            }
        }
    }

    // ── controls ──────────────────────────────────────────────────────────────
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
                text: ctl.spec.label ?? ""
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
            options: ctl.spec.options ?? []
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
                model: ctl.spec.options ?? []
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
                width: parent.width - 56 - Metrics.s3
                value: ((Number(ctl.val ?? ctl.spec.from) || 0) - ctl.spec.from) / ((ctl.spec.to - ctl.spec.from) || 1)
                onMoved: v => {
                    const raw = ctl.spec.from + v * (ctl.spec.to - ctl.spec.from);
                    const stepped = Math.round(raw / ctl.spec.step) * ctl.spec.step;
                    ctl.apply(ctl.spec.kind === "int" ? Math.round(stepped) : Number(stepped.toFixed(3)));
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                horizontalAlignment: Text.AlignRight
                role: "label"
                numeric: true
                tone: "muted"
                text: ctl.val === "auto" ? "auto" : ctl.spec.kind === "int" ? Math.round(Number(ctl.val ?? 0)) : Number(ctl.val ?? 0).toFixed(ctl.spec.step < 0.1 ? 2 : 1)
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
                placeholder: ctl.spec.default ?? ""
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
                model: ["on_surface", "on_surface_variant", "primary", "secondary", "tertiary", "surface", "surface_variant", "outline", "error"]
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
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            property string typed: ""
            spacing: 4
            Field {
                width: parent.width
                placeholder: "The interface font"
                text: ctl.val ?? ""
                onEdited: t => ctl.typed = t
                onCommitted: t => ctl.apply(t)
            }
            Flow {
                width: parent.width
                spacing: 4
                visible: ctl.typed.length >= 2
                Repeater {
                    model: ctl.typed.length >= 2 ? Qt.fontFamilies().filter(f => f.toLowerCase().includes(ctl.typed.toLowerCase())).slice(0, 8) : []
                    delegate: Chip {
                        required property var modelData
                        text: modelData
                        onClicked: {
                            ctl.apply(modelData);
                            ctl.typed = "";
                        }
                    }
                }
            }
        }
    }
    Component {
        id: imageControl
        Row {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
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
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: 4
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: ["search", "apps", "adjustments-horizontal", "settings", "power", "photo", "clipboard", "screenshot", "camera", "heart", "star", "rocket", "music", "terminal", "world", "home", "bolt", "moon", "sun", "coffee", "keyboard", "bell", "cpu", "layout-grid"].filter(g => Icons.has(g))
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
            Field {
                width: parent.width
                placeholder: "any Tabler icon name"
                text: ctl.val ?? ""
                onCommitted: t => ctl.apply(t.trim())
            }
        }
    }
    // a list of words (app ids, tray item names): one per chip, × removes, the field adds
    Component {
        id: listControl
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            // a TOML list arrives as a Qt sequence, not a JS array
            readonly property var items: ctl.val && typeof ctl.val !== "string" && ctl.val.length !== undefined ? Array.from(ctl.val) : []
            spacing: 4
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: ctl.items
                    delegate: Chip {
                        required property var modelData
                        required property int index
                        text: modelData + "  ×"
                        onClicked: ctl.apply(ctl.items.filter((x, i) => i !== index))
                    }
                }
            }
            Field {
                width: parent.width
                placeholder: "add, then Enter"
                onCommitted: t => {
                    if (t.trim() !== "") {
                        ctl.apply(ctl.items.concat([t.trim()]));
                        text = "";
                    }
                }
            }
        }
    }

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
}
