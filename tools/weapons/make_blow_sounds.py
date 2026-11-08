#!/usr/bin/env python3
"""Synthesise the sounds of a blow, for mods/orthoverse_combat/sounds, so a
player hears how good a hit was:

    orthoverse_combat_swing.ogg    every release: the weapon through the air
    orthoverse_combat_miss.ogg     nothing hit, or out of reach: a thin swish
    orthoverse_combat_glance.ogg   a glancing blow: a light dull tap
    orthoverse_combat_hit.ogg      a hit: a solid thud
    orthoverse_combat_strong.ogg   a hit in the sweet spot: a heavy thud with a crunch
    orthoverse_combat_crit.ogg     a critical or a stunning head blow: a heavy blow and a ring

Needs numpy (in a venv) and ffmpeg:

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install numpy
    /tmp/venv/bin/python tools/weapons/make_blow_sounds.py mods/orthoverse_combat/sounds

By Keir Finlow-Bates; the sounds are CC0, the code MIT."""
import os, subprocess, sys, tempfile, wave
import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
RATE = 44100
rng = np.random.default_rng(7)


def t(dur):
    return np.arange(int(RATE * dur)) / RATE


def env(x, attack, decay):
    """Rises over `attack` seconds, then dies away with time constant `decay`."""
    n = np.arange(len(x)) / RATE
    return x * np.minimum(1, n / max(attack, 1e-4)) * np.exp(-np.maximum(0, n - attack) / decay)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def sweep_noise(dur, f0, f1):
    """Noise through a band that sweeps from f0 to f1: air moving past."""
    n = rng.standard_normal(len(t(dur)))
    out = np.zeros_like(n)
    lo = hi = 0.0
    for i, v in enumerate(n):
        f = f0 + (f1 - f0) * i / len(n)
        a = np.exp(-2 * np.pi * f / RATE)
        b = np.exp(-2 * np.pi * f * 0.5 / RATE)
        hi = (1 - a) * v + a * hi
        lo = (1 - b) * hi + b * lo
        out[i] = hi - lo
    return out


def thud(dur, f0, f1, noise=0.4, cutoff=900):
    x = t(dur)
    f = f1 + (f0 - f1) * np.exp(-x / 0.03)            # the pitch drops fast
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE)
    hit = lowpass(rng.standard_normal(len(x)), cutoff) * noise * 4
    return env(body + hit, 0.002, dur / 4)


def ring(dur, freqs):
    x = t(dur)
    return env(sum(np.sin(2 * np.pi * f * x) / (k + 1) for k, f in enumerate(freqs)), 0.001, dur / 3)


def mix(*parts):
    n = max(len(p) for p, _ in parts)
    out = np.zeros(n)
    for p, at in parts:
        s = int(at * RATE)
        out[s:s + len(p)] += p[:n - s]
    return out


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    f"{OUT}/orthoverse_combat_{name}.ogg"], check=True)
    os.unlink(path)


swing = env(sweep_noise(0.28, 500, 2200), 0.12, 0.06)
save("swing", swing, 0.5)
save("miss", env(sweep_noise(0.22, 1500, 4000), 0.05, 0.05), 0.45)
save("glance", thud(0.12, 420, 260, noise=0.25, cutoff=2500), 0.55)
save("hit", thud(0.25, 180, 70, noise=0.5, cutoff=1200), 0.85)
crunch = env(lowpass(rng.standard_normal(len(t(0.18))), 3500), 0.001, 0.04)
save("strong", mix((thud(0.4, 140, 48, noise=0.7, cutoff=900), 0), (crunch * 0.8, 0.005)), 0.95)
save("crit", mix((thud(0.4, 150, 50, noise=0.6, cutoff=1000), 0), (crunch * 0.6, 0.004),
                 (ring(0.9, [1320, 1980, 2970]) * 0.35, 0.01)), 0.95)
print("ok")
