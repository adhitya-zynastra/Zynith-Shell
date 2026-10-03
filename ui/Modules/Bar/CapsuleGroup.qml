import QtQuick
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets

// Several widgets in one capsule. An accordion shows its first member and opens towards `direction` while
// the pointer rests on it, closing a moment after it leaves.
Item {
    id: root

    required property var bar
    required property var group
    readonly property var members: group?.members ?? []
    readonly property bool accordion: group?.accordion === true
    readonly property bool vertical: bar.vertical
    readonly property real pad: group?.padding ?? 8
    readonly property real gap: group?.widget_spacing ?? group?.spacing ?? Metrics.s1

    property bool open: !accordion
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                closer.stop();
                root.open = true;
            } else {
                root.rested = false;
                if (root.accordion)
                    closer.restart();
            }
        }
    }
    // resting anywhere on the group runs the hover gesture of the member that has one (the clock, say)
    function hoverMember(): var {
        for (let i = 0; i < list.count; i++) {
            const it = list.itemAt(i)?.item;
            if (it && it.hoverAction !== "")
                return it;
        }
        return null;
    }
    property bool rested: false
    Timer {
        interval: Math.max(0, root.hoverMember()?.opt("hover_delay") ?? 350)
        running: hover.hovered && !root.rested && root.hoverMember() !== null
        onTriggered: {
            root.rested = true;
            const m = root.hoverMember();
            if (m && !m.hoverOpened)
                m.restOpen();
        }
    }
    Timer {
        id: closer
        interval: 700
        onTriggered: root.open = false
    }

    // the members laid out; closed, only the first takes room
    readonly property real firstLength: list.count > 0 && list.itemAt(0) ? (vertical ? list.itemAt(0).height : list.itemAt(0).width) : 0
    readonly property real fullLength: vertical ? grid.implicitHeight : grid.implicitWidth
    property real shownLength: open ? fullLength : firstLength
    Behavior on shownLength {
        Anim {
            role: "spatial"
        }
    }

    implicitWidth: vertical ? bar.thickness - 6 : shownLength + pad * 2
    implicitHeight: vertical ? shownLength + pad * 2 : bar.thickness - 6
    clip: true

    // capsule (a filled pill) · plate (a tone step) · rule (no box: a hairline tick at each end, so a bar
    // reads as one surface with its groups set apart by space and rule)
    readonly property string look: group?.style ?? bar.groupStyle ?? "capsule"
    Rectangle {
        anchors.fill: parent
        radius: root.look === "plate" ? Metrics.radiusPlate : Math.min(width, height) / 2
        visible: group?.enabled !== false && root.look !== "rule"
        color: root.look === "plate" ? Theme.plate : Theme.alpha(Theme.colour(root.group?.fill ?? "surface_variant"), root.group?.opacity ?? 0.5)
        border.width: (root.group?.border ?? "") !== "" ? 1 : 0
        border.color: Theme.colour(root.group?.border ?? "outline")
    }
    // the rule look: a soft wash only while the pointer is in the group (an accordion is opening)
    Rectangle {
        anchors.fill: parent
        visible: root.look === "rule"
        radius: Math.min(width, height) / 2
        color: hover.hovered ? Theme.hover : "transparent"
        Behavior on color {
            ColorAnim {}
        }
    }
    Repeater {
        model: root.look === "rule" && group?.enabled !== false ? [0, 1] : []
        delegate: Rectangle {
            required property int modelData
            readonly property real across: (root.vertical ? root.width : root.height) * 0.38
            x: root.vertical ? (root.width - across) / 2 : (modelData === 0 ? 0 : root.width - 1)
            y: root.vertical ? (modelData === 0 ? 0 : root.height - 1) : (root.height - across) / 2
            width: root.vertical ? across : 1
            height: root.vertical ? 1 : across
            color: Theme.rule
        }
    }

    Grid {
        id: grid
        x: root.vertical ? (root.width - width) / 2 : root.pad
        y: root.vertical ? root.pad : (root.height - height) / 2
        columns: root.vertical ? 1 : Math.max(1, root.members.length)
        spacing: root.gap
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            id: list
            model: root.members
            delegate: BarWidget {
                required property string modelData
                required property int index
                bar: root.bar
                name: modelData
                // the hidden members fade as the accordion closes over them
                opacity: index === 0 || root.open ? 1 : 0
                Behavior on opacity {
                    Anim {
                        role: "effects"
                    }
                }
            }
        }
    }
}
