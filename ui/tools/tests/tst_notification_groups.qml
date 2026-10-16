import QtQuick
import QtTest
import "../../Common/NotificationGroups.js" as G

// Common/NotificationGroups.js: the notification centre's sections, stacks, keyboard order and ages.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_notification_groups.qml
TestCase {
    name: "NotificationGroups"

    // a fixed "now": 16 Oct 2026, 15:00 local
    readonly property real now: new Date(2026, 9, 16, 15, 0, 0).getTime()
    function n(key: int, app: string, minutesAgo: real): var {
        return { key: key, appName: app, summary: "s" + key, body: "b" + key, time: now - minutesAgo * 60000 };
    }
    readonly property var history: [
        n(1, "Discord", 2), n(2, "Firefox", 5), n(3, "Discord", 10), n(4, "Discord", 30),
        n(5, "Mail", 180),
        n(6, "Discord", 60 * 26)
    ]
    function rowsOf(over: var): var {
        return G.build(history, Object.assign({ now: now }, over || {}));
    }

    function test_sections_in_time_order() {
        const sections = rowsOf().filter(r => r.kind === "section").map(r => r.label);
        compare(sections, ["Now", "Today", "Earlier"]);
    }

    function test_one_stack_per_app_newest_first() {
        const groups = rowsOf().filter(r => r.kind === "group");
        compare(groups.map(g => g.app), ["Discord", "Firefox", "Mail", "Discord"]);
        compare(groups[0].entries.map(e => e.key), [1, 3, 4]);
        verify(groups[0].stacked);
        verify(!groups[1].stacked, "a group of one is never stacked");
    }

    function test_an_opened_app_unstacks() {
        const groups = rowsOf({ opened: { Discord: true } }).filter(r => r.kind === "group");
        verify(groups[0].open && !groups[0].stacked);
    }

    function test_search_lists_matches_alone() {
        const groups = rowsOf({ query: "discord" }).filter(r => r.kind === "group");
        compare(groups.length, 4);
        verify(groups.every(g => g.entries.length === 1 && !g.stacked));
        compare(rowsOf({ query: "nothing like this" }).length, 0);
    }

    function test_grouping_off_lists_each() {
        const groups = rowsOf({ grouping: false }).filter(r => r.kind === "group");
        compare(groups.length, 6);
    }

    function test_keyboard_order() {
        // stacked Discord is one stop; open, it is its header and then each card
        const closed = G.stops(rowsOf());
        compare(closed.map(s => s.id), ["g:now:Discord", "e2", "e5", "e6"]);
        const open = G.stops(rowsOf({ opened: { Discord: true } }));
        compare(open.map(s => s.id), ["g:now:Discord", "e1", "e3", "e4", "e2", "e5", "e6"]);
    }

    function test_steps_hold_at_the_ends_and_survive_removal() {
        const list = G.stops(rowsOf());
        compare(G.step(list, "e2", 1), "e5");
        compare(G.step(list, "e6", 1), "e6");
        compare(G.step(list, "g:now:Discord", -1), "g:now:Discord");
        // e5 dismissed: the stop at its old index takes its place
        const after = list.filter(s => s.id !== "e5");
        compare(G.step(after, "e5", 0, 2), "e6");
        compare(G.step([], "e1", 1), "");
    }

    function test_ages_in_words() {
        compare(G.ago(now - 20 * 1000, now), "now");
        compare(G.ago(now - 4 * 60000, now), "4m");
        compare(G.ago(now - 2 * 3600000, now), "2h");
        compare(G.ago(new Date(2026, 9, 15, 20, 0).getTime(), now), "yesterday");
        compare(G.ago(new Date(2026, 9, 13, 9, 0).getTime(), now), "3d");
        compare(G.ago(new Date(2026, 8, 2, 9, 0).getTime(), now), "2 Sep");
    }
}
