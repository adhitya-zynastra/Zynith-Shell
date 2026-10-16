import QtQuick
import QtTest
import "../../Common/Droplet.js" as D

// Common/Droplet.js: the water-drop silhouette. It must be finite at every t, grow without jumping, end exactly as
// the panel (so the hand-over to the resting card is invisible), keep its boxes inside it, and map every edge.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_droplet.qml
TestCase {
    name: "Droplet"

    readonly property var g: ({ edge: "top", attached: true, ox: 420, along: 600, depth: 300, corners: [0, 0, 16, 16], radius: 16 })
    function at(t: real, over: var): var {
        return D.shape(t, Object.assign({}, g, over || {}));
    }
    function area(b: var): real {
        return b.w * b.h;
    }

    function test_every_value_is_finite() {
        for (const edge of ["top", "bottom", "left", "right"]) {
            for (const attached of [true, false]) {
                for (let t = 0; t <= 1.0001; t += 0.025) {
                    const s = at(t, { edge: edge, attached: attached });
                    verify(!/NaN|Infinity/.test(s.path), edge + " " + attached + " t=" + t + ": " + s.path.slice(0, 80));
                    for (const k of ["x", "y", "w", "h"])
                        verify(isFinite(s.bounds[k]) && isFinite(s.head[k]), edge + " t=" + t + " " + k);
                }
            }
        }
    }
    function test_it_ends_exactly_as_the_panel() {
        const s = at(1);
        compare(s.bounds.x, 0);
        compare(s.bounds.y, 0);
        fuzzyCompare(s.bounds.w, 600, 0.01);
        fuzzyCompare(s.bounds.h, 300, 0.01);
        compare(s.neck, null, "no neck left at rest");
        compare(s.content, 1);
        compare(s.join, 1);
        compare(s.phase, "rest");
    }
    function test_it_starts_from_nothing() {
        const s = at(0);
        verify(area(s.bounds) < 1, "nothing at t = 0: " + JSON.stringify(s.bounds));
        compare(s.content, 0);
    }
    function test_it_grows_without_jumps() {
        // the swell's area may only grow, and no step of 1/60 adds more than a sixth of the panel
        let last = area(at(0.5).head);
        for (let t = 0.5 + 1 / 60; t <= 1.0001; t += 1 / 60) {
            const a = area(at(t).head);
            verify(a >= last - 0.5, "the head never shrinks while it swells (t=" + t.toFixed(3) + ")");
            verify(a - last <= 600 * 300 / 6, "no jump at t=" + t.toFixed(3) + ": " + (a - last));
            last = a;
        }
    }
    function test_the_drop_hangs_from_where_it_was_asked_for() {
        const s = at(0.5);
        const centre = s.head.x + s.head.w / 2;
        fuzzyCompare(centre, 420, 0.5, "the drop is centred on the origin");
        verify(s.neck !== null, "attached: a neck holds it to the edge");
        verify(s.head.y > 0, "it hangs away from the edge");
        verify(Math.abs(s.head.w - s.head.h) < 0.5, "and is round");
    }
    function test_the_page_arrives_only_with_the_swell() {
        compare(at(0.45).content, 0, "nothing of the page inside the drop");
        verify(at(0.75).content > 0 && at(0.75).content < 1);
    }
    function test_a_floating_panel_has_no_neck() {
        for (let t = 0; t <= 1.0001; t += 0.1)
            compare(at(t, { attached: false }).neck, null);
    }
    function test_boxes_stay_inside_the_panel() {
        for (let t = 0.05; t <= 1.0001; t += 0.05) {
            const s = at(t);
            verify(s.head.x >= -0.01 && s.head.y >= -0.01 && s.head.x + s.head.w <= 600.01 && s.head.y + s.head.h <= 300.01, "head inside at t=" + t);
            if (s.neck)
                verify(s.neck.x >= -0.01 && s.neck.x + s.neck.w <= 600.01, "neck inside at t=" + t);
        }
    }
    function test_edges_map_into_card_coordinates() {
        // a bottom panel grows up from its bottom side; a left one rightwards from its left side
        const b = at(0.5, { edge: "bottom" });
        verify(b.head.y + b.head.h < 300 && b.head.y > 150, "bottom: the drop hangs above the bottom edge");
        const l = at(0.5, { edge: "left", along: 300, depth: 600, ox: 150 });
        verify(l.head.x > 0 && l.head.x < 150, "left: it hangs right of the left edge");
        fuzzyCompare(l.head.y + l.head.h / 2, 150, 0.5, "left: centred on the origin along the edge");
        const r = at(0.5, { edge: "right", along: 300, depth: 600, ox: 150 });
        verify(r.head.x + r.head.w < 600 && r.head.x > 300, "right: it hangs left of the right edge");
    }
    function test_an_origin_near_the_end_is_kept_inside() {
        const s = at(0.5, { ox: 2 });
        verify(s.head.x >= 0, "pulled in from the end: " + s.head.x);
    }

    // the head's corners come back in the card's order, so a rounded rectangle (and the blur's region) can draw it
    function test_head_corners_follow_the_card() {
        const done = at(1, { attached: false, corners: [4, 8, 12, 16] });
        compare(done.head.corners, [4, 8, 12, 16]);
        for (const edge of ["top", "bottom", "left", "right"]) {
            const end = at(1, { edge: edge, attached: false, corners: [4, 8, 12, 16] });
            compare(end.head.corners, [4, 8, 12, 16], edge);
        }
        // without the head, the path holds only the neck and the menisci
        const mid = at(0.4);
        verify(at(0.4, { pathHead: false }).path.length < mid.path.length);
        compare(at(0.1, { attached: false, pathHead: false }).path, "");
    }
}
