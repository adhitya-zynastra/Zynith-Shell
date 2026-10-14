import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// The room the bars on one edge of one output keep windows out of, held by one surface of its own. The bars
// themselves ignore exclusive zones (BarWindow): the compositor lays out the zones of surfaces on the same edge one
// after another, so bars side by side on an edge would have stacked. This surface spans the edge, is one pixel
// deep, draws nothing, takes no input and sits under the windows; its zone is the deepest of the bars there
// (BarModel.reservations), and it is not created when nothing on the edge keeps room.
PanelWindow {
    id: win

    required property string edge
    required property int depth

    WlrLayershell.namespace: "zynith-reserve-" + edge
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: depth
    color: "transparent"
    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }
    implicitWidth: 1
    implicitHeight: 1
    // no input anywhere on it
    mask: Region {}
}
