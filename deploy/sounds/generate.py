#!/usr/bin/env python3
"""Zynith shell sounds — tiny synthesised UI cues (no samples, nothing copyrighted).

Design: short, soft, low-amplitude sine blips with raised-cosine envelopes (no clicks),
mixed at a quiet level so they sit under speech/music. 48 kHz mono 16-bit.

Regenerate:  python3 deploy/sounds/generate.py [OUTDIR]   (default: beside this script; packages: /usr/share/zynith/sounds)
"""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 48_000
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)


def env(i: int, n: int, attack: float = 0.15, release: float = 0.7) -> float:
    """Raised-cosine attack, exponential-ish decay: no clicks at either end."""
    a = max(1, int(n * attack))
    if i < a:
        return 0.5 - 0.5 * math.cos(math.pi * i / a)
    t = (i - a) / max(1, n - a)
    return math.exp(-t / max(1e-3, release)) * (1.0 - t) ** 0.5


def tone(freq: float, ms: float, gain: float, *, attack=0.15, release=0.7, harmonic=0.0):
    n = int(RATE * ms / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        v = math.sin(2 * math.pi * freq * t)
        if harmonic:
            v += harmonic * math.sin(2 * math.pi * freq * 2 * t)
        out.append(v * env(i, n, attack, release) * gain)
    return out


def mix(*layers):
    n = max(len(layer) for layer in layers)
    buf = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            buf[i] += v
    return buf


def at(offset_ms: float, samples):
    return [0.0] * int(RATE * offset_ms / 1000) + list(samples)


def write(name: str, samples, peak: float):
    high = max(1e-9, max(abs(v) for v in samples))
    scale = peak / high
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples
    )
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"{path.name:22} {len(samples)/RATE*1000:6.0f} ms  {path.stat().st_size/1024:5.1f} KB")


# One step of volume: a single soft blip, deliberately tiny (it can repeat quickly).
write("volume-tick", tone(1180, 42, 1.0, attack=0.12, release=0.45), peak=0.16)

# Mute / unmute: distinct from a step — a lower two-tone fall.
write("mute", mix(tone(640, 120, 1.0, release=0.5), at(55, tone(430, 130, 0.9, release=0.55))), peak=0.20)

# Notification: a calm rising third, the most "musical" cue of the set.
write(
    "notification",
    mix(tone(784, 190, 1.0, release=0.6, harmonic=0.10), at(85, tone(1046, 230, 0.85, release=0.7))),
    peak=0.24,
)

# Lock: settling downward. Unlock: the same shape rising.
write("lock", mix(tone(620, 170, 1.0, release=0.5), at(80, tone(415, 220, 0.9, release=0.6))), peak=0.20)
write("unlock", mix(tone(495, 160, 1.0, release=0.5), at(75, tone(740, 220, 0.9, release=0.65))), peak=0.20)

# Screenshot: a short dry tick, no shutter theatrics.
write("screenshot", mix(tone(2100, 26, 1.0, attack=0.08, release=0.25), tone(1400, 34, 0.5, release=0.3)), peak=0.18)
