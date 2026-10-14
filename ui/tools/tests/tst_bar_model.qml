import QtQuick
import QtTest
import "../../Common/BarModel.js" as M

// Common/BarModel.js: bar instances and their component instances, as the Bar Manager edits them.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_bar_model.qml
TestCase {
    name: "BarModel"

    function empty() {
        return { bars: [], widgets: {} };
    }
    function made(state, spec, name, seed) {
        return M.create(state, spec || {}, name, seed);
    }

    // 1. create
    function test_create_blank_bar_has_its_own_id_and_a_name_from_where_it_sits() {
        const r = made(empty(), { edge: "top", anchor: "start" }, undefined, 1);
        compare(r.state.bars.length, 1);
        const b = r.state.bars[0];
        compare(b.id, r.id);
        verify(b.id.startsWith("bar-"));
        compare(b.name, "Top left");
        compare(b.enabled, true);
        compare(b.widgets, { start: [], center: [], end: [] });
    }
    function test_create_never_reuses_an_id_or_a_name() {
        let s = empty();
        const a = made(s, { edge: "right", anchor: "center" }, undefined, 7);
        const b = made(a.state, { edge: "right", anchor: "center" }, undefined, 7);
        verify(a.id !== b.id);
        compare(b.state.bars.map(x => x.name), ["Right centre", "Right centre 2"]);
    }
    function test_create_from_kinds_makes_component_instances() {
        const r = made(empty(), { widgets: { center: ["clock", "clock"] } }, "Clocks", 1);
        const list = r.state.bars[0].widgets.center;
        compare(list.length, 2);
        verify(list[0] !== list[1], "two of a kind are two instances");
        compare(r.state.widgets[list[0]].type, "clock");
        compare(r.state.widgets[list[1]].type, "clock");
    }

    // 2. rename
    function test_rename_keeps_the_id_and_stays_unique() {
        let r = made(empty(), {}, "A", 1);
        r = made(r.state, {}, "B", 2);
        const idB = r.id;
        const s = M.rename(r.state, idB, "  A  ");
        compare(M.find(s, idB).name, "A 2");
        compare(M.find(s, idB).id, idB);
        compare(M.rename(s, idB, "   "), s, "an empty name is refused");
    }

    // 3. duplicate
    function test_duplicate_copies_components_into_their_own_instances() {
        let r = made(empty(), { widgets: { center: ["clock"] } }, "Top", 1);
        const clock = r.state.bars[0].widgets.center[0];
        let s = Object.assign({}, r.state, { widgets: Object.assign({}, r.state.widgets, { [clock]: { type: "clock", format: "%H:%M" } }) });
        const d = M.duplicate(s, r.id, 9);
        compare(d.state.bars.length, 2);
        const copy = M.find(d.state, d.id);
        compare(copy.name, "Top copy");
        const copied = copy.widgets.center[0];
        verify(copied !== clock);
        compare(d.state.widgets[copied].format, "%H:%M", "settings come along");
        compare(M.indexOf(d.state, d.id), 1, "the copy sits right after the original");
    }

    // 4. delete (and its undo)
    function test_delete_drops_only_its_own_instances_and_restores() {
        let r = made(empty(), { widgets: { end: ["network"] } }, "One", 1);
        const own = r.state.bars[0].widgets.end[0];
        let s = r.state;
        // a shared kind table, named by this bar and another, must survive
        s = { bars: s.bars.concat([{ id: "other", name: "Other", widgets: { start: ["clock"] } }]), widgets: Object.assign({}, s.widgets, { clock: { format: "x" } }) };
        s = M.setKey(s, r.id, "widgets", { start: ["clock"], center: [], end: [own] });
        const gone = M.remove(s, r.id);
        compare(gone.state.bars.map(b => b.id), ["other"]);
        compare(gone.state.widgets[own], undefined, "its own instance went with it");
        compare(gone.state.widgets.clock.format, "x", "a kind's shared settings stay");
        const back = M.restore(gone.state, gone.removed);
        compare(back.bars.map(b => b.id), [r.id, "other"]);
        compare(back.widgets[own].type, "network");
    }

    // 5. disable and enable
    function test_enable_toggle() {
        const r = made(empty(), {}, "X", 1);
        compare(M.find(M.setEnabled(r.state, r.id, false), r.id).enabled, false);
        compare(M.find(M.setEnabled(M.setEnabled(r.state, r.id, false), r.id, true), r.id).enabled, true);
    }

    // 6–8. add, remove, reorder components
    function test_add_component_is_always_an_instance_of_its_own() {
        let r = made(empty(), {}, "X", 1);
        let s = M.addComponent(r.state, r.id, "end", "volume");
        s = M.addComponent(s, r.id, "end", "volume");
        const list = M.find(s, r.id).widgets.end;
        compare(list.length, 2);
        verify(list[0] !== list[1]);
        compare(M.addComponent(s, r.id, "middle", "volume"), s, "an unknown section is refused");
    }
    function test_a_new_instance_starts_from_the_kinds_own_settings() {
        let r = made({ bars: [], widgets: { network: { show_label: false } } }, {}, "X", 1);
        const s = M.addComponent(r.state, r.id, "end", "network");
        const inst = M.find(s, r.id).widgets.end[0];
        compare(s.widgets[inst], { show_label: false, type: "network" });
        compare(s.widgets.network, { show_label: false }, "the kind's table itself is left as it was");
    }
    function test_remove_component_drops_its_instance() {
        let r = made(empty(), { widgets: { end: ["volume", "battery"] } }, "X", 1);
        const [vol, bat] = r.state.bars[0].widgets.end;
        const s = M.removeComponent(r.state, r.id, "end", 0);
        compare(M.find(s, r.id).widgets.end, [bat]);
        compare(s.widgets[vol], undefined);
    }
    function test_move_component_within_and_across_sections() {
        let r = made(empty(), { widgets: { start: ["launcher"], center: ["clock"], end: ["volume", "battery"] } }, "X", 1);
        const w0 = r.state.bars[0].widgets;
        let s = M.moveComponent(r.state, r.id, "end", 1, -1);
        compare(M.find(s, r.id).widgets.end, [w0.end[1], w0.end[0]]);
        s = M.moveComponent(s, r.id, "center", 0, -1);
        compare(M.find(s, r.id).widgets.start, [w0.start[0], w0.center[0]], "past the start it joins the previous section's end");
        compare(M.find(s, r.id).widgets.center, []);
        compare(M.moveComponent(s, r.id, "start", 0, -1), s, "nothing before the first section");
    }

    // 9. two of a kind, configured apart
    function test_two_clocks_have_separate_settings() {
        let r = made(empty(), { widgets: { center: ["clock"] } }, "X", 1);
        let s = M.addComponent(r.state, r.id, "center", "clock");
        const [a, b] = M.find(s, r.id).widgets.center;
        const widgets = Object.assign({}, s.widgets);
        widgets[a] = Object.assign({}, widgets[a], { format: "%H:%M" });
        widgets[b] = Object.assign({}, widgets[b], { format: "%I:%M %p", timezone: "UTC" });
        compare(widgets[a].format, "%H:%M");
        compare(widgets[b].timezone, "UTC");
        compare(widgets[a].timezone, undefined);
    }
    function test_separate_turns_a_shared_component_into_its_own() {
        const s = { bars: [{ id: "a", name: "A", widgets: { center: ["clock"] } }, { id: "b", name: "B", widgets: { center: ["clock"] } }], widgets: { clock: { format: "%H" } } };
        compare(M.usage(s, "clock"), 2);
        const t = M.separate(s, "b", "center", 0);
        const own = M.find(t, "b").widgets.center[0];
        verify(own !== "clock");
        compare(t.widgets[own], { format: "%H", type: "clock" });
        compare(M.usage(t, "clock"), 1);
    }

    // 10–12. three bars on the top edge, one on the right, moving one leaves the rest
    function test_three_top_bars_and_a_right_bar_are_independent() {
        const p = M.applyPreset(empty(), M.presetByKey("three-top"), "add", 100);
        compare(p.ids.length, 3);
        let s = p.state;
        compare(s.bars.map(b => [b.edge, b.anchor]), [["top", "start"], ["top", "center"], ["top", "end"]]);
        const right = made(s, { edge: "right", anchor: "center" }, "Right", 200);
        s = right.state;
        compare(s.bars.length, 4);
        const before = JSON.stringify(s.bars.filter(b => b.id !== p.ids[1]));
        s = M.place(s, p.ids[1], "bottom", "center");
        compare(M.find(s, p.ids[1]).edge, "bottom");
        compare(JSON.stringify(s.bars.filter(b => b.id !== p.ids[1])), before, "the others did not move");
        // every component on them is an instance of its own
        const all = s.bars.reduce((a, b) => a.concat(M.entriesOf(b)), []);
        compare(new Set(all).size, all.length);
    }
    function test_reservations_share_an_edge_instead_of_stacking() {
        const p = M.applyPreset(empty(), M.presetByKey("three-top"), "add", 1);
        const r = M.reservations(p.state.bars, "eDP-1");
        compare(r.top, 40, "34 thick + 6 margin, once — not three times");
        compare(r.left, 0);
        const off = M.setKey(p.state, p.ids[0], "visibility", "smart");
        compare(M.reservations(off.bars, "eDP-1").top, 40, "a hiding bar keeps no room, the others still do");
        const deeper = M.setKey(p.state, p.ids[2], "thickness", 50);
        compare(M.reservations(deeper.bars, "eDP-1").top, 56, "the deepest bar on the edge decides");
        const elsewhere = M.setKey(p.state, p.ids[0], "screens", ["HDMI-A-1"]);
        compare(M.reservations(elsewhere.bars, "HDMI-A-1").top, 40);
    }
    function test_along_range_respects_the_neighbouring_edges_when_asked() {
        const reserved = { top: 40, bottom: 0, left: 39, right: 0 };
        compare(M.alongRange({ edge: "top" }, 1920, reserved), [0, 1920]);
        compare(M.alongRange({ edge: "top", reference: "workspace" }, 1920, reserved), [39, 1920]);
        compare(M.alongRange({ edge: "right", reference: "workspace" }, 1200, reserved), [40, 1200]);
    }

    // presets add or replace without deleting anything
    function test_preset_replace_turns_the_old_layout_off_and_keeps_it() {
        let r = made(empty(), {}, "Mine", 1);
        const p = M.applyPreset(r.state, M.presetByKey("top"), "replace", 50);
        compare(p.state.bars.length, 2);
        compare(M.find(p.state, r.id).enabled, false);
        compare(M.find(p.state, p.ids[0]).enabled, true);
    }
    function test_custom_preset_round_trip_makes_fresh_instances() {
        let r = made(empty(), { edge: "left", anchor: "fill", widgets: { center: ["clock"] } }, "Rail", 1);
        const c = r.state.bars[0].widgets.center[0];
        let s = { bars: r.state.bars, widgets: Object.assign({}, r.state.widgets, { [c]: { type: "clock", format: "%H" } }) };
        const preset = M.presetFrom(s, [r.id], "My rail", "custom-1");
        compare(preset.bars[0].spec.widgets.center[0], { type: "clock", settings: { format: "%H" } });
        const p = M.applyPreset(s, preset, "add", 9);
        const fresh = M.find(p.state, p.ids[0]);
        compare(fresh.name, "Rail 2");
        compare(fresh.edge, "left");
        verify(fresh.widgets.center[0] !== c);
        compare(p.state.widgets[fresh.widgets.center[0]].format, "%H");
    }

    function test_reset_keeps_identity_and_contents() {
        let r = made(empty(), { edge: "bottom", anchor: "end", thickness: 60, opacity: 0.3, widgets: { end: ["clock"] } }, "B", 1);
        const s = M.reset(r.state, r.id);
        const b = M.find(s, r.id);
        compare(b.edge, "bottom");
        compare(b.anchor, "end");
        compare(b.name, "B");
        compare(b.thickness, undefined);
        compare(b.opacity, undefined);
        compare(b.widgets.end.length, 1);
    }
    function test_reorder_bars() {
        let s = made(empty(), {}, "A", 1).state;
        s = made(s, {}, "B", 2).state;
        s = made(s, {}, "C", 3).state;
        const c = s.bars[2].id;
        s = M.move(s, c, -1);
        compare(s.bars.map(b => b.name), ["A", "C", "B"]);
        compare(M.move(s, s.bars[0].id, -1), s, "nothing above the first");
    }

    // 14. migration
    function test_migrate_v1_names_bars_from_ids_and_keeps_every_key() {
        const v1 = { bar: [{ id: "rail", edge: "left", anchor: "end", custom_future_key: 3, widgets: { end: ["tray"] } }, { id: "top-2", edge: "top" }], widget: { tray: { drawer: true } } };
        const m = M.migrate(v1);
        verify(m.changed);
        compare(m.file.schema, 2);
        compare(m.file.bar.map(b => [b.id, b.name]), [["rail", "Rail"], ["top-2", "Top 2"]]);
        compare(m.file.bar[0].custom_future_key, 3);
        compare(m.file.widget, v1.widget);
        const again = M.migrate(m.file);
        verify(!again.changed, "idempotent");
        compare(again.file, m.file);
    }
    function test_migrate_repairs_duplicate_and_missing_ids() {
        const m = M.migrate({ bar: [{ id: "a" }, { id: "a" }, { edge: "top" }] });
        const got = m.file.bar.map(b => b.id);
        compare(new Set(got).size, 3);
        compare(got[0], "a");
        verify(m.notes.some(n => n.indexOf("two bars had the id a") >= 0));
    }

    // 15. invalid configuration
    function test_validate_recovers_from_nonsense() {
        const v = M.validate({ bars: [42, { id: "x", edge: "diagonal", anchor: 5, thickness: "big", enabled: "false", widgets: { start: "clock", end: [1, "battery", ""] }, screens: "eDP-1" }], widgets: [] });
        compare(v.state.bars.length, 1);
        const b = v.state.bars[0];
        compare(b.edge, "top");
        compare(b.anchor, "center");
        compare(b.thickness, undefined);
        compare(b.enabled, false);
        compare(b.widgets.start, ["clock"]);
        compare(b.widgets.end, ["battery"]);
        compare(b.screens, ["eDP-1"]);
        compare(v.state.widgets, {});
        verify(v.problems.length >= 5);
    }
    function test_validate_keeps_a_good_layout_unchanged() {
        const good = { bars: [{ id: "a", name: "A", edge: "top", anchor: "fill", widgets: { start: ["clock"] } }], widgets: { clock: {} } };
        const v = M.validate(good);
        compare(v.problems, []);
        compare(v.state.bars[0], good.bars[0]);
    }

    function test_places_said_in_plain_words() {
        const r = made(empty(), { edge: "top", anchor: "left" }, "A", 1);
        compare(r.state.bars[0].anchor, "start");
        compare(M.find(M.place(r.state, r.id, "right", "bottom"), r.id).anchor, "end");
        compare(M.find(M.place(r.state, r.id, "top", "Centre"), r.id).anchor, "center");
        compare(M.place(r.state, r.id, "top", "diagonal"), r.state, "nonsense is refused");
    }
    function test_position_labels() {
        compare(M.positionLabel({ edge: "top", anchor: "start" }), "Top · Left");
        compare(M.positionLabel({ edge: "right", anchor: "end" }), "Right · Bottom");
        compare(M.positionLabel({ edge: "bottom", anchor: "fill" }), "Bottom · Full length");
    }

    // ── corners ──
    readonly property var sheet: ({ w: 400, h: 40 })
    function test_corners_each_on_its_own() {
        const b = { edge: "top", thickness: 40, radius: 4, radius_top_left: 1, radius_top_right: 2, radius_bottom_right: 3, radius_bottom_left: 20 };
        compare(M.cornerRadii(b, sheet, 1, null), [1, 2, 3, 20]);
        compare(M.cornerRadii(Object.assign({}, b, { radius_top_right: -1 }), sheet, 1, null), [1, 4, 3, 20], "-1 follows the radius");
    }
    function test_corners_linked_and_pill() {
        compare(M.cornerRadii({ edge: "top", thickness: 40, radius: 6 }, sheet, 1, null), [6, 6, 6, 6]);
        compare(M.cornerRadii({ edge: "top", thickness: 40 }, sheet, 1, null), [20, 20, 20, 20], "no radius: a pill");
        compare(M.cornerRadii({ edge: "top", thickness: 40, radius: 6 }, sheet, 1.5, null), [9, 9, 9, 9], "the theme's corner scale applies");
    }
    function test_corners_are_held_to_what_the_sheet_can_show() {
        compare(M.cornerRadii({ edge: "top", thickness: 39, radius: 0, radius_bottom_left: 48 }, { w: 300, h: 39 }, 1, null), [0, 0, 0, 19.5]);
    }
    function test_flowing_into_the_edge_squares_only_the_edge_corners() {
        // one tested rail: top edge, right end, flows into the edge; top right 48 can only ever be square
        const rail = { edge: "top", anchor: "end", thickness: 39, margin: 0, concave_edge_corners: true, radius: 0, radius_top_right: 48, radius_bottom_left: 48 };
        compare(M.cornerRadii(rail, { w: 300, h: 39 }, 1, null), [0, 0, 0, 19.5]);
        compare(M.squaredCorners(rail), [0, 1], "Settings is told which corners are square, and why");
        compare(M.squaredCorners(Object.assign({}, rail, { margin: 6 })), [], "with a gap to the edge nothing is squared");
        compare(M.squaredCorners({ edge: "left", anchor: "fill", concave_edge_corners: true }), [1, 2], "a full-length bar flows into the screen's ends: its inner corners");
    }
    function test_a_joined_panel_squares_only_its_own_corners_and_lets_go() {
        const b = { edge: "top", thickness: 40, radius: 10 };
        compare(M.cornerRadii(b, sheet, 1, { start: true, end: false, progress: 1 }), [10, 10, 10, 0], "start side of the inner (bottom) edge: bottom left");
        compare(M.cornerRadii(b, sheet, 1, { start: false, end: true, progress: 1 }), [10, 10, 0, 10], "end side: bottom right");
        compare(M.cornerRadii(b, sheet, 1, { start: true, end: true, progress: 0.5 }), [10, 10, 5, 5], "halfway there");
        compare(M.cornerRadii(b, sheet, 1, { start: true, end: true, progress: 0 }), [10, 10, 10, 10], "detached: the configured radii again");
        compare(M.cornerRadii({ edge: "left", thickness: 40, radius: 10 }, { w: 40, h: 400 }, 1, { start: true, end: false, progress: 1 }), [10, 0, 10, 10], "a left bar: top right");
    }
    function test_linking_and_unlinking_keeps_the_shape() {
        let r = made(empty(), { edge: "top", thickness: 40, radius: 8 }, "A", 1);
        verify(M.cornersLinked(M.find(r.state, r.id)));
        let s = M.setCornersLinked(r.state, r.id, false);
        const b = M.find(s, r.id);
        compare([b.radius_top_left, b.radius_top_right, b.radius_bottom_right, b.radius_bottom_left], [8, 8, 8, 8], "each corner starts as drawn");
        verify(!M.cornersLinked(b));
        s = M.setKey(s, r.id, "radius_top_left", 14);
        s = M.setCornersLinked(s, r.id, true);
        const c = M.find(s, r.id);
        compare(c.radius, 14, "linked again: the top left corner's value");
        compare(c.radius_top_left, undefined);
        compare(M.cornerRadii(c, sheet, 1, null), [14, 14, 14, 14]);
        // an unset radius (a pill) unlinks to the pill's radius
        let p = made(empty(), { edge: "top", thickness: 30 }, "P", 2);
        const q = M.find(M.setCornersLinked(p.state, p.id, false), p.id);
        compare(q.radius_bottom_left, 15);
    }
}
