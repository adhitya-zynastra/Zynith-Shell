import QtQuick
import qs.Common

Item {
    id: root

    property string icon: ""
    property int size: Metrics.control
    property int iconSize: Metrics.icon
    property string tone: "ink"
    property bool active: false
    signal clicked

    implicitWidth: size
    implicitHeight: size
    opacity: enabled ? 1 : 0.4

    Interactive {
        anchors.fill: parent
        radius: root.size / 2
        active: root.active
        enabled: root.enabled
        onClicked: root.clicked()
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        tone: root.active ? "accent" : root.tone
    }
}
