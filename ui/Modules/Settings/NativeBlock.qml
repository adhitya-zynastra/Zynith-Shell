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

    // folded by default: one line saying what is inside and where it applies; opened by a click, and by itself
    // when a search lands in it. Nothing is removed, only kept out of the way of the page's own settings.
    property bool open: false
    readonly property bool unfolded: open || query !== ""

    Item {
        width: parent.width
        height: head.implicitHeight
        SectionHead {
            id: head
            anchors.fill: parent
            index: "∗"
            title: root.inactive ? root.name + " · native, off while Zynith draws it" : root.name
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "data"
                tone: disclose.containsMouse ? "accent" : "faint"
                text: (section.count > 0 ? section.count + (section.count === 1 ? " setting" : " settings") : "") + (root.unfolded ? "  ▴" : "  ▾")
            }
        }
        MouseArea {
            id: disclose
            anchors.fill: parent
            anchors.margins: -Metrics.s2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }
    Label {
        visible: !root.unfolded
        width: parent.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "The native shell's own settings on this subject — they shape the lock screen, the apps' theme templates and the native fallback. Click to show them."
    }
    Label {
        visible: root.inactive && root.unfolded
        width: parent.width
        role: "caption"
        tone: "faint"
        wrapMode: Text.WordWrap
        text: "These shape the native shell's version, which is switched off. They apply again only if Zynith or native surfaces hands it back."
    }
    RegistrySection {
        id: section
        visible: root.unfolded
        height: visible ? implicitHeight : 0
        width: parent.width
        section: root.entry.section
        groupFilter: root.entry.groups ?? []
        exclude: root.entry.exclude ?? []
        query: root.query
        advanced: root.advanced
    }
}
