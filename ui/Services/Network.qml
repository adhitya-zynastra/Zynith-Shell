pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// Connection state from NetworkManager through the native NetworkState, which follows only NetworkManager
// itself and the access point in use. Passwords never come here: NetworkManager asks the native secret agent.
Singleton {
    id: root

    readonly property bool available: NetworkState.available
    readonly property bool wifiEnabled: NetworkState.wifiEnabled
    readonly property bool hasWifi: NetworkState.hasWifi
    readonly property bool connected: NetworkState.connected
    readonly property bool wired: NetworkState.kind === "ethernet"
    readonly property string name: wired ? "Wired" : NetworkState.name
    // the active VPN's name ("" when none)
    readonly property string vpn: NetworkState.vpnName ?? ""
    readonly property real strength: NetworkState.strength

    readonly property string glyph: wired ? "device-desktop" : !wifiEnabled || !connected ? "wifi-off" : strength > 0.66 ? "wifi" : strength > 0.33 ? "wifi-2" : "wifi-1"

    // nearby networks exist only while something holds them (the Wi-Fi panel)
    readonly property var networks: NetworkState.networks
    function retain(): void {
        NetworkState.retain();
    }
    function release(): void {
        NetworkState.release();
    }

    function setWifiEnabled(on: bool): void {
        NetworkState.setWifiEnabled(on);
    }
    function connectTo(ssid: string): void {
        NetworkState.connectTo(ssid);
    }
    function disconnect(): void {
        NetworkState.disconnectActive();
    }
}
