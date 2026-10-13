import QtQuick
import qs.Common
import qs.Components
import qs.Services

// Under a Zynith page: the native shell's settings on the same subject, under a name a person would use
// (`title`). Those shaping a native surface Zynith draws instead (`owner` in [surfaces]) change nothing while
// Zynith draws it, so they appear only with Advanced settings on, and say so; so does a block marked `advanced`.
Column {
    id: root
    spacing: Metrics.s4

    required property var entry
    property string query: ""
    property bool advanced: false
    readonly property bool inactive: (entry.owner ?? "") !== "" && (Config.surfaces?.[entry.owner] ?? "native") === "zynith"
    readonly property bool shown: (advanced || (!inactive && !(entry.advanced ?? false)) || query !== "") && (section.count > 0 || query === "")
    readonly property string name: entry.title ?? ("Native " + (entry.groups?.length > 0 ? entry.groups.join(", ") : entry.section).toLowerCase())
    visible: shown
    height: shown ? implicitHeight : 0

    SectionHead {
        width: parent.width
        index: "∗"
        title: root.inactive ? root.name + " · native, off while Zynith draws it" : root.name
    }
    Label {
        visible: root.inactive
        width: parent.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "These shape the native shell's version, which is switched off. They apply again only if Zynith or native surfaces hands it back."
    }
    RegistrySection {
        id: section
        width: parent.width
        section: root.entry.section
        groupFilter: root.entry.groups ?? []
        exclude: root.entry.exclude ?? []
        query: root.query
        advanced: root.advanced
    }
}
