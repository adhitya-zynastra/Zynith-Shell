import QtQuick
import qs.Common
import qs.Services

// A row of tabs across the top of a surface. Which tabs and in what order is the caller's (from config); each is
// { id, label, icon }. connected is Zynith's own command bar, as the native shell had it: every section an icon,
// the current one unfolding its name; on a switch the old name folds away while the new one unfolds and the
// row makes room — and here the selection is the page's sheet itself reaching up into the strip.
Item {
    id: root

    property var tabs: []
    property string current: ""
    property bool showIcons: true
    property bool showLabels: true
    // connected (icon beside label on a plate that rises out of the page's sheet and stretches into the next tab:
    // the selection and the page are one surface) | stacked (icon over label, an underline that slides) |
    // inline (icon beside label, a pill that slides)
    property string style: "connected"
    readonly property bool connected: style === "connected"
    readonly property bool inline: style === "inline" || connected
    // the sheet the connected plate joins (the caller draws it right under the strip): its colour and its
    // horizontal extent in this item's coordinates, so the plate's fillets stop at its edges
    property color sheetColor: Theme.well
    property real sheetLeft: 0
    property real sheetRight: width
    // how far below the row the sheet begins (the plate reaches down to it)
    property real sheetGap: Metrics.s3
    // false: the caller draws the plate with its sheet as one shape (plateLeft/plateRight, plateRadius)
    property bool drawPlate: true
    signal picked(string id)

    implicitHeight: connected ? row.height + sheetGap : inline ? row.height : row.height + indicator.height + Metrics.s2 + separator.height

    // ── connected: one plate, the page's own surface, reaching up into the current tab ──
    // Its two edges move on their own clocks: the one leading the way arrives first, the trailing one follows,
    // so switching stretches the plate across and lets it settle into the new tab (continuity, not a blink).
    readonly property real plateRadius: Metrics.radiusPlate
    property real plateLeft: 0
    property real plateRight: 0
    property int shownIndex: -1
    // read from the source, not through indicator's bindings: a change handler can run before they update
    // connected layout: an icon's width for every tab, plus its name's for the current one; the row centred
    readonly property real iconSlot: Metrics.icon + Metrics.s4 * 2
    // each tab's name as measured, reported by the tabs themselves (repeater.itemAt is not something a binding
    // can follow, so a layout read through it stayed at its first, unmeasured answer)
    property var labelWidths: []
    function reportLabel(i: int, w: real): void {
        if (labelWidths[i] === w)
            return;
        const next = labelWidths.slice();
        next[i] = w;
        labelWidths = next;
        // a measurement is not a switch: the plate goes straight to where it belongs
        if (!leftMove.running && !rightMove.running)
            placePlate(false);
    }
    // the layout glides only once every name is measured: before that a change is the strip finding its
    // shape, not a switch to animate
    property bool settled: false
    function unfold(i: int): real {
        return showLabels ? (labelWidths[i] ?? 0) + Metrics.s2 : 0;
    }
    function tabWidthFor(j: int, cur: int): real {
        return iconSlot + (j === cur ? unfold(j) : 0);
    }
    function rowStartFor(cur: int): real {
        let total = 0;
        for (let j = 0; j < tabs.length; j++)
            total += tabWidthFor(j, cur);
        return Math.max(0, (width - total) / 2);
    }
    readonly property int currentIndex: tabs.findIndex(t => t.id === current)
    // where the row of tabs settles (connected: centred, so the strip has room either side of it)
    readonly property real rowLeft: connected ? rowStartFor(currentIndex) : 0
    readonly property real rowRight: {
        if (!connected)
            return width;
        let w = 0;
        for (let j = 0; j < tabs.length; j++)
            w += tabWidthFor(j, currentIndex);
        return rowLeft + w;
    }
    function slotWidth(): real {
        return width / Math.max(1, tabs.length);
    }
    // where tab i ends up when cur is current (read from the source, not through bindings: a change handler can
    // run before they update)
    function edgesFor(i: int): var {
        if (!connected)
            return [i * slotWidth() + Metrics.s1, (i + 1) * slotWidth() - Metrics.s1];
        let x = rowStartFor(i);
        for (let j = 0; j < i; j++)
            x += tabWidthFor(j, i);
        return [x, x + tabWidthFor(i, i)];
    }
    function placePlate(animate: bool): void {
        const i = tabs.findIndex(t => t.id === current);
        if (i < 0 || width <= 0)
            return;
        const e = edgesFor(i);
        const forward = i > shownIndex;
        if (!animate || shownIndex < 0 || Motion.reduced) {
            leftMove.stop();
            rightMove.stop();
            plateLeft = e[0];
            plateRight = e[1];
        } else {
            leftMove.to = e[0];
            rightMove.to = e[1];
            // the leading edge on the quick curve, the trailing one on the slow
            leftMove.duration = forward ? Motion.spatialSlow : Motion.spatialFast;
            rightMove.duration = forward ? Motion.spatialFast : Motion.spatialSlow;
            leftMove.restart();
            rightMove.restart();
        }
        shownIndex = i;
    }
    onCurrentChanged: placePlate(settled)
    onWidthChanged: placePlate(false)
    onTabsChanged: {
        settled = false;
        labelWidths = [];
        placePlate(false);
    }
    onLabelWidthsChanged: {
        if (!settled && tabs.length > 0 && labelWidths.length === tabs.length && !labelWidths.includes(undefined))
            Qt.callLater(() => settled = true);
    }
    Component.onCompleted: placePlate(false)
    NumberAnimation {
        id: leftMove
        target: root
        property: "plateLeft"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.spatialCurve
    }
    NumberAnimation {
        id: rightMove
        target: root
        property: "plateRight"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.spatialCurve
    }
    Item {
        id: plate
        visible: root.connected && root.drawPlate && indicator.i >= 0
        x: root.plateLeft
        width: Math.max(0, root.plateRight - root.plateLeft)
        height: root.height
        Rectangle {
            anchors.fill: parent
            color: root.sheetColor
            topLeftRadius: root.plateRadius
            topRightRadius: root.plateRadius
            bottomLeftRadius: 0
            bottomRightRadius: 0
        }
        // concave fillets where the plate meets the sheet, unless the plate is at the sheet's own edge
        ConcaveCorner {
            visible: plate.x - r >= root.sheetLeft - 0.5
            r: root.plateRadius
            fill: root.sheetColor
            solid: "br"
            x: -r
            y: plate.height - r
        }
        ConcaveCorner {
            visible: plate.x + plate.width + r <= root.sheetRight + 0.5
            r: root.plateRadius
            fill: root.sheetColor
            solid: "bl"
            x: plate.width
            y: plate.height - r
        }
    }

    // inline: the pill under the current tab, sliding between them
    Rectangle {
        id: pill
        visible: root.inline && !root.connected && indicator.i >= 0
        x: indicator.i * indicator.slot + 3
        width: indicator.slot - 6
        height: row.height
        radius: height / 2
        color: Theme.alpha(Theme.accent, 0.16)
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.35)
        Behavior on x {
            Anim {
                role: "spatial"
            }
        }
    }

    Row {
        id: row
        // connected: the tabs keep their own widths and the row is centred (and glides as it re-centres)
        x: root.connected ? root.rowStartFor(root.currentIndex) : 0
        width: root.connected ? implicitWidth : parent.width
        Behavior on x {
            enabled: root.connected && root.settled
            Anim {
                role: "spatial"
            }
        }
        Repeater {
            id: repeater
            model: root.tabs
            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool isCurrent: modelData.id === root.current
                readonly property real contentWidth: content.implicitWidth
                readonly property real labelWidth: nameMetrics.advanceWidth
                onLabelWidthChanged: root.reportLabel(index, labelWidth)
                Component.onCompleted: root.reportLabel(index, labelWidth)
                width: root.connected ? root.iconSlot + (tab.isCurrent ? root.unfold(tab.index) : 0) : (root.width / Math.max(1, root.tabs.length))
                Behavior on width {
                    enabled: root.connected && root.settled
                    Anim {
                        role: "spatial"
                    }
                }
                height: root.inline ? 34 : content.implicitHeight + Metrics.s3 * 2
                TextMetrics {
                    id: nameMetrics
                    font.family: Type.ui
                    font.pixelSize: Type.label
                    font.weight: Font.Medium
                    text: tab.modelData.label ?? tab.modelData.id
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    color: area.containsMouse && !tab.isCurrent ? Theme.hover : "transparent"
                    visible: !root.connected || !tab.isCurrent
                    radius: root.inline ? height / 2 : Metrics.radiusPlate
                    Behavior on color {
                        ColorAnim {}
                    }
                }
                // connected: the icon, and the name unfolding beside it (only the current tab's)
                Row {
                    visible: root.connected
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.s4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: tab.modelData.icon ?? ""
                        size: Metrics.icon
                        color: tab.isCurrent ? Theme.ink : Theme.inkMuted
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, tab.width - root.iconSlot - Metrics.s2 + Metrics.s4)
                        height: name.implicitHeight
                        clip: true
                        Label {
                            id: name
                            role: "label"
                            tone: "ink"
                            font.weight: Font.Medium
                            opacity: tab.isCurrent ? 1 : 0
                            Behavior on opacity {
                                Anim {
                                    role: "effects"
                                }
                            }
                            text: tab.modelData.label ?? tab.modelData.id
                        }
                    }
                }
                Grid {
                    id: content
                    visible: !root.connected
                    anchors.centerIn: parent
                    columns: root.inline ? 2 : 1
                    spacing: root.inline ? Metrics.s2 : 3
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Icon {
                        visible: root.showIcons
                        name: tab.modelData.icon ?? ""
                        size: root.inline ? 15 : 18
                        color: tab.isCurrent ? Theme.accent : Theme.inkMuted
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Label {
                        visible: root.showLabels
                        role: "label"
                        tone: tab.isCurrent ? "accent" : "muted"
                        text: tab.modelData.label ?? tab.modelData.id
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(tab.modelData.id)
                }
            }
        }
    }

    // the indicator: as wide as the current tab's content, sliding between tabs
    Rectangle {
        id: indicator
        visible: !root.inline && i >= 0
        readonly property int i: root.tabs.findIndex(t => t.id === root.current)
        readonly property Item tabItem: i >= 0 ? repeater.itemAt(i) : null
        readonly property real slot: row.width / Math.max(1, root.tabs.length)
        anchors.top: row.bottom
        anchors.topMargin: Metrics.s1
        width: tabItem ? Math.max(24, tabItem.contentWidth) : 0
        height: 3
        radius: 1.5
        x: i * slot + (slot - width) / 2
        color: Theme.accent
        Behavior on x {
            Anim {
                role: "spatial"
            }
        }
        Behavior on width {
            Anim {
                role: "spatial"
            }
        }
    }
    Rectangle {
        id: separator
        visible: !root.inline
        anchors.top: indicator.bottom
        anchors.topMargin: Metrics.s1
        width: parent.width
        height: Metrics.hairline
        color: Theme.hairline
    }
}
