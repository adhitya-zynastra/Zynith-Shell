import QtQuick
import Quickshell
import Quickshell.Wayland

// A clear layer over a screen that takes the next click anywhere on it (`caught`) while `active`: what closes a
// popup when the click lands on the shell's own desktop or bars. Those are the same client as the popup, so its
// grab counts them as inside. Popups stay above it; a click on another app's window is the grab's to handle.
LazyLoader {
    id: root

    property var screen: null
    signal caught

    PanelWindow {
        screen: root.screen
        WlrLayershell.namespace: "zynith-click-catcher"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.caught()
        }
    }
}
