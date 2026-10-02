import QtQuick
import qs.Common
import qs.Widgets

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
            required property string modelData

            sourceComponent: Registry.component(modelData)
            onLoaded: {
                item.vertical = Qt.binding(() => root.bar.vertical);
                item.screen = Qt.binding(() => root.bar.screen);
                item.bar = root.bar;
            }
            Component.onCompleted: if (!sourceComponent)
                console.warn("zynith: unknown widget type", modelData)
        }
    }
}
