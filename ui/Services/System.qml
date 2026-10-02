pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU and memory, sampled only while something on screen holds a reference (retain/release), at the
// policy's update interval. This is the spike's stand-in for the native sampler in Zynith.Native.
Singleton {
    id: root

    property int demand: 0
    property real cpu: 0          // 0..1 across all cores
    property real memUsed: 0      // 0..1
    property real memTotalGiB: 0
    property var lastCpu: null

    function retain(): void {
        demand++;
        if (demand === 1)
            sample();
    }
    function release(): void {
        demand = Math.max(0, demand - 1);
    }
    function sample(): void {
        stat.reload();
        meminfo.reload();
    }

    Timer {
        running: root.demand > 0
        repeat: true
        interval: ExperiencePolicy.updateIntervalMs
        onTriggered: root.sample()
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n", 1)[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total;
                root.cpu = dt > 0 ? 1 - (idle - root.lastCpu.idle) / dt : 0;
            }
            root.lastCpu = {
                idle: idle,
                total: total
            };
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const total = parseInt((t.match(/^MemTotal:\s*(\d+)/m) || [])[1] || "0");
            const avail = parseInt((t.match(/^MemAvailable:\s*(\d+)/m) || [])[1] || "0");
            root.memTotalGiB = total / 1048576;
            root.memUsed = total > 0 ? 1 - avail / total : 0;
        }
    }
}
