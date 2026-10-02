import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Widgets on the desktop, under the windows: one layer per output, every widget placed from widgets.toml at its
// centre, size and rotation (a layout made for another resolution scales with it). Only interactive widgets take
// pointer input; everything else lets clicks through to the desktop.
Scope {
    id: root

    readonly property bool owned: (Config.surfaces?.desktop_widgets ?? "native") === "zynith"

    Variants {
        model: root.owned ? Quickshell.screens : []

        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property var widgets: Config.widgets.filter(w => !w.output || w.output === modelData.name)

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
            mask: Region {
                item: interactive
            }
            // the union of interactive widgets is approximated by the media card when there is one
            Item {
                id: interactive
                property Item card: null
                x: card ? card.x : 0
                y: card ? card.y : 0
                width: card && card.visible ? card.width : 0
                height: card && card.visible ? card.height : 0
            }

            Repeater {
                model: win.widgets

                delegate: Item {
                    id: slot
                    required property var modelData
                    readonly property var ref: modelData.reference ?? [win.width, win.height]
                    readonly property real sx: win.width / (ref[0] || win.width)
                    readonly property real sy: win.height / (ref[1] || win.height)
                    readonly property real boxW: (modelData.width ?? 0) * sx
                    readonly property real boxH: (modelData.height ?? 0) * sy

                    width: boxW > 0 ? boxW : (loader.item?.implicitWidth ?? 0)
                    height: boxH > 0 ? boxH : (loader.item?.implicitHeight ?? 0)
                    x: (modelData.cx ?? 0) * sx - width / 2
                    y: (modelData.cy ?? 0) * sy - height / 2
                    rotation: (modelData.rotation ?? 0) * 180 / Math.PI
                    transform: Scale {
                        origin.x: slot.width / 2
                        xScale: slot.modelData.flip ? -1 : 1
                    }

                    Loader {
                        id: loader
                        anchors.fill: slot.boxW > 0 ? parent : undefined
                        sourceComponent: ({
                                clock: clock,
                                label: label,
                                sticker: sticker,
                                audio_visualizer: visualizer,
                                visualizer: visualizer,
                                weather: weather,
                                media_player: media,
                                media: media
                            })[slot.modelData.type] ?? null
                        onLoaded: {
                            item.settings = Qt.binding(() => slot.modelData.settings ?? {});
                            if (item.interactive)
                                interactive.card = slot;
                        }
                    }
                }
            }

            Component {
                id: clock
                DesktopClock {}
            }
            Component {
                id: label
                DesktopLabel {}
            }
            Component {
                id: sticker
                DesktopSticker {}
            }
            Component {
                id: visualizer
                DesktopVisualizer {}
            }
            Component {
                id: weather
                DesktopWeather {}
            }
            Component {
                id: media
                DesktopMedia {}
            }
        }
    }
}
