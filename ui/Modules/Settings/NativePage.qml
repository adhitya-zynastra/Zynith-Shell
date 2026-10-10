import QtQuick
import qs.Common
import qs.Components
import qs.Services

// A native settings section as a page of its own: its title, a filter, the advanced switch, and every
// setting it has (or the groups the route names), as the native Settings window drew them.
Column {
    id: root
    spacing: Metrics.s5

    required property var route
    // a setting to show alone (search), cleared from the chip
    property string focusTitle: ""

    PanelHeader {
        width: parent.width
        title: root.route.title
        caption: "From the native shell · " + section.count + " settings"
    }
    FilterRow {
        id: filterRow
        width: parent.width
        text: root.focusTitle
        onTextEdited: t => root.focusTitle = t
    }
    RegistrySection {
        id: section
        width: parent.width
        section: root.route.section
        groupFilter: root.route.groups ?? []
        query: filterRow.text
        advanced: filterRow.advanced
    }
}
