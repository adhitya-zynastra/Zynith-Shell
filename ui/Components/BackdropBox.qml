import QtQuick

// Where a surface's compositor backdrop goes, in the window's coordinates — kept on while the surface moves.
//
// A backdrop region reaches the compositor out of step with the picture it belongs to (a frame either way), so a
// region set to the surface's own rectangle frosts past an edge while it grows or slides (a pale rim) and falls short
// while it shrinks. In motion this box is the overlap of the surface's rectangle in this frame and in the last one:
// whichever of the two frames the compositor pairs it with, it lies inside what is drawn. At rest it is the rectangle
// itself. So the selected material is there from the first frame to the last, never withheld while things move.
//
//   rect: the surface as drawn, in window coordinates (x, y, w, h — with its transforms applied)
//   moving: the rectangle is animating (the box follows it frame by frame)
// (an empty item: it draws nothing; BlurRegion's `gate` says whose opacity counts)
Item {
    id: root

    property var rect: ({ x: 0, y: 0, w: 0, h: 0 })
    property bool moving: false

    property var last: rect
    property var box: rect
    x: box.x
    y: box.y
    width: Math.max(0, box.w)
    height: Math.max(0, box.h)

    function overlap(a: var, b: var): var {
        const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
        return { x: x, y: y, w: Math.min(a.x + a.w, b.x + b.w) - x, h: Math.min(a.y + a.h, b.y + b.h) - y };
    }
    // the box is worked out whenever the rectangle changes (against the last frame's), and the last frame's is taken
    // once a frame: right whichever runs first in a frame, the animations or this
    onRectChanged: {
        if (moving)
            box = overlap(rect, last);
        else {
            last = rect;
            box = rect;
        }
    }
    onMovingChanged: {
        last = rect;
        box = rect;
    }
    FrameAnimation {
        running: root.moving
        onTriggered: root.last = root.rect
    }
}
