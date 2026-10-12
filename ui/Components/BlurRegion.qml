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
    // the compositor's blur cannot fade: kept while its item fades or scales, it outlives it as a frosted box
    // the item's size. With followOpacity, the blur is there only while the item is shown and (all but) opaque,
    // so it goes at the start of a fade-out and comes as a fade-in lands.
    property bool followOpacity: false
    property real shownAt: 0.98
    readonly property bool shown: item !== null && item.visible && (!followOpacity || item.opacity >= shownAt)

    readonly property Region region: Region {
        item: root.item
        radius: root.radius
    }

    function apply(): void {
        if (!window)
            return;
        window.BackgroundEffect.blurRegion = ExperiencePolicy.blur && shown ? region : null;
    }

    Component.onCompleted: apply()
    onItemChanged: apply()
    onShownChanged: apply()
    onWindowChanged: apply()
    readonly property Connections policy: Connections {
        target: ExperiencePolicy
        function onBlurChanged(): void {
            root.apply();
        }
    }
}
