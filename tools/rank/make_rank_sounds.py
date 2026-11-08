#!/usr/bin/env python3
"""Synthesise the rank sounds, for mods/orthoverse_rank/sounds:

    orthoverse_rank_up.ogg   a rising three-note chime with a bell's ring
    orthoverse_rank_xp.ogg   a small soft tick, when experience is gained

Needs numpy (in a venv) and ffmpeg:

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install numpy
    /tmp/venv/bin/python tools/rank/make_rank_sounds.py mods/orthoverse_rank/sounds

By Keir Finlow-Bates; the sounds are CC0, the code MIT."""
import os, subprocess, sys, tempfile, wave
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
RATE = 44100


def bell(freq, dur, gain=1.0):
    x = np.arange(int(RATE * dur)) / RATE
    tone = sum(np.sin(2 * np.pi * freq * m * x) * a for m, a in ((1, 1), (2.0, 0.4), (3.01, 0.18), (4.2, 0.08)))
    return gain * tone * np.minimum(1, x / 0.004) * np.exp(-x / (dur / 4))


def mix(parts, dur):
    out = np.zeros(int(RATE * dur))
    for p, at in parts:
        s = int(at * RATE)
        out[s:s + len(p)] += p[:len(out) - s]
    return out


def save(name, x, gain):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    f"{OUT}/orthoverse_rank_{name}.ogg"], check=True)
    os.unlink(path)


# C5, E5, G5, then C6 held
save("up", mix([(bell(523.25, 0.5), 0), (bell(659.25, 0.5), 0.13), (bell(783.99, 0.6), 0.26),
                (bell(1046.5, 1.4, 1.2), 0.42)], 1.9), 0.8)
save("xp", bell(1568, 0.18, 1.0), 0.35)
print("ok")
