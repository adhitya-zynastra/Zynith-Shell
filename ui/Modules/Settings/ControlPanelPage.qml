import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Which modules the Control Panel shows, and in what order.
Column {
    id: root
    spacing: Metrics.s5

    readonly property var all: [
        { id: "header", label: "Who and when", detail: "Picture, name, date, the time" },
        { id: "levels", label: "Levels", detail: "Volume, microphone, brightness" },
        { id: "connectivity", label: "Connectivity", detail: "Wi‑Fi and Bluetooth" },
        { id: "toggles", label: "Switches", detail: "Do not disturb, night light, stay awake, microphone" },
        { id: "media", label: "Now playing" },
        { id: "power", label: "Power", detail: "Power profile and Experience" },
        { id: "system", label: "System", detail: "CPU and memory" },
        { id: "notifications", label: "Latest notifications" },
        { id: "clipboard", label: "Latest clipboard entries" }
    ]
    readonly property var enabled: Config.controlPanel?.modules ?? []
    // enabled modules in their order, then the rest
    readonly property var ordered: enabled.map(id => all.find(m => m.id === id)).filter(m => m).concat(all.filter(m => !enabled.includes(m.id)))

    function save(list: var): void {
        Config.write("panels", "control_panel.modules", list);
    }
    function toggle(id: string): void {
        save(enabled.includes(id) ? enabled.filter(m => m !== id) : enabled.concat([id]));
    }
    function move(id: string, by: int): void {
        const list = enabled.slice();
        const i = list.indexOf(id), j = i + by;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        list.splice(i, 1);
        list.splice(j, 0, id);
        save(list);
    }

    PanelHeader {
        width: parent.width
        title: "Control Panel"
        caption: "Quick interaction; configuration lives here in Settings"
    }

    Card {
        width: parent.width
        caption: "Modules"

        Repeater {
            model: root.ordered
            delegate: Item {
                required property var modelData
                readonly property bool on: root.enabled.includes(modelData.id)
                width: parent.width
                height: 48

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Label {
                        role: "body"
                        tone: parent.parent.on ? "ink" : "faint"
                        text: parent.parent.modelData.label
                    }
                    Label {
                        visible: !!parent.parent.modelData.detail
                        role: "label"
                        tone: "faint"
                        text: parent.parent.modelData.detail ?? ""
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    IconButton {
                        visible: parent.parent.on
                        icon: "chevron-down"
                        rotation: 180
                        tone: "muted"
                        onClicked: root.move(parent.parent.modelData.id, -1)
                    }
                    IconButton {
                        visible: parent.parent.on
                        icon: "chevron-down"
                        tone: "muted"
                        onClicked: root.move(parent.parent.modelData.id, 1)
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: parent.parent.on
                        onToggled: root.toggle(parent.parent.modelData.id)
                    }
                }
            }
        }
    }

    Card {
        width: parent.width
        caption: "Size"

        SettingSlider {
            title: "Width"
            domain: "panels"
            key: "control_panel.width"
            from: 360
            to: 560
            step: 10
            format: v => Math.round(v) + " px"
        }
    }
}
