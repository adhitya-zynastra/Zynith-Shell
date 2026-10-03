import QtQuick
import qs.Common

// A live value as one typographic unit: the number in the display face with steady tabular figures, its
// unit small in the data voice, an optional caption above.
Column {
    id: root
    property string caption: ""
    property string value: ""
    property string unit: ""
    // display | display2 | headline | title
    property string size: "headline"
    property string tone: "ink"
    spacing: 2

    Label {
        visible: root.caption !== ""
        role: "data"
        tone: "faint"
        text: root.caption
    }
    Row {
        spacing: 4
        Label {
            id: number
            role: root.size
            numeric: true
            tone: root.tone
            text: root.value
        }
        Label {
            visible: root.unit !== ""
            anchors.baseline: number.baseline
            role: "data"
            tone: "faint"
            text: root.unit
        }
    }
}
