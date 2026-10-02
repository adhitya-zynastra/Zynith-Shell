pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What the machine can do, read once at startup from /proc and sysfs. It only recommends a profile;
// the user's choice always wins (ExperiencePolicy).
Singleton {
    id: root

    property string cpuModel: ""
    property int cpuThreads: 0
    property real memGiB: 0
    property var gpus: []
    property bool hasBattery: false
    readonly property bool ready: cpuThreads > 0 && memGiB > 0

    readonly property bool discreteGpu: gpus.some(g => g.discrete)
    readonly property string gpuSummary: gpus.length === 0 ? "unknown GPU"
        : gpus.map(g => g.label).join(" + ")

    // high: room for every effect; mid: a typical modern laptop; low: keep things light
    readonly property string tier: {
        if (!ready)
            return "mid";
        if (cpuThreads >= 16 && memGiB >= 24 && discreteGpu)
            return "high";
        if (cpuThreads >= 8 && memGiB >= 12)
            return "mid";
        return "low";
    }
    readonly property string recommendedProfile: tier === "high" ? "enhanced" : tier === "mid" ? "balanced" : "performance"

    function addGpu(uevent: string, vramText: string): void {
        const driver = (uevent.match(/^DRIVER=(.*)$/m) || [])[1] || "";
        const pci = ((uevent.match(/^PCI_ID=(.*)$/m) || [])[1] || "").toLowerCase();
        if (!driver || gpus.some(g => g.pci === pci))
            return;
        const vendor = pci.split(":")[0];
        const device = pci.split(":")[1] || "";
        const vramGiB = vramText ? parseInt(vramText) / 1073741824 : 0;
        let discrete = false;
        if (driver === "nvidia" || driver === "nouveau")
            discrete = true;
        else if (driver === "amdgpu")
            discrete = vramGiB >= 2;
        else if (vendor === "8086")
            discrete = device.startsWith("56") || device.startsWith("e2"); // Arc A/B-series cards
        const name = vendor === "8086" ? "Intel" : vendor === "10de" ? "NVIDIA" : vendor === "1002" ? "AMD" : vendor;
        gpus = gpus.concat([{
                pci: pci,
                driver: driver,
                discrete: discrete,
                vramGiB: vramGiB,
                label: name + (discrete ? " (discrete)" : " (integrated)")
            }]);
    }

    FileView {
        path: "/proc/cpuinfo"
        onLoaded: {
            const t = text();
            root.cpuThreads = (t.match(/^processor\s*:/gm) || []).length;
            root.cpuModel = ((t.match(/^model name\s*:\s*(.*)$/m) || [])[1] || "").trim();
        }
    }

    FileView {
        path: "/proc/meminfo"
        onLoaded: {
            const kb = parseInt((text().match(/^MemTotal:\s*(\d+)/m) || [])[1] || "0");
            root.memGiB = kb / 1048576;
        }
    }

    Instantiator {
        model: [0, 1, 2, 3]
        delegate: QtObject {
            id: card

            required property int modelData
            property string uevent: ""
            property string vram: ""
            property bool vramDone: false

            function settle(): void {
                if (uevent !== "" && vramDone)
                    root.addGpu(uevent, vram);
            }

            readonly property FileView ueventFile: FileView {
                path: "/sys/class/drm/card" + card.modelData + "/device/uevent"
                printErrors: false
                onLoaded: {
                    card.uevent = text();
                    card.settle();
                }
            }
            readonly property FileView vramFile: FileView {
                path: "/sys/class/drm/card" + card.modelData + "/device/mem_info_vram_total"
                printErrors: false
                onLoaded: {
                    card.vram = text();
                    card.vramDone = true;
                    card.settle();
                }
                onLoadFailed: {
                    card.vramDone = true;
                    card.settle();
                }
            }
        }
    }

    FileView {
        path: "/sys/class/power_supply/BAT0/type"
        printErrors: false
        onLoaded: root.hasBattery = true
    }
    FileView {
        path: "/sys/class/power_supply/BAT1/type"
        printErrors: false
        onLoaded: root.hasBattery = true
    }
}
