pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Connection state from NetworkManager. Read-only for now: the secret agent stays native (zynith-secure).
Singleton {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var network: wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool connected: wired !== null || network !== null
    readonly property string name: wired ? "Wired" : network ? network.name : ""
    readonly property real strength: network ? network.signalStrength : 0

    readonly property string glyph: wired ? "device-desktop" : !wifiEnabled || !network ? "wifi-off" : strength > 0.66 ? "wifi" : strength > 0.33 ? "wifi-2" : "wifi-1"

    function setWifiEnabled(on: bool): void {
        Networking.wifiEnabled = on;
    }
}
