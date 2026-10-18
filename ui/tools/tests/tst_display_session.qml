import QtQuick
import QtTest
import Zynith.Native

// DisplayConfig against a running niri (NIRI_SOCKET): every request it makes must be accepted — the trial, the
// timed-out revert and an explicit revert. Run inside a test niri, never against a real display:
//   <in the nested session> qmltestrunner -import ../build/ui-native/qml -input tools/tests/tst_display_session.qml
TestCase {
    name: "DisplaySession"
    property var log: []
    Connections {
        target: DisplayConfig
        function onApplied(o: string, ok: bool, m: string): void { log.push("applied " + ok + " " + m); }
        function onFinished(o: string, kept: bool, m: string): void { log.push("finished " + kept + " " + m); }
    }
    function init() { log = []; }
    function test_trial_then_timeout_restores() {
        tryVerify(() => DisplayConfig.outputs.length > 0, 3000);
        const name = DisplayConfig.outputs[0].name;
        DisplayConfig.setTransform(name, "90", 5);
        tryVerify(() => log.length >= 1, 3000);
        compare(log[0], "applied true ");
        verify(DisplayConfig.pending);
        tryVerify(() => log.length >= 2, 9000, "the countdown ends by itself");
        compare(log[1], "finished false Orientation restored");
        compare(DisplayConfig.lastError, "");
        verify(!DisplayConfig.pending);
    }
    function test_explicit_revert() {
        tryVerify(() => DisplayConfig.outputs.length > 0, 3000);
        const name = DisplayConfig.outputs[0].name;
        DisplayConfig.setTransform(name, "flipped-270", 10);
        tryVerify(() => log.length >= 1, 3000);
        compare(log[0], "applied true ");
        DisplayConfig.revert();
        tryVerify(() => log.length >= 2, 3000);
        compare(log[1], "finished false Orientation restored");
    }
    function test_missing_output_is_refused() {
        DisplayConfig.setTransform("NOPE-9", "90", 5);
        tryVerify(() => log.length >= 1, 3000);
        verify(log[0].startsWith("applied false"), log[0]);
        verify(!DisplayConfig.pending);
    }
}
