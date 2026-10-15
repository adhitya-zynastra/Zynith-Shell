import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// A form drawn from a settings schema ({ key, label, kind, default, options, from, to, step, when, hint }):
// one control per setting, shown only while its `when` holds. `valueOf(key)` gives the current value,
// `shows(spec)` whether a setting applies, and every change is reported as changed(key, value).
// Kinds: toggle choice select slider int text colour font image glyph list multi pick path number button.
Column {
    id: root

    property var schema: []
    property var valueOf: key => undefined
    property var shows: spec => true
    // a setting that is unset shows its default but marks itself as following it
    property var isSet: key => false
    signal changed(string key, var value)
    signal cleared(string key)
    // commitOnRelease: a slider being dragged reports previewed(key, value) and only its release is a change (one
    // write, one undo step); off, every movement is a change, as before
    property bool commitOnRelease: false
    signal previewed(string key, var value)
    // the drag is over: committed with `value`, or canceled (the setting is unchanged)
    signal previewEnded(string key, var value, bool canceled)
    // a hairline between settings (a list, as the native Settings draws its sections)
    property bool divided: false
    // fine-tuning rows (adv): "gate" waits for Settings' Advanced switch; "hide" leaves them out (a page that
    // shows them in an Advanced section of its own); "only" shows nothing else (that section)
    property string advanced: "gate"

    spacing: divided ? Metrics.s3 : Metrics.s4

    Repeater {
        model: root.schema
        delegate: Item {
            id: row
            required property var modelData
            // a fine-tuning row (adv) waits for Settings' "Advanced settings", as Ryoku's Hub gates its own
            readonly property bool adv: modelData.adv ?? false
            readonly property bool shown: root.shows(modelData) && (root.advanced === "only" ? adv : root.advanced === "hide" ? !adv : (!adv || Config.settingsAdvanced))
            readonly property var value: root.valueOf(modelData.key)
            width: root.width
            height: shown ? column.implicitHeight + (root.divided ? Metrics.s3 : 0) : 0
            visible: shown
            Rectangle {
                visible: root.divided && row.shown
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -root.spacing / 2 - 0.5
                width: parent.width
                height: Metrics.hairline
                color: Theme.hairline
            }
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
                            list: listControl,
                            pairs: pairsControl,
                            multi: multiControl,
                            pick: pickControl,
                            path: pathControl,
                            number: numberControl,
                            button: buttonControl
                        })[row.modelData.kind] ?? textControl
                    onLoaded: {
                        item.spec = Qt.binding(() => row.modelData);
                        item.val = Qt.binding(() => row.value);
                        item.apply = v => root.changed(row.modelData.key, v);
                        if (item.preview !== undefined) {
                            item.preview = v => root.previewed(row.modelData.key, v);
                            item.endPreview = (v, canceled) => root.previewEnded(row.modelData.key, v, canceled);
                            item.live = Qt.binding(() => !root.commitOnRelease);
                        }
                    }
                }
                Label {
                    visible: (row.modelData.hint ?? "") !== "" && row.modelData.kind !== "text" && row.modelData.kind !== "toggle"
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
            // the label and what it does on the left, the switch on the right
            implicitHeight: Math.max(28, toggleText.implicitHeight)
            Column {
                id: toggleText
                anchors.left: parent.left
                anchors.right: toggleSwitch.left
                anchors.rightMargin: Metrics.s4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Label {
                    width: parent.width
                    role: "label"
                    wrapMode: Text.WordWrap
                    text: ctl.spec.label ?? ""
                }
                Label {
                    visible: (ctl.spec.hint ?? "") !== ""
                    width: parent.width
                    role: "micro"
                    tone: "faint"
                    wrapMode: Text.WordWrap
                    text: ctl.spec.hint ?? ""
                }
            }
            Toggle {
                id: toggleSwitch
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
            property var preview: v => {}
            property var endPreview: (v, canceled) => {}
            // live: every movement is applied (the old way); else movements preview and the release applies
            property bool live: true
            property var shown: undefined
            property var lastApplied: undefined
            spacing: Metrics.s3
            function toValue(v: real): var {
                const raw = ctl.spec.from + v * (ctl.spec.to - ctl.spec.from);
                const stepped = Math.round(raw / ctl.spec.step) * ctl.spec.step;
                return ctl.spec.kind === "int" ? Math.round(stepped) : Number(stepped.toFixed(3));
            }
            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 56 - Metrics.s3
                value: ((Number(ctl.val ?? ctl.spec.from) || 0) - ctl.spec.from) / ((ctl.spec.to - ctl.spec.from) || 1)
                step: (ctl.spec.step || 1) / ((ctl.spec.to - ctl.spec.from) || 1)
                onMoved: v => {
                    const x = ctl.toValue(v);
                    ctl.shown = x;
                    if (ctl.live) {
                        if (x !== ctl.lastApplied) {
                            ctl.lastApplied = x;
                            ctl.apply(x);
                        }
                    } else {
                        ctl.preview(x);
                    }
                }
                onCommitted: v => {
                    const x = ctl.toValue(v);
                    ctl.shown = undefined;
                    if (!ctl.live || x !== ctl.lastApplied) {
                        ctl.lastApplied = x;
                        ctl.apply(x);
                    }
                    if (!ctl.live)
                        ctl.endPreview(x, false);
                }
                onCanceled: {
                    ctl.shown = undefined;
                    if (!ctl.live)
                        ctl.endPreview(undefined, true);
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                horizontalAlignment: Text.AlignRight
                role: "label"
                numeric: true
                tone: "muted"
                readonly property var v: ctl.shown !== undefined ? ctl.shown : ctl.val
                text: v === "auto" ? "auto" : ctl.spec.kind === "int" ? Math.round(Number(v ?? 0)) : Number(v ?? 0).toFixed(ctl.spec.step < 0.1 ? 2 : 1)
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
                model: ctl.spec.roles ?? ["on_surface", "on_surface_variant", "primary", "secondary", "tertiary", "surface", "surface_variant", "outline", "error"]
                delegate: Rectangle {
                    required property var modelData
                    width: 26
                    height: 26
                    radius: height / 2
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
                        radius: Metrics.radiusControl
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

    // a table of names to values ({ "Bass boost" = "music" }): each pair a chip, a new one typed as
    // "name = value"
    Component {
        id: pairsControl
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            readonly property var table: ctl.val && typeof ctl.val === "object" ? Object.assign({}, ctl.val) : ({})
            spacing: 4
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: Object.keys(ctl.table)
                    delegate: Chip {
                        required property string modelData
                        text: modelData + " → " + ctl.table[modelData] + "  ×"
                        onClicked: {
                            const t = Object.assign({}, ctl.table);
                            delete t[modelData];
                            ctl.apply(t);
                        }
                    }
                }
            }
            Field {
                width: parent.width
                placeholder: ctl.spec.placeholder ?? "name = value, then Enter"
                onCommitted: t => {
                    const at = t.indexOf("=");
                    if (at > 0 && t.slice(at + 1).trim() !== "") {
                        const table = Object.assign({}, ctl.table);
                        table[t.slice(0, at).trim()] = t.slice(at + 1).trim();
                        ctl.apply(table);
                        text = "";
                    }
                }
            }
        }
    }

    // several of the options at once: each chip toggles its own
    Component {
        id: multiControl
        Flow {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            readonly property var chosen: ctl.val && typeof ctl.val !== "string" && ctl.val.length !== undefined ? Array.from(ctl.val) : []
            spacing: 4
            Repeater {
                model: ctl.spec.options ?? []
                delegate: Chip {
                    required property var modelData
                    readonly property bool on: ctl.chosen.includes(modelData.key)
                    text: modelData.label
                    active: on
                    onClicked: ctl.apply(on ? ctl.chosen.filter(k => k !== modelData.key) : ctl.chosen.concat([modelData.key]))
                }
            }
        }
    }
    // one of many (fonts, palettes, outputs): what is chosen, and a search over the rest
    Component {
        id: pickControl
        Column {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            property string typed: ""
            readonly property var current: (ctl.spec.options ?? []).find(o => o.key === String(ctl.val))
            spacing: 4
            Field {
                width: parent.width
                placeholder: (ctl.current?.label ?? String(ctl.val ?? "")) || "Search…"
                onEdited: t => ctl.typed = t
            }
            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: (ctl.spec.options ?? []).filter(o => ctl.typed === "" ? o.key === String(ctl.val) : o.label.toLowerCase().includes(ctl.typed.toLowerCase())).slice(0, 24)
                    delegate: Chip {
                        required property var modelData
                        text: modelData.label
                        active: String(ctl.val) === modelData.key
                        onClicked: ctl.apply(modelData.key)
                    }
                }
            }
        }
    }
    // a file or a folder: typed, or chosen in a dialog (spec.browse: file · folder)
    Component {
        id: pathControl
        Row {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            spacing: Metrics.s2
            Field {
                width: parent.width - browse.width - Metrics.s2
                placeholder: ctl.spec.placeholder || (ctl.spec.browse === "folder" ? "/path/to/folder" : "/path/to/file")
                text: ctl.val ?? ""
                onCommitted: t => ctl.apply(t)
            }
            Chip {
                id: browse
                icon: "folder"
                text: "Choose"
                onClicked: chooser.running = true
            }
            Process {
                id: chooser
                command: ["zenity", "--file-selection", "--title=Choose"].concat(ctl.spec.browse === "folder" ? ["--directory"] : [])
                stdout: StdioCollector {
                    onStreamFinished: if (text.trim() !== "")
                        ctl.apply(text.trim())
                }
            }
        }
    }
    // a number that may be left unset (empty)
    Component {
        id: numberControl
        Field {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            width: 160
            placeholder: ctl.spec.placeholder || "not set"
            text: ctl.val === null || ctl.val === undefined ? "" : String(ctl.val)
            onCommitted: t => ctl.apply(t.trim() === "" ? null : Number(t))
        }
    }
    // an action rather than a value (spec.action: its label)
    Component {
        id: buttonControl
        Item {
            id: ctl
            property var spec: ({})
            property var val
            property var apply: v => {}
            implicitHeight: 30
            Chip {
                icon: ctl.spec.icon ?? "external-link"
                text: ctl.spec.action ?? "Open"
                onClicked: ctl.apply(true)
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
        radius: Metrics.radiusControl
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
