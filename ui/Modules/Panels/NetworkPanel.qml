import QtQuick
import Quickshell
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
    property bool active: true

    padding: Metrics.s6
    spacing: Metrics.s4
    readonly property real inner: width - padding * 2

    // the list (and NetworkManager's per-network signals) exists only while this panel is on screen
    property bool holding: false
    function syncList(): void {
        if (active && !holding) {
            Network.retain();
            holding = true;
        } else if (!active && holding) {
            Network.release();
            holding = false;
        }
    }
    onActiveChanged: syncList()
    Component.onCompleted: syncList()
    Component.onDestruction: if (holding)
        Network.release()

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
            model: ScriptModel {
                values: Network.networks.slice(0, 9)
                objectProp: "ssid"
            }

            delegate: ListRow {
                required property var modelData
                width: root.inner
                icon: modelData.strength > 0.66 ? "wifi" : modelData.strength > 0.33 ? "wifi-2" : "wifi-1"
                title: modelData.ssid
                detail: !modelData.secured ? "Open" : modelData.known ? "Saved" : "Secured"
                trailing: modelData.connected ? "Connected" : modelData.busy ? "…" : ""
                active: modelData.connected
                busy: modelData.busy
                onClicked: modelData.connected ? Network.disconnect() : Network.connectTo(modelData.ssid)
            }
        }

        Label {
            visible: Network.networks.length === 0
            width: root.inner
            role: "body"
            tone: "faint"
            text: "Looking for networks…"
        }
    }
}
