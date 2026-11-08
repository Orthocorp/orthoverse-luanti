#!/usr/bin/env python3
"""Draw the adventure weapons (16 x 16) in each material, for
mods/orthoverse_combat/textures:

    orthoverse_combat_<kind>_<material>.png   the picture (inventory and hand)

and a preview sheet. Needs Pillow (in a venv):

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow
    /tmp/venv/bin/python tools/weapons/make_weapon_textures.py mods/orthoverse_combat/textures

By Keir Finlow-Bates; the pictures are CC BY-SA 3.0, the code MIT."""
import os, sys
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)

MATERIALS = {   # dark, mid, light
    "steel": ((118, 123, 138), (196, 201, 212), (236, 240, 250)),
    "bronze": ((112, 66, 28), (176, 112, 52), (226, 166, 96)),
    "mese": ((150, 126, 16), (222, 198, 40), (255, 242, 128)),
    "diamond": ((34, 140, 160), (104, 214, 232), (204, 250, 255)),
}
WOOD, WOOD_D = (120, 80, 40), (80, 50, 25)
GOLD = (220, 180, 60)
OUT_C = (30, 28, 30)


def new():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))


def put(p, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        p[x, y] = c + (255,) if len(c) == 3 else c


def diag(p, i0, i1, c, side=None):
    """Along the diagonal from bottom left (i = 0) to top right (i = 15)."""
    for i in range(i0, i1 + 1):
        put(p, i, 15 - i, c)
        if side:
            put(p, i + 1, 15 - i, side)


def outline(im):
    p = im.load()
    o = im.copy()
    q = o.load()
    for y in range(16):
        for x in range(16):
            if p[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    X, Y = x + dx, y + dy
                    if 0 <= X < 16 and 0 <= Y < 16 and p[X, Y][3] and p[X, Y][:3] != OUT_C:
                        q[x, y] = OUT_C + (255,)
                        break
    return o


def sword(m, blade, guard, grip, wide=False):
    d, mid, l = m
    im = new()
    p = im.load()
    for i in range(blade[0], blade[1] + 1):
        put(p, i, 15 - i, mid)
        put(p, i + 1, 15 - i, l)
        if wide:
            put(p, i, 16 - i, d)
    for k in range(-3 if wide else -2, 4 if wide else 3):
        put(p, guard + k, 15 - guard + k, GOLD)
    for i in range(max(0, guard - grip), guard):
        put(p, i, 15 - i, WOOD)
    put(p, max(0, guard - grip - 1), 15 - max(0, guard - grip - 1), GOLD)
    return outline(im)


def dagger(m): return sword(m, (6, 12), 5, 2)
def short_sword(m): return sword(m, (5, 14), 4, 3)
def broadsword(m): return sword(m, (5, 14), 4, 3, wide=True)


def spear(m):
    d, mid, l = m
    im = new()
    p = im.load()
    diag(p, 0, 11, WOOD)
    diag(p, 12, 15, mid)
    put(p, 12, 4, d); put(p, 11, 3, d); put(p, 13, 2, l)
    return outline(im)


def war_hammer(m):
    d, mid, l = m
    im = new()
    p = im.load()
    diag(p, 0, 11, WOOD)
    for k in range(-3, 4):          # the head, across the shaft
        put(p, 11 - k, 4 - k, mid)
        put(p, 12 - k, 4 - k, d)
        put(p, 11 + k, 4 + k, d) if k in (-1, 0, 1) else None
    put(p, 8, 1, l); put(p, 9, 2, l)
    return outline(im)


def _ball(p, m, cx, cy, r):
    d, mid, l = m
    for y in range(16):
        for x in range(16):
            dd = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if dd <= r:
                shade = (x - cx) - (y - cy)       # lit from the top left
                put(p, x, y, l if shade < -1.2 else d if shade > 1.4 else mid)


def mace(m):
    im = new()
    p = im.load()
    diag(p, 0, 9, WOOD, WOOD_D)
    _ball(p, m, 11.5, 3.5, 2.6)
    return outline(im)


def morning_star(m):
    d, mid, l = m
    im = new()
    p = im.load()
    diag(p, 0, 9, WOOD, WOOD_D)
    _ball(p, m, 11.5, 3.5, 2.2)
    for x, y in ((11, 0), (15, 3), (12, 7), (8, 4), (14, 0), (14, 6), (9, 1), (9, 6)):   # spikes
        put(p, x, y, l if y < 4 else d)
    return outline(im)


KINDS = {
    "dagger": dagger, "short_sword": short_sword, "broadsword": broadsword,
    "spear": spear, "war_hammer": war_hammer, "mace": mace, "morning_star": morning_star,
}


if __name__ == "__main__":
    sheet = Image.new("RGBA", (len(MATERIALS) * 72 + 16, len(KINDS) * 72 + 16), (52, 52, 62, 255))
    for row, (kind, draw) in enumerate(KINDS.items()):
        for col, (mat, pal) in enumerate(MATERIALS.items()):
            im = draw(pal)
            im.save(f"{OUT}/orthoverse_combat_{kind}_{mat}.png")
            sheet.alpha_composite(im.resize((64, 64), Image.NEAREST), (8 + col * 72, 8 + row * 72))
    sheet.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview.png"))
    print("ok")
