import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Under a Zynith page: the native shell's settings on the same subject. Those that shape a native surface
// Zynith now draws instead (`owner` in [surfaces]) are folded and say so — they apply only when that surface
// is handed back to the native shell.
Column {
    id: root
    spacing: Metrics.s4

    required property var entry
    property string query: ""
    property bool advanced: false
    readonly property bool inactive: (entry.owner ?? "") !== "" && (Config.surfaces?.[entry.owner] ?? "native") === "zynith"
    property bool open: !inactive || query !== ""

    Item {
        width: parent.width
        height: head.implicitHeight
        visible: section.count > 0 || root.query === ""
        SectionHead {
            id: head
            width: parent.width - toggle.width - Metrics.s3
            index: "∗"
            title: (root.inactive ? "Native " : "From the native shell · ") + (root.entry.groups?.length > 0 ? root.entry.groups.join(", ") : root.entry.section) + "  (" + section.count + ")"
        }
        Chip {
            id: toggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.open ? "Hide" : "Show"
            onClicked: root.open = !root.open
        }
    }
    Label {
        visible: root.inactive && root.open
        width: parent.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "Zynith draws this surface, so these shape the native one, which is off. They apply again if Zynith UI → surfaces hands it back."
    }
    RegistrySection {
        id: section
        visible: root.open
        width: parent.width
        section: root.entry.section
        groupFilter: root.entry.groups ?? []
        query: root.query
        advanced: root.advanced
    }
}
