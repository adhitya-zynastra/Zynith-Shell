import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Desktop widgets: where they are edited (on the desktop itself, Mod+Alt+W), and the ones placed — each
// shown or hidden, or removed — from widgets.toml. Moving, sizing and their settings stay in the editor,
// where they can be seen.
Column {
    id: root
    spacing: Metrics.s5

    readonly property var placed: Array.from(Config.widgets)
    function update(i: int, changes: var): void {
        const list = placed.map(w => Object.assign({}, w));
        Object.assign(list[i], changes);
        Config.setWidgets(list);
    }
    function remove(i: int): void {
        Config.setWidgets(placed.filter((w, j) => j !== i));
    }

    PanelHeader {
        width: parent.width
        title: "Desktop widgets"
        caption: "Placed, moved and set up on the desktop itself"
    }

    Card {
        width: parent.width
        Label {
            width: parent.width
            role: "body"
            wrapMode: Text.WordWrap
            text: "The editor opens over the wallpaper: drag to move, handles to size and turn, a click for each widget's settings, the + for new ones. Mod+Alt+W opens it too."
        }
        Chip {
            icon: "layout-dashboard"
            text: "Edit the desktop"
            onClicked: Quickshell.execDetached([Paths.uiScript, "cmd", "desktop-edit"])
        }
    }

    Card {
        width: parent.width
        caption: root.placed.length + (root.placed.length === 1 ? " widget" : " widgets")

        Repeater {
            model: root.placed
            delegate: Item {
                id: placedRow
                required property var modelData
                required property int index
                readonly property var kind: WidgetTypes.find(modelData.type ?? "")
                width: parent.width
                height: 44

                Icon {
                    id: kindIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: placedRow.kind?.icon ?? "layout-dashboard"
                    tone: placedRow.modelData.hidden ? "faint" : "ink"
                }
                Column {
                    anchors.left: kindIcon.right
                    anchors.leftMargin: Metrics.s3
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        role: "body"
                        tone: placedRow.modelData.hidden ? "faint" : "ink"
                        text: placedRow.kind?.label ?? placedRow.modelData.type
                    }
                    Label {
                        role: "caption"
                        tone: "faint"
                        text: (placedRow.modelData.output || "every screen") + "  ·  " + Math.round(placedRow.modelData.width ?? 0) + "×" + Math.round(placedRow.modelData.height ?? 0)
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "muted"
                        text: "Shown"
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: placedRow.modelData.hidden !== true
                        onToggled: root.update(placedRow.index, { hidden: placedRow.modelData.hidden !== true })
                    }
                    IconButton {
                        icon: "trash"
                        tone: "muted"
                        onClicked: root.remove(placedRow.index)
                    }
                }
            }
        }
        Label {
            visible: root.placed.length === 0
            role: "label"
            tone: "faint"
            text: "Nothing on the desktop yet"
        }
    }

    Card {
        width: parent.width
        caption: "What can be placed"
        Flow {
            width: parent.width
            spacing: Metrics.s2
            Repeater {
                model: WidgetTypes.types
                delegate: Chip {
                    required property var modelData
                    icon: modelData.icon
                    text: modelData.label
                    onClicked: Quickshell.execDetached([Paths.uiScript, "cmd", "desktop-edit"])
                }
            }
        }
    }
}
