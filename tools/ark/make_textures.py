#!/usr/bin/env python3
"""Paint the textures for The Silent Ark (mods/orthoverse_ark) and its
monsters (mods/orthoverse_monsters: the hunter drone, the enforcer, the heavy
turret, the sleeper, the Custodian), and synthesise their sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/ark/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds; the skins
are drawn over Minetest Game's player skin layout, mods/mtg/player_api)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
TEX = os.path.join(ROOT, "mods/orthoverse_ark/textures")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
SND = os.path.join(ROOT, "mods/orthoverse_ark/sounds")
MSND = os.path.join(ROOT, "mods/orthoverse_monsters/sounds")
for d in (TEX, MON, SND, MSND):
    os.makedirs(d, exist_ok=True)

CLEAR = (0, 0, 0, 0)


def h(u, v, s=0):
    n = (u * 374761393 + v * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def jit(c, u, v, s, amt=6):
    d = int((h(u, v, s) - 0.5) * 2 * amt)
    out = tuple(max(0, min(255, x + d)) for x in c[:3])
    return out + ((c[3],) if len(c) > 3 else (255,))


def shade(c, f):
    return tuple(max(0, min(255, int(x * f))) for x in c[:3])


def mix(a, b, k):
    return tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))


def tile(fn, w=16, hgt=None):
    hgt = hgt or w
    img = Image.new("RGBA", (w, hgt), CLEAR)
    for v in range(hgt):
        for u in range(w):
            c = fn(u, v)
            if c is not None:
                img.putpixel((u, v), c if len(c) == 4 else tuple(c) + (255,))
    return img


def save(img, name, folder=TEX, prefix="orthoverse_ark_"):
    img.save(os.path.join(folder, prefix + name + ".png"))


SPACE = (6, 7, 12)
WHITE = (214, 218, 222)
GREY = (150, 156, 164)
DARK = (58, 62, 70)
CYAN = (120, 220, 255)
AMBER = (255, 180, 60)
RED = (200, 40, 34)

# ----------------------------------------------------------------------------
# Space


def space(u, v):
    return jit(SPACE, u, v, 1, 3)


def stars(seed, count, bright):
    pts = [(int(h(i, 1, seed) * 16), int(h(i, 2, seed) * 16), i) for i in range(count)]

    def f(u, v):
        for x, y, i in pts:
            if (u, v) == (x, y):
                tint = [(255, 255, 255), (200, 220, 255), (255, 230, 190), (255, 200, 170)][i % 4]
                return shade(tint, bright if i == 0 else bright * 0.6)
            if bright > 0.9 and i == 0 and abs(u - x) + abs(v - y) == 1:
                return shade((170, 190, 255), 0.6)
        return space(u, v)
    return f


def giant(core, edge, s):
    """A red giant's surface: boiling cells, darker lanes between"""
    def f(u, v):
        cell = h(u // 3, v // 3, s)
        lane = (u % 3 == 0) or (v % 3 == 0)
        c = mix(edge, core, cell)
        if lane and h(u, v, s + 1) > 0.4:
            c = shade(c, 0.8)
        return jit(c, u, v, s + 2, 10)
    return f


def planet_sea(u, v):
    deep = h(u // 4, v // 4, 20) > 0.5
    return jit((24, 70, 160) if deep else (34, 96, 190), u, v, 21, 8)


def planet_land(u, v):
    c = (52, 140, 60) if h(u // 3, v // 3, 22) > 0.35 else (98, 150, 70)
    if h(u, v, 23) > 0.92:
        c = (140, 120, 80)
    return jit(c, u, v, 24, 10)


def planet_cloud(u, v):
    c = (236, 240, 246) if h(u // 2, v // 2, 25) > 0.3 else (190, 205, 225)
    return jit(c, u, v, 26, 6)


save(tile(space), "space")
save(tile(stars(30, 1, 1.0)), "star_1")
save(tile(stars(31, 3, 0.8)), "star_2")
save(tile(stars(32, 2, 1.0)), "star_3")
save(tile(giant((255, 210, 120), (240, 120, 40), 40)), "giant_core")
save(tile(giant((240, 110, 40), (190, 40, 24), 41)), "giant")
save(tile(giant((190, 50, 30), (110, 18, 14), 42)), "giant_edge")
save(tile(planet_sea), "planet_sea")
save(tile(planet_land), "planet_land")
save(tile(planet_cloud), "planet_cloud")

# ----------------------------------------------------------------------------
# The ship


def hull(u, v):
    if u in (0, 15) or v in (0, 15):
        return jit(shade(WHITE, 0.72), u, v, 2, 4)
    if (u, v) in ((2, 2), (13, 2), (2, 13), (13, 13)):
        return shade(WHITE, 0.6)
    return jit(WHITE, u, v, 3, 5)


def hull_rib(u, v):
    if v % 4 == 0:
        return jit(shade(WHITE, 0.7), u, v, 4, 4)
    if v % 4 == 1:
        return jit(shade(WHITE, 1.05), u, v, 5, 3)
    return jit(shade(WHITE, 0.92), u, v, 6, 5)


def hull_dark(u, v):
    if u in (0, 15) or v in (0, 15):
        return jit(shade(DARK, 0.7), u, v, 7, 4)
    return jit(DARK, u, v, 8, 6)


def frame(u, v):
    if u in (0, 1, 14, 15) or v in (0, 1, 14, 15):
        return jit(GREY, u, v, 9, 6)
    return jit(shade(GREY, 0.8), u, v, 10, 6)


def deck(u, v):
    if u % 4 == 0 or v % 4 == 0:
        return jit((70, 74, 82), u, v, 11, 4)
    return jit((112, 118, 126), u, v, 12, 6)


def strip(u, v):
    if v in (6, 7, 8, 9):
        return jit((230, 248, 255), u, v, 13, 4)
    return hull(u, v)


def frost(u, v):
    return jit((200, 225, 240), u, v, 14, 14)


def hazard(u, v):
    return (230, 190, 30) if ((u + v) // 4) % 2 == 0 else (30, 30, 34)


def window(u, v):
    if u in (0, 15) or v in (0, 15):
        return GREY + (255,)
    if u == v or u == v + 1:
        return (200, 230, 255, 60)
    return (120, 160, 200, 26)


def dead_plant(u, v):
    stems = [(7, 0.0), (4, -0.3), (11, 0.3)]
    for x, lean in stems:
        if v >= 5 and abs(u - (x + lean * (15 - v))) < 0.6:
            return jit((110, 96, 70), u, v, 15, 10)
    if v in (5, 6) and u in (3, 4, 10, 11):
        return (90, 80, 60)
    return None


def overgrowth(u, v):
    w = math.sin(u * 0.9 + v * 0.4) + math.sin(v * 0.7 - u * 0.3)
    if w > 0.6:
        return jit((210, 210, 200), u, v, 16, 10)
    return jit((150, 160, 140), u, v, 17, 12)


save(tile(hull), "hull")
save(tile(hull_rib), "hull_rib")
save(tile(hull_dark), "hull_dark")
save(tile(frame), "frame")
save(tile(deck), "deck")
save(tile(strip), "strip")
save(tile(frost), "frost")
save(tile(hazard), "hazard")
save(tile(window), "window")
save(tile(dead_plant), "dead_plant")
save(tile(overgrowth), "overgrowth")


# Panels with something on them: drawn over the hull
def panel(draw):
    def f(u, v):
        c = draw(u, v)
        return c if c is not None else hull(u, v)
    return f


def air_station(u, v):
    if 4 <= u <= 11 and 2 <= v <= 13:
        if u in (4, 11) or v in (2, 13):
            return (60, 70, 80)
        if v >= 6:
            return jit((60, 200, 120), u, v, 18, 10)     # the gauge, full
        return (30, 40, 50)
    if v == 15 and u in range(3, 13):
        return (40, 120, 200)
    return None


def terminal(u, v):
    if 2 <= u <= 13 and 2 <= v <= 11:
        if u in (2, 13) or v in (2, 11):
            return (30, 34, 40)
        if v % 2 == 0 and u < 4 + int(h(v, 0, 19) * 9):
            return CYAN
        return (8, 26, 36)
    if v in (13, 14) and 3 <= u <= 12:
        return (40, 44, 50) if u % 2 else (70, 76, 84)
    return None


def bulkhead(u, v):
    if v < 3 or v > 12:
        return hazard(u, v)
    if u == 8:
        return (30, 30, 34)
    return jit((96, 100, 108), u, v, 20, 5)


def pod_door(u, v):
    if u in (0, 15) or v in (0, 15):
        return hazard(u, v)
    if u in (7, 8) or v in (7, 8):
        return (40, 40, 46)
    return jit((110, 116, 124), u, v, 21, 5)


def bridge_door(u, v):
    if u in (0, 1, 14, 15):
        return (40, 44, 52)
    if u == 8:
        return (20, 20, 24)
    if v in (3, 12):
        return (200, 40, 34)
    return jit((84, 92, 104), u, v, 22, 5)


def core_tex(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    k = max(0, 1 - d / 8)
    return jit(mix((40, 30, 120), (180, 160, 255), k * k), u, v, 23, 8)


def core_dead(u, v):
    return jit((40, 40, 50), u, v, 24, 6)


def launch(u, v):
    if 3 <= u <= 12 and 3 <= v <= 12:
        if v in (4, 5) and 4 <= u <= 11:
            return RED
        if u in (7, 8) and 5 <= v <= 11:
            return shade(RED, 0.8)
        return hazard(u, v) if (u in (3, 12) or v in (3, 12)) else (40, 40, 46)
    return None


def pod_side(u, v):
    if u in (0, 15) or v in (0, 15):
        return GREY + (255,)
    return jit((180, 190, 200), u, v, 25, 5)


def sleeper_face(u, v, top):
    """the frosted glass front of a pod, and the figure behind it"""
    if u in (0, 15) or (not top and v == 15) or (top and v == 0):
        return GREY + (255,)
    figure = False
    if top:
        figure = (5 <= u <= 10 and 5 <= v <= 12) or (3 <= u <= 12 and v >= 14)
    else:
        figure = (4 <= u <= 11 and v <= 9) or (5 <= u <= 7 and v > 9) or (8 <= u <= 10 and v > 9)
    c = (110, 140, 170) if figure else (170, 200, 225)
    if h(u, v, 26) > 0.8:
        c = (230, 240, 250)
    return jit(c, u, v, 27, 8) + ()


def pod_open(u, v, top):
    if u in (0, 15) or (not top and v == 15) or (top and v == 0):
        return GREY + (255,)
    if h(u, v, 28) > 0.93:
        return (200, 220, 240, 200)
    return None


def mist(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    a = int(max(0, 1 - d / 8) * 150)
    return (230, 240, 255, a)


save(tile(panel(air_station)), "air_station")
save(tile(panel(terminal)), "terminal")
save(tile(bulkhead), "bulkhead")
save(tile(pod_door), "pod_door")
save(tile(bridge_door), "bridge_door")
save(tile(core_tex), "core")
save(tile(core_dead), "core_dead")
save(tile(panel(launch)), "launch")
save(tile(pod_side), "pod_side")
save(tile(lambda u, v: sleeper_face(u, v, False)), "pod_front")
save(tile(lambda u, v: sleeper_face(u, v, True)), "pod_front_top")
save(tile(lambda u, v: pod_open(u, v, False)), "pod_open")
save(tile(lambda u, v: pod_open(u, v, True)), "pod_open_top")
save(tile(mist), "mist")


# The suit's air on the screen: a bubble, and an empty one
def bubble(full):
    def f(u, v):
        d = math.hypot(u - 7.5, v - 7.5)
        if d > 7:
            return None
        if d > 5.8:
            return (20, 60, 90, 255) if full else (40, 50, 60, 200)
        if not full:
            return (30, 40, 50, 110)
        if (u - 5) ** 2 + (v - 5) ** 2 < 4:
            return (230, 250, 255, 255)
        return (90, 190, 240, 255)
    return f


save(tile(bubble(True)), "air")
save(tile(bubble(False)), "air_empty")


# Marks (their inventory pictures only)
def mark(letter_rows, col):
    def f(u, v):
        if u in (0, 15) or v in (0, 15):
            return col
        r = (v - 4) // 2
        c = (u - 4) // 2
        if 0 <= r < len(letter_rows) and 0 <= c < 4 and letter_rows[r][c] == "#" and 4 <= u < 12 and 4 <= v < 4 + 2 * len(letter_rows):
            return col
        return (20, 24, 30, 160)
    return f


V = ["#..#", "#..#", "#..#", ".##."]
G = [".###", "#...", "#.##", ".###"]
T = ["####", ".#..", ".#..", ".#.."]
save(tile(mark(V, (120, 200, 255, 255))), "mark_vacuum")
save(tile(mark(G, (180, 255, 160, 255))), "mark_lowg")
save(tile(mark(V, (220, 255, 200, 255))), "mark_vacuum_lowg")
save(tile(mark(T, (255, 220, 120, 255))), "mark_tether")

# ----------------------------------------------------------------------------
# The monsters' skins (64 x 32, Minetest Game's player layout)

HEAD = {"top": (8, 0, 8, 8), "bottom": (16, 0, 8, 8), "right": (0, 8, 8, 8), "front": (8, 8, 8, 8),
        "left": (16, 8, 8, 8), "back": (24, 8, 8, 8)}
BODY = {"top": (20, 16, 8, 4), "bottom": (28, 16, 8, 4), "right": (16, 20, 4, 12), "front": (20, 20, 8, 12),
        "left": (28, 20, 4, 12), "back": (32, 20, 8, 12)}
ARM = {"top": (44, 16, 4, 4), "bottom": (48, 16, 4, 4), "right": (40, 20, 4, 12), "front": (44, 20, 4, 12),
       "left": (48, 20, 4, 12), "back": (52, 20, 4, 12)}
LEG = {"top": (4, 16, 4, 4), "bottom": (8, 16, 4, 4), "right": (0, 20, 4, 12), "front": (4, 20, 4, 12),
       "left": (8, 20, 4, 12), "back": (12, 20, 4, 12)}


def skin(fn, face, pal, seed):
    img = Image.new("RGBA", (64, 32), CLEAR)
    for part, rects in (("head", HEAD), ("body", BODY), ("arm", ARM), ("leg", LEG)):
        for side, (x, y, w, hh) in rects.items():
            for v in range(hh):
                for u in range(w):
                    c = fn(part, side, x + u, y + v, u, v, w, hh)
                    if c is not None:
                        img.putpixel((x + u, y + v), c if len(c) == 4 else tuple(c) + (255,))
    x, y = HEAD["front"][0], HEAD["front"][1]
    for v, row in enumerate(face):
        for u, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x + u, y + v), jit(pal[ch], u, v, seed, 6))
    return img


# The enforcer: dark steel plate, a white chest stripe, one red eye slit
STEEL = (78, 84, 94)


def enforcer(part, side, X, Y, u, v, w, hh):
    if part == "body" and side == "front" and 3 <= u <= 4:
        return (210, 214, 220)
    if part in ("arm", "leg") and v in (5, 6):
        return (40, 44, 50)
    if (u + v) % 7 == 0 and h(X, Y, 50) > 0.5:
        return shade(STEEL, 1.25)
    return jit(STEEL, X, Y, 51, 8)


ENF_FACE = ["........",
            "........",
            "........",
            "krrrrrrk",
            "........",
            "........",
            ".kkkkkk.",
            "........"]
save(skin(enforcer, ENF_FACE, {"k": (24, 26, 30), "r": (255, 40, 30)}, 52), "enforcer", MON, "orthoverse_monsters_")


# The sleeper: a pale colonist in a blue ship's suit, frost on it
def sleeper(part, side, X, Y, u, v, w, hh):
    frosty = h(X, Y, 60) > 0.87
    if frosty:
        return jit((225, 238, 248), X, Y, 61, 8)
    if part == "head":
        if side in ("top", "back") or (side in ("left", "right") and v < 3):
            return jit((60, 50, 44), X, Y, 62, 8)      # hair, matted
        return jit((176, 186, 196), X, Y, 63, 8)       # skin, blue with cold
    if part == "arm" and v >= 9:
        return jit((176, 186, 196), X, Y, 64, 8)
    if part == "body" and side == "front" and v == 2 and 1 <= u <= 2:
        return (230, 200, 60)                          # a mission patch
    return jit((40, 80, 140), X, Y, 65, 10)


SLEEPER_FACE = ["........",
                "........",
                "........",
                ".ww..ww.",
                ".wk..kw.",
                "........",
                "..kkkk..",
                "........"]
save(skin(sleeper, SLEEPER_FACE, {"w": (220, 230, 240), "k": (40, 40, 50)}, 66), "sleeper", MON, "orthoverse_monsters_")


# The Custodian: a heavy industrial machine, yellow and black, a wide visor
def custodian(part, side, X, Y, u, v, w, hh):
    if part == "body" and v >= 9:
        return hazard(u + X, v)
    if part in ("arm", "leg") and v in (0, 1, 10, 11):
        return (30, 30, 34)
    if part == "head" and side != "front":
        return jit((60, 62, 66), X, Y, 70, 6)
    if h(X, Y, 71) > 0.9:
        return (120, 90, 20)
    return jit((214, 170, 40), X, Y, 72, 10)


CUST_FACE = ["kkkkkkkk",
             "k......k",
             "kccccccK",
             "kccccccK",
             "k......k",
             "........",
             ".kkkkkk.",
             "........"]
save(skin(custodian, CUST_FACE, {"k": (30, 30, 34), "K": (30, 30, 34), "c": (120, 230, 255)}, 73), "custodian", MON,
     "orthoverse_monsters_")


# The hunter drone (a sprite): a dark body, a cutting arm, a red eye
def hunter_drone(u, v):
    d = math.hypot(u - 7.5, v - 7)
    if d < 2:
        return (255, 50, 30)
    if d < 5.5:
        return jit((50, 54, 62), u, v, 80, 8)
    if v == 12 and 3 <= u <= 12:
        return (140, 144, 150)
    if 12 < v <= 15 and u in (4, 11):
        return (180, 184, 190)
    if v in (6, 7) and (u <= 1 or u >= 14):
        return (90, 96, 104)
    return None


save(tile(hunter_drone), "hunter_drone", MON, "orthoverse_monsters_")


# The heavy turret (a cube): armoured, twin barrels on its front
def ht_top(u, v):
    if u in (0, 15) or v in (0, 15):
        return (30, 32, 36)
    return jit((70, 74, 80), u, v, 81, 8) if (u // 4 + v // 4) % 2 else jit((90, 94, 100), u, v, 82, 8)


def ht_side(u, v):
    if v in (0, 15):
        return (30, 32, 36)
    if v in (4, 11):
        return hazard(u, v)
    return jit((80, 84, 92), u, v, 83, 8)


def ht_front(u, v):
    if (u in (4, 5) or u in (10, 11)) and 6 <= v <= 10:
        return (16, 16, 18)
    if v in (2, 3) and 6 <= u <= 9:
        return (255, 60, 30)
    return ht_side(u, v)


save(tile(ht_top), "heavy_turret_top", MON, "orthoverse_monsters_")
save(tile(ht_side), "heavy_turret_side", MON, "orthoverse_monsters_")
save(tile(ht_front), "heavy_turret_front", MON, "orthoverse_monsters_")

# ----------------------------------------------------------------------------
# Sounds

RATE = 44100


def write(folder, name, samples):
    samples = np.clip(samples, -1, 1)
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "s.wav")
        with wave.open(w, "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes((samples * 32000).astype(np.int16).tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", w, "-c:a", "libvorbis", "-q:a", "3",
                        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        os.path.join(folder, name + ".ogg")], check=True)


def env(n, a, r):
    e = np.ones(n)
    a, r = max(1, int(a * RATE)), max(1, int(r * RATE))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


rng = np.random.default_rng(23)


def noise(n, smooth=1):
    x = rng.normal(0, 1, n)
    if smooth > 1:
        x = np.convolve(x, np.ones(smooth) / smooth, mode="same")
        x /= max(1e-6, np.abs(x).max())
    return x


def secs(s):
    return int(s * RATE)


# air filling a suit: a hiss
n = secs(1.2)
write(SND, "orthoverse_ark_hiss", noise(n) * env(n, 0.05, 0.5) * 0.5)

# a bulkhead slamming: a deep boom and a ring
n = secs(1.6)
t = np.arange(n) / RATE
boom = noise(n, 40) * np.exp(-t * 6) + np.sin(2 * np.pi * 48 * t) * np.exp(-t * 3) * 0.8
ring = np.sin(2 * np.pi * 310 * t) * np.exp(-t * 4) * 0.2
write(SND, "orthoverse_ark_slam", (boom + ring) * 0.8)

# a cryo pod cracking open: ice, then a sigh of gas
n = secs(1.4)
t = np.arange(n) / RATE
cracks = sum(noise(n) * np.exp(-np.clip(t - k, 0, None) * 60) * (t > k) for k in (0.0, 0.08, 0.15, 0.27)) * 0.6
gas = noise(n, 6) * env(n, 0.2, 0.7) * 0.35 * (t > 0.3)
write(SND, "orthoverse_ark_crack", cracks + gas)

# the ship's mind dying: a falling hum
n = secs(3.0)
t = np.arange(n) / RATE
f = 220 * np.exp(-t * 0.9) + 30
ph = 2 * np.pi * np.cumsum(f) / RATE
write(SND, "orthoverse_ark_powerdown", (np.sin(ph) * 0.6 + np.sin(2 * ph) * 0.2) * env(n, 0.05, 1.0))

# the escape pod's launch: clamps, then a rising roar
n = secs(2.5)
t = np.arange(n) / RATE
clamps = sum(noise(n) * np.exp(-np.clip(t - k, 0, None) * 40) * (t > k) for k in (0.0, 0.12)) * 0.5
roar = noise(n, 15) * np.clip((t - 0.3) / 1.5, 0, 1) * 0.7
write(SND, "orthoverse_ark_launch", (clamps + roar) * env(n, 0.01, 0.4))

# a sleeper's moan: low, cracked
n = secs(1.5)
t = np.arange(n) / RATE
f = 120 + 25 * np.sin(2 * np.pi * 1.2 * t) - 20 * t
ph = 2 * np.pi * np.cumsum(f) / RATE
write(MSND, "orthoverse_monsters_sleeper_moan", (np.sin(ph) * 0.5 + np.sin(2.5 * ph) * 0.2 + noise(n, 10) * 0.2) * env(n, 0.3, 0.6))
print("done")
