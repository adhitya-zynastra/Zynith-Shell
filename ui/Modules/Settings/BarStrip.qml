import QtQuick
import qs.Common
import qs.Components
import qs.Services
import "../../Common/BarModel.js" as BarModel

// The bar's components as they sit on it, in its own direction: three regions (Start, Center, End — on a vertical
// bar Top, Middle, Bottom), each holding components and groups. A group is drawn as what it is: a named
// container round its members.
//   Click: select (Ctrl / Shift click: pick several, then Group). Drag: move — between components to place it there,
//   onto a component to group the two, into a group to join it. Keys: arrows select, Ctrl+arrows move,
//   G groups the picked, Delete removes.
FocusScope {
    id: strip

    required property var page
    readonly property bool vertical: page.vertical
    readonly property var bar: page.bar ?? ({})
    implicitWidth: vertical ? 132 : parent?.width ?? 600
    implicitHeight: vertical ? body.implicitHeight : header.height + body.height

    function regionLabel(s: string): string {
        if (s === "center")
            return vertical ? "Middle" : "Center";
        return vertical ? (s === "start" ? "Top" : "Bottom") : (s === "start" ? "Start · left" : "End · right");
    }

    // ── the drop target under a point (strip coordinates), as the page's drag asks ──
    // { section, index } insert there · { group, index } into a group · { merge: { section, index } } group with it
    function targetAt(px: real, py: real): var {
        for (let z = 0; z < 3; z++) {
            const region = box.regions[z];
            const rp = region.mapFromItem(strip, px, py);
            const inside = vertical ? (rp.y >= -8 && rp.y <= region.height + 8 && px >= -40 && px <= strip.width + 40) : (rp.x >= -8 && rp.x <= region.width + 8 && py >= -40 && py <= strip.height + 40);
            if (!inside)
                continue;
            const tiles = region.tiles();
            const along = vertical ? rp.y : rp.x;
            for (let i = 0; i < tiles.length; i++) {
                const t = tiles[i];
                const tp = t.mapFromItem(strip, px, py);
                const a = vertical ? tp.y : tp.x, len = vertical ? t.height : t.width;
                const within = tp.x >= 0 && tp.y >= 0 && tp.x <= t.width && tp.y <= t.height;
                if (t.isGroup && within && !strip.page.draggingGroup())
                    return { group: t.gid, index: t.memberIndexAt(t.mapToItem(t.membersItem, tp.x, tp.y)) };
                if (!t.isGroup && within && a > len * 0.28 && a < len * 0.72 && strip.page.canMergeWith(region.section, t.entryIndex))
                    return { merge: { section: region.section, index: t.entryIndex } };
            }
            let index = 0;
            for (let i = 0; i < tiles.length; i++) {
                const c = tiles[i].mapToItem(region, tiles[i].width / 2, tiles[i].height / 2);
                if ((vertical ? c.y : c.x) < along)
                    index = i + 1;
            }
            return { section: region.section, index: index };
        }
        return null;
    }
    readonly property var hover: page.dragging ? targetAt(page.dragPoint.x - strip.mapToItem(page, 0, 0).x, page.dragPoint.y - strip.mapToItem(page, 0, 0).y) : null

    // ── keys ──
    Keys.onPressed: event => page.stripKey(event)

    Row {
        id: header
        visible: !strip.vertical
        width: parent.width
        height: visible ? 22 : 0
        Repeater {
            model: BarModel.sections
            delegate: Label {
                required property string modelData
                required property int index
                width: header.width / 3
                horizontalAlignment: index === 0 ? Text.AlignLeft : index === 1 ? Text.AlignHCenter : Text.AlignRight
                role: "micro"
                caps: true
                tone: strip.hover && strip.hover.section === modelData ? "accent" : "faint"
                text: strip.regionLabel(modelData)
            }
        }
    }

    // the bar itself, as a long sheet holding the three regions
    Rectangle {
        id: body
        y: header.height
        width: parent.width
        height: box.implicitHeight + Metrics.s3 * 2
        implicitHeight: height
        radius: Metrics.radiusLg
        color: Theme.well
        border.width: strip.activeFocus ? 2 : 1
        border.color: strip.activeFocus ? Theme.focus : Theme.hairline

        // the three regions: side by side on a horizontal bar (a third each), stacked on a vertical one (each as
        // tall as what it holds)
        Grid {
            id: box
            x: strip.vertical ? Metrics.s2 : Metrics.s3
            y: Metrics.s3
            width: parent.width - x * 2
            columns: strip.vertical ? 1 : 3
            readonly property real tallest: Math.max(64, r0.need, r1.need, r2.need)
            readonly property var regions: [r0, r1, r2]
            Region {
                id: r0
                section: "start"
                width: strip.vertical ? box.width : box.width / 3
                height: strip.vertical ? Math.max(84, need) : box.tallest
            }
            Region {
                id: r1
                section: "center"
                width: strip.vertical ? box.width : box.width / 3
                height: strip.vertical ? Math.max(84, need) : box.tallest
            }
            Region {
                id: r2
                section: "end"
                width: strip.vertical ? box.width : box.width / 3
                height: strip.vertical ? Math.max(84, need) : box.tallest
            }
        }
        // the regions' borders: thin rules, so three places read as three
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                color: Theme.hairline
                readonly property var next: box.regions[index + 1]
                x: strip.vertical ? Metrics.s3 : box.x + box.width / 3 * (index + 1)
                y: strip.vertical ? box.y + next.y : Metrics.s3
                width: strip.vertical ? body.width - Metrics.s3 * 2 : 1
                height: strip.vertical ? 1 : body.height - Metrics.s3 * 2
            }
        }
    }

    // ── one region: its entries, aligned as the bar aligns them ──
    component Region: Item {
        id: region
        property string section
        objectName: "region-" + section
        readonly property var entries: BarModel.list(strip.bar.widgets?.[section])
        readonly property bool targeted: strip.hover !== null && strip.hover.section === section
        // the room its entries take (and the label on a vertical bar)
        readonly property real need: strip.vertical ? flow.childrenRect.height + 26 : flow.childrenRect.height + 8
        function tiles(): var {
            const out = [];
            for (let i = 0; i < tileRepeater.count; i++)
                out.push(tileRepeater.itemAt(i));
            return out;
        }
        Rectangle {
            anchors.fill: parent
            radius: Metrics.radiusMd
            color: region.targeted ? Theme.alpha(Theme.accent, 0.07) : "transparent"
        }
        Label {
            visible: strip.vertical
            x: Metrics.s1
            y: 0
            role: "micro"
            caps: true
            tone: region.targeted ? "accent" : "faint"
            text: strip.regionLabel(region.section)
        }
        Label {
            visible: region.entries.length === 0 && !strip.page.dragging
            anchors.centerIn: parent
            width: parent.width - Metrics.s3
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            role: "caption"
            tone: "faint"
            text: "Empty"
        }
        Flow {
            id: flow
            readonly property real used: strip.vertical ? implicitHeight : childrenRect.width
            // start packs to the start, center to the middle, end to the end — as on the bar
            // start packs to its start, center to the middle, end to its end — as on the bar (order kept)
            x: strip.vertical ? (parent.width - width) / 2 : region.section === "start" ? 0 : region.section === "center" ? (parent.width - childrenRect.width) / 2 : parent.width - childrenRect.width - Metrics.s1
            y: strip.vertical ? 20 : (parent.height - childrenRect.height) / 2
            width: strip.vertical ? Math.min(parent.width, 116) : parent.width - Metrics.s1
            flow: strip.vertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: Metrics.s2
            Repeater {
                id: tileRepeater
                model: region.entries
                delegate: Entry {
                    required property string modelData
                    required property int index
                    name: modelData
                    section: region.section
                    entryIndex: index
                }
            }
        }
        // where a dragged component will go
        Rectangle {
            visible: region.targeted && strip.hover.index !== undefined
            readonly property var tiles: region.tiles()
            readonly property var anchorTile: tiles.length === 0 ? null : tiles[Math.min(strip.hover?.index ?? 0, tiles.length - 1)]
            readonly property bool after: (strip.hover?.index ?? 0) >= tiles.length
            readonly property point at: anchorTile ? anchorTile.mapToItem(region, after ? anchorTile.width : 0, after ? anchorTile.height : 0) : Qt.point(region.width / 2, region.height / 2)
            color: Theme.accent
            radius: 1.5
            width: strip.vertical ? Math.min(region.width - 8, 100) : 3
            height: strip.vertical ? 3 : Math.min(region.height, 52)
            x: strip.vertical ? (region.width - width) / 2 : (anchorTile ? (after ? at.x + 2 : at.x - Metrics.s2 / 2 - 1.5) : region.width / 2 - 1.5)
            y: strip.vertical ? (anchorTile ? (after ? at.y + 2 : at.y - Metrics.s2 / 2 - 1.5) : region.height / 2 - 1.5) : (region.height - height) / 2
        }
    }

    // ── one entry: a component, or a group with its members ──
    component Entry: Loader {
        id: entry
        property string name
        property string section
        property int entryIndex
        readonly property bool isGroup: name.startsWith("group:")
        readonly property string gid: isGroup ? name.slice(6) : ""
        readonly property var membersItem: item?.membersItem ?? null
        function memberIndexAt(p: point): int {
            return item?.memberIndexAt ? item.memberIndexAt(p) : 0;
        }
        sourceComponent: isGroup ? groupTile : componentTile
        Component {
            id: componentTile
            Tile {
                name: entry.name
                at: ({ section: entry.section, index: entry.entryIndex })
            }
        }
        Component {
            id: groupTile
            GroupTile {
                gid: entry.gid
                at: ({ section: entry.section, index: entry.entryIndex })
            }
        }
    }

    // a component
    component Tile: Rectangle {
        id: tile
        property string name
        property var at
        readonly property var info: BarWidgetTypes.find(BarModel.typeOf(strip.page.state, name))
        readonly property bool selected: strip.page.isSelected(at)
        readonly property bool picked: strip.page.isPicked(at)
        readonly property bool mergeTarget: strip.hover?.merge !== undefined && at.group === undefined && strip.hover.merge.section === at.section && strip.hover.merge.index === at.index
        readonly property bool dragged: strip.page.dragging && strip.page.dragFrom !== null && JSON.stringify(strip.page.dragFrom) === JSON.stringify(at)
        objectName: "entry-" + name
        width: strip.vertical ? 104 : 74
        height: strip.vertical ? 44 : 56
        radius: Metrics.radiusMd
        color: mergeTarget ? Theme.accentSoft : picked ? Theme.alpha(Theme.accent, 0.16) : selected ? Theme.selected : tileArea.containsMouse ? Theme.hover : Theme.plate
        border.width: selected || mergeTarget ? 2 : picked ? 1 : 0
        border.color: Theme.accent
        opacity: dragged ? 0.4 : 1
        Behavior on color {
            ColorAnim {}
        }
        Icon {
            id: tileIcon
            x: strip.vertical ? Metrics.s3 : (parent.width - width) / 2
            y: strip.vertical ? (parent.height - height) / 2 : Metrics.s3
            name: tile.info?.icon ?? "help"
            size: 18
            tone: tile.info ? (tile.selected ? "accent" : "ink") : "danger"
        }
        Label {
            x: strip.vertical ? tileIcon.x + tileIcon.width + Metrics.s2 : Metrics.s1
            y: strip.vertical ? (parent.height - height) / 2 : tileIcon.y + tileIcon.height + Metrics.s1
            width: strip.vertical ? parent.width - x - Metrics.s2 : parent.width - Metrics.s1 * 2
            horizontalAlignment: strip.vertical ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
            role: "caption"
            tone: tile.selected ? "ink" : "muted"
            text: tile.info?.label ?? ("Unknown: " + tile.name)
        }
        Label {
            visible: tile.mergeTarget
            anchors.bottom: parent.top
            anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            role: "micro"
            tone: "accent"
            text: "Group with this"
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: strip.page.dragProxy
            drag.threshold: 6
            onPressed: mouse => strip.page.pressEntry(tile, tile.at, mouse.modifiers)
            onPositionChanged: mouse => {
                if (drag.active)
                    strip.page.dragMove(tile, mouse.x, mouse.y, tile.at, tile.info?.icon ?? "", tile.info?.label ?? "");
            }
            onReleased: strip.page.dragRelease()
            onClicked: mouse => {
                strip.forceActiveFocus();
                strip.page.clickEntry(tile.at, mouse.modifiers);
            }
        }
    }

    // a group: a container round its members, its name on it
    component GroupTile: Rectangle {
        id: group
        property string gid
        property var at
        readonly property var spec: BarModel.groupById(strip.bar, gid) ?? BarModel.list(Config.barGroups).find(g => g.id === gid) ?? null
        readonly property var members: BarModel.list(spec?.members)
        readonly property bool selected: strip.page.isSelected(at)
        readonly property bool targeted: strip.hover?.group === gid
        readonly property alias membersItem: memberFlow
        objectName: "group-" + gid
        function memberIndexAt(p: point): int {
            let index = 0;
            for (let i = 0; i < memberRepeater.count; i++) {
                const m = memberRepeater.itemAt(i);
                if ((strip.vertical ? m.y + m.height / 2 : m.x + m.width / 2) < (strip.vertical ? p.y : p.x))
                    index = i + 1;
            }
            return index;
        }
        width: strip.vertical ? 116 : Math.max(96, memberFlow.childrenRect.width + Metrics.s2 * 2)
        height: strip.vertical ? Math.max(64, memberFlow.childrenRect.height + 22 + Metrics.s2) : 74
        radius: Metrics.radiusLg
        color: targeted ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.accent, 0.06)
        border.width: selected || targeted ? 2 : 1
        border.color: selected || targeted ? Theme.accent : Theme.accentLine
        // its name: the handle that selects and drags the whole group
        Rectangle {
            id: nameTab
            x: Metrics.s2
            y: 3
            width: Math.min(parent.width - Metrics.s2 * 2, nameLabel.implicitWidth + 22)
            height: 16
            radius: 8
            color: group.selected ? Theme.accent : Theme.accentSoft
            Icon {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                name: "layers-intersect"
                size: 10
                tone: group.selected ? "onAccent" : "accent"
            }
            Label {
                id: nameLabel
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                elide: Text.ElideRight
                role: "micro"
                color: group.selected ? Theme.onAccent : Theme.accent
                text: group.spec?.name ?? ("Group " + group.gid)
            }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: strip.page.dragProxy
            drag.threshold: 6
            onPressed: mouse => strip.page.pressEntry(group, group.at, mouse.modifiers)
            onPositionChanged: mouse => {
                if (drag.active)
                    strip.page.dragMove(group, mouse.x, mouse.y, group.at, "layers-intersect", group.spec?.name ?? "Group");
            }
            onReleased: strip.page.dragRelease()
            onClicked: mouse => {
                strip.forceActiveFocus();
                strip.page.clickEntry(group.at, mouse.modifiers);
            }
        }
        Flow {
            id: memberFlow
            x: Metrics.s2
            y: 22
            width: strip.vertical ? parent.width - Metrics.s2 * 2 : childrenRect.width
            flow: strip.vertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: Metrics.s1
            Repeater {
                id: memberRepeater
                model: group.members
                delegate: Tile {
                    required property string modelData
                    required property int index
                    name: modelData
                    at: ({ group: group.gid, index: index })
                    width: strip.vertical ? 100 : 62
                    height: strip.vertical ? 34 : 46
                }
            }
        }
        // where a dragged component joins it
        Rectangle {
            visible: group.targeted
            readonly property int i: strip.hover?.index ?? 0
            readonly property var m: memberRepeater.count === 0 ? null : memberRepeater.itemAt(Math.min(i, memberRepeater.count - 1))
            readonly property bool after: i >= memberRepeater.count
            color: Theme.accent
            radius: 1.5
            width: strip.vertical ? 90 : 3
            height: strip.vertical ? 3 : 40
            x: strip.vertical ? memberFlow.x + 4 : memberFlow.x + (m ? (after ? m.x + m.width + 1 : m.x - 3) : 0)
            y: strip.vertical ? memberFlow.y + (m ? (after ? m.y + m.height + 1 : m.y - 3) : 0) : memberFlow.y + 3
        }
    }
}
