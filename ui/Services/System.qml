pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native

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

    // ── what only the native system monitor has (one sampler, not two): the GPU, disks by path and network
    // by interface. Widgets need() them; while any are needed the native sample is asked at the update
    // interval (sysmon-stats holds GPU readers and disk paths on a lease that lapses when nobody asks). ──
    property var needs: ({})
    property var nativeStats: ({})
    function need(key: string): void {
        const n = Object.assign({}, needs);
        n[key] = (n[key] ?? 0) + 1;
        needs = n;
        askNative();
    }
    function unneed(key: string): void {
        const n = Object.assign({}, needs);
        if ((n[key] ?? 0) <= 1)
            delete n[key];
        else
            n[key]--;
        needs = n;
    }
    readonly property bool nativeWanted: Object.keys(needs).length > 0
    function askNative(): void {
        const keys = Object.keys(needs);
        if (keys.length === 0)
            return;
        const want = { disks: keys.filter(k => k.startsWith("disk:")).map(k => k.slice(5)) };
        for (const k of ["gpu_temp", "gpu_usage", "gpu_vram"])
            if (keys.includes(k))
                want[k] = true;
        CoreClient.call("sysmon-stats " + JSON.stringify(want), text => {
            try {
                root.nativeStats = JSON.parse(text);
                for (const k of ["gpu_temp", "gpu_usage"])
                    if (root.nativeStats[k] !== null && root.nativeStats[k] !== undefined)
                        root.push(k, k === "gpu_temp" ? Math.min(1, root.nativeStats[k] / 100) : root.nativeStats[k] / 100);
            } catch (e) {}
        });
    }
    Timer {
        running: root.nativeWanted
        repeat: true
        interval: ExperiencePolicy.updateIntervalMs
        onTriggered: root.askNative()
    }
    // which native needs a stat has
    function needsFor(name: string, o: var): string {
        if (name === "gpu_temp" || name === "gpu_usage")
            return name;
        if (name === "gpu_vram" || name === "gpu_vram_used")
            return "gpu_vram";
        if (name.startsWith("disk_"))
            return "disk:" + ((o?.path ?? "") !== "" ? o.path : "/");
        if ((name === "net_rx" || name === "net_tx") && (o?.iface ?? "") !== "")
            return "iface";
        return "";
    }

    function bytes(b: real): string {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < u.length - 1) {
            b /= 1024;
            i++;
        }
        return (i >= 3 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
    // a speed as the native widget says it: unit auto | kb | mb, compact (1.2M rather than 1.2 MB/s)
    function speed(bps: real, unit: string, compact: bool): string {
        const kb = bps / 1024, mb = bps / 1048576;
        const useMb = unit === "mb" || (unit !== "kb" && bps >= 1048576);
        const v = useMb ? mb : kb;
        const n = v >= 100 || !useMb ? v.toFixed(0) : v.toFixed(1);
        return compact ? n + (useMb ? "M" : "K") : n + (useMb ? " MB/s" : " KB/s");
    }

    // a stat by its widget name: the value, a 0..1 level for gauges, and how to say it; o carries the
    // widget's path, iface, unit and compact for the disk and network stats
    function read(name: string, o: var): var {
        const nat = nativeStats;
        switch (name) {
        case "gpu_temp":
            return nat.gpu_temp === null || nat.gpu_temp === undefined ? { value: 0, level: 0, text: "—", label: "GPU temp" } : { value: nat.gpu_temp, level: Math.min(1, nat.gpu_temp / 100), text: Math.round(nat.gpu_temp) + "°", label: "GPU temp" };
        case "gpu_usage":
            return nat.gpu_usage === null || nat.gpu_usage === undefined ? { value: 0, level: 0, text: "—", label: "GPU" } : { value: nat.gpu_usage / 100, level: nat.gpu_usage / 100, text: Math.round(nat.gpu_usage) + "%", label: "GPU" };
        case "gpu_vram":
        case "gpu_vram_used": {
            const used = nat.gpu_vram_used, total = nat.gpu_vram_total;
            if (!used || !total)
                return { value: 0, level: 0, text: "—", label: "VRAM" };
            return { value: used / total, level: used / total, text: name === "gpu_vram" ? Math.round(used / total * 100) + "%" : bytes(used), label: "VRAM" };
        }
        case "ram_used":
            return { value: memUsed, level: memUsed, text: (memUsed * memTotalGiB).toFixed(1) + " GB", label: "Memory" };
        case "disk_used_pct":
        case "disk_used":
        case "disk_free_pct":
        case "disk_free": {
            const path = (o?.path ?? "") !== "" ? o.path : "/";
            const d = (nat.disks ?? {})[path];
            if (!d)
                return { value: 0, level: 0, text: "—", label: "Disk" };
            const used = d.used_pct / 100;
            const text = name === "disk_used_pct" ? Math.round(d.used_pct) + "%" : name === "disk_free_pct" ? Math.round(100 - d.used_pct) + "%" : name === "disk_used" ? bytes(d.total - d.free) : bytes(d.available);
            return { value: used, level: used, text: text, label: "Disk " + path };
        }
        case "net_rx":
        case "net_tx": {
            const iface = o?.iface ?? "";
            const at = iface !== "" ? (nat.interfaces ?? {})[iface] : null;
            const bps = at ? (name === "net_rx" ? at.rx : at.tx) : (name === "net_rx" ? rxBps : txBps);
            return { value: bps, level: Math.min(1, bps / 12500000), text: speed(bps, o?.unit ?? "auto", o?.compact === true), label: (name === "net_rx" ? "Down" : "Up") + (iface !== "" ? " " + iface : "") };
        }
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
