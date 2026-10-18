import QtQuick
import QtTest
import "../../Common/IslandModel.js" as I

// Common/IslandModel.js: the island's activities, their priority and their ends.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_island_model.qml
TestCase {
    name: "IslandModel"

    function test_a_notification_outranks_music_and_ends_on_time() {
        let l = [];
        l = I.upsert(l, I.media({ present: true, playing: true, title: "T" }, false, 1000));
        l = I.upsert(l, I.notification({ key: 7, appName: "Mail", summary: "Hi", body: "There" }, 5000, "full", 2000));
        compare(I.primary(l, "").kind, "notification");
        compare(I.secondary(l, "").kind, "media");
        compare(I.nextEnd(l), 7000);
        compare(I.primary(I.live(l, 7001), "").kind, "media", "gone after its timeout");
    }
    function test_critical_stays_and_outranks_everything() {
        let l = [I.notification({ key: 1, summary: "a" }, 5000, "full", 0), I.notification({ key: 2, summary: "b" }, 0, "full", 10)];
        compare(I.primary(l, "").data.key, 2);
        compare(I.live(l, 1e9).length, 1);
        compare(I.nextEnd([l[1]]), 0);
    }
    function test_newest_of_equals_first() {
        const l = [I.device("Speakers", "volume", 100), I.power(true, 0.6, 200)];
        compare(I.primary(l, "").kind, "power");
    }
    function test_the_one_the_user_picked_stays_shown_while_it_lasts() {
        let l = [I.media({ present: true, playing: true }, false, 0), I.notification({ key: 3, summary: "x" }, 4000, "full", 10)];
        compare(I.primary(l, "media").kind, "media");
        compare(I.secondary(l, "media").kind, "notification");
        l = I.remove(l, "media");
        compare(I.primary(l, "media").kind, "notification", "a pick that is gone falls back");
    }
    function test_privacy() {
        const e = { key: 1, appName: "Chat", summary: "Ana", body: "secret" };
        compare(I.notification(e, 4000, "summary", 0).data.body, "");
        compare(I.notification(e, 4000, "app", 0).data.summary, "");
        compare(I.notification(e, 4000, "full", 0).data.body, "secret");
    }
    function test_media_only_while_playing_unless_paused_is_kept() {
        compare(I.media({ present: true, playing: false }, false, 0), null);
        compare(I.media({ present: true, playing: false }, true, 0).priority, I.priorities.paused);
        compare(I.media({ present: false, playing: true }, true, 0), null);
    }
    function test_replacing_keeps_one_per_id() {
        let l = I.upsert([], I.device("A", "volume", 0));
        l = I.upsert(l, I.device("B", "headphones", 5));
        compare(l.length, 1);
        compare(l[0].data.name, "B");
    }
}
