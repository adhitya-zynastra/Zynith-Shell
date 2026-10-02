import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common
import qs.Components
import qs.Services

// Status icons from apps. Click activates, right click opens the app's menu (both reserved), middle click
// is the secondary action. Items can be hidden or (in drawer mode) pinned to the bar; the rest wait in a
// drawer that opens from a chevron. Passive items hide unless asked not to.
BarItem {
    id: root

    readonly property var hidden: opt("hidden") ?? []
    readonly property var pinned: opt("pinned") ?? []
    readonly property bool drawer: opt("drawer") === true
    function idOf(item: var): string {
        return item.id || item.title || "";
    }
    readonly property var items: SystemTray.items.values.filter(i => !hidden.includes(idOf(i)) && !(opt("hide_passive") !== false && i.status === Status.Passive))
    readonly property var onBar: drawer ? items.filter(i => pinned.includes(idOf(i))) : items
    readonly property var inDrawer: drawer ? items.filter(i => !pinned.includes(idOf(i))) : []
    shown: items.length > 0
    interactive: false
    spacing: Metrics.s3

    component TrayIcon: Item {
        id: entry
        required property var modelData
        property real size: 18
        width: size
        height: size
        // an icon name the theme lacks would draw Qt's checkerboard; those get a plain glyph instead
        readonly property string source: {
            const icon = entry.modelData.icon ?? "";
            if (icon.startsWith("image://icon/"))
                return Quickshell.iconPath(icon.substring(13).split("?")[0], true);
            return icon;
        }
        IconImage {
            anchors.fill: parent
            visible: entry.source !== ""
            source: entry.source
            asynchronous: true
            opacity: area.containsMouse ? 1 : 0.85
            scale: area.pressed ? 0.9 : 1
            Glide on scale {
                epsilon: 0.001
            }
        }
        Icon {
            anchors.centerIn: parent
            visible: entry.source === ""
            name: "apps"
            tone: "muted"
        }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    entry.modelData.secondaryActivate();
                } else if (mouse.button === Qt.RightButton || entry.modelData.onlyMenu) {
                    if (entry.modelData.hasMenu) {
                        const p = entry.mapToItem(null, 0, entry.height);
                        entry.modelData.display(root.bar, p.x, p.y + 4);
                    }
                } else {
                    entry.modelData.activate();
                }
            }
        }
    }

    Repeater {
        model: root.onBar
        delegate: TrayIcon {}
    }

    // the drawer's handle and the drawer itself, a small grid under (or beside) the bar
    Item {
        id: handle
        visible: root.drawer && root.inDrawer.length > 0
        width: 18
        height: 18
        Icon {
            anchors.centerIn: parent
            name: root.vertical ? (root.bar?.edge === "right" ? "chevron-left" : "chevron-right") : (root.bar?.edge === "bottom" ? "chevron-down" : "chevron-down")
            size: 14
            color: root.iconInk
            rotation: drawerWindow.visible ? 180 : 0
            Behavior on rotation {
                Anim {
                    role: "spatialFast"
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: drawerWindow.visible = !drawerWindow.visible
        }
        PopupWindow {
            id: drawerWindow
            anchor.item: handle
            anchor.edges: root.vertical ? (root.bar?.edge === "right" ? Edges.Left : Edges.Right) : (root.bar?.edge === "bottom" ? Edges.Top : Edges.Bottom)
            anchor.gravity: anchor.edges
            anchor.margins.top: 10
            anchor.margins.bottom: 10
            anchor.margins.left: 10
            anchor.margins.right: 10
            color: "transparent"
            readonly property int cols: root.opt("drawer_columns") ?? 3
            readonly property real cell: (root.opt("drawer_item_size") ?? 18) + 18
            implicitWidth: cols * cell + 16
            implicitHeight: Math.ceil(root.inDrawer.length / cols) * cell + 16
            Glass {
                anchors.fill: parent
                radius: Metrics.radiusLg
                raised: true
                Grid {
                    anchors.centerIn: parent
                    columns: drawerWindow.cols
                    Repeater {
                        model: root.inDrawer
                        delegate: Item {
                            required property var modelData
                            width: drawerWindow.cell
                            height: drawerWindow.cell
                            TrayIcon {
                                anchors.centerIn: parent
                                modelData: parent.modelData
                                size: root.opt("drawer_item_size") ?? 18
                            }
                        }
                    }
                }
            }
        }
    }
}
