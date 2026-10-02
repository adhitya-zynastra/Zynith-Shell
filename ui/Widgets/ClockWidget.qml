import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Time first, the date as a quiet caption. Stacked on a vertical bar.
BarItem {
    id: root

    active: PanelRouter.isOpen("control", screen?.name ?? "")
    spacing: Metrics.s3
    onClicked: bar?.openPanel("control", root)

    Label {
        role: "title"
        numeric: true
        font.weight: Font.Medium
        font.letterSpacing: root.vertical ? 0 : 0.5
        text: root.vertical ? Qt.formatTime(Time.now, "HH\nmm") : Qt.formatTime(Time.now, "HH:mm")
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.92
    }
    Label {
        visible: !root.vertical && (root.bar?.thickness ?? 34) >= 30
        role: "caption"
        tone: "faint"
        caps: true
        text: Qt.formatDate(Time.now, "ddd d")
    }
}
