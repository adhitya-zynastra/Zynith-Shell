import QtQuick
import QtTest
import Zynith.Native

// DisplayConfig (native): the edit that persists an orientation into niri's own configuration. It must touch only
// the first top-level block for that output (the one niri uses), keep everything else byte for byte, ignore
// comments, and write nothing for a no-op.
//   QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner -import ../build/ui-native/qml -input tools/tests/tst_display_config.qml
TestCase {
    name: "DisplayConfig"

    readonly property string cfg: '// output "eDP-1" { transform "180" }  (a comment, not a block)\n'
        + 'input {\n    keyboard {\n        numlock\n    }\n}\n\n'
        + 'output "eDP-1" {\n    mode "1920x1200@59.999"\n    scale 1.0\n}\n\n'
        + 'layout {\n    gaps 15\n}\n'
        + 'output "eDP-1" {\n    scale 2.0\n}\n'

    function test_canonical_names() {
        compare(DisplayConfig.canonical("Normal"), "normal");
        compare(DisplayConfig.canonical("_90"), "90");
        compare(DisplayConfig.canonical("270"), "270");
        compare(DisplayConfig.canonical("Flipped180"), "flipped-180");
        compare(DisplayConfig.canonical("flipped-90"), "flipped-90");
        compare(DisplayConfig.canonical("sideways"), "");
    }
    function test_inserts_into_the_first_block_only() {
        const out = DisplayConfig.withTransform(cfg, "eDP-1", "90");
        const lines = out.split("\n");
        const first = lines.indexOf('output "eDP-1" {');
        compare(lines[first + 1], '    transform "90"', "right after the opening line, block indent");
        compare(out.split('transform "90"').length - 1, 1, "once");
        verify(out.indexOf('output "eDP-1" {\n    scale 2.0\n}') >= 0, "the later block untouched");
        verify(out.startsWith('// output "eDP-1" { transform "180" }'), "the comment untouched");
        compare(out.replace('    transform "90"\n', ""), cfg, "nothing else changed");
    }
    function test_replaces_and_removes_an_existing_line() {
        const rotated = DisplayConfig.withTransform(cfg, "eDP-1", "270");
        const again = DisplayConfig.withTransform(rotated, "eDP-1", "180");
        compare(again.split("transform").length - 1, 2, "the comment's and one line");
        verify(again.indexOf('    transform "180"') >= 0);
        compare(DisplayConfig.withTransform(again, "eDP-1", "normal"), cfg, "normal removes the line: the file is as it was");
    }
    function test_no_block_appends_one_and_normal_is_a_no_op() {
        const text = 'output "eDP-1" {\n    scale 1.0\n}\n';
        compare(DisplayConfig.withTransform(text, "HDMI-A-1", "normal"), text);
        const out = DisplayConfig.withTransform(text, "HDMI-A-1", "90");
        verify(out.startsWith(text));
        verify(out.indexOf('output "HDMI-A-1" {\n    transform "90"\n}') > 0);
        verify(DisplayConfig.hasOutputBlock(out, "HDMI-A-1"));
        verify(!DisplayConfig.hasOutputBlock(cfg, "DP-2"));
    }
    function test_unknown_transform_changes_nothing() {
        compare(DisplayConfig.withTransform(cfg, "eDP-1", "sideways"), cfg);
    }
}
