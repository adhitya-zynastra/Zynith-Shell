import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import "../../Common/Placement.js" as Placement

// Widgets on the desktop, under the windows: one layer per output, every widget placed from widgets.toml at its
// centre, size and rotation (anchored ones keep their distance to an edge; free ones scale with the screen).
// Only interactive widgets (media, calendar, volume, session, buttons) take the pointer; everything else lets
// clicks through. While the editor is open (Mod+Alt+W) it draws the widgets itself, above the windows.
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

                // input reaches only the interactive widgets: one region per such widget
                property int revision: 0
                readonly property var interactiveSlots: {
                    revision;
                    const out = [];
                    for (let i = 0; i < slots.count; i++) {
                        const s = slots.itemAt(i);
                        if (s && s.visible && s.view.interactive)
                            out.push(s);
                    }
                    return out;
                }
                Variants {
                    id: maskRegions
                    model: win.interactiveSlots
                    delegate: Region {
                        required property var modelData
                        item: modelData
                    }
                }
                mask: Region {
                    regions: maskRegions.instances
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
                            rotation: (modelData.rotation ?? 0) * 180 / Math.PI
                            transform: Scale {
                                origin.x: slot.width / 2
                                xScale: slot.modelData.flip ? -1 : 1
                            }
                            Component.onCompleted: win.revision++
                            onVisibleChanged: win.revision++

                            WidgetView {
                                id: view
                                anchors.fill: parent
                                spec: slot.modelData
                                onInteractiveChanged: win.revision++
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
}
