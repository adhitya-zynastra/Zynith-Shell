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
    // on a vertical bar a value is a readout: small, mono, tracked, under its glyph
    readonly property bool readout: item.vertical
    color: muted ? Theme.alpha(item.ink, readout ? 0.62 : 0.7) : item.ink
    font.family: readout ? Type.mono : item.family
    font.pixelSize: Math.round((readout ? Type.data * 0.86 : size) * item.fontScale)
    font.weight: readout ? Font.Medium : item.weight
    font.letterSpacing: readout ? 0.6 : 0
    horizontalAlignment: readout ? Text.AlignHCenter : Text.AlignLeft
    font.features: Type.tabular
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
