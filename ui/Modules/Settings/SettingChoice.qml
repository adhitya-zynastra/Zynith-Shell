import QtQuick
import qs.Components

// One of a few named values. options: [{ key, label }]
SettingRow {
    id: root
    property var options: []
    controlWidth: Math.max(160, options.length * 86)

    Segmented {
        width: parent.width
        current: String(root.value)
        options: root.options
        onPicked: key => root.write(key)
    }
}
