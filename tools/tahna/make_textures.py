#!/usr/bin/env python3
"""Paint the textures for the Tomb of Tahna (mods/orthoverse_tahna) and its
monsters (mods/orthoverse_monsters: the mummy, the tomb guardian, scarabs,
Tahna herself), and synthesise its sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/tahna/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds; the skins
are drawn over Minetest Game's player skin layout, mods/mtg/player_api)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image, ImageDraw

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
TEX = os.path.join(ROOT, "mods/orthoverse_tahna/textures")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
SND = os.path.join(ROOT, "mods/orthoverse_tahna/sounds")
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


def tile(fn, w=16, hgt=None):
    hgt = hgt or w
    img = Image.new("RGBA", (w, hgt), CLEAR)
    for v in range(hgt):
        for u in range(w):
            c = fn(u, v)
            if c is not None:
                img.putpixel((u, v), c if len(c) == 4 else tuple(c) + (255,))
    return img


def save(img, name, folder=TEX, prefix="orthoverse_tahna_"):
    img.save(os.path.join(folder, prefix + name + ".png"))


SAND = (214, 186, 128)
SANDSTONE = (196, 164, 106)
GOLD = (214, 172, 58)
GOLD_L = (246, 214, 112)
GOLD_D = (148, 108, 30)
LAPIS = (38, 70, 150)
LAPIS_L = (70, 110, 200)
RED = (170, 52, 40)
TURQ = (64, 170, 160)
BLACK = (30, 26, 22)
CLAY = (176, 112, 70)
STONE = (120, 116, 108)
STONE_D = (84, 80, 74)

# ----------------------------------------------------------------------------
# The tomb's blocks


def glyph_wall(u, v):
    """Sandstone carved with rows of signs"""
    base = jit(SANDSTONE, u, v, 1, 7)
    if v in (0, 15):
        return shade(base, 0.8)
    row = (v - 1) // 5
    vv = (v - 1) % 5
    col = u // 4
    uu = u % 4
    k = int(h(col, row, 3) * 6)
    shapes = [
        {(1, 1), (2, 1), (1, 2), (2, 2), (1, 3), (2, 3)},             # a block
        {(1, 0), (1, 1), (1, 2), (1, 3), (2, 3)},                     # a hook
        {(0, 2), (1, 1), (2, 1), (3, 2)},                             # an eye's brow
        {(1, 0), (2, 1), (1, 2), (2, 3)},                             # a snake
        {(0, 3), (1, 2), (2, 1), (3, 0)},                             # a staff
        {(1, 1), (2, 1), (1, 3), (2, 3), (0, 2), (3, 2)},             # a ring
    ]
    if vv < 4 and (uu, vv) in shapes[k]:
        return shade(base, 0.62)
    return base


save(tile(glyph_wall), "glyphs")
save(tile(lambda u, v: jit(SANDSTONE, u, v, 2, 6) if (u % 8 and v % 8) else shade(SANDSTONE, 0.78)), "sandstone_block")


def gold_tile(u, v):
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    return jit(GOLD if (u + v) % 7 else GOLD_L, u, v, 3, 8)


save(tile(gold_tile), "gold_tile")


def scorched(u, v):
    base = jit((70, 64, 58), u, v, 4, 10)
    if h(u, v, 5) > 0.7:
        return jit((30, 26, 24), u, v, 6, 6)
    return base


save(tile(scorched), "scorched")


# A floor flag with a hairline crack: what a trap's plate looks like
def flag(u, v, seed=7, cracked=False):
    base = jit((150, 144, 132), u, v, seed, 8)
    if u in (0, 15) or v in (0, 15):
        return shade(base, 0.75)
    if cracked and ((u == v and 3 <= u <= 12) or (u == v + 1 and 4 <= u <= 9)):
        return shade(base, 0.6)
    return base


save(tile(lambda u, v: flag(u, v)), "flag")
save(tile(lambda u, v: flag(u, v, 7, True)), "flag_cracked")


# A dart hole in a cobble-coloured wall
def dart_hole(u, v):
    base = jit((112, 110, 104), u, v, 8, 14)
    if (u - 7.5) ** 2 + (v - 7.5) ** 2 <= 4:
        return (20, 18, 16)
    if (u - 7.5) ** 2 + (v - 7.5) ** 2 <= 7:
        return (60, 58, 54)
    return base


save(tile(dart_hole), "dart_hole")


# A flame jet's nozzle: a bronze mouth in the wall
def nozzle(u, v):
    base = jit((112, 110, 104), u, v, 9, 14)
    d = (u - 7.5) ** 2 + (v - 7.5) ** 2
    if d <= 5:
        return (30, 20, 14)
    if d <= 14:
        return jit((150, 100, 50), u, v, 10, 10)
    if v >= 12 and h(u, v, 11) > 0.5:
        return (40, 36, 32)        # soot
    return base


save(tile(nozzle), "nozzle")


# The underside of the falling ceiling: dark stone, iron bands
def crusher(u, v):
    if v in (3, 12):
        return jit((60, 56, 52), u, v, 12, 6)
    return jit(STONE_D, u, v, 13, 10)


save(tile(crusher), "crusher")


# Spikes in a pit (plantlike: transparent round)
def spikes(u, v):
    for cx in (2, 7, 12):
        top = 3 + (cx % 3)
        if v >= top and abs(u - cx) <= (v - top) // 4:
            return jit((150, 150, 156), u, v, 14, 12) if v < 13 else (90, 60, 50, 255)
    return None


save(tile(spikes), "spikes")


# A dart in flight
def dart(u, v):
    if v in (7, 8) and 2 <= u <= 12:
        return (100, 70, 40)
    if 12 <= u <= 14 and abs(v - 7.5) <= (14 - u) + 0.5:
        return (170, 170, 176)
    if u <= 3 and v in (6, 9):
        return (200, 60, 50)
    return None


save(tile(dart), "dart")


# A flame (particle)
def flame(u, v):
    d = math.hypot(u - 7.5, (v - 9) * 0.8)
    if d > 7:
        return None
    if d < 3:
        return (255, 240, 170, 255)
    if d < 5:
        return (255, 170, 60, 230)
    return (220, 70, 30, 180)


save(tile(flame), "flame")


# Dust (particle) and the whirlwind (a sprite)
def dust(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 7:
        return None
    a = int(200 * (1 - d / 7))
    return (200, 176, 130, a)


save(tile(dust), "dust")


def whirlwind(u, v):
    # a funnel, wider at the top, banded
    w = 2 + (31 - v) * 0.36
    if abs(u - 15.5) > w:
        return None
    band = int((u - 15.5 + v * 0.6) / 3) % 2
    c = (196, 168, 116) if band else (160, 132, 88)
    edge = abs(u - 15.5) > w - 1.5
    return c + ((150 if edge else 220),)


save(tile(whirlwind, 32, 32), "whirlwind")


# The canopic jars: clay, with a painted band, each lid a different head
def jar_side(lid):
    head = {"jackal": (40, 36, 34), "falcon": (120, 86, 50), "woman": (190, 150, 100)}[lid]

    def fn(u, v):
        if v <= 4:
            # the lid's head
            if lid == "jackal" and v <= 1 and u in (4, 5, 10, 11):
                return head          # ears
            if v >= 1 and 4 <= u <= 11:
                if v == 3 and u in (6, 9):
                    return (240, 220, 160)    # eyes
                if lid == "falcon" and v == 4 and u in (7, 8):
                    return (230, 190, 60)     # beak
                return jit(head, u, v, 15, 8)
            return None
        if v == 5:
            return GOLD if 3 <= u <= 12 else None
        w = 6 if v < 14 else 5
        if abs(u - 7.5) > w:
            return None
        if v in (8, 9):
            return LAPIS if u % 3 else GOLD
        if v == 11 and u % 4 == 1:
            return BLACK
        return jit(CLAY, u, v, 16, 10)
    return fn


for lid in ("jackal", "falcon", "woman"):
    save(tile(jar_side(lid)), "jar_" + lid)


def jar_top(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 4.5:
        return None
    return jit((90, 70, 50), u, v, 17, 8)


save(tile(jar_top), "jar_top")


def shards(u, v):
    if h(u, v, 18) > 0.8:
        return jit(CLAY, u, v, 19, 14)
    if h(u, v, 20) > 0.95:
        return LAPIS
    return None


save(tile(shards), "shards")


# The pedestal a jar stands on
def pedestal(u, v):
    if v <= 1 or v >= 14:
        return jit(GOLD_D, u, v, 21, 8)
    return jit((210, 200, 180), u, v, 22, 6)


save(tile(pedestal), "pedestal")


# The sarcophagus: lapis and gold bands; its lid a painted queen
def sarc_side(u, v):
    if v in (0, 15) or u in (0, 15):
        return GOLD_D
    if v % 4 == 2:
        return GOLD
    return jit(LAPIS if (u // 2 + v // 4) % 2 else LAPIS_L, u, v, 23, 6)


save(tile(sarc_side), "sarc_side")


def sarc_lid(u, v):
    # the lid seen from above, the queen's head at the top of the texture
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    if v <= 5 and 4 <= u <= 11:
        if v <= 1:
            return GOLD
        if v == 3 and u in (6, 9):
            return BLACK
        return jit((200, 160, 100), u, v, 24, 6) if 5 <= u <= 10 else (GOLD if u % 2 else LAPIS)
    if 6 <= v <= 8:
        return GOLD if u % 2 else TURQ          # the collar
    if v >= 9 and 5 <= u <= 10:
        return jit(GOLD, u, v, 25, 10) if (u == 7 or u == 8) else jit(LAPIS, u, v, 26, 6)
    return jit(LAPIS_L, u, v, 27, 6)


save(tile(sarc_lid), "sarc_lid")


def sarc_open(u, v):
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    if u in (1, 14) or v in (1, 14):
        return LAPIS
    return jit((40, 32, 26), u, v, 28, 6)


save(tile(sarc_open), "sarc_open")


# The Sceptre of Tahna: gold, lapis bands, a turquoise eye at the head
def sceptre(u, v):
    # a diagonal staff from bottom left to top right, a head at the top
    d = u - (15 - v)
    if v <= 5 and u >= 10:
        r = math.hypot(u - 12.5, v - 2.5)
        if r <= 1.2:
            return TURQ
        if r <= 2.8:
            return GOLD_L if (u + v) % 2 else GOLD
    if abs(d) <= 0 or abs(d) <= 1 and v > 4:
        if (v % 4) == 0:
            return LAPIS
        return GOLD if d == 0 else GOLD_D
    return None


save(tile(sceptre), "sceptre")


# The false door: grand, gilded, painted with a closed eye
def false_door(u, v):
    if u in (0, 15) or v in (0, 15):
        return GOLD_D
    if u in (1, 14):
        return GOLD
    if 5 <= v <= 9 and 3 <= u <= 12:
        if v == 7 and 5 <= u <= 10:
            return BLACK
        return jit((230, 220, 196), u, v, 29, 4)
    return jit((120, 70, 40), u, v, 30, 8)


save(tile(false_door), "false_door")


# A sandstone slab door (the pyramid's): plain, heavy
def slab(u, v):
    if v in (0, 15) or u in (0, 15):
        return shade(SANDSTONE, 0.7)
    return jit(shade(SANDSTONE, 0.9), u, v, 31, 6)


save(tile(slab), "slab")


# A lever: a bronze handle (inventory) and its plate
def lever(u, v):
    if 6 <= u <= 9 and 2 <= v <= 11:
        return (150, 100, 50)
    if 4 <= u <= 11 and 11 <= v <= 14:
        return (90, 86, 80)
    if 5 <= u <= 10 and v <= 2:
        return GOLD
    return None


save(tile(lever), "lever")
save(tile(lambda u, v: jit((150, 100, 50), u, v, 32, 8)), "bronze")


# The arch's lintel: an open eye carved in it
def arch_eye(u, v):
    base = jit(SANDSTONE, u, v, 33, 6)
    d = (u - 7.5) ** 2 / 36 + (v - 7.5) ** 2 / 9
    if d <= 0.28:
        return BLACK
    if d <= 1.0:
        return (236, 228, 210)
    if abs(d - 1.15) < 0.18:
        return shade(SANDSTONE, 0.55)
    return base


save(tile(arch_eye), "arch_eye")


# Paintings: each 32 x 32 (two blocks by two), cut into four 16 x 16 tiles
def fresco(name, draw_fn):
    img = Image.new("RGBA", (32, 32), (222, 200, 150, 255))
    px = img.load()
    for v in range(32):
        for u in range(32):
            px[u, v] = jit((222, 200, 150), u, v, 40, 8)
    d = ImageDraw.Draw(img)
    draw_fn(d)
    d.rectangle([0, 0, 31, 31], outline=(120, 80, 40))
    d.rectangle([1, 1, 30, 30], outline=GOLD_D)
    for i, (x, y) in enumerate(((0, 16), (16, 16), (0, 0), (16, 0))):
        # 1: bottom left, 2: bottom right, 3: top left, 4: top right
        img.crop((x, y, x + 16, y + 16)).save(os.path.join(TEX, "orthoverse_tahna_fresco_%s_%d.png" % (name, i + 1)))


def figure(d, x, y, col=(40, 30, 20)):
    # a walking figure in profile, 8 high: head, body, legs
    d.rectangle([x + 1, y, x + 2, y + 1], fill=col)
    d.rectangle([x + 1, y + 2, x + 2, y + 5], fill=col)
    d.line([x + 1, y + 6, x, y + 8], fill=col)
    d.line([x + 2, y + 6, x + 3, y + 8], fill=col)
    d.line([x + 2, y + 3, x + 4, y + 4], fill=col)


def sphinx_door(d):
    # a sphinx lying, head right, a dark doorway between its paws
    d.rectangle([3, 18, 28, 20], fill=(200, 160, 90))          # the sand
    d.rectangle([4, 13, 18, 17], fill=(184, 140, 80))         # the body
    d.rectangle([17, 6, 23, 13], fill=(184, 140, 80))         # the head
    d.rectangle([16, 6, 18, 12], fill=LAPIS)                  # the headdress
    d.rectangle([19, 6, 23, 7], fill=LAPIS)
    d.rectangle([18, 15, 28, 17], fill=(184, 140, 80))        # the paws
    d.rectangle([22, 13, 24, 15], fill=(20, 16, 12))          # the door
    figure(d, 26, 20)
    d.line([27, 19, 24, 15], fill=RED)                        # an arrow to it
    d.rectangle([5, 24, 26, 25], fill=GOLD_D)


def falling_ceiling(d):
    d.rectangle([3, 4, 28, 9], fill=(90, 86, 80))             # the ceiling, coming down
    for x in (7, 15, 23):
        d.line([x, 10, x, 13], fill=RED)                      # arrows down
        d.line([x - 1, 12, x, 13], fill=RED)
        d.line([x + 1, 12, x, 13], fill=RED)
    figure(d, 6, 17)
    d.rectangle([14, 22, 20, 23], fill=(60, 50, 40))          # one crushed flat
    figure(d, 24, 17)
    d.line([27, 21, 30, 21], fill=GOLD_D)                     # running out
    d.rectangle([3, 26, 28, 27], fill=(120, 110, 100))


def gold_path(d):
    for i in range(6):
        x = 4 + i * 4
        c = GOLD if i % 2 == 0 else (110, 100, 90)
        d.rectangle([x, 24, x + 3, 26], fill=c)
    for x in (9, 17, 25):
        d.polygon([(x, 23), (x - 2, 15), (x, 17), (x + 1, 12), (x + 2, 17), (x + 3, 15), (x + 2, 23)], fill=(230, 110, 40))
    figure(d, 5, 15, (40, 30, 20))
    d.rectangle([4, 4, 27, 6], fill=GOLD_D)


def three_jars(d):
    # the queen seated, three jars before her
    d.rectangle([4, 10, 9, 22], fill=LAPIS)                   # the throne
    d.rectangle([7, 6, 10, 9], fill=(200, 160, 100))          # her face
    d.rectangle([6, 4, 11, 6], fill=GOLD)                     # her crown
    d.rectangle([8, 10, 11, 21], fill=(240, 236, 220))        # her robe
    d.line([12, 8, 15, 4], fill=GOLD, width=1)                # the sceptre
    for i, x in enumerate((15, 20, 25)):
        d.rectangle([x, 16, x + 3, 21], fill=CLAY)
        d.rectangle([x, 14, x + 3, 15], fill=[(40, 36, 34), (120, 86, 50), (190, 150, 100)][i])
        d.line([x - 1, 23, x + 4, 23], fill=GOLD_D)
    d.rectangle([3, 26, 28, 27], fill=RED)


def spears(d):
    # a door, a figure before it, spears up through the floor
    d.rectangle([11, 4, 21, 22], fill=(120, 70, 40))
    d.rectangle([13, 9, 19, 12], fill=(230, 220, 196))
    for x in (6, 9, 23, 26, 15):
        d.line([x, 25, x, 16], fill=(170, 170, 176))
        d.point([x, 15], fill=(220, 220, 230))
    figure(d, 14, 17, (60, 30, 20))
    d.rectangle([3, 25, 28, 27], fill=(110, 100, 90))


fresco("sphinx", sphinx_door)
fresco("ceiling", falling_ceiling)
fresco("gold", gold_path)
fresco("jars", three_jars)
fresco("spears", spears)

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


LINEN = (210, 198, 168)


def wrapped(X, Y, u, v, seed, base=LINEN):
    """Bandages: bands that wind round, a darker seam between, stains"""
    if (v + (u // 3)) % 3 == 0:
        return jit(shade(base, 0.72), X, Y, seed, 6)
    if h(X, Y, seed + 1) > 0.9:
        return jit((140, 120, 80), X, Y, seed + 2, 8)
    return jit(base, X, Y, seed + 3, 10)


def mummy(part, side, X, Y, u, v, w, hh):
    return wrapped(X, Y, u, v, 50)


MUMMY_FACE = ["........",
              "........",
              "........",
              ".kk..kk.",
              ".ke..ek.",
              "........",
              "...kk...",
              "........"]
save(skin(mummy, MUMMY_FACE, {"k": (40, 30, 20), "e": (190, 220, 120)}, 51), "mummy", MON, "orthoverse_monsters_")


# Tahna: wrapped in fine linen, a gold and blue striped headdress, a gold
# collar and girdle, green eyes that glow
def tahna(part, side, X, Y, u, v, w, hh):
    if part == "head":
        if side in ("top", "back", "left", "right") or (side == "front" and v <= 1):
            return GOLD if (v + u) % 3 else LAPIS
        return wrapped(X, Y, u, v, 60, (226, 214, 184))
    if part == "body":
        if v <= 2 and side in ("front", "back", "left", "right"):
            return GOLD if u % 2 else TURQ
        if side == "front" and v == 8:
            return GOLD
        if side == "front" and v >= 9 and 3 <= u <= 4:
            return GOLD_D
        return wrapped(X, Y, u, v, 61, (226, 214, 184))
    if part == "arm" and v >= 9 and side != "top":
        return GOLD if v == 9 else wrapped(X, Y, u, v, 62, (226, 214, 184))
    return wrapped(X, Y, u, v, 63, (226, 214, 184))


TAHNA_FACE = ["gggggggg",
              "gbbbbbbg",
              "g......g",
              "gkk..kkg",
              ".ke..ek.",
              "........",
              "...rr...",
              "........"]
save(skin(tahna, TAHNA_FACE, {"g": GOLD, "b": LAPIS, "k": BLACK, "e": (120, 255, 160), "r": (130, 40, 40)}, 64),
     "tahna", MON, "orthoverse_monsters_")


# The tomb guardian: a statue come to life, black basalt with gold bands, a
# jackal's long dark face (painted), red eyes
BASALT = (48, 46, 50)


def guardian(part, side, X, Y, u, v, w, hh):
    if part == "head" and side == "top":
        return GOLD if u in (1, 6) else jit(BASALT, X, Y, 70, 8)
    if part == "body" and v in (0, 1):
        return GOLD
    if part == "body" and side == "front" and v >= 7:
        return GOLD if u % 2 == 0 else jit(BASALT, X, Y, 71, 8)
    if part in ("arm", "leg") and v in (0, 11):
        return GOLD_D
    return jit(BASALT, X, Y, 72, 10)


GUARD_FACE = ["kk....kk",
              "kk....kk",
              "........",
              ".rr..rr.",
              "........",
              "..kkkk..",
              "..kkkk..",
              "...gg..."]
save(skin(guardian, GUARD_FACE, {"k": (20, 18, 20), "r": (230, 40, 30), "g": GOLD}, 73), "guardian", MON,
     "orthoverse_monsters_")


# The scarab (a cube): a shining dark green shell
def scarab_top(u, v):
    if u in (7, 8):
        return (20, 30, 20)
    d = math.hypot(u - 7.5, v - 7.5)
    if d > 7.5:
        return (30, 40, 30)
    return jit((40, 90, 60) if h(u, v, 80) > 0.25 else (90, 170, 120), u, v, 81, 10)


def scarab_side(u, v):
    if v >= 12:
        return (20, 20, 16) if u % 3 == 0 else None
    return jit((30, 70, 46), u, v, 82, 10)


def scarab_front(u, v):
    if v >= 12:
        return (20, 20, 16) if u % 3 == 0 else None
    if v in (5, 6) and u in (4, 11):
        return (200, 40, 30)
    if v >= 8 and u in (6, 9):
        return (20, 20, 16)
    return jit((30, 70, 46), u, v, 83, 10)


save(tile(scarab_top), "scarab_top", MON, "orthoverse_monsters_")
save(tile(scarab_side), "scarab_side", MON, "orthoverse_monsters_")
save(tile(scarab_front), "scarab_front", MON, "orthoverse_monsters_")

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
                        os.path.join(folder, name + ".ogg")], check=True)


def env(n, a, r):
    e = np.ones(n)
    a, r = max(1, int(a * RATE)), max(1, int(r * RATE))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


rng = np.random.default_rng(11)


def noise(n, smooth=1):
    x = rng.normal(0, 1, n)
    if smooth > 1:
        x = np.convolve(x, np.ones(smooth) / smooth, mode="same")
        x /= max(1e-6, np.abs(x).max())
    return x


def secs(s):
    return int(s * RATE)


# a jar breaking: a crack and falling bits
n = secs(0.7)
t = np.arange(n) / RATE
crack = noise(n) * np.exp(-t * 30)
bits = sum((noise(n) * np.exp(-np.clip(t - k, 0, None) * 50) * (t > k)) for k in (0.12, 0.2, 0.31, 0.45)) * 0.4
write(SND, "orthoverse_tahna_jar", (crack + bits) * 0.8)

# stone grinding (the ceiling, the slab)
n = secs(1.6)
t = np.arange(n) / RATE
grind = noise(n, 60) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t)) + 0.3 * np.sin(2 * np.pi * 55 * t)
write(SND, "orthoverse_tahna_grind", grind * env(n, 0.1, 0.3) * 0.8)

# darts: a click and a hiss
n = secs(0.35)
t = np.arange(n) / RATE
write(SND, "orthoverse_tahna_darts", (noise(n) * np.exp(-t * 18) * 0.6 + np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 80) * 0.4))

# flames: a roar
n = secs(1.2)
t = np.arange(n) / RATE
write(SND, "orthoverse_tahna_flame", noise(n, 12) * env(n, 0.05, 0.5) * 0.9)

# spears: metal scraping up
n = secs(0.5)
t = np.arange(n) / RATE
sweep = np.sin(2 * np.pi * (600 + 2400 * t) * t)
write(SND, "orthoverse_tahna_spears", (sweep * 0.4 + noise(n) * 0.3) * env(n, 0.01, 0.2))

# the archway: a hollow whoosh
n = secs(0.9)
t = np.arange(n) / RATE
write(SND, "orthoverse_tahna_whoosh", noise(n, 30) * np.sin(np.pi * t / 0.9) * 0.9)

# the sarcophagus opening: a long low scrape
n = secs(2.2)
t = np.arange(n) / RATE
write(SND, "orthoverse_tahna_sarcophagus", (noise(n, 90) * 0.8 + 0.3 * np.sin(2 * np.pi * 40 * t)) * env(n, 0.3, 0.6))

# Tahna's wail (a falling, wavering voice), her dust (a hiss), the whirlwind
n = secs(1.8)
t = np.arange(n) / RATE
f = 420 - 160 * t + 18 * np.sin(2 * np.pi * 6 * t)
ph = 2 * np.pi * np.cumsum(f) / RATE
voice = np.sin(ph) * 0.5 + np.sin(2 * ph) * 0.2 + noise(n, 8) * 0.15
write(MSND, "orthoverse_monsters_tahna_wail", voice * env(n, 0.2, 0.6))
n = secs(1.0)
write(MSND, "orthoverse_monsters_tahna_dust", noise(n, 4) * env(n, 0.05, 0.6) * 0.7)
n = secs(1.4)
t = np.arange(n) / RATE
write(MSND, "orthoverse_monsters_tahna_wind", noise(n, 25) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t)) * env(n, 0.2, 0.4))
# a mummy's groan, and the scarabs' clicking
n = secs(1.3)
t = np.arange(n) / RATE
f = 95 + 10 * np.sin(2 * np.pi * 2 * t)
ph = 2 * np.pi * np.cumsum(f) / RATE
write(MSND, "orthoverse_monsters_mummy_groan", (np.sin(ph) * 0.6 + np.sin(3 * ph) * 0.2 + noise(n, 20) * 0.2) * env(n, 0.2, 0.5))
n = secs(0.6)
t = np.arange(n) / RATE
clicks = sum(np.exp(-np.clip(t - k, 0, None) * 300) * (t > k) * noise(n) for k in np.arange(0, 0.55, 0.045))
write(MSND, "orthoverse_monsters_scarab_click", clicks * 0.5)
print("done")
