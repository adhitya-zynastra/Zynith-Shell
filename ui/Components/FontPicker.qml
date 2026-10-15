import QtQuick
import qs.Common

// Picks a font family from the ones Qt can see, by looking rather than remembering names: the field shows the
// current family in its own face; a click unfolds (in place, so it stays inside the card or form that holds it)
// a search box and every family, each drawn in itself. Type to filter; Up/Down move, Enter takes, Escape folds.
// A configured family that is not installed is kept and marked, so a replacement can be chosen.
//
// value: the configured family ("" = the default). fallback: what "" means, named for the user.
Column {
    id: root

    property string value: ""
    property string fallback: "The interface font"
    property bool enabled: true
    signal picked(string family)   // "" = back to the default

    property bool open: false
    property string query: ""
    // read when the list unfolds (fonts installed since show up the next time it opens), never while drawing
    property var families: []
    readonly property bool missing: value !== "" && families.length > 0 && !families.includes(value)
    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return q === "" ? families : families.filter(f => f.toLowerCase().includes(q));
    }
    // the shell's own faces, named in the list
    function roleOf(family: string): string {
        return family === Type.ui ? "Zynith · interface" : family === Type.display ? "Zynith · display" : family === Type.mono ? "Zynith · monospace" : "";
    }

    function unfold(): void {
        families = Qt.fontFamilies();
        query = "";
        open = true;
        const i = shown.indexOf(value);
        list.currentIndex = i;
        if (i >= 0)
            list.positionViewAtIndex(i, ListView.Center);
        search.forceActiveFocus();
    }
    function fold(): void {
        open = false;
        query = "";
    }
    function take(family: string): void {
        picked(family);
        fold();
    }

    spacing: Metrics.s2

    // the current choice, in its own face
    Rectangle {
        width: root.width
        height: 34
        radius: Metrics.radiusControl
        color: Theme.well
        opacity: root.enabled ? 1 : 0.4
        border.width: Metrics.hairline
        border.color: root.open ? Theme.accentLine : root.missing ? Theme.alpha(Theme.danger, 0.6) : Theme.hairline
        Label {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.right: chevron.left
            anchors.rightMargin: Metrics.s2
            anchors.verticalCenter: parent.verticalCenter
            role: "body"
            elide: Text.ElideRight
            tone: root.value === "" ? "muted" : root.missing ? "danger" : "ink"
            font.family: root.value !== "" ? root.value : Type.ui
            text: root.value === "" ? root.fallback : root.value + (root.missing ? "  ·  not installed" : "")
        }
        Icon {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 14
            tone: "faint"
            rotation: root.open ? 180 : 0
            Behavior on rotation {
                Anim {
                    role: "effects"
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open ? root.fold() : root.unfold()
        }
    }

    // the list: search, then every family
    Rectangle {
        visible: root.open
        width: root.width
        height: visible ? listColumn.implicitHeight + Metrics.s2 * 2 : 0
        radius: 12
        color: Theme.alpha(Theme.base, 0.55)
        border.width: Metrics.hairline
        border.color: Theme.hairline

        Column {
            id: listColumn
            x: Metrics.s2
            y: Metrics.s2
            width: parent.width - Metrics.s2 * 2
            spacing: Metrics.s2

            Rectangle {
                width: parent.width
                height: 30
                radius: Metrics.radiusControl
                color: Theme.well
                border.width: Metrics.hairline
                border.color: search.activeFocus ? Theme.accentLine : Theme.hairline
                Icon {
                    id: lens
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 13
                    tone: "faint"
                }
                TextInput {
                    id: search
                    anchors.left: lens.right
                    anchors.leftMargin: Metrics.s2
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.ink
                    font.family: Type.ui
                    font.pixelSize: Type.label
                    clip: true
                    text: root.query
                    onTextEdited: {
                        root.query = text;
                        list.currentIndex = root.shown.length > 0 ? 0 : -1;
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down) {
                            list.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            list.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (list.currentIndex >= 0 && list.currentIndex < root.shown.length)
                                root.take(root.shown[list.currentIndex]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.fold();
                            event.accepted = true;
                        }
                    }
                    Label {
                        visible: search.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "faint"
                        text: root.families.length + " fonts · type to find one"
                    }
                }
            }

            Row {
                spacing: Metrics.s2
                Chip {
                    text: "Default (" + root.fallback + ")"
                    active: root.value === ""
                    onClicked: root.take("")
                }
            }

            ListView {
                id: list
                width: parent.width
                height: Math.min(280, Math.max(36, contentHeight))
                clip: true
                model: root.shown
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: false
                highlightMoveDuration: 0
                delegate: Rectangle {
                    id: entry
                    required property string modelData
                    required property int index
                    readonly property bool chosen: modelData === root.value
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width
                    height: 34
                    radius: Metrics.radiusControl
                    color: entry.current ? Theme.accentSoft : entryArea.containsMouse ? Theme.hover : "transparent"
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.s3
                        anchors.right: tag.left
                        anchors.rightMargin: Metrics.s2
                        anchors.verticalCenter: parent.verticalCenter
                        role: "body"
                        elide: Text.ElideRight
                        font.family: entry.modelData
                        text: entry.modelData
                    }
                    Row {
                        id: tag
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s2
                        Label {
                            visible: text !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            role: "micro"
                            tone: "faint"
                            font.family: Type.ui
                            text: root.roleOf(entry.modelData)
                        }
                        Icon {
                            visible: entry.chosen
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: 14
                            tone: "accent"
                        }
                    }
                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.take(entry.modelData)
                    }
                }
                Label {
                    visible: list.count === 0
                    anchors.centerIn: parent
                    role: "label"
                    tone: "faint"
                    text: root.families.length === 0 ? "No fonts found" : "No font matches “" + root.query + "”"
                }
            }
        }
    }
}
