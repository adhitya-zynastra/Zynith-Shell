import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One widget on a bar, by name: its kind's component with its settings and actions applied.
Loader {
    id: root

    required property var bar
    required property string name
    // the capsule group it sits in (its foreground colours the widget), or null
    property var group: null
    readonly property var spec: Config.resolveBarWidget(name)

    // workspaces: the native styles (regular · minimal · focus_hint, the default) are the one-to-one widget;
    // pills · numbers · dots · icons · line are the evolved one
    readonly property string kind: BarWidgetTypes.canonical(spec.type)
    sourceComponent: kind === "workspaces" && ["regular", "minimal", "focus_hint"].includes(spec.settings?.style ?? "regular") ? Registry.workspacesClassic : Registry.component(kind)
    onLoaded: {
        item.vertical = Qt.binding(() => root.bar.vertical);
        item.screen = Qt.binding(() => root.bar.screen);
        item.bar = root.bar;
        if (item.group !== undefined)
            item.group = Qt.binding(() => root.group);
        item.type = Qt.binding(() => BarWidgetTypes.canonical(root.spec.type));
        item.name = Qt.binding(() => root.name);
        item.settings = Qt.binding(() => root.spec.settings);
        item.actions = Qt.binding(() => root.spec.actions);
    }
    Component.onCompleted: if (!sourceComponent)
        console.warn("zynith: unknown bar widget", name, "(" + spec.type + ")")
}
