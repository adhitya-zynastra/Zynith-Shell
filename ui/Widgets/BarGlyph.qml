import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// A glyph on a bar in its widget's icon colour, or the widget's own picture (custom_image, tinted when
// custom_image_colorize).
Item {
    id: g
    required property Item item
    property string name: ""
    property real size: Metrics.icon
    property color colour: item.iconInk
    readonly property string picture: item.opt("custom_image") ?? ""
    implicitWidth: size
    implicitHeight: size
    Icon {
        anchors.centerIn: parent
        visible: g.picture === ""
        name: g.name
        size: g.size
        color: g.colour
    }
    Image {
        id: pic
        anchors.fill: parent
        visible: g.picture !== "" && !g.item.opt("custom_image_colorize")
        source: g.picture !== "" ? (g.picture.startsWith("/") ? "file://" + g.picture : g.picture) : ""
        sourceSize.width: g.size * 2
        sourceSize.height: g.size * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    // tinted: the picture's shape in the icon colour
    Image {
        anchors.fill: parent
        visible: g.picture !== "" && g.item.opt("custom_image_colorize") === true
        source: pic.source
        sourceSize: pic.sourceSize
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        layer.enabled: visible
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: g.colour
            brightness: 0.35
        }
    }
}
