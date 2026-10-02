import QtQuick
import QtQuick.Effects
import qs.Common

// A title and/or a line of text.
Item {
    id: root
    property var settings: ({})
    readonly property bool shadowed: settings.shadow ?? false
    opacity: settings.opacity ?? 1

    Column {
        id: body
        anchors.centerIn: parent
        spacing: 2
        Text {
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.settings.title ?? ""
            font.family: root.settings.font_family ?? Type.ui
            font.pixelSize: root.settings.description ? root.height * 0.55 : Math.max(10, root.height * 0.8)
            color: Theme.pal(root.settings.color ?? "on_surface")
        }
        Text {
            visible: text !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.settings.description ?? ""
            font.family: root.settings.font_family ?? Type.ui
            font.pixelSize: Math.max(10, root.settings.title ? root.height * 0.35 : root.height * 0.8)
            color: Theme.pal(root.settings.color ?? "on_surface_variant")
        }
    }
    layer.enabled: root.shadowed
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.6
        shadowVerticalOffset: 2
    }
}
