import QtQuick
import qs.Common

// A page's heading on the Control Panel's hero: what the page is about on the left (an indexed eyebrow, the
// subject in the heading voice, one line of detail) and its one live readout on the right (display numerals,
// the unit set smaller, a data caption). heading: { eyebrow, title, detail, value, unit, caption }; anything
// missing is left out rather than filled.
Item {
    id: root

    property var heading: ({})
    property bool narrow: false
    // room the strip of tabs takes at the bottom (the type sits above it)
    property real bottomRoom: 0

    readonly property string valueText: String(heading?.value ?? "")

    Column {
        id: left
        anchors.left: parent.left
        anchors.right: readout.visible ? readout.left : parent.right
        anchors.rightMargin: Metrics.s6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomRoom
        spacing: Metrics.s1
        Label {
            visible: text !== ""
            role: "data"
            tone: "accent"
            text: root.heading?.eyebrow ?? ""
        }
        Label {
            width: parent.width
            role: "heading"
            text: root.heading?.title ?? ""
            style: Text.Raised
            styleColor: Theme.alpha(Theme.base, 0.3)
        }
        Label {
            visible: text !== "" && !root.narrow
            width: parent.width
            role: "caption"
            tone: "muted"
            text: root.heading?.detail ?? ""
        }
    }

    Column {
        id: readout
        visible: root.valueText !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomRoom
        spacing: 0
        Row {
            anchors.right: parent.right
            spacing: Metrics.s1
            Label {
                id: value
                role: root.narrow ? "headline" : "display"
                numeric: true
                text: root.valueText
                style: Text.Raised
                styleColor: Theme.alpha(Theme.base, 0.3)
            }
            Label {
                visible: text !== ""
                anchors.baseline: value.baseline
                role: root.narrow ? "label" : "title"
                tone: "muted"
                text: root.heading?.unit ?? ""
            }
        }
        Label {
            visible: text !== ""
            anchors.right: parent.right
            role: "data"
            tone: "muted"
            text: root.heading?.caption ?? ""
        }
    }
}
