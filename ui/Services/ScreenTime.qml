pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native

// Screen time as the native shell keeps it (screen-time [days]): the total, the apps, and the hours of today
// or the days of a range. Read while something shows it, again every few minutes while it stays open.
Singleton {
    id: root

    property int days: 1
    property var data: ({ enabled: false, total: 0, apps: [], buckets: [], labels: [] })
    readonly property bool enabled: data.enabled ?? false
    readonly property int total: data.total ?? 0
    readonly property var apps: data.apps ?? []
    readonly property var buckets: data.buckets ?? []
    readonly property var labels: data.labels ?? []
    readonly property bool hourly: data.hourly ?? true
    property int consumers: 0

    function retain(): void {
        if (++consumers === 1)
            refresh();
    }
    function release(): void {
        consumers = Math.max(0, consumers - 1);
    }
    function setDays(n: int): void {
        if (n === days)
            return;
        days = n;
        refresh();
    }
    function refresh(): void {
        CoreClient.call("screen-time " + root.days, text => {
            try {
                root.data = JSON.parse(text);
            } catch (e) {}
        });
    }
    Timer {
        running: root.consumers > 0
        repeat: true
        interval: 300000
        onTriggered: root.refresh()
    }

    // 3h 12m · 45m · under a minute
    function format(seconds: real): string {
        const h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60);
        return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m" : seconds > 0 ? "<1m" : "0m";
    }
}
