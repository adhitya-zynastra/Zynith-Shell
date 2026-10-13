import QtQuick
import qs.Common
import qs.Services

// A row of tabs across the top of a surface, with one indicator that slides to the current tab (Caelestia's
// dashboard tabs). Which tabs and in what order is the caller's (from config); each is { id, label, icon }.
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
    function slotWidth(): real {
        return width / Math.max(1, tabs.length);
    }
    function edgesFor(i: int): var {
        const inset = Metrics.s1;
        return [i * slotWidth() + inset, (i + 1) * slotWidth() - inset];
    }
    function placePlate(animate: bool): void {
        const i = tabs.findIndex(t => t.id === current);
        if (i < 0 || slotWidth() <= 0)
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
    onCurrentChanged: placePlate(true)
    onWidthChanged: placePlate(false)
    onTabsChanged: placePlate(false)
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
        width: parent.width
        Repeater {
            id: repeater
            model: root.tabs
            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool isCurrent: modelData.id === root.current
                readonly property real contentWidth: content.implicitWidth
                width: row.width / Math.max(1, root.tabs.length)
                height: root.inline ? 34 : content.implicitHeight + Metrics.s3 * 2

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
                Grid {
                    id: content
                    anchors.centerIn: parent
                    columns: root.inline ? 2 : 1
                    spacing: root.inline ? Metrics.s2 : 3
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    Icon {
                        visible: root.showIcons
                        name: tab.modelData.icon ?? ""
                        size: root.inline ? 15 : 18
                        color: tab.isCurrent ? (root.connected ? Theme.ink : Theme.accent) : Theme.inkMuted
                        Behavior on color {
                            ColorAnim {}
                        }
                    }
                    Label {
                        visible: root.showLabels
                        role: "label"
                        tone: tab.isCurrent ? (root.connected ? "ink" : "accent") : "muted"
                        font.weight: tab.isCurrent && root.connected ? Font.Medium : Font.Normal
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
