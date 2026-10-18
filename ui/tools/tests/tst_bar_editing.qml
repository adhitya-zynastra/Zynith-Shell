import QtQuick
import QtTest
import "../../Common/BarModel.js" as M

// Common/BarModel.js, the parts the bar editor drives: corner shapes (round / square / concave, per corner) and
// their fillets, groups, and moving entries by drag and drop.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_bar_editing.qml
TestCase {
    name: "BarEditing"

    // the fillet table BarWindow had before per-corner shapes (concave_edge_corners only): the new general rule
    // must draw an older bar exactly as it was
    function legacyTable(edge, mode, px, py, pw, ph, r) {
        const t = {
            top: { inner: [[px, py + ph, "tl"], [px + pw - r, py + ph, "tr"]], edge: [[px - r, py, "tr"], [px + pw, py, "tl"]] },
            bottom: { inner: [[px, py - r, "bl"], [px + pw - r, py - r, "br"]], edge: [[px - r, py + ph - r, "br"], [px + pw, py + ph - r, "bl"]] },
            left: { inner: [[px + pw, py, "tl"], [px + pw, py + ph - r, "bl"]], edge: [[px, py - r, "bl"], [px, py + ph, "tl"]] },
            right: { inner: [[px - r, py, "tr"], [px - r, py + ph - r, "br"]], edge: [[px + pw - r, py - r, "br"], [px + pw - r, py + ph, "tr"]] }
        };
        return t[edge][mode].map(f => f[0] + "," + f[1] + "," + f[2]).sort();
    }
    function test_older_concave_bars_draw_their_fillets_exactly_as_before() {
        const room = { start: 40, end: 40, inner: 40, outer: 40 };
        for (const edge of M.edges) {
            const vert = edge === "left" || edge === "right";
            const pill = vert ? { x: 10, y: 20, w: 40, h: 500 } : { x: 20, y: 10, w: 500, h: 40 };
            // a centred bar flush with its edge: fillets beyond its ends
            const centred = { edge: edge, anchor: "center", margin: 0, thickness: 40, concave_edge_corners: true, concave_radius: 18 };
            compare(M.fillets(centred, pill, room).map(f => f.x + "," + f.y + "," + f.solid).sort(), legacyTable(edge, "edge", pill.x, pill.y, pill.w, pill.h, 18), edge + " edge mode");
            // a full-length bar: fillets on its inner side, into the screen's ends
            const full = { edge: edge, anchor: "fill", margin: 0, offset: 0, thickness: 40, concave_edge_corners: true, concave_radius: 18 };
            compare(M.fillets(full, pill, room).map(f => f.x + "," + f.y + "," + f.solid).sort(), legacyTable(edge, "inner", pill.x, pill.y, pill.w, pill.h, 18), edge + " inner mode");
        }
    }
    function test_older_concave_size_follows_the_theme_scale_as_it_did() {
        const room = { start: 60, end: 60, inner: 60, outer: 60 };
        const pill = { x: 30, y: 0, w: 600, h: 34 };
        // sized from the bar's radius: scaled (0.85 × 25)
        compare(M.fillets({ edge: "top", anchor: "center", margin: 0, radius: 25, concave_edge_corners: true }, pill, room, undefined, 0.85)[0].r, 21.25);
        // concave_radius, or half the thickness: not scaled
        compare(M.fillets({ edge: "top", anchor: "center", margin: 0, radius: 25, concave_radius: 18, concave_edge_corners: true }, pill, room, undefined, 0.85)[0].r, 18);
        compare(M.fillets({ edge: "top", anchor: "center", margin: 0, thickness: 40, concave_edge_corners: true }, pill, room, undefined, 0.85)[0].r, 20);
    }
    function test_converting_an_older_bar_keeps_its_drawn_sizes_under_a_scale() {
        const s = { bars: [{ id: "b", name: "B", edge: "top", anchor: "center", margin: 0, thickness: 40, concave_edge_corners: true, concave_radius: 17, widgets: {} }], widgets: {} };
        const before = M.cornerShapes(s.bars[0], undefined, 0.85).map(c => c.shape + ":" + c.size);
        const after = M.cornerShapes(M.setCornerShape(s, "b", 3, "square", 0.85).bars[0], undefined, 0.85).map(c => c.shape + ":" + c.size);
        compare(after.slice(0, 2), before.slice(0, 2));
    }
    function test_legacy_flag_still_needs_no_margin() {
        const b = { edge: "top", anchor: "center", margin: 6, concave_edge_corners: true };
        compare(M.cornerShapes(b).map(c => c.shape), ["round", "round", "round", "round"]);
    }

    // where a concave corner can be
    function test_concave_needs_a_screen_edge_to_curve_into() {
        // a full-height left bar: its ends reach the top and bottom edges
        const rail = { edge: "left", anchor: "fill", margin: 0, offset: 0 };
        compare(M.concaveBlocked(rail, 1, undefined), "", "inner top corner curves into the top edge");
        compare(M.concaveBlocked(rail, 2, undefined), "", "inner bottom corner");
        verify(M.concaveBlocked(rail, 0, undefined) !== "", "the outer top corner is the screen's own corner");
        // with a gap to its edge, the outer corner at a reached end can curve too
        compare(M.concaveBlocked(Object.assign({}, rail, { margin: 8 }), 0, undefined), "");
        // a centred, flush bar: its outer corners curve into its own edge, its inner ones have nothing
        const mid = { edge: "top", anchor: "center", margin: 0 };
        compare(M.concaveBlocked(mid, 0, undefined), "");
        verify(M.concaveBlocked(mid, 3, undefined) !== "");
        // floating away from its edge: nothing
        verify(M.concaveBlocked(Object.assign({}, mid, { margin: 6 }), 0, undefined) !== "");
    }
    function test_a_blocked_concave_corner_is_drawn_square_and_says_why() {
        const b = { edge: "top", anchor: "center", margin: 6, shape_top_left: "concave" };
        const c = M.cornerShapes(b)[0];
        compare(c.wanted, "concave");
        compare(c.shape, "square");
        verify(c.blocked.length > 0);
        compare(M.cornerRadii(b, { w: 500, h: 34 }, 1, null)[0], 0);
    }
    function test_one_corner_concave_on_a_left_rail() {
        const rail = { edge: "left", anchor: "fill", margin: 0, offset: 0, thickness: 40, shape_top_right: "concave", radius_top_right: 16 };
        const f = M.fillets(rail, { x: 0, y: 0, w: 40, h: 1200 }, { start: 0, end: 0, inner: 30, outer: 0 });
        compare(f.length, 1);
        compare([f[0].x, f[0].y, f[0].r, f[0].solid, f[0].corner], [40, 0, 16, "tl", 1]);
        compare(M.cornerRadii(rail, { w: 40, h: 1200 }, 1, null)[1], 0, "the sheet's own corner is square there");
    }
    function test_a_fillet_never_outgrows_the_room_its_window_keeps() {
        const b = { edge: "top", anchor: "center", margin: 0, shape_top_left: "concave", radius_top_left: 40 };
        compare(M.fillets(b, { x: 12, y: 0, w: 300, h: 34 }, { start: 12, end: 12, inner: 12, outer: 0 })[0].r, 12);
    }
    function test_reference_workspace_end_short_of_the_screen_does_not_touch() {
        const b = { edge: "left", anchor: "fill", offset: 0 };
        compare(M.endsTouch(b, [34, 1200], 1200), { start: false, end: true });
    }

    // setting shapes
    function state(bar) {
        return { bars: [Object.assign({ id: "b", name: "B", widgets: { start: [], center: [], end: [] } }, bar)], widgets: {} };
    }
    function test_first_corner_choice_turns_the_old_flag_into_explicit_shapes_drawn_the_same() {
        const s = state({ edge: "left", anchor: "fill", margin: 0, offset: 0, thickness: 40, concave_edge_corners: true, concave_radius: 18 });
        const before = M.cornerShapes(s.bars[0]).map(c => c.shape + c.size);
        const next = M.setCornerShape(s, "b", 0, "square");
        const b = next.bars[0];
        compare(b.concave_edge_corners, undefined);
        compare(b.shape_top_right, "concave");
        compare(b.shape_bottom_right, "concave");
        const after = M.cornerShapes(b);
        compare(after[1].shape + after[1].size, before[1]);
        compare(after[2].shape + after[2].size, before[2]);
        compare(after[0].shape, "square");
    }
    function test_round_again_restores_a_visible_radius() {
        let s = state({ edge: "top", thickness: 30 });
        s = M.setCornerShape(s, "b", 2, "square");
        compare(s.bars[0].radius_bottom_right, 0);
        s = M.setCornerShape(s, "b", 2, "round");
        compare(s.bars[0].radius_bottom_right, 15);
        compare(M.cornerShapes(s.bars[0])[2].shape, "round");
    }
    function test_no_concave_left_leaves_no_shape_keys() {
        let s = state({ edge: "top", margin: 0 });
        s = M.setCornerShape(s, "b", 0, "concave");
        compare(s.bars[0].shape_top_left, "concave");
        s = M.setCornerShape(s, "b", 0, "round");
        compare(Object.keys(s.bars[0]).filter(k => k.startsWith("shape_")), []);
    }
    function test_corner_size() {
        let s = state({ edge: "top" });
        s = M.setCornerSize(s, "b", 3, 9.6);
        compare(s.bars[0].radius_bottom_left, 10);
        s = M.setCornerSize(s, "b", 3, undefined);
        compare(s.bars[0].radius_bottom_left, undefined);
    }

    // groups
    function bar3() {
        return { bars: [{ id: "b", name: "B", widgets: { start: ["a", "b2", "c"], center: ["d"], end: [] } }], widgets: { a: { type: "clock" }, b2: { type: "volume" }, c: { type: "battery" }, d: { type: "media" } } };
    }
    function test_group_two_components_in_place() {
        const r = M.groupEntries(bar3(), "b", "start", [1, 2], "Status");
        const bar = r.state.bars[0];
        compare(bar.widgets.start, ["a", "group:" + r.id]);
        compare(M.groupById(bar, r.id).members, ["b2", "c"]);
        compare(M.groupById(bar, r.id).name, "Status");
    }
    function test_ungroup_puts_members_back_where_the_group_was() {
        const r = M.groupEntries(bar3(), "b", "start", [0, 1]);
        const back = M.ungroup(r.state, "b", r.id);
        compare(back.bars[0].widgets.start, ["a", "b2", "c"]);
        compare(back.bars[0].group, undefined);
    }
    function test_move_within_and_across_sections() {
        let s = M.moveEntry(bar3(), "b", { section: "start", index: 0 }, { section: "start", index: 3 });
        compare(s.bars[0].widgets.start, ["b2", "c", "a"], "to the end of its own section");
        s = M.moveEntry(s, "b", { section: "start", index: 0 }, { section: "end", index: 0 });
        compare(s.bars[0].widgets.start, ["c", "a"]);
        compare(s.bars[0].widgets.end, ["b2"]);
    }
    function test_move_into_and_out_of_a_group() {
        const r = M.groupEntries(bar3(), "b", "start", [1]);
        let s = M.moveEntry(r.state, "b", { section: "center", index: 0 }, { group: r.id, index: 1 });
        compare(M.groupById(s.bars[0], r.id).members, ["b2", "d"]);
        compare(s.bars[0].widgets.center, []);
        s = M.moveEntry(s, "b", { group: r.id, index: 0 }, { section: "end", index: 0 });
        compare(s.bars[0].widgets.end, ["b2"]);
        compare(M.groupById(s.bars[0], r.id).members, ["d"]);
    }
    function test_an_emptied_group_goes() {
        const r = M.groupEntries(bar3(), "b", "start", [2]);
        const s = M.moveEntry(r.state, "b", { group: r.id, index: 0 }, { section: "center", index: 1 });
        compare(s.bars[0].widgets.start, ["a", "b2"]);
        compare(s.bars[0].widgets.center, ["d", "c"]);
        compare(s.bars[0].group, undefined);
    }
    function test_groups_do_not_nest() {
        const r1 = M.groupEntries(bar3(), "b", "start", [0]);
        const r2 = M.groupEntries(r1.state, "b", "start", [1, 2]);
        const s = M.moveEntry(r2.state, "b", { section: "start", index: 0 }, { group: r2.id, index: 0 });
        compare(s, r2.state, "nothing changes");
    }
    function test_remove_a_member_and_a_whole_group() {
        const r = M.groupEntries(bar3(), "b", "start", [1, 2]);
        let s = M.removeEntry(r.state, "b", { group: r.id, index: 0 });
        compare(M.groupById(s.bars[0], r.id).members, ["c"]);
        compare(s.widgets.b2, undefined, "its table goes with it");
        s = M.removeEntry(s, "b", { section: "start", index: 1 });
        compare(s.bars[0].widgets.start, ["a"]);
        compare(s.widgets.c, undefined);
        compare(s.bars[0].group, undefined);
    }
    function test_insert_a_new_component_anywhere() {
        const r = M.insertComponent(bar3(), "b", "clock", { section: "start", index: 1 });
        compare(r.state.bars[0].widgets.start, ["a", r.name, "b2", "c"]);
        compare(r.state.widgets[r.name].type, "clock");
        const g = M.groupEntries(r.state, "b", "end", []);
        compare(g.id, "", "an empty selection makes no group");
    }

    function test_a_generated_name_follows_the_bar_a_chosen_one_stays() {
        let s = M.create({ bars: [], widgets: {} }, { edge: "bottom", anchor: "start" }, undefined, 1).state;
        const id = s.bars[0].id;
        compare(s.bars[0].name, "Bottom left");
        s = M.place(s, id, "right", "end");
        compare(s.bars[0].name, "Right bottom");
        s = M.rename(s, id, "Status");
        s = M.place(s, id, "top", "center");
        compare(s.bars[0].name, "Status");
    }
}
