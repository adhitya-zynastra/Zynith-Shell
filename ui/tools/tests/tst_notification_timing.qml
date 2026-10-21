import QtQuick
import QtTest
import "../../Common/NotificationTiming.js" as T

// Common/NotificationTiming.js: how long a popup stays, per the notification spec's expire_timeout.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -input tools/tests/tst_notification_timing.qml
TestCase {
    name: "NotificationTiming"

    readonly property int def: 6000
    function n(over: var): var {
        return Object.assign({ urgency: 1, resident: false, expireTimeout: -1, timeoutOverride: 0 }, over);
    }

    // blueman's pairing request: Confirm/Deny, expire_timeout 0 — it must wait for an answer
    function test_zero_means_never() {
        compare(T.popupTimeout(n({ expireTimeout: 0 }), def), 0);
        compare(T.popupTimeout(n({ expireTimeout: 0, urgency: 0 }), def), 0);
    }
    function test_zero_wins_over_a_rule() {
        compare(T.popupTimeout(n({ expireTimeout: 0, timeoutOverride: 3000 }), def), 0);
    }
    function test_minus_one_is_the_default() {
        compare(T.popupTimeout(n({}), def), def);
        compare(T.popupTimeout(n({ urgency: 0 }), def), def * 0.7);
    }
    function test_sender_time_is_kept() {
        compare(T.popupTimeout(n({ expireTimeout: 5000 }), def), 5000);
        compare(T.popupTimeout(n({ expireTimeout: 60000 }), def), 60000);
        compare(T.popupTimeout(n({ expireTimeout: 300 }), def), 2000);
    }
    function test_critical_and_resident_stay() {
        compare(T.popupTimeout(n({ urgency: 2, expireTimeout: 5000 }), def), 0);
        compare(T.popupTimeout(n({ resident: true }), def), 0);
    }
    function test_rule_over_default() {
        compare(T.popupTimeout(n({ timeoutOverride: 9000 }), def), 9000);
    }
}
