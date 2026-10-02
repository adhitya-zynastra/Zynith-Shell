import QtQuick
import Quickshell
import Zynith.Native
import qs.Common
import qs.Components
import qs.Services

// Open windows as app icons (and titles if asked), in their workspaces' order; pinned apps wait at the
// front, dimmed, until they run. Left click focuses (or launches a pinned app), middle click closes —
// reserved; the wheel cycles windows (its actions). Grouped by workspace in capsules if asked.
BarItem {
    id: root

    readonly property var windows: {
        NiriState.workspaces;
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
                source: root.iconFor(modelData)
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

    Repeater {
        model: root.shownWindows
        delegate: Item {
            id: task
            required property var modelData
            required property int index
            readonly property bool focused: modelData.focused === true || (Workspaces.focusedWindow?.id ?? -1) === modelData.id
            readonly property bool newSpace: root.opt("group_by_workspace") === true && index > 0 && root.shownWindows[index - 1].workspaceId !== modelData.workspaceId
            width: (root.vertical ? root.cross - 4 : row.implicitWidth + 8) + (newSpace && !root.vertical ? 8 : 0)
            height: root.vertical ? root.iconSize + 8 + (newSpace ? 8 : 0) : root.cross - 4
            opacity: focused ? (root.opt("active_opacity") ?? 1) : (root.opt("inactive_opacity") ?? 1)

            // a gap and a hairline between workspaces when grouped
            Rectangle {
                visible: task.newSpace
                x: root.vertical ? 4 : 0
                y: root.vertical ? 0 : 6
                width: root.vertical ? parent.width - 8 : 1
                height: root.vertical ? 1 : parent.height - 12
                color: Theme.alpha(root.ink, 0.2)
            }
            Rectangle {
                anchors.fill: row
                anchors.margins: -3
                radius: 8
                color: task.focused ? Theme.alpha(Theme.accent, 0.14) : hover.containsMouse ? Theme.hover : "transparent"
                Behavior on color {
                    ColorAnim {}
                }
            }
            Row {
                id: row
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: task.newSpace && !root.vertical ? 4 : 0
                anchors.verticalCenterOffset: task.newSpace && root.vertical ? 4 : 0
                spacing: 4
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconSize
                    height: root.iconSize
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    source: root.iconFor(task.modelData.appId)
                    asynchronous: true
                }
                BarText {
                    item: root
                    visible: root.opt("show_window_title") === true && !root.vertical
                    width: Math.min(implicitWidth, root.opt("window_title_max_width") ?? 100)
                    text: task.modelData.title
                    muted: !task.focused
                }
            }
            // the active indicator: a short line under (or beside) the focused window
            Rectangle {
                visible: root.opt("show_active_indicator") !== false && task.focused
                anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
                anchors.bottom: root.vertical ? undefined : parent.bottom
                anchors.left: root.vertical ? parent.left : undefined
                width: root.vertical ? 2 : 10
                height: root.vertical ? 10 : 2
                radius: 1
                color: Theme.colour(root.opt("active_indicator_color") ?? "primary")
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
                                id: task.modelData.id
                            }
                        });
                    else
                        NiriState.focusWindow(task.modelData.id);
                }
            }
        }
    }
}
