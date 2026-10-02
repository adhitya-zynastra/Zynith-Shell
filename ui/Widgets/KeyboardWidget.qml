import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services
import Zynith.Native

// The keyboard layout: an icon and its name (short or full); hidden with one layout if asked.
BarItem {
    id: root
    readonly property string layout: Workspaces.keyboardLayout
    readonly property bool single: NiriState.keyboardLayouts.length < 2
    shown: layout !== "" && !(opt("hide_when_single_layout") === true && single)
    BarGlyph {
        item: root
        visible: root.opt("show_glyph") !== false
        name: root.opt("glyph") || "keyboard"
    }
    BarText {
        item: root
        visible: root.opt("show_label") !== false
        font.capitalization: Font.AllUppercase
        text: root.opt("display") === "full" ? root.layout : root.layout.replace(/\s*\(.*\)/, "").slice(0, 3)
    }
}
