pragma Singleton
import QtQuick
// test stand-in for Common/Theme (colours only matter to the eye)
QtObject {
    readonly property color accent: "#8af"
    readonly property color accentSoft: "#335"
    readonly property color accentLine: "#88f"
    readonly property color danger: "#f55"
    readonly property color ink: "#eee"
    readonly property color inkMuted: "#aaa"
    readonly property color inkFaint: "#777"
    readonly property color hover: "#333"
    readonly property color hairline: "#444"
    readonly property color well: "#222"
    readonly property color base: "#111"
    readonly property color rule: "#555"
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
}
