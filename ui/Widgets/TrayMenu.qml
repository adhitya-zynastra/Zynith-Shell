import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Components

// An app's tray menu, drawn by the shell rather than by Qt's stock menu: a card that unfolds from the bar, its
// rows arriving one after another. One highlight glides to the row under the pointer (or the keys); a submenu
// slides in beside its parent within the same card, which grows or shrinks to fit, and a back row returns.
// Choosing an entry folds the card away. A click anywhere else dismisses it: on another app's window through the
// popup's grab, and on the shell's own surfaces (the desktop, the bars: the same client, so inside the grab)
// through a clear catcher laid over the screen while it is open.
// Keys (↑/↓ move, Enter or → opens, ← or Backspace back, Escape closes) apply when the popup has the keyboard;
// under niri a bar's popup does not get it, since bars take no keys.
PopupWindow {
    id: root

    // the bar it belongs to, and the edge it opens away from (top: it unfolds downwards)
    property var bar: null
    readonly property string edge: bar?.edge ?? "top"
    property real minWidth: 200
    property real maxWidth: 340

    // the open menus, outermost first: [{ handle, title }]
    property var stack: []
    readonly property int depth: stack.length - 1
    property bool folding: false
    // where the pointer was first seen over the menu (scene coordinates), and whether it has moved since: rows
    // sliding in under a resting pointer report hover moves without the pointer moving, and must not mark one
    property point restAt: Qt.point(-1, -1)
    property bool pointerLive: false
    function notePointer(item: Item, x: real, y: real): bool {
        if (pointerLive)
            return true;
        const p = item.mapToItem(null, x, y);
        if (restAt.x < 0) {
            restAt = p;
            return false;
        }
        pointerLive = Math.abs(p.x - restAt.x) + Math.abs(p.y - restAt.y) > 3;
        return pointerLive;
    }

    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real shadowRoom: 14
    readonly property real pad: Metrics.s1 + 2
    readonly property real rowHeight: 30

    function open(item: Item, handle: var): void {
        if (!handle)
            return;
        stack = [{ handle: handle, title: "" }];
        anchor.item = item;
        folding = false;
        restAt = Qt.point(-1, -1);
        pointerLive = false;
        unfold.value = 0;
        roomHeight = 0;
        visible = true;
        unfoldIn.restart();
    }
    function close(): void {
        if (!visible || folding)
            return;
        folding = true;
        if (Motion.exit === 0) {
            visible = false;
            return;
        }
        unfoldOut.restart();
    }
    function enter(entry: var): void {
        stack = stack.concat([{ handle: entry, title: entry.text }]);
    }
    function back(): void {
        if (depth > 0)
            stack = stack.slice(0, -1);
    }
    function choose(entry: var): void {
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren) {
            enter(entry);
            return;
        }
        entry.triggered();
        close();
    }

    anchor.edges: edge === "bottom" ? Edges.Top : edge === "left" ? Edges.Right : edge === "right" ? Edges.Left : Edges.Bottom
    anchor.gravity: anchor.edges
    anchor.margins.top: 6
    anchor.margins.bottom: 6
    anchor.margins.left: 6
    anchor.margins.right: 6
    grabFocus: true
    color: "transparent"
    visible: false
    onVisibleChanged: if (!visible) {
        stack = [];
        folding = false;
    }

    // the window keeps the largest page it has shown while open, so the card can shrink inside it without the
    // surface being resized under an animation
    property real roomHeight: 0
    readonly property real pageHeight: pages.currentHeight
    onPageHeightChanged: roomHeight = Math.max(roomHeight, pageHeight)
    implicitWidth: card.targetWidth + shadowRoom * 2
    implicitHeight: Math.max(roomHeight, pageHeight, rowHeight) + shadowRoom * 2

    ClickCatcher {
        active: root.visible && root.bar !== null
        screen: root.bar?.screen ?? null
        onCaught: root.close()
    }

    // 0 → 1 as the card unfolds from the bar
    QtObject {
        id: unfold
        property real value: 0
    }
    NumberAnimation {
        id: unfoldIn
        target: unfold
        property: "value"
        to: 1
        duration: Motion.enter
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.spatialFastCurve
    }
    NumberAnimation {
        id: unfoldOut
        target: unfold
        property: "value"
        to: 0
        duration: Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.exitCurve
        onFinished: root.visible = false
    }

    Item {
        id: card
        readonly property real targetWidth: Math.round(Math.max(root.minWidth, Math.min(root.maxWidth, pages.currentWidth)))
        readonly property bool fromBelow: root.edge === "bottom"
        x: root.shadowRoom + (root.edge === "right" ? (1 - unfold.value) * 12 : root.edge === "left" ? -(1 - unfold.value) * 12 : 0)
        y: fromBelow ? parent.height - root.shadowRoom - height : root.shadowRoom
        width: targetWidth
        // the card grows out of the bar edge; a page change resizes it on the spatial curve
        height: Math.max(0, shownHeight * (root.vertical ? 1 : unfold.value))
        opacity: root.vertical ? unfold.value : Math.min(1, unfold.value * 3)
        property real shownHeight: root.pageHeight
        Behavior on shownHeight {
            enabled: root.visible && unfold.value === 1
            NumberAnimation {
                duration: Motion.spatialFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spatialFastCurve
            }
        }
        Behavior on width {
            enabled: root.visible && unfold.value === 1
            NumberAnimation {
                duration: Motion.spatialFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spatialFastCurve
            }
        }

        Glass {
            anchors.fill: parent
            radius: Metrics.radiusMd + 2
            raised: true
        }

        Item {
            anchors.fill: parent
            clip: true

            // the pages side by side; the strip slides so the deepest open one shows
            Item {
                id: pages
                // the page on show registers itself (Repeater.itemAt is not a binding)
                property Item current: null
                readonly property real currentHeight: current ? current.implicitHeight : root.rowHeight + root.pad * 2
                readonly property real currentWidth: current ? current.naturalWidth : root.minWidth
                width: card.width
                height: parent.height
                // anchored to the edge the card unfolds from, so rows appear in place as it grows
                y: card.fromBelow ? parent.height - currentHeight : 0
                x: -root.depth * card.width
                Behavior on x {
                    enabled: root.visible
                    NumberAnimation {
                        duration: Motion.spatialFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spatialFastCurve
                    }
                }

                Repeater {
                    id: strip
                    model: root.stack
                    delegate: Page {
                        required property var modelData
                        required property int index
                        x: index * card.width
                        width: card.width
                        handle: modelData.handle
                        title: modelData.title
                        current: index === root.depth
                    }
                }
            }
        }
    }

    // one menu level: its rows, the gliding highlight, and its keys
    component Page: FocusScope {
        id: page
        property var handle: null
        property string title: ""
        property bool current: false
        // the row under the pointer or the keys; -1 for none
        property int cursor: -1
        readonly property bool nested: title !== ""
        readonly property var entries: opener.children?.values ?? []
        implicitHeight: column.implicitHeight + root.pad * 2
        // the width the widest row asks for
        readonly property real naturalWidth: Array.from(column.children).reduce((w, c) => Math.max(w, c.naturalWidth ?? 0), 0) + root.pad * 2
        focus: current
        function claim(): void {
            if (!current)
                return;
            pages.current = page;
            forceActiveFocus();
        }
        onCurrentChanged: claim()
        Component.onCompleted: claim()

        QsMenuOpener {
            id: opener
            menu: page.handle
        }

        function step(by: int): void {
            const n = entries.length;
            if (n === 0)
                return;
            let i = cursor;
            for (let k = 0; k < n; k++) {
                i = ((i + by) % n + n) % n;
                if (!entries[i].isSeparator && entries[i].enabled) {
                    cursor = i;
                    return;
                }
            }
        }
        Keys.onUpPressed: step(-1)
        Keys.onDownPressed: step(1)
        Keys.onReturnPressed: if (cursor >= 0)
            root.choose(entries[cursor])
        Keys.onEnterPressed: if (cursor >= 0)
            root.choose(entries[cursor])
        Keys.onRightPressed: if (cursor >= 0 && entries[cursor].hasChildren)
            root.enter(entries[cursor])
        Keys.onLeftPressed: root.back()
        Keys.onEscapePressed: nested ? root.back() : root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace && nested) {
                root.back();
                event.accepted = true;
            }
        }

        // the highlight: one plate that glides to the row it marks
        Rectangle {
            id: lens
            readonly property Item target: page.cursor >= 0 ? rows.itemAt(page.cursor) : (backRow.hovered ? backRow : null)
            property Item last: null
            onTargetChanged: if (target)
                last = target
            x: root.pad
            width: page.width - root.pad * 2
            y: last ? last.mapToItem(page, 0, 0).y : root.pad
            height: last ? last.height : root.rowHeight
            radius: Metrics.radiusSm + 2
            color: Theme.hover
            opacity: target ? 1 : 0
            Behavior on y {
                enabled: lens.opacity > 0
                NumberAnimation {
                    duration: Motion.spatialFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spatialFastCurve
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.focus
                }
            }
            // a sliver of accent on its leading edge
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 3
                width: 2
                height: parent.height * 0.5
                radius: 1
                color: Theme.accent
            }
        }

        Column {
            id: column
            x: root.pad
            y: root.pad
            width: page.width - root.pad * 2

            Item {
                id: backRow
                visible: page.nested
                readonly property bool hovered: backArea.containsMouse
                readonly property real naturalWidth: visible ? backLine.implicitWidth : 0
                width: parent.width
                height: visible ? root.rowHeight : 0
                Row {
                    id: backLine
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s2
                    leftPadding: Metrics.s3
                    rightPadding: Metrics.s3
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-left"
                        size: 14
                        color: Theme.inkMuted
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        tone: "muted"
                        text: page.title.replace(/_(?!_)/g, "")
                    }
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }
            Rectangle {
                visible: page.nested
                width: parent.width
                height: visible ? 1 : 0
                color: Theme.alpha(Theme.ink, 0.08)
            }

            Repeater {
                id: rows
                model: opener.children
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool separator: modelData.isSeparator
                    readonly property bool checkable: modelData.buttonType !== QsMenuButtonType.None
                    readonly property bool checked: modelData.checkState === Qt.Checked
                    readonly property bool radio: modelData.buttonType === QsMenuButtonType.RadioButton
                    // mark, gap, text, and the submenu chevron, with the row's padding
                    readonly property real naturalWidth: separator ? 0 : Metrics.s3 * 2 + 18 + Metrics.s2 + text.implicitWidth + (modelData.hasChildren ? Metrics.s2 + 14 : 0)
                    width: column.width
                    height: separator ? 9 : root.rowHeight
                    opacity: (modelData.enabled || separator ? 1 : 0.4) * arrive
                    // each row arrives a beat after the one before it, rising into place
                    property real arrive: 0
                    transform: Translate {
                        y: (1 - row.arrive) * (card.fromBelow ? 6 : -6)
                    }
                    SequentialAnimation on arrive {
                        running: true
                        PauseAnimation {
                            duration: page.current && root.depth === 0 ? Math.min(8, row.index) * (Motion.enter > 0 ? 18 : 0) : 0
                        }
                        NumberAnimation {
                            to: 1
                            duration: Motion.contentIn
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.enterCurve
                        }
                    }

                    // a separator is a hairline across the row
                    Rectangle {
                        visible: row.separator
                        anchors.verticalCenter: parent.verticalCenter
                        x: Metrics.s3
                        width: parent.width - Metrics.s3 * 2
                        height: 1
                        color: Theme.alpha(Theme.ink, 0.08)
                    }

                    // a check or radio mark, else the entry's own icon
                    Item {
                        id: mark
                        visible: !row.separator
                        x: Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        IconImage {
                            anchors.fill: parent
                            visible: !row.checkable && source !== ""
                            source: row.checkable ? "" : (row.modelData.icon ?? "")
                            asynchronous: true
                        }
                        Rectangle {
                            visible: row.checkable
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            radius: row.radio ? 7 : 4
                            color: row.checked ? Theme.accent : "transparent"
                            border.width: row.checked ? 0 : 1.5
                            border.color: Theme.alpha(Theme.ink, 0.35)
                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.focus
                                }
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: row.checked && !row.radio
                                name: "check"
                                size: 11
                                color: Theme.onAccent
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: row.checked && row.radio
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.onAccent
                            }
                        }
                    }
                    Label {
                        id: text
                        visible: !row.separator
                        anchors.left: mark.right
                        anchors.leftMargin: Metrics.s2
                        anchors.right: chevron.visible ? chevron.left : parent.right
                        anchors.rightMargin: chevron.visible ? Metrics.s2 : Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        role: "label"
                        elide: Text.ElideRight
                        // menus mark their mnemonics with an underscore
                        text: (row.modelData.text ?? "").replace(/_(?!_)/g, "")
                    }
                    Icon {
                        id: chevron
                        visible: !row.separator && row.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.s3
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-right"
                        size: 14
                        color: Theme.inkMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !row.separator
                        hoverEnabled: true
                        cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        // the pointer marks a row once it moves over it (a menu opening under a resting pointer
                        // marks nothing)
                        onPositionChanged: mouse => {
                            if (root.notePointer(this, mouse.x, mouse.y) && row.modelData.enabled)
                                page.cursor = row.index;
                        }
                        onExited: if (page.cursor === row.index)
                            page.cursor = -1
                        onClicked: root.choose(row.modelData)
                    }
                }
            }
        }
    }
}
