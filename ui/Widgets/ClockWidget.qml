import QtQuick
import qs.Common
import qs.Components
import qs.Services

BarItem {
    id: root

    active: PanelRouter.isOpen("home", screen?.name ?? "")
    spacing: Metrics.s3
    onClicked: bar?.openPanel("home", root)

    Label {
        role: "title"
        numeric: true
        font.weight: Font.Medium
        text: root.vertical ? Qt.formatTime(Time.now, "HH\nmm") : Qt.formatTime(Time.now, "HH:mm")
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.9
    }
    Label {
        visible: !root.vertical
        role: "caption"
        tone: "faint"
        caps: true
        text: Qt.formatDate(Time.now, "ddd d")
    }
}
