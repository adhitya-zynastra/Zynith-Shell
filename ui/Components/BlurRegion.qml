import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// Asks the compositor to blur behind `item` (ext-background-effect) when the policy allows blur.
// niri applies its global blur settings to the region; nothing is blurred inside the shell.
QtObject {
    id: root

    required property var window
    property Item item
    property real radius: 0

    readonly property Region region: Region {
        item: root.item
        radius: root.radius
    }

    function apply(): void {
        if (!window)
            return;
        window.BackgroundEffect.blurRegion = ExperiencePolicy.blur && item ? region : null;
    }

    Component.onCompleted: apply()
    onItemChanged: apply()
    onWindowChanged: apply()
    readonly property Connections policy: Connections {
        target: ExperiencePolicy
        function onBlurChanged(): void {
            root.apply();
        }
    }
}
