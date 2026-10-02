import QtQuick
import qs.Common

Text {
    // caption | label | body | title | headline | display
    property string role: "body"
    // ink | muted | faint | accent
    property string tone: "ink"
    property bool numeric: false
    property bool caps: false

    font.family: role === "display" || numeric ? Type.display : Type.ui
    font.pixelSize: ({
            micro: Type.micro,
            caption: Type.caption,
            label: Type.label,
            body: Type.body,
            title: Type.title,
            headline: Type.headline,
            display: Type.display1
        })[role] ?? Type.body
    font.weight: role === "display" ? Font.Light : role === "title" || role === "headline" ? Font.Medium : Font.Normal
    font.letterSpacing: caps ? Type.tracking : role === "display" ? -1 : 0
    font.capitalization: caps ? Font.AllUppercase : Font.MixedCase
    font.features: numeric ? Type.tabular : ({})
    color: tone === "muted" ? Theme.inkMuted : tone === "faint" ? Theme.inkFaint : tone === "accent" ? Theme.accent : Theme.ink
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
        ColorAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }
}
