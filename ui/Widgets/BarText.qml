import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Text on a bar, in its widget's colour, font and size.
Text {
    required property Item item
    property real size: Type.label
    property bool muted: false
    color: muted ? Theme.alpha(item.ink, 0.7) : item.ink
    font.family: item.family
    font.pixelSize: Math.round(size * item.fontScale)
    font.weight: item.weight
    font.features: Type.tabular
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
