import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Open windows as app icons (and titles if asked), in their workspaces' order; pinned apps wait at the
// front, dimmed, until they run. Left click focuses (or launches a pinned app), middle click closes —
// reserved; the wheel cycles windows (its actions). Grouped by workspace (group_by_workspace): each
// workspace a group — its apps' icons or a count, in a capsule if asked, labelled in the corner or the
// middle, empty ones hidden if asked — coloured focused / occupied / empty / urgent as the native taskbar.
// taskbar_max_width caps its length; past it the strip scrolls to keep the focused window in view.
BarItem {
    id: root

    // asked again when the windows' shape or focus changes; titles only matter when they are shown
    readonly property var windows: {
        NiriState.windowsRevision;
        NiriState.focusedId;
        if (opt("show_window_title") === true)
            NiriState.focusedWindow;
        return NiriState.windowList();
    }
    readonly property var spaces: Workspaces.forScreen(screen, opt("show_all_outputs") === true)
    readonly property var activeSpace: spaces.find(w => w.active)
    readonly property var shownWindows: {
        const ids = spaces.map(s => s.key);
        let list = windows.filter(w => ids.includes(w.workspaceId));
        if (opt("only_active_workspace") === true && activeSpace)
            list = list.filter(w => w.workspaceId === activeSpace.key);
        // workspace order, then as niri lists them
        list.sort((a, b) => ids.indexOf(a.workspaceId) - ids.indexOf(b.workspaceId));
        if (opt("group_single_icon_per_app") === true) {
            const seen = new Set();
            list = list.filter(w => !seen.has(w.workspaceId + "/" + w.appId) && seen.add(w.workspaceId + "/" + w.appId));
        }
        return list;
    }
    readonly property var pinnedApps: (opt("pinned") ?? []).filter(id => !windows.some(w => w.appId === id))
    shown: (shownWindows.length > 0 || pinnedApps.length > 0) && !(opt("focused_output_only") === true && Workspaces.focusedOutput !== (screen?.name ?? ""))
    spacing: opt("item_spacing") ?? 4

    function iconFor(appId: string): string {
        const entry = DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(entry?.icon ?? appId, true);
    }
    readonly property real iconSize: 16 * (opt("icon_scale") ?? 1) * sizeScale

    readonly property bool grouped: opt("group_by_workspace") === true
    readonly property string groupContent: opt("workspace_group_content") ?? "icons"
    // the workspaces as groups, each with its windows (empty ones too, unless hidden)
    readonly property var groups: {
        if (!grouped)
            return [];
        let list = spaces.map(s => ({
                    space: s,
                    windows: shownWindows.filter(w => w.workspaceId === s.key)
                }));
        if (opt("only_active_workspace") === true && activeSpace)
            list = list.filter(g => g.space.key === activeSpace.key);
        if (opt("hide_empty_workspaces") === true)
            list = list.filter(g => g.windows.length > 0);
        return list;
    }
    function spaceColour(space: var, count: int): color {
        if (space.urgent)
            return Theme.colour(opt("urgent_color") ?? "error");
        if (space.active)
            return Theme.colour(opt("focused_color") ?? "primary");
        return Theme.colour(count > 0 ? (opt("occupied_color") ?? "secondary") : (opt("empty_color") ?? "secondary"));
    }
    readonly property real maxLength: Math.max(32, opt("taskbar_max_width") ?? 8192)
    readonly property Item stripRef: strip

    // the strip: capped at taskbar_max_width, scrolling past it (the wheel, or to follow focus)
    Flickable {
        id: strip
        readonly property real full: root.vertical ? content.implicitHeight : content.implicitWidth
        width: root.vertical ? content.implicitWidth : Math.min(full, root.maxLength)
        height: root.vertical ? Math.min(full, root.maxLength) : content.implicitHeight
        contentWidth: content.implicitWidth
        contentHeight: content.implicitHeight
        clip: full > root.maxLength
        interactive: full > root.maxLength
        flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        // the focused window kept in view
        function follow(item: Item): void {
            if (!item || !interactive)
                return;
            const p = item.mapToItem(content, 0, 0);
            if (root.vertical)
                contentY = Math.max(0, Math.min(contentHeight - height, p.y + item.height / 2 - height / 2));
            else
                contentX = Math.max(0, Math.min(contentWidth - width, p.x + item.width / 2 - width / 2));
        }
        Behavior on contentX {
            Anim {
                role: "spatialFast"
            }
        }
        Behavior on contentY {
            Anim {
                role: "spatialFast"
            }
        }

        Grid {
            id: content
            columns: root.vertical ? 1 : 1000
            spacing: root.spacing
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            // pinned apps not running: a click launches them
            Repeater {
                model: root.pinnedApps
                delegate: Item {
                    required property string modelData
                    width: root.iconSize + 6
                    height: root.iconSize + 6
                    opacity: root.opt("pinned_opacity") ?? 0.5
                    Image {
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        source: root.iconFor(parent.modelData)
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const entry = DesktopEntries.heuristicLookup(parent.modelData);
                            if (entry)
                                Apps.launch(entry);
                        }
                    }
                }
            }

            // ungrouped: the windows in a row
            Repeater {
                model: root.grouped ? [] : root.shownWindows
                delegate: Task {
                    required property var modelData
                    host: root
                    win: modelData
                }
            }

            // grouped: each workspace
            Repeater {
                model: root.groups
                delegate: Item {
                    id: group
                    required property var modelData
                    readonly property var space: modelData.space
                    readonly property color tone: root.spaceColour(space, modelData.windows.length)
                    readonly property bool capsule: root.opt("workspace_group_capsule") !== false
                    readonly property bool labelled: root.opt("show_workspace_label") !== false
                    readonly property bool corner: (root.opt("workspace_label_placement") ?? "corner") === "corner"
                    readonly property string label: space.name !== "" && space.name !== undefined ? space.name : String(space.idx ?? space.id ?? "")
                    readonly property real pad: capsule ? 5 : 2
                    width: (root.vertical ? Math.max(groupRow.implicitWidth, root.cross - 6) : groupRow.implicitWidth) + (root.vertical ? 0 : pad * 2)
                    height: (root.vertical ? groupRow.implicitHeight : Math.max(groupRow.implicitHeight, root.cross - 8)) + (root.vertical ? pad * 2 : 0)

                    Rectangle {
                        anchors.fill: parent
                        visible: group.capsule
                        radius: (root.opt("capsule_radius") ?? -1) >= 0 ? Math.min(root.opt("capsule_radius"), Math.min(width, height) / 2) : Math.min(width, height) / 2
                        color: Theme.alpha(group.tone, group.space.active ? 0.2 : 0.1)
                        border.width: group.space.active ? 1 : 0
                        border.color: Theme.alpha(group.tone, 0.6)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: group.space.activate()
                    }
                    Grid {
                        id: groupRow
                        anchors.centerIn: parent
                        columns: root.vertical ? 1 : 1000
                        spacing: 3
                        horizontalItemAlignment: Grid.AlignHCenter
                        verticalItemAlignment: Grid.AlignVCenter
                        // the label in the middle (centered), before the content
                        Label {
                            visible: group.labelled && !group.corner
                            role: "data"
                            color: group.tone
                            text: group.label
                        }
                        // the count, or each window's icon
                        Label {
                            visible: root.groupContent === "count" && group.modelData.windows.length > 0
                            role: "data"
                            tone: "muted"
                            text: String(group.modelData.windows.length)
                        }
                        Repeater {
                            model: root.groupContent === "count" ? [] : group.modelData.windows
                            delegate: Task {
                                required property var modelData
                                host: root
                                win: modelData
                            }
                        }
                        // an empty workspace still shows itself
                        Rectangle {
                            visible: group.modelData.windows.length === 0 && !(group.labelled && !group.corner)
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.alpha(group.tone, 0.6)
                        }
                    }
                    // the label in the corner, small
                    Label {
                        visible: group.labelled && group.corner
                        x: 1
                        y: -2
                        role: "micro"
                        color: group.tone
                        text: group.label
                    }
                }
            }
        }
    }

    // one window: its icon (and title if asked); focused, it is lit and marked
    component Task: Item {
        id: task
        // inline components cannot see the widget's ids: it is passed in
        property Item host: null
        property var win: null
        readonly property bool focused: win?.focused === true || (Workspaces.focusedWindow?.id ?? -1) === (win?.id ?? -2)
        onFocusedChanged: if (focused)
            Qt.callLater(() => task.host.stripRef.follow(task))
        width: task.host.vertical ? task.host.cross - 4 : row.implicitWidth + 8
        height: task.host.vertical ? task.host.iconSize + 8 : task.host.cross - 4
        opacity: task.host.opt("minimal") === true && !focused ? 0.6 : focused ? (task.host.opt("active_opacity") ?? 1) : (task.host.opt("inactive_opacity") ?? 1)
        Rectangle {
            anchors.fill: row
            anchors.margins: -3
            radius: Metrics.radiusControl
            color: task.focused ? Theme.alpha(Theme.accent, 0.14) : hover.containsMouse ? Theme.hover : "transparent"
            Behavior on color {
                ColorAnim {}
            }
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: task.host.iconSize
                height: task.host.iconSize
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: task.host.iconFor(task.win?.appId ?? "")
                asynchronous: true
            }
            BarText {
                item: root
                visible: task.host.opt("show_window_title") === true && !task.host.vertical
                width: Math.min(implicitWidth, task.host.opt("window_title_max_width") ?? 100)
                text: task.win?.title ?? ""
                muted: !task.focused
            }
        }
        // the active indicator: a short line under (or beside) the focused window
        Rectangle {
            visible: task.host.opt("show_active_indicator") !== false && task.focused
            anchors.horizontalCenter: task.host.vertical ? undefined : parent.horizontalCenter
            anchors.verticalCenter: task.host.vertical ? parent.verticalCenter : undefined
            anchors.bottom: task.host.vertical ? undefined : parent.bottom
            anchors.left: task.host.vertical ? parent.left : undefined
            width: task.host.vertical ? 2 : 10
            height: task.host.vertical ? 10 : 2
            radius: 1
            color: Theme.colour(task.host.opt("active_indicator_color") ?? "primary")
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton)
                    NiriState.action({
                        CloseWindow: {
                            id: task.win.id
                        }
                    });
                else
                    NiriState.focusWindow(task.win.id);
            }
        }
    }
}
