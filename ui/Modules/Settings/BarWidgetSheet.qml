import QtQuick
import qs.Common
import qs.Components
import qs.Services

// One component's own settings (its [widget.<name>] table): what is particular to its kind first; its look
// (colour, font, size, capsule) and what clicking it does wait behind a disclosure each.
Column {
    id: ws
    property string name
    readonly property var spec: Config.resolveBarWidget(name)
    readonly property var kind: BarWidgetTypes.find(spec.type)
    readonly property bool plain: spec.type === "spacer" || spec.type === "divider"
    property bool lookOpen: false
    property bool clicksOpen: false
    spacing: Metrics.s4

    function form(schema: var): var {
        return schema;
    }
    Label {
        visible: (ws.kind?.settings ?? []).length === 0
        role: "caption"
        tone: "faint"
        text: "Nothing to set for this one beyond its look."
    }
    SchemaForm {
        width: parent.width
        schema: ws.kind?.settings ?? []
        valueOf: key => BarWidgetTypes.value(ws.spec.type, ws.spec.settings, key)
        shows: spec => BarWidgetTypes.visible(ws.spec.type, spec, ws.spec.settings)
        isSet: key => ws.spec.settings[key] !== undefined
        onChanged: (key, value) => BarEdits.setComponentKey(ws.name, key, value)
        onCleared: key => BarEdits.setComponentKey(ws.name, key, undefined)
        commitOnRelease: true
        onPreviewed: (key, value) => BarEdits.previewComponent(ws.name, key, value)
        onPreviewEnded: (key, value, canceled) => BarEdits.endComponentPreview(ws.name, key, value, canceled)
    }
    Chip {
        visible: !ws.plain
        icon: ws.lookOpen ? "chevron-up" : "chevron-down"
        text: "Its look — colour, font, size, capsule"
        active: ws.lookOpen
        onClicked: ws.lookOpen = !ws.lookOpen
    }
    SchemaForm {
        visible: ws.lookOpen && !ws.plain
        width: parent.width
        schema: BarWidgetTypes.common
        valueOf: key => BarWidgetTypes.value(ws.spec.type, ws.spec.settings, key)
        shows: spec => BarWidgetTypes.visible(ws.spec.type, spec, ws.spec.settings)
        isSet: key => ws.spec.settings[key] !== undefined
        onChanged: (key, value) => BarEdits.setComponentKey(ws.name, key, value)
        onCleared: key => BarEdits.setComponentKey(ws.name, key, undefined)
        commitOnRelease: true
        onPreviewed: (key, value) => BarEdits.previewComponent(ws.name, key, value)
        onPreviewEnded: (key, value, canceled) => BarEdits.endComponentPreview(ws.name, key, value, canceled)
    }
    Chip {
        visible: !ws.plain
        icon: ws.clicksOpen ? "chevron-up" : "chevron-down"
        text: "What clicking it does"
        active: ws.clicksOpen
        onClicked: ws.clicksOpen = !ws.clicksOpen
    }
    BarGestureForm {
        visible: ws.clicksOpen && !ws.plain
        width: parent.width
        actions: ws.spec.actions
        defaults: {
            const out = {};
            for (const g of BarWidgetTypes.gestures)
                out[g] = BarWidgetTypes.action(ws.spec.type, ws.spec.settings, {}, g);
            return out;
        }
        reserved: BarWidgetTypes.find(ws.spec.type)?.reserved ?? []
        onChanged: (gesture, action) => BarEdits.setComponentAction(ws.name, gesture, action)
    }
}
