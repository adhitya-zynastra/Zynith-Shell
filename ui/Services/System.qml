pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU, memory, temperature and network, sampled only while something on screen holds a reference
// (retain/release), at the profile's update interval. Each stat keeps its last minute for graphs.
Singleton {
    id: root

    property int demand: 0
    property real cpu: 0          // 0..1 across all cores
    property real memUsed: 0      // 0..1
    property real memTotalGiB: 0
    property real swapUsed: 0     // 0..1
    property real cpuTemp: 0      // °C, 0 when unknown
    property real cpuFreqGHz: 0
    property real rxBps: 0        // bytes per second, all interfaces but loopback
    property real txBps: 0
    property var lastCpu: null
    property var lastNet: null

    // the last samples of each stat, oldest first: cpu_usage cpu_temp cpu_freq ram_pct swap_pct net_rx net_tx
    property var history: ({})
    readonly property int historyLength: 60

    function retain(): void {
        demand++;
        if (demand === 1) {
            if (thermalPath === "" && !findThermal.running)
                findThermal.running = true;
            sample();
        }
    }
    function release(): void {
        demand = Math.max(0, demand - 1);
    }
    function sample(): void {
        stat.reload();
        meminfo.reload();
        netdev.reload();
        if (thermalPath !== "")
            thermal.reload();
        freq.reload();
    }

    // a stat by its widget name: the value, a 0..1 level for gauges, and how to say it
    function read(name: string): var {
        switch (name) {
        case "cpu_usage":
            return { value: cpu, level: cpu, text: Math.round(cpu * 100) + "%", label: "CPU" };
        case "cpu_temp":
            return { value: cpuTemp, level: Math.min(1, cpuTemp / 100), text: cpuTemp > 0 ? Math.round(cpuTemp) + "°" : "—", label: "Temp" };
        case "cpu_freq":
            return { value: cpuFreqGHz, level: Math.min(1, cpuFreqGHz / 5), text: cpuFreqGHz.toFixed(1) + " GHz", label: "Clock" };
        case "ram_pct":
            return { value: memUsed, level: memUsed, text: Math.round(memUsed * 100) + "%", label: "Memory" };
        case "swap_pct":
            return { value: swapUsed, level: swapUsed, text: Math.round(swapUsed * 100) + "%", label: "Swap" };
        case "net_rx":
            return { value: rxBps, level: Math.min(1, rxBps / 12500000), text: rate(rxBps), label: "Down" };
        case "net_tx":
            return { value: txBps, level: Math.min(1, txBps / 12500000), text: rate(txBps), label: "Up" };
        }
        return { value: 0, level: 0, text: "", label: "" };
    }
    function rate(bps: real): string {
        return bps < 1024 ? Math.round(bps) + " B/s" : bps < 1048576 ? (bps / 1024).toFixed(0) + " KB/s" : (bps / 1048576).toFixed(1) + " MB/s";
    }
    function push(name: string, level: real): void {
        const h = Object.assign({}, history);
        const list = (h[name] ?? []).concat([level]);
        h[name] = list.length > historyLength ? list.slice(list.length - historyLength) : list;
        history = h;
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
                root.push("cpu_usage", root.cpu);
            }
            root.lastCpu = { idle: idle, total: total };
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const num = k => parseInt((t.match(new RegExp("^" + k + ":\\s*(\\d+)", "m")) || [])[1] || "0");
            const total = num("MemTotal"), avail = num("MemAvailable");
            const swapTotal = num("SwapTotal"), swapFree = num("SwapFree");
            root.memTotalGiB = total / 1048576;
            root.memUsed = total > 0 ? 1 - avail / total : 0;
            root.swapUsed = swapTotal > 0 ? 1 - swapFree / swapTotal : 0;
            root.push("ram_pct", root.memUsed);
            root.push("swap_pct", root.swapUsed);
        }
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m || m[1] === "lo")
                    continue;
                const f = m[2].split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now();
            if (root.lastNet) {
                const dt = (now - root.lastNet.t) / 1000;
                if (dt > 0) {
                    root.rxBps = Math.max(0, (rx - root.lastNet.rx) / dt);
                    root.txBps = Math.max(0, (tx - root.lastNet.tx) / dt);
                    root.push("net_rx", Math.min(1, root.rxBps / 12500000));
                    root.push("net_tx", Math.min(1, root.txBps / 12500000));
                }
            }
            root.lastNet = { rx: rx, tx: tx, t: now };
        }
    }

    // the package temperature, from coretemp (Intel) or k10temp (AMD); found once
    property string thermalPath: ""
    Process {
        id: findThermal
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do n=$(cat \"$h/name\" 2>/dev/null); case \"$n\" in coretemp|k10temp|zenpower) echo \"$h/temp1_input\"; exit;; esac; done"]
        stdout: StdioCollector {
            onStreamFinished: root.thermalPath = text.trim()
        }
    }
    FileView {
        id: thermal
        path: root.thermalPath
        onLoaded: {
            root.cpuTemp = parseInt(text()) / 1000;
            root.push("cpu_temp", Math.min(1, root.cpuTemp / 100));
        }
    }
    FileView {
        id: freq
        path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        printErrors: false
        onLoaded: {
            root.cpuFreqGHz = parseInt(text()) / 1e6;
            root.push("cpu_freq", Math.min(1, root.cpuFreqGHz / 5));
        }
    }
}
