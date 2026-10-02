import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The weather now: its condition and temperature (each if asked), from what the native shell fetched.
BarItem {
    id: root
    shown: Weather.valid
    Component.onCompleted: Weather.retain()
    Component.onDestruction: Weather.release()
    BarGlyph {
        item: root
        visible: root.opt("show_condition") !== false
        name: Weather.glyph(Weather.data.current?.code ?? 0, Weather.data.current?.isDay ?? true)
    }
    BarText {
        item: root
        visible: root.opt("show_temperature") !== false && !root.vertical
        width: Math.min(implicitWidth, root.opt("max_length") ?? 160)
        text: Math.round(Weather.data.current?.temperature ?? 0) + (Weather.data.unit ?? "°")
    }
}
