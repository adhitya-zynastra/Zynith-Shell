import QtQuick
import qs.Common
import qs.Components
import qs.Services

// What can go on a bar, by category, with a line on what each is for. Type to search (names and what they do);
// click one to add it (to the region you picked, or where it usually goes); or drag it onto the bar.
Column {
    id: lib

    required property var page
    property string query: ""
    property string category: ""
    readonly property var items: BarWidgetTypes.library(query, category)
    spacing: Metrics.s3

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    SearchField {
        id: search
        objectName: "bar-library-search"
        width: parent.width
        placeholder: "Search components — e.g. clock, wifi, music"
        onTextChanged: lib.query = text
        onAccepted: if (lib.items.length > 0)
            lib.page.addKind(lib.items[0].type)
        onEscaped: text = ""
    }
    Flow {
        width: parent.width
        spacing: Metrics.s1
        Chip {
            text: "All"
            active: lib.category === ""
            onClicked: lib.category = ""
        }
        Repeater {
            model: BarWidgetTypes.categories
            delegate: Chip {
                required property var modelData
                text: modelData.label
                active: lib.category === modelData.key
                onClicked: lib.category = lib.category === modelData.key ? "" : modelData.key
            }
        }
    }
    Label {
        visible: lib.items.length === 0
        role: "caption"
        tone: "faint"
        text: "Nothing matches “" + lib.query + "”"
    }
    // what the hovered one is for
    Label {
        width: parent.width
        height: 16
        elide: Text.ElideRight
        role: "caption"
        tone: lib.hovered !== "" ? "muted" : "faint"
        text: lib.hovered !== "" ? (BarWidgetTypes.find(lib.hovered)?.label ?? "") + " — " + (BarWidgetTypes.descriptions[lib.hovered] ?? "") : "Click one to add it, or drag it onto the bar."
    }
    property string hovered: ""
    // by category (or one category, or what the search found), each a compact tile
    Repeater {
        model: lib.query.trim() !== "" || lib.category !== "" ? [{ key: "", label: "", kinds: lib.items.map(t => t.type) }] : BarWidgetTypes.categories.map(c => ({ key: c.key, label: c.label, kinds: c.kinds.filter(k => BarWidgetTypes.find(k)) }))
        delegate: Column {
            id: cat
            required property var modelData
            width: lib.width
            spacing: Metrics.s1
            Label {
                visible: cat.modelData.label !== ""
                role: "micro"
                caps: true
                tone: "faint"
                text: cat.modelData.label
            }
            Flow {
                width: parent.width
                spacing: Metrics.s1
                Repeater {
                    model: cat.modelData.kinds
                    delegate: Rectangle {
                        id: card
                        required property string modelData
                        readonly property var info: BarWidgetTypes.find(modelData)
                        objectName: "library-" + modelData
                        width: cardRow.implicitWidth + Metrics.s3 * 2
                        height: 32
                        radius: 16
                        color: cardArea.containsMouse ? Theme.accentSoft : Theme.plate
                        border.width: cardArea.containsMouse ? 1 : 0
                        border.color: Theme.accentLine
                        Row {
                            id: cardRow
                            anchors.centerIn: parent
                            spacing: Metrics.s2
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: card.info?.icon ?? "help"
                                size: 15
                                tone: "accent"
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "label"
                                text: card.info?.label ?? card.modelData
                            }
                        }
                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            drag.target: lib.page.dragProxy
                            drag.threshold: 6
                            onContainsMouseChanged: lib.hovered = containsMouse ? card.modelData : (lib.hovered === card.modelData ? "" : lib.hovered)
                            onPressed: mouse => lib.page.pressNew(card, card.modelData)
                            onPositionChanged: mouse => {
                                if (drag.active)
                                    lib.page.dragMove(card, mouse.x, mouse.y, null, card.info?.icon ?? "", card.info?.label ?? "");
                            }
                            onReleased: lib.page.dragRelease()
                            onClicked: lib.page.addKind(card.modelData)
                        }
                    }
                }
            }
        }
    }
}
