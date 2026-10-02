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

    readonly property var devices: (Bluetooth.adapter?.devices.values ?? []).filter(d => d.paired || d.name).slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

    PanelHeader {
        width: root.inner
        title: "Bluetooth"
        caption: Bluetooth.available ? Bluetooth.summary : "No adapter"
        canGoBack: root.canGoBack
        onBack: root.back()

        IconButton {
            visible: Bluetooth.enabled
            anchors.verticalCenter: parent.verticalCenter
            icon: "activity"
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

    Column {
        width: root.inner
        spacing: Metrics.s1
        visible: Bluetooth.enabled

        Repeater {
            model: root.devices.slice(0, 10)

            delegate: ListRow {
                required property var modelData
                width: root.inner
                icon: modelData.connected ? "bluetooth-connected" : "bluetooth"
                title: modelData.name
                detail: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : modelData.paired ? "Paired" : ""
                trailing: modelData.connected ? "Connected" : modelData.pairing ? "Pairing" : ""
                active: modelData.connected
                busy: modelData.pairing
                onClicked: modelData.connected ? modelData.disconnect() : modelData.paired ? modelData.connect() : modelData.pair()
            }
        }
    }
}
