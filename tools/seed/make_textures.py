#!/usr/bin/env python3
"""Paint the textures for The Seed: the growth's blocks, the survey camp's
gear and crane (mods/orthoverse_seed) and the growth's monsters
(mods/orthoverse_monsters), and synthesise their sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/seed/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "monsters"))
from esp32_mobs import h, jit, paint, HEAD, BODY, ARM, LEG  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SEED = os.path.join(ROOT, "mods/orthoverse_seed/textures")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
SOUNDS = os.path.join(ROOT, "mods/orthoverse_seed/sounds")
MSOUNDS = os.path.join(ROOT, "mods/orthoverse_monsters/sounds")
for d in (SEED, MON, SOUNDS, MSOUNDS):
    os.makedirs(d, exist_ok=True)

CLEAR = (0, 0, 0, 0)


def tile(fn, size=16):
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            img.putpixel((u, v), fn(u, v))
    return img


def save(img, name, folder=SEED):
    img.save(os.path.join(folder, name))


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def smooth(u, v, s, scale=4.0, size=16):
    """Tileable value noise, 0 to 1."""
    fu, fv = u / scale, v / scale
    n = int(size / scale)
    u0, v0 = int(math.floor(fu)), int(math.floor(fv))
    tu, tv = fu - u0, fv - v0
    tu, tv = tu * tu * (3 - 2 * tu), tv * tv * (3 - 2 * tv)

    def c(a, b):
        return h(a % n, b % n, s)
    top = c(u0, v0) + (c(u0 + 1, v0) - c(u0, v0)) * tu
    bot = c(u0, v0 + 1) + (c(u0 + 1, v0 + 1) - c(u0, v0 + 1)) * tu
    return top + (bot - top) * tv


# --- the growth -----------------------------------------------------------------
PURPLE = (92, 40, 96)
PURPLE_D = (54, 22, 60)
PURPLE_L = (140, 70, 132)
VEIN = (190, 60, 120)
FLESH = (150, 62, 72)
FLESH_D = (96, 34, 46)
FLESH_L = (196, 104, 104)
GLOW = (120, 255, 200)


def veins(u, v, s, size=16):
    """1 on a vein, falling off beside it."""
    a = smooth(u, v, s, 4.0, size)
    b = smooth(u, v, s + 7, 8.0, size)
    return max(0.0, 1 - abs(a - b) * 9)


def crust(u, v, s=1):
    n = smooth(u, v, s, 4.0)
    c = mix(PURPLE_D, PURPLE_L, n)
    w = veins(u, v, s + 3)
    if w > 0.5:
        c = mix(c, VEIN, (w - 0.5) * 2)
    return jit(c, u, v, s, 6)


save(tile(lambda u, v: crust(u, v)), "orthoverse_seed_crust.png")


def crust_side(u, v):
    # crust hanging over dirt
    edge = 4 + int(h(u, 0, 5) * 4)
    if v < edge:
        return crust(u, v, 2)
    d = (106, 76, 52)
    return jit(d, u, v, 9, 10)


save(tile(crust_side), "orthoverse_seed_crust_side.png")


def ribbed(u, v, s=4, dark=False):
    # a wall of ribs (horizontal), wet highlights on their tops
    r = (v + int(smooth(u, 0, s, 8.0) * 3)) % 5
    base = FLESH_D if dark else FLESH
    c = {0: mix(base, FLESH_L, 0.6), 1: base, 2: base, 3: mix(base, (40, 10, 20), 0.35), 4: mix(base, (30, 8, 16), 0.6)}[r]
    w = veins(u, v, s + 11)
    if w > 0.6 and r in (1, 2):
        c = mix(c, PURPLE, 0.6)
    return jit(c, u, v, s, 7)


save(tile(lambda u, v: ribbed(u, v)), "orthoverse_seed_wall.png")
save(tile(lambda u, v: ribbed(u, v, 6, True)), "orthoverse_seed_wall_dark.png")


def flesh(u, v, s=8):
    n = smooth(u, v, s, 4.0)
    c = mix(FLESH_D, FLESH_L, n)
    w = veins(u, v, s + 2)
    if w > 0.4:
        c = mix(c, (110, 20, 60), (w - 0.4))
    return jit(c, u, v, s, 6)


save(tile(lambda u, v: flesh(u, v)), "orthoverse_seed_flesh.png")


def nodule(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 3.2:
        return mix((255, 255, 240), GLOW, d / 3.2)
    if d < 5.5:
        return mix(GLOW, (40, 120, 110), (d - 3.2) / 2.3)
    return flesh(u, v, 12)


save(tile(nodule), "orthoverse_seed_nodule.png")


def ash(u, v):
    n = smooth(u, v, 21, 4.0)
    c = mix((70, 68, 66), (150, 146, 140), n)
    if h(u, v, 22) > 0.93:
        c = (200, 196, 190, 255)
    return jit(c, u, v, 23, 8)


save(tile(ash), "orthoverse_seed_ash.png")


def membrane(u, v):
    w = veins(u, v, 31)
    n = smooth(u, v, 32, 8.0)
    c = mix((170, 90, 140), (220, 150, 180), n)
    if w > 0.45:
        c = mix(c, (120, 20, 70), (w - 0.45) * 1.8)
    # a slit down the middle, puckered
    if u in (7, 8) and 2 < v < 14:
        c = mix(c, (70, 10, 40), 0.7)
    return c[:3] + (215,)


save(tile(membrane), "orthoverse_seed_membrane.png")


def acid(u, v, f=0):
    n = smooth((u + f) % 16, v, 41, 4.0)
    c = mix((60, 150, 30), (170, 240, 70), n)
    if h(u, (v + f * 3) % 16, 42) > 0.94:
        c = (230, 255, 160, 255)
    return c[:3] + (200,)


frames = Image.new("RGBA", (16, 16 * 8))
for f in range(8):
    frames.paste(tile(lambda u, v: acid(u, v, f * 2)), (0, 16 * f))
save(frames, "orthoverse_seed_acid_animated.png")
save(tile(lambda u, v: acid(u, v)), "orthoverse_seed_acid.png")


def pad(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 7.6:
        return CLEAR
    c = mix((80, 110, 50), (140, 150, 70), smooth(u, v, 51, 4.0))
    ang = math.atan2(v - 7.5, u - 7.5)
    if abs(math.sin(ang * 4)) < 0.12 and d > 1.5:
        c = mix(c, (50, 70, 30), 0.6)
    if d > 6.6:
        c = mix(c, (60, 40, 50), 0.5)
    return jit(c, u, v, 52, 6)


save(tile(pad), "orthoverse_seed_pad.png")
save(tile(lambda u, v: mix(pad(u, v), (40, 40, 30), 0.3) if pad(u, v)[3] else CLEAR), "orthoverse_seed_pad_side.png")


def egg(u, v, burst=False):
    c = mix((210, 196, 160), (236, 226, 196), smooth(u, v, 61, 4.0))
    w = veins(u, v, 62)
    if w > 0.5:
        c = mix(c, (170, 60, 90), (w - 0.5) * 2)
    if burst:
        d = math.hypot(u - 7.5, v - 5)
        if d < 4.5:
            return mix((40, 30, 20), (90, 70, 40), d / 4.5)
        if d < 5.5:
            return (200, 220, 140, 255)
    return jit(c, u, v, 63, 6)


save(tile(egg), "orthoverse_seed_egg.png")
save(tile(lambda u, v: egg(u, v, True)), "orthoverse_seed_egg_burst.png")


def vent(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 3:
        return (20, 10, 16, 255)
    if d < 4.5:
        return mix((60, 30, 40), (120, 160, 90), (d - 3) / 1.5)
    if d < 6.5:
        return mix((130, 170, 90), FLESH_D, (d - 4.5) / 2)
    return flesh(u, v, 71)


save(tile(vent), "orthoverse_seed_vent.png")


def creep(u, v):
    n = smooth(u, v, 81, 4.0)
    if n < 0.32:
        return CLEAR
    c = mix(PURPLE_D, PURPLE_L, n)
    return jit(c, u, v, 82, 6)


save(tile(creep), "orthoverse_seed_creep.png")


def heart(u, v):
    n = smooth(u, v, 91, 4.0)
    c = mix((120, 10, 30), (220, 50, 60), n)
    w = veins(u, v, 92)
    if w > 0.4:
        c = mix(c, (255, 140, 120), (w - 0.4) * 1.5)
    return jit(c, u, v, 93, 5)


save(tile(heart), "orthoverse_seed_heart.png")


def shell(u, v):
    n = smooth(u, v, 101, 4.0)
    c = mix((40, 16, 30), (90, 40, 60), n)
    k = h(u // 3, v // 3, 102)
    if k > 0.8:
        c = mix(c, (130, 70, 90), 0.5)
    return jit(c, u, v, 103, 6)


save(tile(shell), "orthoverse_seed_shell.png")


def spore(u, v):
    d = math.hypot(u - 3.5, v - 3.5)
    if d > 3.6:
        return CLEAR
    return mix((220, 255, 170), (120, 180, 80), d / 3.6)[:3] + (int(230 - d * 40),)


save(tile(spore, 8), "orthoverse_seed_spore.png")


def overlay():
    size = 128
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            n = smooth(u, v, 111, 16.0, size) * 0.6 + smooth(u, v, 112, 8.0, size) * 0.4
            edge = max(abs(u - 63.5), abs(v - 63.5)) / 64
            a = max(0, n - 0.35) * 1.4 + edge ** 3 * 0.8
            img.putpixel((u, v), (150, 190, 90, int(max(0, min(1, a)) * 200)))
    return img


save(overlay(), "orthoverse_seed_spores_overlay.png")

# --- the camp's gear --------------------------------------------------------------


def fire_pot(u, v):
    # a clay pot with a burning rag
    if v < 5:
        if 6 <= u <= 9 and v >= 2 + (u % 2):
            return (255, 180 - v * 20, 40, 255)
        if 7 <= u <= 8 and v < 2:
            return (255, 230, 120, 255)
        if 5 <= u <= 10 and v == 4:
            return (200, 190, 170, 255)
        return CLEAR
    d = math.hypot(u - 7.5, (v - 10.5) * 1.1)
    if d < 5.2:
        c = mix((176, 92, 56), (110, 54, 34), d / 5.2)
        if v == 8:
            c = mix(c, (60, 30, 20), 0.5)
        return jit(c, u, v, 121, 6)
    if 6 <= u <= 9 and v == 5:
        return (120, 60, 36, 255)
    return CLEAR


save(tile(fire_pot), "orthoverse_seed_fire_pot.png")


def flame(u, v):
    d = math.hypot(u - 3.5, (v - 4) * 0.8)
    if d > 3.5:
        return CLEAR
    return mix((255, 240, 160), (255, 80, 20), d / 3.5)[:3] + (int(255 - d * 50),)


save(tile(flame, 8), "orthoverse_seed_flame.png")


def mask(u, v):
    # a breathing mask: a dark face piece, two round filters
    for cx in (4.5, 11.5):
        d = math.hypot(u - cx, v - 10.5)
        if d < 3:
            return mix((150, 150, 140), (90, 90, 84), d / 3)
    if 4 <= v <= 11 and 3 <= u <= 12:
        d = math.hypot(u - 7.5, (v - 7.5) * 1.4)
        if d < 5.5:
            c = mix((60, 64, 70), (36, 38, 44), d / 5.5)
            if 4 <= v <= 6 and u in (5, 6, 9, 10):
                c = (160, 220, 230, 255)   # the eye glass
            return c
    if v == 6 and (u < 3 or u > 12):
        return (90, 70, 50, 255)   # the strap
    return CLEAR


save(tile(mask), "orthoverse_seed_mask.png")


def rifle(u, v):
    # drawn on the diagonal, stock at the bottom left, muzzle at the top right
    a = (u + (15 - v)) / 2.0   # along
    b = (u - (15 - v)) / 2.0   # across
    if -1.2 <= b <= 1.2 and 2 <= a <= 14:
        c = (70, 76, 86)
        if a > 12:
            c = (40, 44, 50)
        if 7 <= a <= 10 and b > 0.2:
            c = (100, 220, 255)   # the charge cell
        if a < 5:
            c = (110, 80, 50)     # the stock
        return jit(c + (255,), u, v, 131, 6)
    if 5 <= a <= 7 and 1.2 < b <= 3.2:
        return (50, 54, 60, 255)  # the grip
    return CLEAR


save(tile(rifle), "orthoverse_seed_rifle.png")


def bolt(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 2.5:
        return (240, 255, 255, 255)
    if d < 5:
        return mix((140, 230, 255), (40, 120, 255), (d - 2.5) / 2.5)[:3] + (int(255 - (d - 2.5) * 70),)
    if d < 7.5:
        return (60, 140, 255, int(90 - (d - 5) * 34))
    return CLEAR


save(tile(bolt), "orthoverse_seed_plasma.png")


def rack(u, v):
    c = (70, 74, 82) if (u in (0, 15) or v in (0, 15)) else (52, 56, 62)
    if v in (4, 11) and 1 <= u <= 14:
        c = (120, 126, 136)
    if u in (4, 8, 12) and 4 <= v <= 11:
        c = (90, 220, 255) if v == 7 else (36, 38, 44)
    return jit(c + (255,), u, v, 141, 5)


save(tile(rack), "orthoverse_seed_rack.png")


def stores(u, v):
    c = (96, 104, 76)
    if u in (0, 15) or v in (0, 15):
        c = (60, 66, 48)
    if 5 <= v <= 10 and 3 <= u <= 12:
        c = (200, 196, 180)
        if 6 <= v <= 9 and u in (7, 8):
            c = (200, 50, 40)
        if v in (7, 8) and 5 <= u <= 10:
            c = (200, 50, 40)
    return jit(c + (255,), u, v, 151, 6)


save(tile(stores), "orthoverse_seed_stores.png")

# --- the crane -------------------------------------------------------------------
STEEL = (96, 102, 112)
YELLOW = (220, 180, 40)


def rail(u, v):
    if v in (0, 1, 14, 15):
        c = (70, 74, 82)
    elif 6 <= u <= 9:
        c = STEEL
    else:
        c = (40, 42, 48)
    if v in (0, 15) and (u // 2) % 2 == 0:
        c = YELLOW
    return jit(c + (255,), u, v, 161, 5)


save(tile(rail), "orthoverse_seed_rail.png")


def trolley(u, v):
    c = YELLOW if not (u in (0, 15) or v in (0, 15)) else (120, 96, 20)
    if 4 <= u <= 11 and 4 <= v <= 11:
        c = (60, 62, 70)
        if (u + v) % 4 == 0:
            c = (90, 94, 104)
    return jit(c + (255,), u, v, 171, 5)


save(tile(trolley), "orthoverse_seed_trolley.png")


def cable(u, v):
    if 7 <= u <= 8:
        return (60, 60, 64, 255) if (v + u) % 3 else (110, 110, 116, 255)
    return CLEAR


save(tile(cable), "orthoverse_seed_cable.png")


def magnet(u, v, on):
    c = (150, 30, 30) if v < 11 else ((200, 200, 210) if not on else (140, 220, 255))
    if u in (0, 15) or v == 0:
        c = (90, 20, 20)
    if v >= 11 and (u + v) % 2 == 0:
        c = mix(c + (255,), (255, 255, 255), 0.3 if on else 0)[:3]
    return jit(c + (255,), u, v, 181, 4)


save(tile(lambda u, v: magnet(u, v, False)), "orthoverse_seed_magnet.png")
save(tile(lambda u, v: magnet(u, v, True)), "orthoverse_seed_magnet_on.png")
save(tile(lambda u, v: (150, 30, 30, 255) if not (u in (0, 15) or v in (0, 15)) else (90, 20, 20, 255)),
     "orthoverse_seed_magnet_top.png")


def container(u, v, top=False):
    if top:
        c = (196, 96, 36) if not (u in (0, 15) or v in (0, 15)) else (130, 60, 24)
        if u in (3, 12) and v in (3, 12):
            c = (90, 90, 96)
        return jit(c + (255,), u, v, 191, 6)
    c = (200, 100, 40) if u % 3 else (150, 70, 28)
    if v in (0, 15):
        c = (130, 60, 24)
    if v in (6, 7) and 3 <= u <= 12:
        c = (240, 236, 220)
    return jit(c + (255,), u, v, 192, 6)


save(tile(lambda u, v: container(u, v)), "orthoverse_seed_container.png")
save(tile(lambda u, v: container(u, v, True)), "orthoverse_seed_container_top.png")

GLYPHS = {
    "left": ["....#...", "...##...", "..######", ".#######", ".#######", "..######", "...##...", "....#..."],
    "right": ["...#....", "...##...", "######..", "#######.", "#######.", "######..", "...##...", "...#...."],
    "up": ["...##...", "..####..", ".######.", "########", "..####..", "..####..", "..####..", "..####.."],
    "down": ["..####..", "..####..", "..####..", "..####..", "########", ".######.", "..####..", "...##..."],
    "magnet": ["########", "########", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##"],
}


def button(u, v, glyph, lit=(240, 200, 60)):
    c = (54, 58, 66)
    if u in (0, 15) or v in (0, 15):
        c = (90, 96, 106)
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 6.5:
        c = (30, 32, 36)
    g = GLYPHS[glyph]
    gu, gv = u - 4, v - 4
    if 0 <= gu < 8 and 0 <= gv < 8 and g[gv][gu] == "#":
        c = lit
    return jit(c + (255,), u, v, 201, 3)


for gname in GLYPHS:
    save(tile(lambda u, v: button(u, v, gname)), "orthoverse_seed_button_" + gname + ".png")
save(tile(lambda u, v: button(u, v, "magnet", (120, 220, 255))), "orthoverse_seed_button_magnet_on.png")

# --- the monsters ---------------------------------------------------------------


def husk_skin():
    img = Image.new("RGBA", (64, 32), CLEAR)
    SUIT = (196, 110, 40)

    def suit(u, v, w, hh, s=1):
        c = jit(SUIT + (255,), u, v, s, 10)
        n = smooth(u * 2 % 16, v * 2 % 16, s + 40, 4.0)
        if n > 0.55:
            c = mix(c, PURPLE, (n - 0.55) * 3)
        if h(u, v, s + 3) > 0.9:
            c = mix(c, GLOW, 0.6)
        return c

    for part in (BODY, ARM, LEG):
        for r in part.values():
            paint(img, r, lambda u, v, w, hh: suit(u, v, w, hh, r[0] + r[1]))

    def head(u, v, w, hh):
        c = mix((70, 64, 70), (40, 36, 44), v / 8)
        n = smooth(u * 2 % 16, v * 2 % 16, 77, 4.0)
        if n > 0.45:
            c = mix(c, PURPLE_L, (n - 0.45) * 2)
        return jit(c, u, v, 78, 6)

    for r in HEAD.values():
        paint(img, r, head)
    # the visor, cracked and grown over, two glowing points behind it
    paint(img, (9, 11, 6, 3), lambda u, v, w, hh: (GLOW + (255,)) if (u, v) in ((1, 1), (4, 1)) else
          mix((60, 90, 110), PURPLE, h(u, v, 79)))
    return img


save(husk_skin(), "orthoverse_monsters_husk.png", MON)


def cube_face(seed, base, glow=None, mouth=False, eyes=False):
    def f(u, v):
        c = mix(base, mix(base, (0, 0, 0), 0.5), smooth(u, v, seed, 4.0))
        w = veins(u, v, seed + 1)
        if w > 0.5:
            c = mix(c, VEIN, (w - 0.5) * 1.6)
        if glow and math.hypot(u - 7.5, v - 7.5) < 3:
            c = mix(glow, c, math.hypot(u - 7.5, v - 7.5) / 3)
        if mouth and 4 <= u <= 11 and 9 <= v <= 12:
            c = (30, 10, 16, 255) if v in (10, 11) else (230, 220, 190, 255) if u % 2 else c
        if eyes and v == 5 and u in (4, 5, 10, 11):
            c = (255, 240, 90, 255)
        return jit(c, u, v, seed + 2, 5)
    return tile(f)


save(cube_face(301, (70, 40, 80)), "orthoverse_monsters_crawler_side.png", MON)
save(cube_face(302, (90, 50, 96)), "orthoverse_monsters_crawler_top.png", MON)
save(cube_face(303, (70, 40, 80), mouth=True, eyes=True), "orthoverse_monsters_crawler_front.png", MON)
save(cube_face(311, (120, 70, 60)), "orthoverse_monsters_spitter_side.png", MON)
save(cube_face(312, (120, 70, 60), mouth=True), "orthoverse_monsters_spitter_front.png", MON)
save(cube_face(321, (120, 40, 80), glow=(255, 200, 230)), "orthoverse_monsters_ganglion.png", MON)
save(cube_face(331, (150, 30, 50), glow=(255, 255, 220)), "orthoverse_monsters_nodule.png", MON)
save(cube_face(341, (130, 50, 70)), "orthoverse_monsters_tendril.png", MON)


def puff(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 7.4:
        return CLEAR
    c = mix((230, 255, 190), (130, 170, 80), d / 7.4)
    if h(u, v, 351) > 0.85:
        c = (255, 255, 230, 255)
    return c[:3] + (int(240 - d * 18),)


save(tile(puff), "orthoverse_monsters_spore_puff.png", MON)


def acid_orb(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 3:
        return (230, 255, 160, 255)
    if d < 6:
        return mix((170, 240, 70), (60, 150, 30), (d - 3) / 3)[:3] + (int(255 - (d - 3) * 50),)
    return CLEAR


save(tile(acid_orb), "orthoverse_monsters_acid_orb.png", MON)

# --- sounds -----------------------------------------------------------------
RATE = 44100
rng = np.random.default_rng(23)


def write_ogg(name, x, gain=0.8, folder=SOUNDS):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(folder, name)], check=True)
    os.unlink(path)


def secs(s):
    return np.arange(int(RATE * s)) / RATE


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, "same")


# squelch: a membrane opening
t = secs(0.6)
x = lowpass(rng.standard_normal(len(t)), 40) * 6 * np.exp(-t / 0.25) + np.sin(2 * np.pi * np.cumsum(180 - 120 * t) / RATE) * np.exp(-t / 0.2)
write_ogg("orthoverse_seed_squelch.ogg", x, 0.7)
# burn: a fire pot bursting
t = secs(1.0)
x = lowpass(rng.standard_normal(len(t)), 6) * np.exp(-t / 0.35) + rng.standard_normal(len(t)) * (rng.random(len(t)) > 0.97) * np.exp(-t / 0.5)
write_ogg("orthoverse_seed_burn.ogg", x, 0.7)
# pop: an egg sac bursting
t = secs(0.35)
write_ogg("orthoverse_seed_pop.ogg", lowpass(rng.standard_normal(len(t)), 20) * 5 * np.exp(-t / 0.06) + np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.1), 0.7)
# the Lung: a long breath in, then out
t = secs(2.2)
env = np.sin(np.pi * t / 2.2) ** 2
write_ogg("orthoverse_seed_inhale.ogg", lowpass(rng.standard_normal(len(t)), 25) * env * (0.6 + 0.4 * t / 2.2), 0.6)
t = secs(2.6)
env = np.minimum(1, t / 0.15) * np.exp(-t / 1.1)
write_ogg("orthoverse_seed_gust.ogg", lowpass(rng.standard_normal(len(t)), 12) * env, 0.8)
# heartbeat: lub-dub, looped near the Heart
t = secs(1.1)
beat = lambda t0: np.sin(2 * np.pi * 52 * (t - t0)) * np.exp(-np.maximum(0, t - t0) / 0.07) * (t >= t0)
write_ogg("orthoverse_seed_heartbeat.ogg", beat(0.0) + 0.7 * beat(0.22), 0.8)
# spit: a spitter's acid
t = secs(0.4)
write_ogg("orthoverse_monsters_spit.ogg", lowpass(rng.standard_normal(len(t)), 8) * np.exp(-t / 0.08) + np.sin(2 * np.pi * np.cumsum(400 - 600 * t) / RATE) * np.exp(-t / 0.12) * 0.5, 0.6, MSOUNDS)
# the plasma rifle: a rising whine and a crack; a hit
t = secs(0.45)
whine = np.sin(2 * np.pi * np.cumsum(600 + 2400 * t) / RATE) * np.exp(-t / 0.15)
write_ogg("orthoverse_seed_plasma_fire.ogg", whine + rng.standard_normal(len(t)) * np.exp(-t / 0.02) * 0.6, 0.6)
t = secs(0.5)
write_ogg("orthoverse_seed_plasma_hit.ogg", rng.standard_normal(len(t)) * np.exp(-t / 0.06) + np.sin(2 * np.pi * 220 * t) * np.exp(-t / 0.2) * 0.5, 0.7)
t = secs(0.3)
write_ogg("orthoverse_seed_click.ogg", np.sin(2 * np.pi * 1200 * t) * np.exp(-t / 0.02), 0.4)
# the crane: a motor whirr, a clank, the magnet's hum
t = secs(0.5)
write_ogg("orthoverse_seed_crane.ogg", (np.sign(np.sin(2 * np.pi * 70 * t)) * 0.3 + np.sin(2 * np.pi * 140 * t) * 0.5) * np.sin(np.pi * t / 0.5) + lowpass(rng.standard_normal(len(t)), 4) * 0.1, 0.5)
t = secs(0.6)
write_ogg("orthoverse_seed_clank.ogg", (np.sin(2 * np.pi * 310 * t) + np.sin(2 * np.pi * 467 * t) * 0.7 + rng.standard_normal(len(t)) * np.exp(-t / 0.01)) * np.exp(-t / 0.15), 0.8)
t = secs(0.8)
write_ogg("orthoverse_seed_magnet.ogg", (np.sin(2 * np.pi * 100 * t) + 0.4 * np.sin(2 * np.pi * 200 * t)) * np.minimum(1, t / 0.05) * np.exp(-t / 0.5), 0.5)
# the wither: a long falling sigh
t = secs(4.0)
write_ogg("orthoverse_seed_wither.ogg", lowpass(rng.standard_normal(len(t)), 30) * np.exp(-t / 1.6) * 3 + np.sin(2 * np.pi * np.cumsum(140 - 30 * t) / RATE) * np.exp(-t / 1.2), 0.8)
# crawlers chitter; husks groan through a mask; the Heart's cry
t = secs(0.5)
clicks = (rng.random(len(t)) > 0.995).astype(float)
write_ogg("orthoverse_monsters_crawler.ogg", np.convolve(clicks, np.sin(2 * np.pi * 2500 * secs(0.005)) * 1.0, "same") + lowpass(rng.standard_normal(len(t)), 3) * 0.05, 0.6, MSOUNDS)
t = secs(1.2)
write_ogg("orthoverse_monsters_husk.ogg", np.sin(2 * np.pi * np.cumsum(110 + 20 * np.sin(2 * np.pi * 3 * t)) / RATE) * np.sin(np.pi * t / 1.2) + lowpass(rng.standard_normal(len(t)), 6) * 0.4 * np.sin(np.pi * t / 1.2), 0.6, MSOUNDS)
t = secs(1.5)
write_ogg("orthoverse_monsters_heart_cry.ogg", np.sin(2 * np.pi * np.cumsum(300 - 180 * t) / RATE) * np.exp(-t / 0.6) + lowpass(rng.standard_normal(len(t)), 10) * np.exp(-t / 0.5), 0.8, MSOUNDS)
print("ok")
