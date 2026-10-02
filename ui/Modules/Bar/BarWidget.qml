import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One widget on a bar, by name: its kind's component with its settings and actions applied.
Loader {
    id: root

    required property var bar
    required property string name
    readonly property var spec: Config.resolveBarWidget(name)

    sourceComponent: Registry.component(BarWidgetTypes.canonical(spec.type))
    onLoaded: {
        item.vertical = Qt.binding(() => root.bar.vertical);
        item.screen = Qt.binding(() => root.bar.screen);
        item.bar = root.bar;
        item.type = Qt.binding(() => BarWidgetTypes.canonical(root.spec.type));
        item.name = Qt.binding(() => root.name);
        item.settings = Qt.binding(() => root.spec.settings);
        item.actions = Qt.binding(() => root.spec.actions);
    }
    Component.onCompleted: if (!sourceComponent)
        console.warn("zynith: unknown bar widget", name, "(" + spec.type + ")")
}
