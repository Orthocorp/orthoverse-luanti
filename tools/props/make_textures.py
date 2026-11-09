#!/usr/bin/env python3
"""Paint the textures for The Mill at Withy Ford: the props
(mods/orthoverse_props) and two monsters (mods/orthoverse_monsters): the
kobold in a painted skull mask and the Ringmaster (a hexer in a fine coat).

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow
    /tmp/venv/bin/python tools/props/make_textures.py .

(run from the repository root, after tools/monsters/make_monster_skins.py)

By Keir Finlow-Bates; the textures are CC BY-SA 3.0, the code MIT."""
import colorsys, os, sys
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "monsters"))
from esp32_mobs import h, jit, HEAD  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
PROPS = os.path.join(ROOT, "mods/orthoverse_props/textures")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
os.makedirs(PROPS, exist_ok=True)
CLEAR = (0, 0, 0, 0)


def tile(fn, size=16):
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            img.putpixel((u, v), fn(u, v))
    return img


# A crack, drawn over stone brick: the loose brick that works a hidden catch
CRACK = {(4, 6), (5, 6), (6, 7), (7, 7), (8, 8), (9, 8), (9, 9), (10, 10), (11, 10), (7, 6), (6, 5)}
tile(lambda u, v: (30, 26, 22, 200) if (u, v) in CRACK else CLEAR).save(os.path.join(PROPS, "orthoverse_props_crack.png"))

WOOD = (128, 92, 52)
WOOD_D = (86, 60, 34)
IRON = (70, 72, 78)


def windlass(wound):
    def fn(u, v):
        d = ((u - 7.5) ** 2 + (v - 7.5) ** 2) ** 0.5
        # the crank handle: up when wound, down when not
        hy = range(2, 8) if wound else range(8, 14)
        if u in (7, 8) and v in hy:
            return (60, 62, 66, 255)
        if 5 <= u <= 10 and v == (2 if wound else 13):
            return (150, 110, 60, 255)
        if d <= 3:
            return jit(IRON, u, v, 3, 6)
        if 3 < d <= 4.2:
            return (180, 150, 60, 255) if (u + v) % 3 == 0 else jit(WOOD_D, u, v, 4, 6)
        return jit(WOOD, u, v, 5, 8) if v % 5 else jit(WOOD_D, u, v, 6, 5)
    return fn


tile(windlass(False)).save(os.path.join(PROPS, "orthoverse_props_windlass.png"))
tile(windlass(True)).save(os.path.join(PROPS, "orthoverse_props_windlass_wound.png"))


def sluice(u, v):
    if v in (2, 3, 12, 13):
        return jit(IRON, u, v, 7, 5) if u % 5 else (140, 140, 150, 255)
    return jit(WOOD_D if u % 4 == 0 else WOOD, u, v, 8, 8)


tile(sluice).save(os.path.join(PROPS, "orthoverse_props_sluice.png"))


def ledger(u, v):
    if u in (0, 15) or v in (0, 15):
        return (70, 30, 20, 255)
    if 2 <= u <= 13 and 2 <= v <= 13:
        if v % 2 == 0 and 3 <= u <= 12 and h(u, v, 9) > 0.3:
            return (60, 50, 40, 255)
        return (226, 214, 180, 255)
    return (120, 40, 30, 255)


tile(ledger).save(os.path.join(PROPS, "orthoverse_props_ledger.png"))

# --- monsters -------------------------------------------------------------
# The kobold in a painted skull mask: the kobold, its face a skull
kob = Image.open(os.path.join(MON, "orthoverse_monsters_kobold.png")).convert("RGBA")
x, y, w, hh = HEAD["front"]
skull = [
    "BWWWWWWB",
    "WWWWWWWW",
    "WKKWWKKW",
    "WKKWWKKW",
    "WWWKKWWW",
    "BWWWWWWB",
    "BWKWKWKB",
    "BBWWWWBB",
]
pal = {"W": (232, 226, 208, 255), "K": (20, 16, 14, 255), "B": None}
for v, row in enumerate(skull):
    for u, ch in enumerate(row):
        if pal[ch]:
            kob.putpixel((x + u, y + v), jit(pal[ch], u, v, 10, 4))
# the painted white streaks down its arms and body: bones on a sheet
for (bx, by) in [(20, 20), (21, 24), (22, 28), (44, 20), (45, 26), (4, 20), (5, 26)]:
    for d in range(3):
        kob.putpixel((bx + d % 2, by + d), (226, 220, 200, 255))
kob.save(os.path.join(MON, "orthoverse_monsters_masked.png"))

# The Ringmaster: the hexer's skin in a deep red coat with gold
hx = Image.open(os.path.join(MON, "orthoverse_monsters_hexer.png")).convert("RGBA")
out = Image.new("RGBA", hx.size, CLEAR)
for v in range(hx.size[1]):
    for u in range(hx.size[0]):
        r, g, b, a = hx.getpixel((u, v))
        if a == 0:
            continue
        hh_, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if v >= 16:   # the body, arms and legs: the coat
            hh_ = 0.98
            s = min(1, s * 1.4 + 0.25)
            if (u + v) % 7 == 0 and l > 0.25:
                rr, gg, bb = 210, 170, 60
                out.putpixel((u, v), (rr, gg, bb, a))
                continue
        r2, g2, b2 = colorsys.hls_to_rgb(hh_, l, s)
        out.putpixel((u, v), (int(r2 * 255), int(g2 * 255), int(b2 * 255), a))
out.save(os.path.join(MON, "orthoverse_monsters_ringmaster.png"))
print("ok")
