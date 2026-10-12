import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import "../../Common/Placement.js" as Placement

// Widgets on the desktop, under the windows: one layer per output, every widget placed from widgets.toml at its
// centre, size and rotation (anchored ones keep their distance to an edge; free ones scale with the screen).
// Interactive widgets (media, calendar, volume, session, buttons) take the pointer. A right click on the bare
// desktop or on any widget opens the desktop's menu: edit the widgets, add one, a widget's settings, hide it.
// While the editor is open (Mod+Alt+W, or that menu) it draws the widgets itself, above the windows.
Scope {
    id: root

    readonly property bool owned: (Config.surfaces?.desktop_widgets ?? "native") === "zynith"

    Variants {
        model: root.owned ? Quickshell.screens : []

        delegate: Scope {
            id: perScreen
            required property var modelData

            PanelWindow {
                id: win
                screen: perScreen.modelData

                readonly property var widgets: Config.widgets.filter(w => (!w.output || w.output === perScreen.modelData.name) && !w.hidden)

                WlrLayershell.namespace: "zynith-desktop"
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // the whole desktop takes the pointer (a right click anywhere opens the menu); under the windows,
                // so only bare desktop is reached. Left clicks on a still widget land on nothing, as on the wallpaper.
                property int revision: 0

                // the widget under a point of this window, if any
                function widgetAt(x: real, y: real): var {
                    for (let i = slots.count - 1; i >= 0; i--) {
                        const s = slots.itemAt(i);
                        if (!s || !s.visible)
                            continue;
                        const p = s.mapFromItem(null, x, y);
                        if (p.x >= 0 && p.y >= 0 && p.x <= s.width && p.y <= s.height)
                            return s.modelData;
                    }
                    return null;
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    enabled: !Desktop.editing
                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton)
                            menu.openAt(mouse.x, mouse.y, win.widgetAt(mouse.x, mouse.y));
                        else
                            menu.shown = false;
                    }
                }

                // the widgets step back while the editor shows them
                Item {
                    id: stage
                    anchors.fill: parent
                    // for diagnostics: the desktop's own pixels, windows or not
                    Component.onCompleted: PanelRouter.barItems["desktop@" + perScreen.modelData.name] = stage
                    opacity: Desktop.editing ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity {
                        Anim {
                            role: "effects"
                        }
                    }

                    Repeater {
                        id: slots
                        model: win.widgets

                        delegate: Item {
                            id: slot
                            required property var modelData
                            readonly property alias view: view
                            readonly property var place: Placement.place(modelData, Desktop.geometry(modelData), win.width, win.height)

                            width: place.width > 0 ? place.width : view.implicitWidth
                            height: place.height > 0 ? place.height : view.implicitHeight
                            x: place.x + (place.width > 0 ? 0 : place.width / 2 - width / 2)
                            y: place.y + (place.height > 0 ? 0 : place.height / 2 - height / 2)
                            // rotation turns the widget; a flip mirrors it in its own frame, before the turn (as the
                            // native shell: the mirror is the content's, so a turned, flipped widget keeps its edge)
                            rotation: (modelData.rotation ?? 0) * 180 / Math.PI
                            Component.onCompleted: win.revision++
                            onVisibleChanged: win.revision++

                            WidgetView {
                                id: view
                                anchors.fill: parent
                                transform: Scale {
                                    origin.x: view.width / 2
                                    xScale: slot.modelData.flip ? -1 : 1
                                }
                                spec: slot.modelData
                                onInteractiveChanged: win.revision++
                            }
                        }
                    }
                }

                // ── the desktop's menu (right click) ──
                Glass {
                    id: menu
                    property bool shown: false
                    property var target: null      // the widget right-clicked, if any
                    Component.onCompleted: PanelRouter.barItems["desktop-menu@" + perScreen.modelData.name] = menu
                    function openAt(x: real, y: real, w: var): void {
                        target = w;
                        menuCol.forceLayout();
                        menu.x = Math.max(8, Math.min(win.width - menu.width - 8, x));
                        menu.y = Math.max(8, Math.min(win.height - menu.height - 8, y));
                        shown = true;
                    }
                    readonly property string targetName: target ? (WidgetTypes.find(target.type)?.label ?? target.type) : ""
                    width: 240
                    height: menuCol.implicitHeight + Metrics.s2 * 2
                    radius: Metrics.radiusLg
                    raised: true
                    visible: opacity > 0
                    opacity: shown && !Desktop.editing ? 1 : 0
                    scale: shown ? 1 : 0.96
                    transformOrigin: Item.TopLeft
                    Behavior on opacity {
                        Anim {
                            role: menu.shown ? "enter" : "exit"
                        }
                    }
                    Behavior on scale {
                        Anim {
                            role: "spatialFast"
                        }
                    }
                    Column {
                        id: menuCol
                        x: Metrics.s2
                        y: Metrics.s2
                        width: parent.width - Metrics.s2 * 2
                        spacing: 0
                        Label {
                            visible: menu.target !== null
                            height: menu.target !== null ? implicitHeight : 0
                            leftPadding: Metrics.s3
                            topPadding: Metrics.s2
                            bottomPadding: Metrics.s1
                            role: "micro"
                            caps: true
                            tone: "faint"
                            text: menu.targetName
                        }
                        MenuRow {
                            shown: menu.target !== null
                            icon: "adjustments"
                            text: "Its settings"
                            onClicked: {
                                const id = menu.target.id;
                                menu.shown = false;
                                Desktop.setEditing(true);
                                Desktop.selection = [id];
                                Desktop.inspecting = true;
                            }
                        }
                        MenuRow {
                            shown: menu.target !== null
                            icon: "eye-off"
                            text: "Hide it"
                            onClicked: {
                                Desktop.toggleHidden([menu.target.id]);
                                menu.shown = false;
                            }
                        }
                        Rectangle {
                            visible: menu.target !== null
                            width: parent.width
                            height: menu.target !== null ? Metrics.hairline : 0
                            color: Theme.hairline
                        }
                        MenuRow {
                            icon: "layout-dashboard"
                            text: "Edit widgets"
                            onClicked: {
                                menu.shown = false;
                                Desktop.setEditing(true);
                            }
                        }
                        MenuRow {
                            icon: "plus"
                            text: "Add a widget"
                            onClicked: {
                                menu.shown = false;
                                Desktop.setEditing(true);
                                Desktop.picking = true;
                            }
                        }
                        MenuRow {
                            icon: "settings"
                            text: "Desktop widget settings"
                            onClicked: {
                                menu.shown = false;
                                Quickshell.execDetached([Paths.uiScript, "settings", "widgets"]);
                            }
                        }
                    }
                }
            }


            // the editor, on every screen, while editing
            LazyLoader {
                active: Desktop.editing
                DesktopEditor {
                    screen: perScreen.modelData
                }
            }
        }
    }

    // a row of the desktop menu
    component MenuRow: Rectangle {
        id: row
        property string icon
        property string text
        signal clicked
        width: parent?.width ?? 0
        property bool shown: true
        visible: shown
        height: shown ? 36 : 0
        radius: Metrics.radiusMd
        color: rowArea.containsMouse ? Theme.hover : "transparent"
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.s3
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: row.icon
                size: 15
                tone: "muted"
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "label"
                text: row.text
            }
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }
}
