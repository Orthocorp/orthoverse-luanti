#!/usr/bin/env python3
"""Paint the adventure monsters' skins for Luanti's character.b3d (64 x 32,
the classic layout), plus a preview sheet.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow
    /tmp/venv/bin/python tools/monsters/make_monster_skins.py mods/orthoverse_monsters/textures

Goblin, kobold, orc and skeleton are new; the mossling, hexer and wisp come
from esp32-s3-minetest (esp32_mobs.py). By Keir Finlow-Bates; the textures
are CC BY-SA 3.0, the code MIT."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
from esp32_mobs import (h, jit, paint, ascii_face, HEAD, BODY, ARM, LEG,
                        mossling, hexer, wisp, orb, spark, render_iso, flat, checker, label)

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
CLEAR = (0, 0, 0, 0)


def noisy(pal, light, mid, dark, s, lo=0.25, hi=0.8, amt=6):
    def fn(u, v):
        k = h(u, v, s)
        base = pal[dark] if k < lo else pal[light] if k > hi else pal[mid]
        return jit(base, u, v, s + 1, amt)
    return fn


def fill_faces(img, regions, faces, fn):
    for face in faces:
        paint(img, regions[face], lambda u, v, w, hh, face=face: fn(face, u, v, w, hh))

# =============================== GOBLIN ========================================
# Small (as the mossling), olive-green, big ears, a wide toothy grin, yellow
# eyes with red pupils; ragged leather jerkin, a red rag sash, bare feet.
GP = {
    'G': (104, 128, 56), 'g': (72, 92, 38), 'n': (58, 74, 30), 'L': (136, 160, 74),
    'Y': (244, 214, 64), 'r': (176, 30, 24), 'k': (34, 30, 22), 'K': (22, 12, 10),
    'T': (234, 226, 190), 'J': (96, 64, 38), 'j': (66, 42, 24), 'H': (124, 86, 52),
    'R': (150, 40, 32), 'S': (104, 26, 22), 'B': (48, 36, 24), 'b': (176, 140, 60),
}


def goblin():
    img = Image.new("RGBA", (64, 32), CLEAR)
    skin = noisy(GP, 'L', 'G', 'g', 201)
    ascii_face(img, HEAD['front'], [
        "gkGgGkGg",
        "gGGGGGGg",
        "GkkGGkkG",
        "GYrGGrYG",
        "GGGnnGGG",
        "gKTKKTKg",
        "gGKKKKGg",
        "ggGGGGgg",
    ], GP, 202)
    paint(img, HEAD['top'], lambda u, v, w, hh: jit(GP['k'], u, v, 203, 4) if h(u, v, 204) > 0.82 else skin(u, v))
    paint(img, HEAD['bottom'], lambda u, v, w, hh: jit(GP['g'], u, v, 205, 4))
    paint(img, HEAD['back'], lambda u, v, w, hh: skin(u + 40, v))
    for name, sd in (('left', 206), ('right', 207)):
        def side(u, v, w, hh, sd=sd):
            # a big pointed ear, pale inside
            if (v, u) in ((2, 3), (2, 4), (3, 2), (3, 3), (3, 4), (3, 5), (4, 3), (4, 4), (1, 4)):
                return jit(GP['L'] if (v, u) in ((3, 3), (3, 4)) else GP['G'], u, v, sd, 4)
            if (v, u) in ((3, 6), (2, 5), (4, 5)):
                return jit(GP['n'], u, v, sd, 3)
            return skin(u + sd, v)
        paint(img, HEAD[name], side)

    def leather(u, v, s):
        k = h(u, v, s)
        base = GP['j'] if k < 0.25 else GP['H'] if k > 0.82 else GP['J']
        return jit(base, u, v, s + 1, 6)
    ascii_face(img, BODY['front'], [
        "GgJJJJgG",
        "gJJjjJJg",
        "JJJjjJJJ",
        "JHJjjJHJ",
        "JJJjjJJJ",
        "RRSRRSRR",
        "JJJbBJJJ",
        "JjJJJJjJ",
        "JJjJJjJJ",
        "jJJJJJJj",
        "JjJJjJJj",
        "j.JjJ.Jj".replace('.', 'J'),
    ], GP, 210)
    for name, sd in (('back', 211), ('left', 212), ('right', 213)):
        paint(img, BODY[name], lambda u, v, w, hh, sd=sd: jit(GP['R'], u, v, sd, 4) if v == 5 else leather(u, v, sd))
    paint(img, BODY['top'], lambda u, v, w, hh: skin(u + 60, v))
    paint(img, BODY['bottom'], lambda u, v, w, hh: leather(u, v, 214))

    def arm(face, u, v, w, hh):
        if v < 3: return leather(u, v, 220 + len(face))          # jerkin sleeve stub
        if v >= 11 and face in ('front', 'left', 'right') and u % 2 == 0: return jit(GP['k'], u, v, 221, 3)  # claws
        return skin(u + 70, v)
    fill_faces(img, ARM, ('front', 'back', 'left', 'right'), arm)
    paint(img, ARM['top'], lambda u, v, w, hh: leather(u, v, 222))
    paint(img, ARM['bottom'], lambda u, v, w, hh: skin(u + 80, v))

    def leg(face, u, v, w, hh):
        if v < 6: return leather(u, v, 230 + len(face))           # ragged breeches
        if v == 6: return leather(u, v, 231) if h(u, v, 232) > 0.4 else skin(u, v)
        if v == 11 and face == 'front': return jit(GP['k'] if u % 2 else GP['g'], u, v, 233, 3)
        return skin(u + 90, v)
    fill_faces(img, LEG, ('front', 'back', 'left', 'right'), leg)
    paint(img, LEG['top'], lambda u, v, w, hh: leather(u, v, 234))
    paint(img, LEG['bottom'], lambda u, v, w, hh: jit(GP['g'], u, v, 235, 4))
    return img

# =============================== KOBOLD ========================================
# Small, rust-red scales, a cream belly, little bone horns, yellow slit eyes,
# a snout with nostrils; a leather harness with a brass buckle.
KP = {
    'R': (156, 66, 40), 'r': (110, 42, 28), 'q': (78, 30, 20), 'L': (190, 96, 58),
    'B': (214, 184, 124), 'b': (176, 148, 96), 'H': (226, 214, 180), 'h': (170, 158, 128),
    'Y': (246, 196, 52), 'k': (24, 16, 12), 'K': (40, 18, 14), 'T': (238, 232, 206),
    'J': (82, 56, 34), 'j': (56, 38, 24), 'y': (200, 160, 70),
}


def kobold():
    img = Image.new("RGBA", (64, 32), CLEAR)

    def scales(u, v, s):
        # offset rows of scales: a darker rim at the bottom of each
        row = v // 2
        off = (u + row) % 3
        base = KP['r'] if v % 2 == 1 and off == 0 else KP['L'] if off == 2 and v % 2 == 0 else KP['R']
        return jit(base, u, v, s, 5)
    ascii_face(img, HEAD['front'], [
        "rHrRRrHr",
        "RRRRRRRR",
        "RrqRRqrR",
        "RkYRRYkR",
        "RRRrrRRR",
        "RrkRRkrR",
        "rTKKKKTr",
        "rrBBBBrr",
    ], KP, 301)
    paint(img, HEAD['top'], lambda u, v, w, hh: jit(KP['H'], u, v, 302, 4) if (u, v) in ((1, 6), (6, 6), (1, 5), (6, 5)) else scales(u, v, 303))
    paint(img, HEAD['bottom'], lambda u, v, w, hh: jit(KP['B'], u, v, 304, 4))
    paint(img, HEAD['back'], lambda u, v, w, hh: jit(KP['h'], u, v, 305, 3) if v < 2 and u in (1, 6) else scales(u, v, 306))
    for name, sd in (('left', 307), ('right', 308)):
        paint(img, HEAD[name], lambda u, v, w, hh, sd=sd: jit(KP['B'], u, v, sd, 3) if v >= 6 else
              (jit(KP['k'], u, v, sd, 2) if (u, v) == (5, 3) else scales(u, v, sd)))

    def belly(u, v, s):
        return jit(KP['B'] if (v % 3) else KP['b'], u, v, s, 4)
    def body(face, u, v, w, hh):
        strap = (u == v // 1 % w) if face == 'front' else False
        if face == 'front':
            if (u == v - 1 or u == v - 2) and v < 9: return jit(KP['J'] if u != v - 2 else KP['j'], u, v, 310, 3)  # harness
            if (u, v) in ((3, 4), (4, 4), (3, 5), (4, 5)): return jit(KP['y'], u, v, 311, 4)                       # buckle
            if 2 <= u <= 5: return belly(u, v, 312)
        if face == 'back' and (u == 7 - v or u == 8 - v) and v < 9: return jit(KP['J'], u, v, 313, 3)
        if v >= 10: return jit(KP['J'] if h(u, v, 314) > 0.3 else KP['j'], u, v, 315, 3)                       # loincloth
        return scales(u, v, 316 + len(face))
    fill_faces(img, BODY, ('front', 'back', 'left', 'right'), body)
    paint(img, BODY['top'], lambda u, v, w, hh: scales(u, v, 320))
    paint(img, BODY['bottom'], lambda u, v, w, hh: jit(KP['J'], u, v, 321, 3))

    def limb(face, u, v, w, hh, s, claws_at):
        if v >= claws_at and face in ('front', 'left', 'right') and u % 2 == 0: return jit(KP['T'], u, v, s, 3)
        if face == 'front' and u in (1, 2) and v < claws_at - 1: return belly(u, v, s)
        return scales(u, v, s)
    fill_faces(img, ARM, ('front', 'back', 'left', 'right'), lambda f, u, v, w, hh: limb(f, u, v, w, hh, 330, 11))
    paint(img, ARM['top'], lambda u, v, w, hh: scales(u, v, 331))
    paint(img, ARM['bottom'], lambda u, v, w, hh: jit(KP['q'], u, v, 332, 3))
    fill_faces(img, LEG, ('front', 'back', 'left', 'right'), lambda f, u, v, w, hh: limb(f, u, v, w, hh, 340, 11))
    paint(img, LEG['top'], lambda u, v, w, hh: scales(u, v, 341))
    paint(img, LEG['bottom'], lambda u, v, w, hh: jit(KP['q'], u, v, 342, 3))
    return img

# ================================= ORC =========================================
# Big (a little over player size), grey-green, heavy brow, small red eyes,
# tusks, a black topknot, red war paint; iron pauldrons, a fur collar,
# leather armour with straps and rivets, iron-shod boots.
OP = {
    'O': (110, 128, 92), 'o': (76, 90, 62), 'p': (56, 66, 46), 'n': (60, 72, 50), 'L': (138, 154, 114),
    'k': (26, 24, 24), 'K': (14, 10, 10), 'E': (220, 44, 30), 'e': (120, 20, 16),
    'T': (236, 228, 196), 't': (190, 180, 150), 'P': (168, 34, 26),
    'A': (138, 142, 150), 'a': (90, 92, 100), 'Q': (178, 182, 190), 'F': (98, 78, 58), 'f': (132, 108, 80),
    'J': (92, 62, 38), 'j': (62, 40, 24), 'y': (196, 170, 96),
}


def orc():
    img = Image.new("RGBA", (64, 32), CLEAR)
    skin = noisy(OP, 'L', 'O', 'o', 401)
    ascii_face(img, HEAD['front'], [
        "kkKkkKkk",
        "OOkkkkOO",
        "okkOOkko",
        "OeEOOEeO",
        "PPOonOPP",
        "OOOooOOO",
        "OTKKKKTO",
        "oTOOOOTo",
    ], OP, 402)
    def top(u, v, w, hh):
        if 2 <= u <= 5 and 2 <= v <= 5: return jit(OP['K'] if (u + v) % 2 else OP['k'], u, v, 403, 3)   # topknot
        return jit(OP['k'], u, v, 404, 4) if v < 3 else skin(u, v)
    paint(img, HEAD['top'], top)
    paint(img, HEAD['bottom'], lambda u, v, w, hh: jit(OP['o'], u, v, 405, 4))
    paint(img, HEAD['back'], lambda u, v, w, hh: jit(OP['k'], u, v, 406, 4) if v < 3 or (u in (3, 4) and v < 6) else skin(u + 30, v))
    for name, sd in (('left', 407), ('right', 408)):
        paint(img, HEAD[name], lambda u, v, w, hh, sd=sd: jit(OP['k'], u, v, sd, 4) if v < 2 else
              (jit(OP['P'], u, v, sd, 4) if v == 4 and u > 3 else
               (jit(OP['o'], u, v, sd, 3) if (u, v) in ((2, 3), (2, 4), (3, 3)) else skin(u + sd, v))))

    def leather(u, v, s):
        k = h(u, v, s)
        return jit(OP['j'] if k < 0.25 else OP['J'], u, v, s + 1, 5)
    def fur(u, v, s):
        return jit(OP['f'] if h(u, v, s) > 0.5 else OP['F'], u, v, s + 1, 7)
    def iron(u, v, s):
        if (u + v) % 4 == 0 and h(u, v, s) > 0.5: return jit(OP['Q'], u, v, s, 3)   # rivets and glints
        return jit(OP['A'] if h(u, v, s + 2) > 0.3 else OP['a'], u, v, s + 1, 4)
    def body(face, u, v, w, hh):
        if v < 2: return fur(u, v, 410)                                   # fur collar
        if v == 7: return jit(OP['y'] if face == 'front' and u in (3, 4) else OP['j'], u, v, 411, 3)   # belt
        if face == 'front':
            if u in (3, 4) and v < 7: return jit(OP['a'], u, v, 412, 3)  # iron chest strap
            if 2 <= v <= 6 and u in (1, 6): return iron(u, v, 413)
        if face == 'back' and (u == v - 1 or u == 8 - v) and v < 7: return jit(OP['j'], u, v, 414, 3)
        if v >= 8: return leather(u, v, 415) if (u + v) % 3 else jit(OP['a'], u, v, 416, 3)   # studded skirt
        return leather(u, v, 417 + len(face))
    fill_faces(img, BODY, ('front', 'back', 'left', 'right'), body)
    paint(img, BODY['top'], lambda u, v, w, hh: fur(u, v, 420))
    paint(img, BODY['bottom'], lambda u, v, w, hh: leather(u, v, 421))

    def arm(face, u, v, w, hh):
        if v < 4: return iron(u, v, 430 + len(face))                     # pauldron
        if v == 4: return jit(OP['a'], u, v, 431, 3)
        if v in (8, 9): return leather(u, v, 432)                         # bracer
        return skin(u + 50 + len(face), v)
    fill_faces(img, ARM, ('front', 'back', 'left', 'right'), arm)
    paint(img, ARM['top'], lambda u, v, w, hh: iron(u, v, 433))
    paint(img, ARM['bottom'], lambda u, v, w, hh: skin(u, v + 9))

    def leg(face, u, v, w, hh):
        if v >= 9: return iron(u, v, 440) if v < 11 else jit(OP['a'], u, v, 441, 3)   # iron-shod boots
        if v == 8: return jit(OP['j'], u, v, 442, 3)
        return leather(u, v, 443 + len(face)) if h(u, v, 444) > 0.15 else skin(u, v)
    fill_faces(img, LEG, ('front', 'back', 'left', 'right'), leg)
    paint(img, LEG['top'], lambda u, v, w, hh: leather(u, v, 445))
    paint(img, LEG['bottom'], lambda u, v, w, hh: jit(OP['a'], u, v, 446, 3))
    return img

# ============================== SKELETON =======================================
# Bone on nothing: the gaps are transparent, so you see between the ribs and
# round the limb bones (the entity draws with texture alpha).
SP = {'W': (230, 224, 204), 'w': (180, 174, 152), 'v': (140, 134, 116), 'D': (36, 32, 30), '.': CLEAR,
      'E': (120, 220, 255)}


def skeleton():
    img = Image.new("RGBA", (64, 32), CLEAR)
    def put_rows(rect, rows, seed):
        x, y, w, hh = rect
        for v, row in enumerate(rows):
            for u, ch in enumerate(row):
                if ch == '.': continue
                img.putpixel((x + u, y + v), jit(SP[ch] + (255,) if len(SP[ch]) == 3 else SP[ch], u + x, v + y, seed, 4 if ch in 'Ww' else 2))
    put_rows(HEAD['front'], [
        "wWWWWWWw",
        "WWWWWWWW",
        "WDDWWDDW",
        "WDEWWEDW",
        "wWWDDWWw",
        "wwWWWWww",
        "WDWDWDWW",
        ".wWWWWw.",
    ], 501)
    bone = lambda s: (lambda u, v, w, hh: jit(SP['W'] if h(u, v, s) > 0.2 else SP['w'], u, v, s + 1, 4))
    paint(img, HEAD['top'], bone(502))
    paint(img, HEAD['back'], bone(503))
    for name, sd in (('left', 504), ('right', 505)):
        paint(img, HEAD[name], lambda u, v, w, hh, sd=sd: CLEAR if v == 7 and u > 3 else
              (jit(SP['D'], u, v, sd, 2) if (u, v) in ((5, 4), (6, 4)) else bone(sd)(u, v, w, hh)))
    put_rows(BODY['front'], [
        "wWWWWWWw",
        ".WWWWWW.",
        "W..WW..W",
        ".WWWWWW.",
        "W..WW..W",
        ".wWWWWw.",
        "...WW...",
        "...WW...",
        "..wWWw..",
        ".WWWWWW.",
        "WW.WW.WW",
        "w.....ww",
    ], 510)
    put_rows(BODY['back'], [
        "wWWWWWWw",
        "...WW...",
        "w..WW..w",
        "...WW...",
        "w..WW..w",
        "...WW...",
        "...WW...",
        "...WW...",
        "..wWWw..",
        ".WWWWWW.",
        "WW....WW",
        "w.....ww",
    ], 511)
    for name in ('left', 'right'):
        put_rows(BODY[name], ["WWWW", "....", "W..W", "....", "W..W", "....", "....", "....", ".ww.", "WWWW", "W..W", "w..w"], 512)
    paint(img, BODY['top'], bone(513))
    def limb(face, u, v, w, hh, s):
        if v == 0: return bone(s)(u, v, w, hh)
        if v >= 10: return bone(s)(u, v, w, hh) if (face in ('front', 'back') or u in (1, 2)) and (u + v) % 2 == 0 or v == 10 else CLEAR
        if v == 5: return jit(SP['w'], u, v, s, 3) if u in (1, 2) or face in ('left', 'right') and u in (1, 2) else CLEAR   # joint
        return jit(SP['W'] if u == 1 else SP['w'], u, v, s, 3) if u in (1, 2) else CLEAR
    fill_faces(img, ARM, ('front', 'back', 'left', 'right'), lambda f, u, v, w, hh: limb(f, u, v, w, hh, 520))
    paint(img, ARM['top'], bone(521))
    paint(img, ARM['bottom'], lambda u, v, w, hh: jit(SP['w'], u, v, 522, 3) if (u + v) % 2 == 0 else CLEAR)
    fill_faces(img, LEG, ('front', 'back', 'left', 'right'), lambda f, u, v, w, hh: limb(f, u, v, w, hh, 530))
    paint(img, LEG['top'], lambda u, v, w, hh: bone(531)(u, v, w, hh) if u in (1, 2) else CLEAR)
    paint(img, LEG['bottom'], bone(532))
    return img


MONSTERS = [("goblin", goblin), ("kobold", kobold), ("orc", orc), ("skeleton", skeleton),
            ("mossling", mossling), ("hexer", hexer)]

if __name__ == "__main__":
    skins = {}
    for name, fn in MONSTERS:
        skins[name] = fn()
        skins[name].save(f"{OUT}/orthoverse_monsters_{name}.png")
    wisp().save(f"{OUT}/orthoverse_monsters_wisp.png")
    orb().save(f"{OUT}/orthoverse_monsters_hexer_orb.png")
    spark().save(f"{OUT}/orthoverse_monsters_wisp_spark.png")

    BG = (24, 24, 32, 255)
    sheet = Image.new("RGBA", (6 * 290, 640), BG)
    dr = ImageDraw.Draw(sheet)
    for i, (name, _) in enumerate(MONSTERS):
        tex = skins[name]
        label(dr, (20 + i * 290, 14), name.upper())
        iso = render_iso(tex)
        sheet.alpha_composite(iso, (i * 290, 30))
        sheet.alpha_composite(flat(tex, 'front'), (20 + i * 290, 400))
        sheet.alpha_composite(flat(tex, 'back'), (140 + i * 290, 400))
    sheet.save(f"{OUT}/../preview.png" if os.path.basename(os.path.normpath(OUT)) == "textures" else f"{OUT}/preview.png")
    print("ok")
