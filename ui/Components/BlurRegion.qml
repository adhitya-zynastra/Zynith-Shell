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
    // whether the surface wants its backdrop now (an OSD leaving lets it go as its fade starts: the blur cannot fade)
    property bool active: true
    // whose visibility and opacity count (the item itself, unless it only marks where: Components/BackdropBox)
    property Item gate: item
    readonly property bool shown: active && (items.length > 0 || (item !== null && gate !== null && gate.visible && (!followOpacity || gate.opacity >= shownAt)))

    // more shapes in the window's coordinates: [{ x, y, w, h, cutX, cutY, cut }] — a rectangle, less the circle
    // whose bounding square is cut (an attached panel's fillets)
    property var extra: []
    // several separate shapes instead of one item (a stack of notification cards: one region over the whole stack
    // blurred the gaps between the cards too); each is a rounded rect of `radius`, following its item
    property var items: []
    readonly property Instantiator many: Instantiator {
        model: root.items
        delegate: Region {
            required property var modelData
            item: modelData
            radius: root.radius
        }
        onObjectAdded: root.rebuild()
        onObjectRemoved: root.rebuild()
    }
    function rebuild(): void {
        if (items.length === 0)
            return;
        const list = [];
        for (let i = 0; i < many.count; i++)
            list.push(many.objectAt(i));
        region.regions = list;
        apply();
    }

    readonly property Region region: Region {
        item: root.items.length > 0 ? null : root.item
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
        window.BackgroundEffect.blurRegion = Material.blur && shown ? region : null;
    }

    Component.onCompleted: apply()
    onItemChanged: apply()
    onShownChanged: apply()
    onWindowChanged: apply()
    readonly property Connections policy: Connections {
        target: Material
        function onBlurChanged(): void {
            root.apply();
        }
    }
}
