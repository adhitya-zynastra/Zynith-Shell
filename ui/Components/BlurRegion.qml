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
    // per corner, [top-left, top-right, bottom-right, bottom-left] as Glass takes them (null: radius for all):
    // the blur has the shape the surface has, or it shows as frosted corners past a rounded card
    property var corners: null
    // the compositor's blur cannot fade: kept while its item fades or scales, it outlives it as a frosted box
    // the item's size. With followOpacity, the blur is there only while the item is shown and (all but) opaque,
    // so it goes at the start of a fade-out and comes as a fade-in lands.
    property bool followOpacity: false
    property real shownAt: 0.98
    readonly property bool shown: item !== null && item.visible && (!followOpacity || item.opacity >= shownAt)

    // more shapes in the window's coordinates: [{ x, y, w, h, cutX, cutY, cut }] — a rectangle, less the circle
    // whose bounding square is cut (an attached panel's fillets)
    property var extra: []
    readonly property Region region: Region {
        item: root.item
        radius: root.radius
        topLeftRadius: root.corners ? root.corners[0] : root.radius
        topRightRadius: root.corners ? root.corners[1] : root.radius
        bottomRightRadius: root.corners ? root.corners[2] : root.radius
        bottomLeftRadius: root.corners ? root.corners[3] : root.radius
        Region {
            readonly property var e: root.extra[0] ?? null
            x: e ? e.x : 0
            y: e ? e.y : 0
            width: e ? e.w : 0
            height: e ? e.h : 0
            Region {
                readonly property var e: root.extra[0] ?? null
                shape: RegionShape.Ellipse
                intersection: Intersection.Subtract
                x: e ? e.cutX : 0
                y: e ? e.cutY : 0
                width: e ? e.cut : 0
                height: e ? e.cut : 0
            }
        }
        Region {
            readonly property var e: root.extra[1] ?? null
            x: e ? e.x : 0
            y: e ? e.y : 0
            width: e ? e.w : 0
            height: e ? e.h : 0
            Region {
                readonly property var e: root.extra[1] ?? null
                shape: RegionShape.Ellipse
                intersection: Intersection.Subtract
                x: e ? e.cutX : 0
                y: e ? e.cutY : 0
                width: e ? e.cut : 0
                height: e ? e.cut : 0
            }
        }
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
