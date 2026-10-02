import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Components
import qs.Services

// A title and/or a line of text, fitted to the box.
Item {
    id: root
    property var settings: ({})
    function opt(key: string): var {
        return WidgetTypes.value("label", settings, key);
    }
    readonly property string title: opt("title") ?? ""
    readonly property string line: opt("description") ?? ""
    readonly property color ink: Theme.colour(opt("color"))
    readonly property string family: (opt("font_family") ?? "") !== "" ? opt("font_family") : Type.ui
    opacity: opt("opacity") ?? 1
    implicitWidth: 420
    implicitHeight: 120

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 2
        Text {
            visible: root.title !== ""
            width: parent.width
            height: root.line !== "" ? root.height * 0.6 : root.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            text: root.title
            font.family: root.family
            font.pixelSize: Math.max(10, height * 0.85)
            color: root.ink
        }
        Text {
            visible: root.line !== ""
            width: parent.width
            height: root.title !== "" ? root.height * 0.32 : root.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            wrapMode: Text.WordWrap
            text: root.line
            font.family: root.family
            font.pixelSize: Math.max(10, height * 0.7)
            color: Theme.alpha(root.ink, root.title !== "" ? 0.78 : 1)
        }
    }
    layer.enabled: opt("shadow") === true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 0.6
        shadowVerticalOffset: 2
    }
}
