import QtQuick
import Quickshell.Networking as QsNet
import qs.Common
import qs.Components
import qs.Services

// Wi‑Fi networks. Known networks connect directly; for a new secured network NetworkManager asks the
// native secret agent for the password — it never passes through this UI.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool canGoBack: false
    signal back

    padding: Metrics.s6
    spacing: Metrics.s4
    readonly property real inner: width - padding * 2

    readonly property var networks: (Network.wifi?.networks.values ?? []).slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))

    // scan only while this panel is open
    Component.onCompleted: if (Network.wifi)
        Network.wifi.scannerEnabled = true
    Component.onDestruction: if (Network.wifi)
        Network.wifi.scannerEnabled = false

    PanelHeader {
        width: root.inner
        title: "Wi‑Fi"
        caption: Network.connected ? Network.name : Network.wifiEnabled ? "Not connected" : "Off"
        canGoBack: root.canGoBack
        onBack: root.back()

        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: Network.wifiEnabled
            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
        }
    }

    Column {
        width: root.inner
        spacing: Metrics.s1
        visible: Network.wifiEnabled

        Repeater {
            model: root.networks.slice(0, 9)

            delegate: ListRow {
                required property var modelData
                width: root.inner
                icon: modelData.signalStrength > 0.66 ? "wifi" : modelData.signalStrength > 0.33 ? "wifi-2" : "wifi-1"
                title: modelData.name
                detail: modelData.security === QsNet.WifiSecurityType.Open ? "Open" : modelData.known ? "Saved" : "Secured"
                trailing: modelData.connected ? "Connected" : modelData.stateChanging ? "…" : ""
                active: modelData.connected
                busy: modelData.stateChanging
                onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
            }
        }

        Label {
            visible: root.networks.length === 0
            width: root.inner
            role: "body"
            tone: "faint"
            text: "Looking for networks…"
        }
    }
}
