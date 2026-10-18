pragma Singleton

import QtQuick
import Quickshell

// Frame pacing of animated surfaces, recorded only while an animation runs. Read with `ipc call zynith stats`.
Singleton {
    id: root

    property var records: ({})

    function record(name: string, deltas: var): void {
        if (deltas.length === 0)
            return;
        const sorted = deltas.slice().sort((a, b) => a - b);
        const sum = deltas.reduce((a, b) => a + b, 0);
        const r = Object.assign({}, records);
        const prev = r[name] ?? {
            runs: 0,
            frames: 0,
            over20: 0,
            over33: 0,
            worst: 0,
            sum: 0
        };
        r[name] = {
            runs: prev.runs + 1,
            frames: prev.frames + deltas.length,
            over20: prev.over20 + deltas.filter(d => d > 20).length,
            over33: prev.over33 + deltas.filter(d => d > 33.4).length,
            worst: Math.max(prev.worst, sorted[sorted.length - 1]),
            sum: prev.sum + sum,
            lastMedian: sorted[Math.floor(sorted.length / 2)],
            // the last run frame by frame: where in a transition the slow frames fall (start = building, spread = drawing)
            last: deltas.map(d => Math.round(d))
        };
        records = r;
    }

    function summary(): var {
        const out = {};
        for (const k in records) {
            const v = records[k];
            out[k] = {
                runs: v.runs,
                frames: v.frames,
                meanMs: Number((v.sum / Math.max(1, v.frames)).toFixed(2)),
                worstMs: Number(v.worst.toFixed(1)),
                over20ms: v.over20,
                over33ms: v.over33,
                last: v.last
            };
        }
        return out;
    }

    function reset(): void {
        records = {};
    }
}
