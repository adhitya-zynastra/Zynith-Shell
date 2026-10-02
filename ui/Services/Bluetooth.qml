pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as QsBluetooth

// Adapter and connected devices from BlueZ. Pairing prompts stay with the native agent.
Singleton {
    id: root

    readonly property var adapter: QsBluetooth.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var connected: (adapter?.devices.values ?? []).filter(d => d.connected)
    readonly property string summary: !enabled ? "Off" : connected.length === 0 ? "On" : connected.length === 1 ? connected[0].name : connected.length + " devices"

    function setEnabled(on: bool): void {
        if (adapter)
            adapter.enabled = on;
    }
}
