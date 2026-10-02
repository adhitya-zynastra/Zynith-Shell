import QtQuick
import qs.Common
import qs.Components
import qs.Services

// The keyboard layout, as a short tag; hidden with a single layout.
BarItem {
    id: root

    readonly property string layout: Workspaces.keyboardLayout
    shown: layout !== ""
    interactive: false

    Label {
        role: "caption"
        caps: true
        tone: "muted"
        text: root.layout.replace(/\s*\(.*\)/, "").slice(0, 3)
    }
}
