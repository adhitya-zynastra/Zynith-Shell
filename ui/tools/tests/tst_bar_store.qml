import QtQuick
import QtTest
import Zynith.Native
import "../../Common/BarModel.js" as M

// The bar model through the real config store (Zynith.Native ConfigFile): what QML actually receives from a TOML
// file is not what a test builds by hand (a list arrives list-like, not as an Array; a bar has a `length` key of
// its own). A first migration emptied the bars on exactly that, with every hand-built test passing.
//   tools/tests/run-store-tests.sh
TestCase {
    name: "BarStore"

    // run-store-tests.sh fills it: a.toml b.toml c.toml (copies of fixtures/bars-v1.toml), d.toml (of
    // fixtures/bars-broken.toml), and the untouched originals to compare against
    readonly property string dir: "/tmp/zynith-bar-store-test"

    Component {
        id: fileComponent
        ConfigFile {
            defaults: ({ bar: [{ id: "main", edge: "top" }] })
        }
    }

    function open(name) {
        const f = createTemporaryObject(fileComponent, this, { path: dir + "/" + name });
        tryVerify(() => f.loaded, 3000);
        return f;
    }

    function test_lists_from_the_store_are_read_as_lists() {
        const f = open("a.toml");
        compare(f.error, "", "the fixture parses");
        const raw = f.values.bar;
        compare(M.list(raw).length, 3, "three bars, whatever kind of list the store hands over");
        verify(!M.isList(raw[0]), "a bar with a length key is a table, not a list");
        const v = M.validate({ bars: raw, widgets: f.values.widget });
        compare(v.problems, []);
        compare(v.state.bars.map(b => b.id), ["rail", "time", "top-2"]);
        compare(v.state.bars[0].widgets.end, ["tray", "group:status"]);
        compare(v.state.bars[0].group[0].members, ["network", "volume"]);
    }

    function test_migration_through_the_store_keeps_every_bar_and_key() {
        const f = open("b.toml");
        const m = M.migrate({ schema: f.values.schema, bar: f.values.bar, widget: f.values.widget });
        verify(m.changed);
        compare(m.file.bar.length, 3);
        verify(f.backup("pre-schema-2") !== "");
        verify(f.assign({ schema: m.file.schema, bar: m.file.bar }));
        // read back from disk by a fresh store
        const g = open("b.toml");
        compare(g.values.schema, 2);
        const bars = M.list(g.values.bar);
        compare(bars.map(b => b.name), ["Rail", "Time", "Top 2"]);
        compare(bars[0].length, 0);
        compare(bars[0].thickness, 39);
        compare(g.values.widget.clock.format, "%H:%M");
        // the backup is the file as it was: it reads back as the original does
        const backup = open("b.toml.pre-schema-2");
        const original = open("v1-original.toml");
        compare(JSON.stringify(backup.values), JSON.stringify(original.values));
        // idempotent through the store as well
        verify(!M.migrate({ schema: g.values.schema, bar: g.values.bar, widget: g.values.widget }).changed);
    }

    function test_assign_writes_bars_and_components_together() {
        const f = open("c.toml");
        const state = M.validate({ bars: f.values.bar, widgets: f.values.widget }).state;
        const made = M.create(state, { edge: "top", anchor: "end", widgets: { end: ["clock"] } }, "Top right", 5);
        verify(f.assign({ bar: made.state.bars, widget: made.state.widgets }));
        const g = open("c.toml");
        const bars = M.list(g.values.bar);
        compare(bars.length, 4);
        const inst = bars[3].widgets.end[0];
        compare(g.values.widget[inst].type, "clock", "the new bar's component table landed in the same write");
        compare(g.values.widget.clock.format, "%H:%M", "the shared kind table is untouched");
    }

    function test_a_file_that_does_not_parse_is_never_written_over() {
        const f = open("d.toml");
        verify(f.error !== "");
        f.set("bar", []);
        verify(!f.assign({ bar: [] }));
        verify(open("d.toml").error !== "", "still the broken file: nothing was written over it");
        const aside = f.recover({ schema: 2 });
        verify(aside.indexOf("d.toml.broken-") > 0);
        verify(open(aside.slice(dir.length + 1)).error !== "", "moved aside as it was");
        compare(f.error, "");
        compare(M.list(f.values.bar).map(b => b.id), ["main"], "the default bar again");
    }

    // a key set and then reset leaves the file as it was: no empty [table] behind (Settings' undo relies on it;
    // run-store-tests.sh compares e.toml with the untouched original afterwards)
    function test_reset_leaves_no_empty_table() {
        // the fixture's own header, as a real file carries the one the store wrote
        const f = createTemporaryObject(fileComponent, this, { path: dir + "/e.toml", header: "Bars. (a v1 file as written before schema 2: indented sub-tables, a bar with its own length key)" });
        tryVerify(() => f.loaded, 3000);
        verify(f.values.panels === undefined, "no [panels] table to begin with");
        f.set("panels.attach", false);
        tryVerify(() => f.values.panels?.attach === false, 3000, "the key is written");
        f.reset("panels.attach");
        tryVerify(() => f.values.panels === undefined, 3000, "the emptied table goes with the key");
        verify(!f.has("panels.attach"), "has(): the file no longer sets it");
        f.set("panels.attach", true);
        tryVerify(() => f.has("panels.attach"), 3000, "has(): the file sets it");
        verify(!f.has("bar.0.nothing"), "has(): a key only the defaults might hold is not the file's");
        f.reset("panels.attach");
        tryVerify(() => f.values.panels === undefined, 3000);
        f.reset("nothing.here");
        wait(200);
        verify(f.values.nothing === undefined, "resetting a key that is not there creates nothing");
    }
}
