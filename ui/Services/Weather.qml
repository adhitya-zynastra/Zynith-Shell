pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// The weather the native shell already fetches (weather-status), read while something shows it.
Singleton {
    id: root

    property var data: ({ valid: false })
    readonly property bool valid: data.valid ?? false
    property int consumers: 0

    function retain(): void {
        if (++consumers === 1)
            refresh();
    }
    function release(): void {
        consumers = Math.max(0, consumers - 1);
    }
    function refresh(): void {
        CoreClient.call("weather-status", text => {
            try {
                root.data = JSON.parse(text);
            } catch (e) {}
        });
    }
    Timer {
        running: root.consumers > 0
        repeat: true
        interval: 600000
        onTriggered: root.refresh()
    }

    // WMO weather codes → a glyph
    function glyph(code: int, isDay: bool): string {
        if (code === 0 || code === 1)
            return isDay ? "sun" : "moon-stars";
        if (code === 2 || code === 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "cloud-fog";
        if (code >= 51 && code <= 67 || code >= 80 && code <= 82)
            return "cloud-rain";
        if (code >= 71 && code <= 77 || code === 85 || code === 86)
            return "cloud-snow";
        if (code >= 95)
            return "cloud-storm";
        return "cloud";
    }
}
