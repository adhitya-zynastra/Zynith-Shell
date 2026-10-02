import QtQuick
import qs.Common
import qs.Components

// A number between from and to. format(value) gives the readout.
SettingRow {
    id: root
    property real from: 0
    property real to: 1
    property real step: 0.05
    property var format: v => Math.round(v * 100) + "%"
    controlWidth: 260

    readonly property real current: Number(root.value ?? from)

    Row {
        width: parent.width
        spacing: Metrics.s3
        Slider {
            id: slider
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 56 - Metrics.s3
            value: (root.current - root.from) / (root.to - root.from)
            onMoved: v => {
                const raw = root.from + v * (root.to - root.from);
                root.write(Math.round(raw / root.step) * root.step);
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            horizontalAlignment: Text.AlignRight
            role: "label"
            numeric: true
            tone: "muted"
            text: root.format(root.current)
        }
    }
}
