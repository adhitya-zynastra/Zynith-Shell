import QtQuick
import qs.Common

Text {
    property string name: ""
    property int size: Metrics.icon
    property string tone: "ink"

    text: Icons.glyph(name)
    font.family: Type.icons
    font.pixelSize: size
    color: tone === "muted" ? Theme.inkMuted : tone === "faint" ? Theme.inkFaint : tone === "accent" ? Theme.accent : Theme.ink
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering

    Behavior on color {
        ColorAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }
}
