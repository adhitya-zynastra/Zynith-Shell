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
            } else if (root.accordion) {
                closer.restart();
            }
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

    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        visible: group?.enabled !== false
        color: Theme.alpha(Theme.colour(root.group?.fill ?? "surface_variant"), root.group?.opacity ?? 0.5)
        border.width: (root.group?.border ?? "") !== "" ? 1 : 0
        border.color: Theme.colour(root.group?.border ?? "outline")
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
