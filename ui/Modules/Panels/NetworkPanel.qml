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
    // [panels] list_width: one column, the connection first
    readonly property int preferredWidth: Config.panels?.list_width ?? 440

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
        caption: Network.wired ? "Wired connection" : Network.wifiEnabled ? (Network.connected ? "Connected" : "Not connected") : "Off"
        canGoBack: root.canGoBack
        onBack: root.back()

        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: Network.wifiEnabled
            onToggled: Network.setWifiEnabled(!Network.wifiEnabled)
        }
    }

    // the connection: what you are on, how well, and what keeps it private
    Instrument {
        width: root.inner
        icon: Network.glyph
        iconOn: Network.connected
        caption: Network.connected ? "CONNECTED TO" : "WI‑FI"
        title: Network.connected ? Network.name : Network.wifiEnabled ? "Not connected" : "Wi‑Fi is off"
        detail: Network.wired ? "Ethernet" : !Network.wifiEnabled ? "Click to turn Wi‑Fi on" : !Network.connected ? "Choose a network below" : [root.current ? (root.current.secured ? "Secured" : "Open network") : "", Network.vpn !== "" ? "VPN · " + Network.vpn : ""].filter(t => t !== "").join("  ·  ")
        value: Network.connected && !Network.wired ? String(Math.round(Network.strength * 100)) : ""
        unit: value !== "" ? "%" : ""
        onIconClicked: Network.setWifiEnabled(!Network.wifiEnabled)
    }

    // the one connected, and the rest: the ones you have used first (they join without a password), then by signal
    readonly property var current: Network.networks.find(n => n.connected) ?? null
    readonly property var others: Network.networks.filter(n => !n.connected)
    readonly property var saved: others.filter(n => n.known)
    readonly property var nearby: others.filter(n => !n.known)

    Repeater {
        model: Network.wifiEnabled ? [
            { title: "SAVED", list: root.saved },
            { title: "NEARBY", list: root.nearby }
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
                model: ScriptModel {
                    values: group.modelData.list.slice(0, 6)
                    objectProp: "ssid"
                }
                delegate: ListRow {
                    required property var modelData
                    width: group.width
                    icon: modelData.strength > 0.66 ? "wifi" : modelData.strength > 0.33 ? "wifi-2" : "wifi-1"
                    title: modelData.ssid
                    detail: (modelData.secured ? "Secured" : "Open") + "  ·  " + Math.round(modelData.strength * 100) + "%"
                    trailing: modelData.busy ? "Joining…" : modelData.secured && !modelData.known ? "Password" : ""
                    busy: modelData.busy
                    onClicked: Network.connectTo(modelData.ssid)
                }
            }
        }
    }

    Label {
        visible: Network.wifiEnabled && root.others.length === 0
        width: root.inner
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: Network.networks.length === 0 ? "Looking for networks…" : "No other networks nearby"
    }
    ListRow {
        visible: Network.connected && !Network.wired
        width: root.inner
        icon: "x"
        title: "Disconnect"
        detail: "Leave " + Network.name
        onClicked: Network.disconnect()
    }
}
