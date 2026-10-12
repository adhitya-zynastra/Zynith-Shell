import QtQuick
import qs.Common
import qs.Services

// What one gesture of a bar icon does, picked rather than typed: the panels (PanelCatalog: on their own, or as
// pages of the Control Panel), the commands Actions knows (PanelCatalog.commands), nothing, or a command of your own.
// Shows the current choice by name; a click unfolds the choices in place (not a popup). `panelsOnly` offers
// only panels (a resting pointer opens something; it does not change the volume).
Column {
    id: root

    property var value          // this widget's own action; undefined follows the default
    property string fallback: "" // the default, shown when value is unset
    property bool panelsOnly: false
    property bool enabled: true
    signal picked(var action)    // undefined: back to the default

    property bool open: false
    readonly property string current: value ?? fallback
    spacing: Metrics.s2

    readonly property var groups: {
        const out = [];
        const panels = PanelCatalog.panelActions();
        for (const g of ["Panels", "In the Control Panel"])
            out.push({ title: g, items: panels.filter(p => p.group === g) });
        if (!panelsOnly) {
            const names = [];
            for (const c of PanelCatalog.commands)
                if (!names.includes(c.group))
                    names.push(c.group);
            for (const g of names)
                out.push({ title: g, items: PanelCatalog.commands.filter(c => c.group === g) });
        }
        return out;
    }

    // the current choice; a click unfolds the rest
    Rectangle {
        width: root.width
        height: 32
        radius: 10
        color: Theme.well
        opacity: root.enabled ? 1 : 0.4
        border.width: Metrics.hairline
        border.color: root.open ? Theme.accentLine : Theme.hairline
        Label {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            role: "label"
            tone: root.value === undefined ? "muted" : "ink"
            elide: Text.ElideRight
            text: PanelCatalog.describe(root.current) + (root.value === undefined && root.fallback !== "" ? "  ·  default" : "")
        }
        Icon {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 14
            tone: "faint"
            rotation: root.open ? 180 : 0
            Behavior on rotation {
                Anim {
                    role: "effects"
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    // the choices, grouped
    Column {
        visible: root.open
        width: root.width
        spacing: Metrics.s3
        Flow {
            width: parent.width
            spacing: 4
            Chip {
                text: "Nothing"
                active: root.current === "none"
                onClicked: {
                    root.picked("none");
                    root.open = false;
                }
            }
            Chip {
                visible: root.fallback !== ""
                text: "Default (" + PanelCatalog.describe(root.fallback) + ")"
                active: root.value === undefined
                onClicked: {
                    root.picked(undefined);
                    root.open = false;
                }
            }
        }
        Repeater {
            model: root.groups
            delegate: Column {
                id: group
                required property var modelData
                width: root.width
                spacing: 4
                visible: modelData.items.length > 0
                Label {
                    role: "micro"
                    tone: "faint"
                    caps: true
                    text: group.modelData.title
                }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: group.modelData.items
                        delegate: Chip {
                            required property var modelData
                            text: modelData.label
                            icon: modelData.icon ?? ""
                            active: root.current === modelData.action
                            onClicked: {
                                root.picked(modelData.action);
                                root.open = false;
                            }
                        }
                    }
                }
            }
        }
        // a command of your own (exec …, or any native `noctalia msg` verb)
        Column {
            visible: !root.panelsOnly
            width: root.width
            spacing: 4
            Label {
                role: "micro"
                tone: "faint"
                caps: true
                text: "Your own command"
            }
            Rectangle {
                width: root.width
                height: 32
                radius: 10
                color: Theme.well
                border.width: Metrics.hairline
                border.color: custom.activeFocus ? Theme.accentLine : Theme.hairline
                TextInput {
                    id: custom
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.s3
                    anchors.rightMargin: Metrics.s3
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    font.family: Type.mono
                    font.pixelSize: Type.label
                    clip: true
                    text: root.current
                    onAccepted: {
                        const t = text.trim();
                        root.picked(t === "" ? undefined : t);
                        root.open = false;
                    }
                    Label {
                        visible: custom.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "faint"
                        font.family: Type.mono
                        text: "exec notify-send hi   ·   Enter to use"
                    }
                }
            }
        }
    }
}
