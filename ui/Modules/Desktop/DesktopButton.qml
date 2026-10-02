import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// A glyph (and a label) that runs a command line of your choosing.
Item {
    id: root
    property var settings: ({})
    readonly property bool interactive: true
    function opt(key: string): var {
        return WidgetTypes.value("button", settings, key);
    }
    readonly property string variant: opt("variant")
    readonly property color ink: variant === "primary" ? Theme.onAccent : variant === "destructive" ? Theme.danger : Theme.colour(opt("color"))
    readonly property string label: opt("label") ?? ""

    implicitWidth: 64
    implicitHeight: 64

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        visible: root.opt("background") !== false && root.variant !== "ghost"
        color: root.variant === "primary" ? Theme.accent : root.variant === "outline" ? "transparent" : root.variant === "destructive" ? Theme.alpha(Theme.danger, 0.18) : area.containsMouse ? Theme.hover : Theme.alpha(Theme.base, 0.45)
        border.width: root.variant === "outline" ? 1.5 : Metrics.hairline
        border.color: root.variant === "outline" ? root.ink : Theme.hairline
        scale: area.pressed ? 0.94 : 1
        Glide on scale {
            epsilon: 0.001
        }
    }
    Row {
        anchors.centerIn: parent
        spacing: Metrics.s2
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.opt("glyph") || "heart"
            size: Math.min(root.width, root.height) * 0.42
            color: root.ink
        }
        Label {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            role: "label"
            color: root.ink
            text: root.label
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const cmd = (root.opt("command") ?? "").trim();
            if (cmd !== "")
                Quickshell.execDetached(["sh", "-c", cmd]);
        }
    }
}
