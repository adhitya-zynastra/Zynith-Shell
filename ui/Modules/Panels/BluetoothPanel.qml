import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Paired devices first, then what discovery finds. Pairing prompts are answered by the native agent.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back
    property bool active: true
    onActiveChanged: if (!active && Bluetooth.adapter?.discovering)
        Bluetooth.adapter.discovering = false

    padding: Metrics.s6
    spacing: Metrics.s4
    readonly property real inner: width - padding * 2
    // [panels] list_width: one column, what is connected first
    readonly property int preferredWidth: Config.panels?.list_width ?? 440

    readonly property var all: (Bluetooth.adapter?.devices.values ?? []).filter(d => d.paired || d.name)
    readonly property var connectedDevices: all.filter(d => d.connected)
    readonly property var pairedDevices: all.filter(d => d.paired && !d.connected).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var found: all.filter(d => !d.paired && !d.connected && d.name)
    readonly property var lead: connectedDevices[0] ?? null
    // what kind of thing it is, from BlueZ's own icon name
    function glyph(d: var): string {
        const i = d?.icon ?? "";
        return /mouse/.test(i) ? "mouse" : /keyboard/.test(i) ? "keyboard" : /audio|headset|headphone/.test(i) ? "headphones" : /phone/.test(i) ? "device-mobile" : /watch/.test(i) ? "device-watch" : /computer|laptop/.test(i) ? "device-laptop" : "bluetooth";
    }
    function battery(d: var): string {
        return d?.batteryAvailable ? Math.round(d.battery * 100) + "%" : "";
    }

    PanelHeader {
        width: root.inner
        title: "Bluetooth"
        caption: !Bluetooth.available ? "No adapter" : !Bluetooth.enabled ? "Off" : root.connectedDevices.length === 0 ? "Nothing connected" : root.connectedDevices.length + " connected"
        canGoBack: root.canGoBack
        onBack: root.back()

        IconButton {
            visible: Bluetooth.enabled
            anchors.verticalCenter: parent.verticalCenter
            icon: "scan"
            tone: "muted"
            active: Bluetooth.adapter?.discovering ?? false
            onClicked: Bluetooth.adapter.discovering = !Bluetooth.adapter.discovering
        }
        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: Bluetooth.enabled
            onToggled: Bluetooth.setEnabled(!Bluetooth.enabled)
        }
    }

    // discovery stops when the panel goes away
    Component.onDestruction: if (Bluetooth.adapter?.discovering)
        Bluetooth.adapter.discovering = false

    // what is connected now: the device and its battery, or the state of the radio
    Instrument {
        width: root.inner
        icon: !Bluetooth.enabled ? "bluetooth-off" : root.lead ? root.glyph(root.lead) : "bluetooth"
        iconOn: Bluetooth.enabled && root.lead !== null
        caption: root.lead ? "CONNECTED" : "BLUETOOTH"
        title: !Bluetooth.available ? "No adapter" : !Bluetooth.enabled ? "Bluetooth is off" : root.lead ? root.lead.name : "Nothing connected"
        detail: !Bluetooth.enabled ? "Click to turn Bluetooth on" : root.connectedDevices.length > 1 ? "and " + (root.connectedDevices.length - 1) + " more" : root.lead ? (root.lead.batteryAvailable ? "Battery" : "Connected") : root.pairedDevices.length > 0 ? "Choose a paired device below" : "Scan to find a device"
        value: root.lead && root.lead.batteryAvailable ? String(Math.round(root.lead.battery * 100)) : ""
        unit: value !== "" ? "%" : ""
        onIconClicked: Bluetooth.setEnabled(!Bluetooth.enabled)
    }

    Repeater {
        model: Bluetooth.enabled ? [
            { title: "CONNECTED", list: root.connectedDevices.slice(1), action: "Disconnect" },
            { title: "PAIRED", list: root.pairedDevices, action: "Connect" },
            { title: "FOUND", list: root.found, action: "Pair" }
        ].filter(g => g.list.length > 0) : []
        delegate: Column {
            id: group
            required property var modelData
            width: root.inner
            spacing: Metrics.s1
            SectionHead {
                width: parent.width
                title: group.modelData.title
                Label {
                    role: "data"
                    tone: "faint"
                    text: String(group.modelData.list.length)
                }
            }
            Repeater {
                model: group.modelData.list.slice(0, 6)
                delegate: ListRow {
                    required property var modelData
                    width: group.width
                    icon: root.glyph(modelData)
                    title: modelData.name
                    detail: [root.battery(modelData), modelData.pairing ? "Pairing…" : ""].filter(t => t !== "").join("  ·  ")
                    trailing: group.modelData.action
                    active: modelData.connected
                    busy: modelData.pairing
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.paired ? modelData.connect() : modelData.pair()
                }
            }
        }
    }
    // the lead device's own way out
    ListRow {
        visible: Bluetooth.enabled && root.lead !== null
        width: root.inner
        icon: "x"
        title: "Disconnect"
        detail: root.lead ? root.lead.name : ""
        onClicked: root.lead.disconnect()
    }
}
