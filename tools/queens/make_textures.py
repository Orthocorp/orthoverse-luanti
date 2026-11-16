#!/usr/bin/env python3
"""Paint the textures for Eight Queens (mods/orthoverse_queens): the
eight coloured floor tiles (each colour with its own pattern, so the regions
can be told apart without telling colours apart), the queens and the
crosses players set on them, the doors, the throne, the crown, and the
Queen's skin, and synthesise its sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/queens/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds; the Queen's
skin is made from Minetest Game's player skin, mods/mtg/player_api)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import colorsys, math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
TEX = os.path.join(ROOT, "mods/orthoverse_queens/textures")
SND = os.path.join(ROOT, "mods/orthoverse_queens/sounds")
for d in (TEX, SND):
    os.makedirs(d, exist_ok=True)

CLEAR = (0, 0, 0, 0)


def h(u, v, s=0):
    n = (u * 374761393 + v * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def jit(c, u, v, s, amt=6):
    d = int((h(u, v, s) - 0.5) * 2 * amt)
    return tuple(max(0, min(255, x + d)) for x in c[:3]) + ((c[3],) if len(c) > 3 else (255,))


def shade(c, f):
    return tuple(max(0, min(255, int(x * f))) for x in c[:3])


def tile(fn, size=16):
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            c = fn(u, v)
            if c is not None:
                img.putpixel((u, v), c if len(c) == 4 else tuple(c) + (255,))
    return img


def save(img, name):
    img.save(os.path.join(TEX, "orthoverse_queens_" + name + ".png"))


GOLD = (212, 170, 60)
GOLD_D = (150, 110, 30)
GOLD_L = (245, 215, 120)
IVORY = (238, 230, 210)
IVORY_D = (200, 188, 160)
RED = (150, 25, 40)
RED_D = (100, 15, 28)

# The eight colours of the floor, and the pattern each carries (a colour-blind
# player tells the regions apart by the pattern)
COLOURS = [
    ("violet", (172, 136, 214), "diamond"),
    ("orange", (240, 158, 82), "dots"),
    ("blue", (108, 158, 226), "rows"),
    ("green", (136, 196, 108), "columns"),
    ("grey", (186, 184, 178), "plain"),
    ("red", (226, 108, 100), "slant"),
    ("yellow", (232, 212, 98), "plus"),
    ("teal", (98, 200, 192), "ring"),
]


def pattern(kind, u, v):
    """True where the pattern is drawn (in a darker shade of the colour)"""
    if kind == "diamond":
        return abs(u - 7.5) + abs(v - 7.5) in (5.0, 6.0)
    if kind == "dots":
        return (u % 8 in (3, 4)) and (v % 8 in (3, 4))
    if kind == "rows":
        return v % 8 in (3, 4)
    if kind == "columns":
        return u % 8 in (3, 4)
    if kind == "plain":
        return False
    if kind == "slant":
        return (u + v) % 8 in (0, 1)
    if kind == "plus":
        return (u in (7, 8) and 4 <= v <= 11) or (v in (7, 8) and 4 <= u <= 11)
    if kind == "ring":
        d = math.hypot(u - 7.5, v - 7.5)
        return 4.0 <= d <= 5.6
    return False


for i, (name, col, kind) in enumerate(COLOURS):
    for sh, f in (("light", 1.0), ("dark", 0.84)):
        base = shade(col, f)
        mark = shade(col, f * 0.72)

        def fn(u, v, base=base, mark=mark, kind=kind, i=i):
            c = mark if pattern(kind, u, v) else base
            return jit(c, u, v, i * 7 + (1 if f < 1 else 0), 4)
        save(tile(fn), "tile_%s_%s" % (name, sh))

# The floor before a run paints it: plain pale stone
save(tile(lambda u, v: jit((214, 210, 200), u, v, 99, 5)), "tile_blank")


# A queen: ivory, with a gold crown band (for the nodebox's faces)
def queen_side(u, v):
    if v <= 2:
        return GOLD_L if u % 3 == 1 else GOLD
    if v == 3:
        return GOLD_D
    return jit(IVORY if u not in (0, 15) else IVORY_D, u, v, 5, 5)


save(tile(queen_side), "queen")
save(tile(lambda u, v: jit(IVORY, u, v, 6, 5)), "queen_top")


# The inventory picture of a queen
def queen_icon(u, v):
    # crown points, head, waist, skirt, base
    rows = {
        1: (5, 6, 9, 10), 2: (5, 6, 7, 8, 9, 10), 3: tuple(range(5, 11)),
    }
    if v in rows:
        return GOLD if u in rows[v] else None
    if v == 4:
        return GOLD_D if 5 <= u <= 10 else None
    if 5 <= v <= 6:
        return IVORY if 6 <= u <= 9 else None
    if 7 <= v <= 9:
        return IVORY if 7 <= u <= 8 else None
    if 10 <= v <= 12:
        w = v - 9
        return (IVORY if u not in (7 - w, 8 + w) else IVORY_D) if 7 - w <= u <= 8 + w else None
    if 13 <= v <= 14:
        return IVORY_D if 3 <= u <= 12 else None
    return None


save(tile(queen_icon), "queen_icon")


# A cross, to mark a square that cannot hold a queen
def cross(u, v):
    if abs(u - v) <= 1 and 2 <= u <= 13 or abs(u + v - 15) <= 1 and 2 <= u <= 13:
        return (60, 40, 40)
    return None


save(tile(cross), "cross")


# The doors to the throne room: gilded panels on white
def door(u, v):
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    if u in (2, 13) or v in (2, 13):
        return GOLD
    if 4 <= u <= 11 and 4 <= v <= 11:
        if abs(u - 7.5) + abs(v - 7.5) <= 3:
            return GOLD_L
        return jit((240, 236, 226), u, v, 8, 3)
    return jit((240, 236, 226), u, v, 9, 3)


save(tile(door), "door")


# The throne: red velvet and gold
save(tile(lambda u, v: jit(RED if (u + v) % 6 else RED_D, u, v, 10, 6)), "velvet")
save(tile(lambda u, v: jit(GOLD if (u * 3 + v) % 7 else GOLD_L, u, v, 11, 8)), "gold")


# The crown, on its cushion: gold with jewels
def crown(u, v):
    if v <= 1:
        return GOLD_L if u % 4 in (1, 2) else None
    if v <= 5:
        if v == 3 and u % 5 == 2:
            return (200, 30, 40) if u % 10 == 2 else (40, 90, 200)
        return jit(GOLD, u, v, 12, 10)
    return jit(GOLD_D, u, v, 13, 8)


save(tile(crown), "crown")
save(tile(lambda u, v: jit((120, 20, 60) if (u // 4 + v // 4) % 2 else (140, 30, 70), u, v, 14, 6)), "cushion")
save(tile(lambda u, v: jit((236, 232, 222), u, v, 15, 4)), "plinth")

# The Queen's banner on the walls: purple, a gold crown
def banner(u, v):
    if u in (0, 15):
        return GOLD_D
    if 4 <= v <= 8 and 4 <= u <= 11:
        if v == 4 and u % 2 == 0:
            return GOLD_L
        if v >= 5:
            return GOLD
    if v >= 14 and (u + v) % 2 == 0:
        return GOLD
    return jit((90, 40, 120), u, v, 16, 5)


save(tile(banner), "banner")

# The notice in the hall
def notice(u, v):
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    if 3 <= v <= 12 and 3 <= u <= 12 and v % 2 == 1:
        return (110, 100, 90) if h(u, v, 17) > 0.3 else (236, 228, 205)
    return (236, 228, 205)


save(tile(notice), "notice")

# ----------------------------------------------------------------------------
# The Queen's skin: Minetest Game's player recoloured, in a purple gown with
# long fair hair and a gold crown

base = Image.open(os.path.join(ROOT, "mods/mtg/player_api/models/character.png")).convert("RGBA")


def recolour(px, target):
    r, g, b, a = px
    _, l, _ = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    tr, tg, tb = (x / 255 for x in target)
    th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
    nl = max(0, min(1, tl * (0.55 + l * 1.4)))
    rr, gg, bb = colorsys.hls_to_rgb(th, nl, ts)
    return (int(rr * 255), int(gg * 255), int(bb * 255), a)


GOWN = (110, 50, 150)
HAIR = (226, 196, 120)
img = base.copy()
W, H = img.size
for y in range(H):
    for x in range(W):
        r, g, b, a = img.getpixel((x, y))
        if a == 0:
            continue
        if g > r + 20 and g > b + 10:
            img.putpixel((x, y), recolour((r, g, b, a), GOWN))
        elif y >= 16 and x < 16 and b > r + 20:
            img.putpixel((x, y), recolour((r, g, b, a), GOWN))
        elif y < 16 and r < 80 and g < 50 and b < 30 and r > g > b:
            img.putpixel((x, y), recolour((r, g, b, a), HAIR))
# long hair down the back and sides of the head
for (fx, fy) in ((0, 8), (16, 8), (24, 8)):
    for yy in range(fy, fy + 8):
        for xx in range(fx, fx + 8):
            if yy >= fy + 2 and (xx in (fx, fx + 7) or fx == 24):
                img.putpixel((xx, yy), jit(HAIR + (255,), xx, yy, 70, 6))
# the crown: a gold band round the top of the head (the head's sides are at
# y 8..15, x 0..31: front 8..15), points on the top row
for x in range(0, 32):
    img.putpixel((x, 8), GOLD + (255,))
    img.putpixel((x, 9), (GOLD_L if x % 2 else GOLD) + (255,))
for x in range(8, 16):
    for y in range(0, 8):
        img.putpixel((x, y), jit(GOLD + (255,), x, y, 71, 10) if (x in (8, 15) or y in (0, 7)) else img.getpixel((x, y)))
# a gold collar and girdle on the gown
for x in range(20, 28):
    img.putpixel((x, 20), GOLD + (255,))
    img.putpixel((x, 26), GOLD_D + (255,))
img.save(os.path.join(TEX, "orthoverse_queens_skin_queen.png"))

# ----------------------------------------------------------------------------
# Sounds: the doors (a deep rumble and a chord), a queen set down (a click
# on stone), the fanfare at the end

RATE = 44100


def write(name, samples):
    samples = np.clip(samples, -1, 1)
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "s.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes((samples * 32000).astype(np.int16).tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3",
                        os.path.join(SND, "orthoverse_queens_" + name + ".ogg")], check=True)


def env(n, attack, release):
    e = np.ones(n)
    a, r = int(attack * RATE), int(release * RATE)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


rng = np.random.default_rng(3)
# a piece set down: a short knock
n = int(0.12 * RATE)
t = np.arange(n) / RATE
knock = (np.sin(2 * np.pi * 900 * t) * 0.5 + rng.normal(0, 0.3, n)) * np.exp(-t * 60)
write("place", knock * 0.8)

# the doors: a low rumble under a rising major chord
n = int(2.6 * RATE)
t = np.arange(n) / RATE
rumble = np.convolve(rng.normal(0, 1, n), np.ones(400) / 400, mode="same") * 4
chord = sum(np.sin(2 * np.pi * f * t) for f in (261.6, 329.6, 392.0, 523.3)) / 4
write("doors", (rumble * 0.6 * np.exp(-t * 0.8) + chord * 0.5 * np.clip(t - 0.4, 0, 1)) * env(n, 0.05, 0.8))

# the fanfare: three rising notes and a held chord, brassy (odd harmonics)
def brass(f, dur):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    w = sum(np.sin(2 * np.pi * f * k * t) / k for k in (1, 2, 3, 4, 5))
    return w * env(n, 0.02, 0.08) * 0.3


fan = np.concatenate([brass(392, 0.18), brass(523.3, 0.18), brass(659.3, 0.18),
                      sum(brass(f, 1.2) for f in (523.3, 659.3, 784.0)) / 2])
write("fanfare", fan)
print("done")
