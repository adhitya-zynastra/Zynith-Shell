import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One section of a bar: its entries in order. An entry is a widget name (a kind, or a [widget.<name>] of its
// own) or group:<id>, a capsule holding several widgets.
Grid {
    id: root

    required property var bar
    property var types: []
    readonly property int count: types.length

    columns: bar.vertical ? 1 : Math.max(1, types.length)
    spacing: bar.spacingOverride >= 0 ? bar.spacingOverride : Metrics.s1
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    Repeater {
        model: root.types

        delegate: Loader {
            id: entry
            required property string modelData
            readonly property bool isGroup: modelData.startsWith("group:")
            readonly property var group: isGroup ? root.bar.groupFor(modelData.slice(6)) : null

            sourceComponent: isGroup ? (group ? groupComponent : null) : widgetComponent
            Component.onCompleted: if (isGroup && !group)
                console.warn("zynith: no capsule group", modelData)
        }
    }

    Component {
        id: widgetComponent
        BarWidget {
            bar: root.bar
            name: parent ? parent.modelData : ""
        }
    }
    Component {
        id: groupComponent
        CapsuleGroup {
            bar: root.bar
            group: parent ? parent.group : null
        }
    }
}
