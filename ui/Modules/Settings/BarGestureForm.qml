import QtQuick
import qs.Common
import qs.Components
import qs.Services

// the gestures, each an action (a native command, exec …, none), its default shown when unset
Column {
    id: gf
    property var actions: ({})
    property var defaults: ({})
    property var reserved: []
    signal changed(string gesture, var action)
    spacing: Metrics.s2
    Repeater {
        model: BarWidgetTypes.gestures
        delegate: Row {
            id: g
            required property string modelData
            readonly property bool own: gf.actions[modelData] !== undefined
            width: gf.width
            spacing: Metrics.s3
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 110
                role: "label"
                tone: "muted"
                text: BarWidgetTypes.gestureLabels[g.modelData]
            }
            // picked from the panels and commands there are (PanelCatalog); hover offers panels only
            ActionPicker {
                width: g.width - 110 - Metrics.s3 - reset.width - Metrics.s3
                value: gf.actions[g.modelData]
                fallback: gf.reserved.includes(g.modelData) ? "" : (gf.defaults[g.modelData] ?? "")
                panelsOnly: g.modelData === "hover"
                enabled: !gf.reserved.includes(g.modelData)
                onPicked: action => gf.changed(g.modelData, action)
            }
            Label {
                id: reset
                anchors.verticalCenter: parent.verticalCenter
                visible: g.own
                role: "micro"
                tone: "faint"
                text: "default"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: gf.changed(g.modelData, undefined)
                }
            }
        }
    }
}
