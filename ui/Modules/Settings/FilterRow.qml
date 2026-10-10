import QtQuick
import qs.Common
import qs.Components

// A filter field with the advanced switch beside it (native settings marked advanced stay hidden until asked).
Row {
    id: root
    property string text: ""
    property bool advanced: false
    signal textEdited(string text)
    spacing: Metrics.s3

    Rectangle {
        width: parent.width - advancedRow.width - Metrics.s3
        height: 34
        radius: Metrics.radiusMd
        color: Theme.well
        border.width: Metrics.hairline
        border.color: field.activeFocus ? Theme.accentLine : Theme.hairline
        Icon {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 14
            tone: "faint"
        }
        TextInput {
            id: field
            anchors.left: glass.right
            anchors.leftMargin: Metrics.s2
            anchors.right: clear.left
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.ink
            font.family: Type.ui
            font.pixelSize: Type.label
            clip: true
            text: root.text
            onTextEdited: {
                root.text = text;
                root.textEdited(text);
            }
            Label {
                visible: field.text === ""
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                tone: "faint"
                text: "Filter these settings"
            }
        }
        IconButton {
            id: clear
            visible: root.text !== ""
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            icon: "x"
            iconSize: 12
            tone: "faint"
            onClicked: {
                root.text = "";
                root.textEdited("");
            }
        }
    }
    Row {
        id: advancedRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.s2
        Label {
            anchors.verticalCenter: parent.verticalCenter
            role: "label"
            tone: "muted"
            text: "Advanced"
        }
        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.advanced
            onToggled: root.advanced = !root.advanced
        }
    }
}
