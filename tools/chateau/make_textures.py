#!/usr/bin/env python3
"""Paint the textures for Death at the Château (mods/orthoverse_chateau): the
château's walls, floors and furniture, the weapons in their places, the
portraits, the guests' skins, and synthesise its sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/chateau/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds; the guests'
skins are made from Minetest Game's player skin, mods/mtg/player_api)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import colorsys, math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
TEX = os.path.join(ROOT, "mods/orthoverse_chateau/textures")
SND = os.path.join(ROOT, "mods/orthoverse_chateau/sounds")
for d in (TEX, SND):
    os.makedirs(d, exist_ok=True)

CLEAR = (0, 0, 0, 0)


def h(u, v, s=0):
    n = (u * 374761393 + v * 668265263 + s * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def jit(c, u, v, s, amt=8):
    d = int((h(u, v, s) - 0.5) * 2 * amt)
    return tuple(max(0, min(255, x + d)) for x in c[:3]) + ((c[3],) if len(c) > 3 else (255,))


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def tile(fn, size=16):
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            c = fn(u, v)
            if c is not None:
                img.putpixel((u, v), c if len(c) == 4 else tuple(c) + (255,))
    return img


def save(img, name):
    img.save(os.path.join(TEX, "orthoverse_chateau_" + name + ".png"))


GOLD = (212, 170, 60)
GOLD_D = (150, 110, 30)
GOLD_L = (245, 215, 120)
WHITE = (236, 232, 222)
OAK = (150, 100, 55)
OAK_D = (110, 70, 35)
MAHOG = (95, 45, 30)
MAHOG_D = (65, 28, 18)
BLACK = (22, 20, 22)

# --- walls, floors, roof --------------------------------------------------------


def parquet(u, v):
    # herringbone: blocks of 4 x 2, turned in alternate columns
    a = (u // 4 + v // 4) % 2
    if a:
        board, along = (v % 4) // 2, u % 4
    else:
        board, along = (u % 4) // 2, v % 4
    base = OAK if (board + (u // 8)) % 2 else (165, 112, 62)
    c = jit(base, u, v, 3, 7)
    if along == 0 or (a and v % 2 == 0 and u % 4 == 0):
        c = mix(c, OAK_D, 0.6)
    return c


save(tile(parquet), "parquet")


def marble(base, vein, s):
    def f(u, v):
        t = math.sin((u + v * 0.6) * 0.7 + 3 * math.sin(v * 0.4 + s) + h(u // 3, v // 3, s) * 2)
        c = jit(base, u, v, s, 5)
        if abs(t) < 0.12:
            c = mix(c, vein, 0.6)
        if u == 0 or v == 0:
            c = mix(c, vein, 0.25)
        return c
    return f


save(tile(marble((232, 230, 226), (150, 150, 160), 1)), "marble_white")
save(tile(marble((40, 38, 44), (120, 115, 125), 2)), "marble_black")
save(tile(marble((200, 140, 150), (120, 60, 70), 4)), "marble_rose")


def panel(u, v):
    c = jit(WHITE, u, v, 5, 4)
    if u in (2, 13) and 2 <= v <= 13 or v in (2, 13) and 2 <= u <= 13:
        return jit(GOLD, u, v, 6, 10)
    if u in (3, 12) and 3 <= v <= 12 or v in (3, 12) and 3 <= u <= 12:
        return mix(c, (190, 185, 175), 0.5)
    return c


save(tile(panel), "panel")


def panel_wood(u, v):
    c = jit(MAHOG, u, v, 7, 6)
    if math.sin(v * 1.3 + h(u, 0, 9) * 3) > 0.8:
        c = mix(c, MAHOG_D, 0.5)
    if u in (1, 14) or v in (1, 14):
        c = mix(c, MAHOG_D, 0.7)
    if u in (2, 13) and 2 <= v <= 13 or v in (2, 13) and 2 <= u <= 13:
        c = mix(c, (150, 90, 55), 0.5)
    return c


save(tile(panel_wood), "panel_wood")


def stone(u, v):
    # limestone ashlar: courses 4 high, blocks 8 long, staggered
    row = v // 4
    off = 4 if row % 2 else 0
    c = jit((222, 210, 182), u, v, 11, 6)
    c = mix(c, (200, 186, 156), h((u + off) // 8, row, 12) * 0.5)
    if v % 4 == 3 or (u + off) % 8 == 0:
        c = mix(c, (165, 150, 120), 0.6)
    return c


save(tile(stone), "stone")


def slate(u, v):
    row = v // 3
    off = 2 if row % 2 else 0
    c = jit((70, 76, 88), u, v, 13, 8)
    if v % 3 == 2 or (u + off) % 4 == 0:
        c = mix(c, (40, 44, 52), 0.7)
    return c


save(tile(slate), "slate")


def cornice(u, v):
    c = jit(WHITE, u, v, 14, 4)
    if v in (1, 14):
        c = GOLD
    if 4 <= v <= 11:
        # egg and dart
        cx = (u % 4) - 1.5
        cy = v - 7.5
        if cx * cx / 2.2 + cy * cy / 9 < 1:
            c = jit(GOLD_L if cx < 0 else GOLD, u, v, 15, 10)
        elif u % 4 == 3:
            c = GOLD_D
    return c


save(tile(cornice), "cornice")


def ceiling(u, v):
    c = jit((240, 236, 226), u, v, 16, 3)
    d = math.hypot(u - 7.5, v - 7.5)
    if 5.5 < d < 6.5:
        c = jit(GOLD, u, v, 17, 12)
    if d < 1.5:
        c = GOLD_L
    if u in (0, 15) or v in (0, 15):
        c = mix(c, GOLD, 0.5)
    return c


save(tile(ceiling), "ceiling")


def damask(base):
    dark = tuple(int(x * 0.72) for x in base)

    def f(u, v):
        c = jit(base, u, v, 18, 4)
        x, y = (u % 8) - 3.5, (v % 16) - 7.5
        if abs(x) * 1.6 + abs(y) * 0.6 < 3 and abs(x) * 1.6 + abs(y) * 0.6 > 1.6:
            c = jit(dark, u, v, 19, 4)
        if abs(x) < 0.6 and abs(y) < 0.6:
            c = dark
        return c
    return f


save(tile(damask((150, 30, 45))), "damask_red")
save(tile(damask((50, 80, 150))), "damask_blue")
save(tile(damask((40, 105, 70))), "damask_green")


def carpet(u, v):
    c = jit((130, 25, 40), u, v, 20, 6)
    if u in (1, 14) or v in (1, 14):
        c = jit(GOLD, u, v, 21, 10)
    d = abs(u - 7.5) + abs(v - 7.5)
    if 3 < d < 4.5:
        c = jit((30, 40, 90), u, v, 22, 6)
    if d < 1.5:
        c = GOLD
    return c


save(tile(carpet), "carpet")


def flagstone(u, v):
    c = jit((120, 118, 110), u, v, 23, 10)
    if u % 8 == 0 or v % 8 == 0:
        c = mix(c, (70, 68, 62), 0.7)
    return c


save(tile(flagstone), "flagstone")


def kitchen_tile(u, v):
    c = (180, 70, 50) if ((u // 4) + (v // 4)) % 2 else (225, 205, 170)
    c = jit(c, u, v, 24, 6)
    if u % 4 == 0 or v % 4 == 0:
        c = mix(c, (110, 90, 70), 0.4)
    return c


save(tile(kitchen_tile), "kitchen_tile")

# --- fittings --------------------------------------------------------------------


def mirror(u, v):
    if u in (0, 15) or v in (0, 15):
        return jit(GOLD_D, u, v, 25, 10)
    if u in (1, 14) or v in (1, 14):
        return jit(GOLD_L, u, v, 26, 10)
    t = (u + v) / 30
    c = mix((170, 185, 200), (225, 232, 240), t)
    if (u - v) % 7 == 0 and 3 < u < 12:
        c = mix(c, (255, 255, 255), 0.6)
    return c


save(tile(mirror), "mirror")


def chandelier(u, v):
    # a crystal chandelier, hanging (plantlike)
    if u in (7, 8) and v < 4:
        return GOLD_D
    rows = {4: (5, 10), 5: (3, 12), 6: (2, 13), 7: (3, 12), 9: (4, 11), 10: (5, 10)}
    if v in rows and rows[v][0] <= u <= rows[v][1]:
        if v in (4, 9):
            return GOLD
        if (u + v) % 2 == 0:
            return (255, 250, 220)
        return (210, 230, 255)
    if v in (8, 11, 12) and u % 3 == 1 and 3 <= u <= 12:
        return (220, 240, 255)
    if v == 3 and u in (4, 6, 9, 11):
        return (255, 220, 120)
    return None


save(tile(chandelier), "chandelier")


def candles(u, v):
    # a pair of candles on a gilt stand (for side tables)
    if v >= 13 and 4 <= u <= 11:
        return GOLD if v == 13 else GOLD_D
    for cx in (5, 10):
        if u == cx and 6 <= v <= 12:
            return (245, 240, 225)
        if u == cx and v in (4, 5):
            return (255, 200, 80) if v == 5 else (255, 240, 170)
    return None


save(tile(candles), "candles")


def fireplace(u, v):
    if u <= 1 or u >= 14 or v <= 2:
        return jit((238, 236, 232), u, v, 27, 5) if not (v == 2) else GOLD
    if v >= 14:
        return (60, 50, 45)
    # the fire
    d = abs(u - 7.5) + (15 - v) * 0.5
    if d < 4.5 and v > 7:
        return (255, int(120 + 80 * h(u, v, 28)), 30)
    if d < 6 and v > 6:
        return (200, 60, 20)
    return jit((30, 24, 22), u, v, 29, 4)


save(tile(fireplace), "fireplace")
save(tile(lambda u, v: jit((238, 236, 232), u, v, 30, 5) if v != 2 else GOLD), "fireplace_side")


def table_top(u, v):
    c = jit((120, 70, 40), u, v, 31, 6)
    if math.sin(u * 0.9 + h(0, v, 32) * 4) > 0.85:
        c = mix(c, (90, 50, 25), 0.5)
    return c


save(tile(table_top), "table_top")


def table_side(u, v):
    c = jit((100, 58, 32), u, v, 33, 6)
    if v in (0, 15):
        c = GOLD
    return c


save(tile(table_side), "table_side")
save(tile(lambda u, v: jit((246, 244, 238), u, v, 34, 3) if not (u in (0, 15) and v % 3 == 0) else (220, 210, 190)), "cloth")


def velvet(base):
    return lambda u, v: jit(mix(base, tuple(int(x * 0.7) for x in base), h(u // 2, v // 2, 35) * 0.6), u, v, 36, 4)


save(tile(velvet((110, 30, 120))), "velvet_purple")
save(tile(velvet((150, 25, 40))), "velvet_red")
save(tile(velvet((40, 60, 130))), "velvet_blue")


def felt(u, v):
    c = jit((30, 110, 55), u, v, 37, 5)
    if u in (0, 15) or v in (0, 15):
        c = (80, 45, 25)
    if (u, v) in ((1, 1), (14, 1), (1, 14), (14, 14)):
        c = (10, 10, 10)
    return c


save(tile(felt), "felt")
save(tile(lambda u, v: jit((90, 50, 28), u, v, 38, 5) if v not in (3, 12) else GOLD), "billiard_side")


def piano_top(u, v):
    c = jit(BLACK, u, v, 39, 3)
    if (u + v) % 9 == 0:
        c = (70, 70, 80)
    return c


save(tile(piano_top), "piano_top")


def piano_keys(u, v):
    if v < 6:
        return jit(BLACK, u, v, 40, 3)
    if v < 11 and u % 3 == 2:
        return (15, 15, 15)
    if u % 3 == 0:
        return (180, 180, 180)
    return (245, 245, 240)


save(tile(piano_keys), "piano_keys")


def harp(u, v):
    if u == 3 and v >= 1:
        return GOLD_D
    if v == 1 and 3 <= u <= 12 or (u - 3) == (14 - v) and u >= 3:
        return GOLD
    if 4 <= u <= 12 and u % 2 == 0 and v > 1 and v < 15 - (u - 3) * 0.9:
        return (240, 235, 220)
    if v == 15 and 2 <= u <= 6:
        return GOLD_D
    return None


save(tile(harp), "harp")


def barrel_side(u, v):
    c = jit((125, 80, 45), u, v, 41, 8)
    if u % 4 == 0:
        c = mix(c, (80, 50, 25), 0.6)
    if v in (2, 3, 12, 13):
        c = (60, 58, 60)
    return c


save(tile(barrel_side), "barrel_side")


def barrel_top(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 7.5:
        return (60, 58, 60)
    c = jit((140, 95, 55), u, v, 42, 6)
    if d > 6.5:
        c = (60, 58, 60)
    if u % 4 == 0:
        c = mix(c, (90, 60, 30), 0.5)
    return c


save(tile(barrel_top), "barrel_top")


def wine_rack(u, v):
    if u % 4 == 0 or v % 4 == 0:
        return jit((95, 60, 35), u, v, 43, 6)
    d = math.hypot(u % 4 - 2, v % 4 - 2)
    if d < 1.3:
        return (40, 60, 30) if h(u // 4, v // 4, 44) > 0.3 else (90, 20, 30)
    return (25, 18, 14)


save(tile(wine_rack), "wine_rack")


def copper(u, v):
    if v in (5, 15):
        return jit((95, 60, 35), u, v, 45, 6)
    pots = [(3, 2, 3), (8, 2, 2), (12, 2, 3), (4, 11, 3), (10, 11, 4)]
    for cx, cy, r in pots:
        if abs(u - cx) <= r and 0 <= v - cy <= r + 1 and v not in (5, 15):
            return jit((205, 110, 60) if u < cx else (170, 85, 45), u, v, 46, 10)
    return None


save(tile(copper), "copper")


def oven(u, v):
    c = jit((150, 70, 50), u, v, 47, 10)
    if v % 4 == 3 or (u + (4 if (v // 4) % 2 else 0)) % 8 == 0:
        c = mix(c, (200, 190, 175), 0.5)
    d = math.hypot(u - 7.5, (v - 10) * 1.3)
    if v >= 6 and d < 5:
        return (255, int(110 + 90 * h(u, v, 48)), 30) if d < 3.5 else (30, 20, 15)
    return c


save(tile(oven), "oven")


def desk_top(u, v):
    c = jit(MAHOG, u, v, 49, 5)
    if 2 <= u <= 13 and 2 <= v <= 13:
        c = jit((40, 80, 50), u, v, 50, 4)   # leather
    if u in (1, 14) and 1 <= v <= 14 or v in (1, 14) and 1 <= u <= 14:
        c = GOLD
    return c


save(tile(desk_top), "desk_top")


def desk_side(u, v):
    c = jit(MAHOG, u, v, 51, 5)
    if v in (1, 14) or u in (1, 14):
        c = GOLD_D
    if v == 4 and 5 <= u <= 10:
        c = GOLD
    return c


save(tile(desk_side), "desk_side")


def drawers(u, v):
    c = jit(MAHOG, u, v, 52, 5)
    if v in (0, 5, 10, 15) or u in (0, 15):
        c = MAHOG_D
    if v in (2, 7, 12) and u in (4, 11):
        c = GOLD
    return c


save(tile(drawers), "drawers")


def safe(open_):
    def f(u, v):
        if u in (0, 15) or v in (0, 15):
            return GOLD_D
        if open_:
            if 2 <= u <= 13 and 2 <= v <= 13:
                return (25, 25, 30) if not (v == 10 and 4 <= u <= 11) else (90, 90, 95)
        c = jit((70, 72, 78), u, v, 53, 5)
        d = math.hypot(u - 7.5, v - 7.5)
        if 2.5 < d < 3.5:
            c = GOLD
        if d < 1.2:
            c = (30, 30, 30)
        if 2.5 < d < 3.5 and (u + v) % 3 == 0:
            c = (40, 40, 40)
        return c
    return f


save(tile(safe(False)), "safe")
save(tile(safe(True)), "safe_open")


def cabinet(vial):
    def f(u, v):
        if u in (0, 15) or v in (0, 15) or v == 8:
            return jit(OAK, u, v, 54, 6)
        c = (180, 205, 210)
        if (u + v) % 6 == 0:
            c = (220, 235, 240)
        # bottles on the shelves
        if v in range(9, 15) and u in (3, 4, 11, 12):
            c = (90, 120, 70) if u < 8 else (120, 70, 40)
        if vial and v in range(3, 8) and u in (7, 8):
            c = (60, 20, 80) if v > 4 else (230, 225, 210)
        if not vial and v == 7 and u in (7, 8):
            c = (150, 170, 175)   # a ring in the dust
        return c
    return f


save(tile(cabinet(True)), "cabinet")
save(tile(cabinet(False)), "cabinet_empty")


def pistols(both):
    def f(u, v):
        c = jit((100, 58, 32), u, v, 55, 5)
        if u in (0, 15) or v in (0, 15):
            c = GOLD_D
        guns = [3, 10] if both else [3]
        for y in guns:
            if v == y and 2 <= u <= 11:
                c = (60, 60, 65)
            if v in (y + 1, y + 2) and 9 <= u <= 12:
                c = (110, 60, 30)
            if v == y + 1 and u == 8:
                c = GOLD
        if not both:
            if v in (9, 12) and u in (4, 10):
                c = GOLD   # empty hooks
        return c
    return f


save(tile(pistols(True)), "pistols")
save(tile(pistols(False)), "pistols_gone")


def candelabra(u, v):
    # the silver candlestick (plantlike)
    S, SD = (215, 218, 225), (150, 152, 160)
    if v >= 14 and 5 <= u <= 10:
        return S if v == 14 else SD
    if u in (7, 8) and 6 <= v <= 13:
        return S if u == 7 else SD
    if v == 6 and 3 <= u <= 12:
        return S
    if u in (3, 12) and v in (4, 5):
        return S
    for cx in (3, 7, 12):
        if u in (cx, cx + (1 if cx == 7 else 0)) and 1 <= v <= 3:
            return (245, 240, 225)
    return None


save(tile(candelabra), "candlestick")


def dust_ring(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if 2.5 < d < 4:
        return (210, 205, 195, 120)
    return None


save(tile(dust_ring), "dust_ring")


def letter_opener(u, v):
    if u == v and 3 <= u <= 10:
        return (250, 245, 230)
    if u == v + 1 and 3 <= v <= 10:
        return (225, 220, 205)
    if 10 <= u <= 13 and 10 <= v <= 13 and abs(u - v) <= 1:
        return GOLD
    return None


save(tile(letter_opener), "letter_opener")


def papers(u, v):
    if 2 <= u <= 12 and 3 <= v <= 13:
        c = (245, 240, 225) if (u + v) % 11 else (230, 222, 205)
        if v % 2 == 0 and 4 <= u <= 11:
            c = (120, 110, 100)
        return c
    return None


save(tile(papers), "papers")


def fire_irons(full):
    def f(u, v):
        if v >= 14 and 4 <= u <= 11:
            return (40, 40, 42)
        if u == 5 and 3 <= v <= 14:
            return (55, 55, 58)        # the tongs
        if u == 10 and 3 <= v <= 14:
            return (55, 55, 58)        # the shovel
        if u == 10 and v in (12, 13):
            return (70, 70, 72)
        if full and u in (7, 8) and 2 <= v <= 13:
            return (35, 35, 38) if u == 7 else (65, 65, 68)  # the poker
        if full and v == 2 and 6 <= u <= 9:
            return GOLD
        if v == 3 and u in (5, 10):
            return GOLD
        return None
    return f


save(tile(fire_irons(True)), "fire_irons")
save(tile(fire_irons(False)), "fire_irons_gone")


def curtain(cord):
    def f(u, v):
        c = jit((150, 25, 40), u, v, 56, 6)
        if u % 4 == 0:
            c = mix(c, (90, 15, 25), 0.6)
        if v <= 1:
            c = GOLD
        if cord and v in (8, 9):
            c = jit(GOLD, u, v, 57, 15)
        if cord and u in (13, 14) and 9 <= v <= 13:
            c = GOLD_L
        return c
    return f


save(tile(curtain(True)), "curtain")
save(tile(curtain(False)), "curtain_gone")


def false_book(u, v):
    # a bookshelf with one red volume standing a little proud
    if v in (0, 7, 8, 15) or u in (0, 15):
        return jit((110, 70, 35), u, v, 58, 5)
    shade = [(120, 30, 30), (40, 60, 100), (40, 80, 40), (110, 80, 40), (70, 40, 80)]
    c = shade[int(h(u, v // 8, 59) * 5) % 5]
    c = jit(c, u, v, 60, 6)
    if v in (1, 9):
        c = (30, 22, 15)
    if u in (9, 10) and 1 <= v <= 6:
        c = (190, 30, 30) if v > 1 else GOLD
    return c


save(tile(false_book), "false_book")


def fortune_top(u, v):
    c = jit((90, 20, 70), u, v, 61, 5)
    if u in (0, 15) or v in (0, 15):
        c = GOLD
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 3:
        c = mix((210, 230, 255), (140, 150, 220), d / 3)
    for cx, cy in ((2, 3), (12, 3), (2, 11), (12, 11)):
        if cx <= u <= cx + 1 and cy <= v <= cy + 2:
            c = (245, 235, 200) if (u, v) != (cx, cy + 1) else GOLD
    return c


save(tile(fortune_top), "fortune_top")
save(tile(lambda u, v: jit((90, 20, 70), u, v, 62, 5) if v != 1 and not (v > 12 and u % 3 == 0) else GOLD), "fortune_side")


def accusation_top(u, v):
    c = desk_top(u, v)
    if 4 <= u <= 11 and 3 <= v <= 12:
        c = (245, 238, 220)
        if v in (5, 7, 9) and 5 <= u <= 10:
            c = (60, 50, 60)
        if v == 11 and 8 <= u <= 10:
            c = (150, 20, 30)   # a seal
    if u == 13 and 2 <= v <= 9:
        c = (240, 240, 240)     # a quill
    return c


save(tile(accusation_top), "accusation_top")


def music_stand(u, v):
    if u in (7, 8) and v >= 8:
        return (40, 40, 42)
    if v == 15 and 4 <= u <= 11:
        return (40, 40, 42)
    if 2 <= u <= 13 and 1 <= v <= 7:
        c = (245, 240, 225)
        if v in (2, 4, 6) and 3 <= u <= 12:
            c = (60, 60, 60)
        if (u + v) % 5 == 0 and v in (2, 3, 4, 5, 6):
            c = (20, 20, 20)
        return c
    return None


save(tile(music_stand), "music_stand")


def menu_card(u, v):
    if 3 <= u <= 12 and 1 <= v <= 14:
        c = (250, 246, 235)
        if u in (3, 12) or v in (1, 14):
            c = GOLD
        if v in (4, 6, 8, 10, 12) and 5 <= u <= 10:
            c = (90, 60, 80)
        if v == 2 and 6 <= u <= 9:
            c = (110, 40, 130)
        return c
    return None


save(tile(menu_card), "menu_card")


def goblet(spilt):
    def f(u, v):
        if spilt:
            if v in (12, 13) and 3 <= u <= 10:
                return (220, 225, 235) if v == 12 else (180, 185, 195)
            if v in (13, 14) and 9 <= u <= 14:
                return (120, 15, 35)
            return None
        if 5 <= u <= 10 and 5 <= v <= 9 and not (v == 9 and u in (5, 10)):
            return (130, 20, 40) if v > 6 else (230, 235, 245)
        if u in (7, 8) and 10 <= v <= 12:
            return (220, 225, 235)
        if v == 13 and 5 <= u <= 10:
            return (200, 205, 215)
        return None
    return f


save(tile(goblet(False)), "goblet")
save(tile(goblet(True)), "goblet_spilt")


def door(top):
    def f(u, v):
        c = jit(WHITE, u, v, 63, 4)
        if u in (0, 15) or (not top and v == 15) or (top and v == 0):
            return GOLD_D
        if u in (7, 8):
            return mix(c, (190, 185, 175), 0.5)
        if (u in (2, 5, 10, 13)) and (3 <= v <= 13):
            return GOLD
        if (v in (3, 13)) and (2 <= u <= 5 or 10 <= u <= 13):
            return GOLD
        if not top and v == 2 and u in (6, 9):
            return GOLD_L   # the handles
        return c
    return f


save(tile(door(False)), "door_low")
save(tile(door(True)), "door_high")


def keyhook(full):
    def f(u, v):
        if 3 <= u <= 12 and 2 <= v <= 6:
            return jit(OAK, u, v, 64, 6)
        if v == 6 and u in (5, 10):
            return (60, 60, 60)
        if full and u == 10 and 7 <= v <= 12:
            return (150, 150, 155)
        if full and 9 <= u <= 11 and 12 <= v <= 14:
            return (150, 150, 155)
        if full and u == 11 and v in (8, 10):
            return (150, 150, 155)
        return None
    return f


save(tile(keyhook(True)), "keyhook")
save(tile(keyhook(False)), "keyhook_empty")


def key_item(u, v):
    d = math.hypot(u - 4, v - 4)
    if 1.5 < d < 3.2:
        return (160, 160, 168)
    if u - v in (0, 1) and 6 <= u <= 13:
        return (140, 140, 148)
    if (u, v) in ((11, 13), (12, 12), (13, 11), (10, 12)):
        return (140, 140, 148)
    return None


save(tile(key_item), "key")


def casebook(u, v):
    if 2 <= u <= 13 and 1 <= v <= 14:
        c = (100, 30, 40)
        if u in (2, 3):
            c = (70, 20, 28)
        if v in (1, 14) or u == 13:
            c = (240, 232, 210)
        if 6 <= u <= 11 and v in (5, 6):
            c = GOLD
        if 7 <= u <= 10 and v == 9:
            c = GOLD
        return c
    return None


save(tile(casebook), "casebook")


def rug(u, v):
    c = carpet(u, v)
    return mix(c, (60, 20, 25), 0.25)


save(tile(rug), "rug")


def ivy(u, v):
    if h(u, v, 65) > 0.55 or (u + v * 3) % 7 == 0:
        return jit((50, 100, 40), u, v, 66, 20)
    return None


save(tile(ivy), "ivy")


def bed_cover(u, v):
    c = jit((150, 120, 170), u, v, 67, 4)
    if v in (0, 15) or u in (0, 15):
        c = GOLD
    return c


save(tile(bed_cover), "bed_cover")


def clock(u, v):
    if u in (2, 13) or v in (0, 15):
        return jit(MAHOG, u, v, 68, 5)
    if 3 <= u <= 12 and 1 <= v <= 14:
        d = math.hypot(u - 7.5, v - 7.5)
        if d < 4.5:
            c = (245, 240, 225)
            if d > 3.7:
                c = GOLD
            if u == 7 and 4 <= v <= 7 or v == 7 and 7 <= u <= 10:
                c = (20, 20, 20)
            return c
        return jit(MAHOG_D, u, v, 69, 5)
    return None


save(tile(clock), "clock")


def clock_case(u, v):
    # the case under the face: a glass door, the pendulum behind it
    if u in (2, 13):
        return jit(MAHOG, u, v, 77, 5)
    if 3 <= u <= 12:
        if u in (3, 12) or v in (0, 15):
            return jit(MAHOG_D, u, v, 78, 5)
        if u in (7, 8) and v <= 9:
            return GOLD_D
        if 9 <= v <= 12 and 6 <= u <= 9 and abs(u - 7.5) + abs(v - 10.5) < 2.6:
            return GOLD
        return mix((60, 40, 30), (150, 140, 120), 0.15 + 0.1 * ((u + v) % 3 == 0))
    return None


save(tile(clock_case), "clock_case")

# --- the people -------------------------------------------------------------------

PEOPLE = {
    # id: coat, trousers or dress, hair, dress?
    "comte": ((105, 40, 145), (40, 25, 50), (85, 75, 72), False),
    "marquise": ((175, 20, 40), (150, 15, 32), (28, 22, 22), True),
    "general": ((225, 165, 30), (30, 35, 72), (225, 225, 225), False),
    "ivoire": ((238, 230, 208), (230, 222, 200), (150, 65, 30), True),
    "emeraude": ((20, 140, 80), (25, 25, 28), (25, 25, 30), False),
    "duc": ((45, 110, 210), (225, 225, 228), (150, 110, 60), False),
    "docteur": ((112, 112, 118), (60, 60, 64), (62, 52, 46), False),
    "or": ((222, 178, 40), (200, 150, 30), (175, 55, 30), True),
    "lenoir": ((28, 28, 32), (20, 20, 22), (195, 195, 200), False),
}

base = Image.open(os.path.join(ROOT, "mods/mtg/player_api/models/character.png")).convert("RGBA")


def recolour(px, target):
    r, g, b, a = px
    _, l, _ = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    tr, tg, tb = (x / 255 for x in target)
    th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
    # keep the shading: the source's lightness relative to its middle
    nl = max(0, min(1, tl * (0.55 + l * 1.4)))
    rr, gg, bb = colorsys.hls_to_rgb(th, nl, ts)
    return (int(rr * 255), int(gg * 255), int(bb * 255), a)


for pid, (coat, legs, hair, dress) in PEOPLE.items():
    img = base.copy()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = img.getpixel((x, y))
            if a == 0:
                continue
            if g > r + 20 and g > b + 10:           # the green shirt: the coat
                img.putpixel((x, y), recolour((r, g, b, a), coat))
            elif y >= 16 and x < 16 and b > r + 20:  # the blue trousers
                img.putpixel((x, y), recolour((r, g, b, a), legs))
            elif y < 16 and r < 80 and g < 50 and b < 30 and r > g > b:   # the brown hair
                img.putpixel((x, y), recolour((r, g, b, a), hair))
    if dress:
        # long hair down the back and sides of the head
        for (fx, fy) in ((0, 8), (16, 8), (24, 8)):
            for yy in range(fy, fy + 8):
                for xx in range(fx, fx + 8):
                    if yy >= fy + 2 and (fx != 24 or True) and (xx in (fx, fx + 7) or fx == 24):
                        img.putpixel((xx, yy), jit(hair + (255,), xx, yy, 70, 6))
    # a gold or white cravat on the coat's front
    for yy in range(20, 23):
        for xx in range(23, 25):
            img.putpixel((xx, yy), (245, 240, 230, 255) if pid != "lenoir" else (200, 30, 40, 255))
    img.save(os.path.join(TEX, "orthoverse_chateau_skin_" + pid + ".png"))


def portrait(pid):
    coat, legs, hair, dress = PEOPLE[pid]
    size = 32
    img = Image.new("RGBA", (size, size), CLEAR)
    bg = {"lenoir": (40, 40, 44)}.get(pid, (70, 55, 45))
    for v in range(size):
        for u in range(size):
            c = jit(mix(bg, (110, 90, 70), (u + v) / 80), u, v, 71, 4)
            if u < 2 or u > 29 or v < 2 or v > 29:
                c = jit(GOLD if (u + v) % 3 else GOLD_D, u, v, 72, 10)
            elif u < 3 or u > 28 or v < 3 or v > 28:
                c = GOLD_L
            img.putpixel((u, v), c)
    skin = (230, 196, 168)
    # shoulders and coat
    for v in range(20, 29):
        for u in range(5, 27):
            w = 8 + (v - 20) * 1.4
            if abs(u - 15.5) < w:
                c = jit(coat, u, v, 73, 8)
                if abs(u - 15.5) < 1.5:
                    c = (245, 240, 230) if pid != "lenoir" else (200, 30, 40)
                img.putpixel((u, v), c)
    # the head
    for v in range(7, 21):
        for u in range(10, 22):
            if ((u - 15.5) / 5.2) ** 2 + ((v - 13.5) / 6.5) ** 2 < 1:
                img.putpixel((u, v), jit(skin, u, v, 74, 4))
    # hair
    for v in range(5, 24 if dress else 12):
        for u in range(8, 24):
            inside = ((u - 15.5) / 6.4) ** 2 + ((v - 12.5) / 7.5) ** 2 < 1
            face = ((u - 15.5) / 4.6) ** 2 + ((v - 14.5) / 5.8) ** 2 < 1 and v >= 10
            if inside and not face and (v < 11 or dress):
                img.putpixel((u, v), jit(hair, u, v, 75, 8))
    # eyes and mouth
    for u in (13, 18):
        img.putpixel((u, 13), (40, 30, 30, 255))
    for u in range(14, 18):
        img.putpixel((u, 17), (150, 70, 70, 255))
    if pid in ("general", "comte"):
        for u in range(13, 19):
            img.putpixel((u, 16), jit(hair, u, 16, 76, 6))   # a moustache
    img.save(os.path.join(TEX, "orthoverse_chateau_portrait_" + pid + ".png"))


for pid in PEOPLE:
    portrait(pid)

# --- sounds -------------------------------------------------------------------------
RATE = 44100
rng = np.random.default_rng(31)


def write_ogg(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(SND, "orthoverse_chateau_" + name + ".ogg")], check=True)
    os.unlink(path)


def secs(s):
    return np.arange(int(RATE * s)) / RATE


def lowpass(x, n):
    return np.convolve(x, np.ones(n) / n, "same")


# the piano: seven notes of C major, from middle C
for i, f in enumerate([261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88]):
    t = secs(1.6)
    x = sum(np.sin(2 * np.pi * f * k * t * (1 + 0.0004 * k)) * (0.6 ** (k - 1)) * np.exp(-t * (1.6 + k * 0.7))
            for k in range(1, 7))
    x *= np.minimum(1, t / 0.004)
    write_ogg("note_%d" % (i + 1), x, 0.6)

# thunder: a crack, then a long low roll
t = secs(4.0)
crack = rng.standard_normal(len(t)) * np.exp(-t / 0.12)
roll = lowpass(rng.standard_normal(len(t)), 120) * 12 * np.exp(-((t - 0.8) ** 2) / 1.2) * (1 + 0.5 * np.sin(t * 7))
write_ogg("thunder", lowpass(crack, 8) * 0.6 + roll, 0.8)

# the cards turning at Madame Or's table
t = secs(0.25)
write_ogg("card", lowpass(rng.standard_normal(len(t)), 3) * np.exp(-t / 0.03), 0.5)

# a safe's bolt, a hidden catch
t = secs(0.5)
x = np.zeros(len(t))
for at in (0.0, 0.12, 0.3):
    i = int(at * RATE)
    n = int(0.04 * RATE)
    x[i:i + n] += rng.standard_normal(n) * np.exp(-np.arange(n) / (0.008 * RATE))
write_ogg("click", lowpass(x, 4), 0.7)

# something heavy turning (the wine rack, the shelf)
t = secs(1.4)
x = lowpass(rng.standard_normal(len(t)), 60) * 8 * (0.5 + 0.5 * np.sin(t * 25)) * np.minimum(1, (1.4 - t) * 4)
write_ogg("grind", x, 0.6)

# a gong for the accusation's answer
t = secs(3.0)
write_ogg("gong", sum(np.sin(2 * np.pi * f * t) * a for f, a in ((110, 1), (166, 0.6), (231, 0.4), (297, 0.25)))
          * np.exp(-t / 0.9), 0.7)
print("done")
