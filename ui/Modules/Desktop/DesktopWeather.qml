import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Now, and the days ahead.
Column {
    id: root
    property var settings: ({})
    readonly property var w: Weather.data
    readonly property color ink: Theme.pal(settings.color ?? "on_surface")
    visible: Weather.valid
    spacing: Metrics.s3

    Component.onCompleted: Weather.retain()
    Component.onDestruction: Weather.release()

    Row {
        spacing: Metrics.s3
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Weather.glyph(root.w.current?.code ?? 0, root.w.current?.isDay ?? true)
            size: 30
            color: root.ink
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.w.current?.temperature ?? 0) + (root.w.unit ?? "°")
            font.family: Type.display
            font.pixelSize: 34
            font.weight: Font.Light
            color: root.ink
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.w.location ?? ""
            font.family: Type.ui
            font.pixelSize: Type.label
            color: Theme.alpha(root.ink, 0.7)
        }
    }
    Row {
        visible: root.settings.show_forecast ?? true
        spacing: Metrics.s5
        Repeater {
            model: (root.w.days ?? []).slice(1, 5)
            delegate: Column {
                required property var modelData
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd").toUpperCase()
                    font.family: Type.ui
                    font.pixelSize: Type.micro
                    font.letterSpacing: Type.tracking
                    color: Theme.alpha(root.ink, 0.6)
                }
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Weather.glyph(modelData.code, true)
                    size: 16
                    color: root.ink
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(modelData.max) + "° " + Math.round(modelData.min) + "°"
                    font.family: Type.ui
                    font.pixelSize: Type.caption
                    color: Theme.alpha(root.ink, 0.8)
                }
            }
        }
    }
}
