import QtQuick
import qs.Common
import qs.Components

// Free text, written when editing finishes (Enter or leaving the field).
SettingRow {
    id: root
    property string placeholder: ""
    controlWidth: 260

    Rectangle {
        width: parent.width
        height: 34
        radius: Metrics.radiusMd
        color: Theme.well
        border.width: field.activeFocus ? 1 : 0
        border.color: Theme.accentLine

        TextInput {
            id: field
            anchors.fill: parent
            anchors.leftMargin: Metrics.s3
            anchors.rightMargin: Metrics.s3
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            selectionColor: Theme.accentSoft
            font.family: Type.ui
            font.pixelSize: Type.body
            clip: true
            text: root.value ?? ""
            onEditingFinished: if (text !== (root.value ?? ""))
                root.write(text)

            Label {
                visible: field.text === "" && !field.activeFocus
                anchors.verticalCenter: parent.verticalCenter
                role: "body"
                tone: "faint"
                text: root.placeholder
            }
        }
    }
}
