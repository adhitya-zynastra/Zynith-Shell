import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The connection: its strength or wired, its name if asked.
BarItem {
    id: root
    active: PanelRouter.isOpen("network", screen?.name ?? "")
    // a VPN (vpn_status, as the native widget): replace (its shield instead of the network glyph) | both |
    // hidden; show_vpn_label adds its name
    readonly property string vpnMode: opt("vpn_status") ?? "replace"
    readonly property bool vpnOn: Network.vpn !== "" && vpnMode !== "hidden"
    BarGlyph {
        item: root
        visible: root.vpnOn
        name: "shield-check"
        colour: root.iconInk
    }
    BarText {
        item: root
        visible: root.vpnOn && root.opt("show_vpn_label") === true && !root.vertical
        muted: true
        text: Network.vpn
    }
    BarGlyph {
        item: root
        visible: !(root.vpnOn && root.vpnMode === "replace")
        name: Network.glyph
        colour: Network.connected ? root.iconInk : Theme.alpha(root.iconInk, 0.45)
    }
    BarText {
        item: root
        visible: root.opt("show_label") !== false && !root.vertical && Network.name !== "" && !(root.vpnOn && root.vpnMode === "replace")
        muted: true
        text: Network.name
    }
}
