import QtQuick
import qs.Components

SettingRow {
    id: root
    controlWidth: 44

    Toggle {
        anchors.right: parent.right
        checked: !!root.value
        onToggled: root.write(!root.value)
    }
}
