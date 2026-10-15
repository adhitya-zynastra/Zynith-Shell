import QtQuick
import qs.Common

Text {
    // micro | caption | label | body | title | headline | heading | display2 | display | displayXL | data
    property string role: "body"
    // ink | muted | faint | accent
    property string tone: "ink"
    property bool numeric: false
    property bool caps: false

    // data: the readout voice (mono, uppercase, tracked) for values, units and section heads; never language
    readonly property bool dataVoice: role === "data"
    font.family: dataVoice ? Type.mono : role === "heading" ? Type.heading : role === "display" || role === "display2" || role === "displayXL" || numeric ? Type.display : Type.ui
    font.pixelSize: ({
            micro: Type.micro,
            caption: Type.caption,
            label: Type.label,
            body: Type.body,
            title: Type.title,
            headline: Type.headline,
            heading: Type.headingSize,
            display2: Type.display2,
            display: Type.display1,
            displayXL: Type.displayXL,
            data: Type.data
        })[role] ?? Type.body
    font.weight: role === "display" || role === "display2" || role === "displayXL" ? Font.Light : dataVoice ? Font.Medium : role === "title" || role === "headline" ? Font.Medium : Font.Normal
    font.letterSpacing: dataVoice ? Type.dataTracking : caps ? Type.tracking : role === "display" || role === "displayXL" ? -1 : role === "heading" ? -0.4 : 0
    font.capitalization: caps || dataVoice ? Font.AllUppercase : Font.MixedCase
    font.features: numeric || dataVoice ? Type.tabular : ({})
    color: tone === "muted" ? Theme.inkMuted : tone === "faint" ? Theme.inkFaint : tone === "accent" ? Theme.accent : tone === "danger" ? Theme.danger : Theme.ink
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
        ColorAnimation {
            duration: Motion.focus
            easing.type: Motion.standardEasing
        }
    }
}
