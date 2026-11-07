"""Token pictures ("cards") for the token metadata: each land drawn isometrically
from the world itself, buildings and all, framed with its crest, name and title.

    make_cards(rgb, heights, x_left, z_top, lands, tokens, heraldry_dir, out_dir)

rgb and heights are the whole map as render_map.render() made it (north up,
one pixel per node). Writes out_dir/<x>_<z>-<hash>.png, named after its own
content, so that a picture that changes gets a new name and marketplaces fetch
it again, and out_dir/index.json ({"x:z": file name}), which the metadata API
reads. Pictures that did not change are left alone; replaced ones are kept for
30 days (marketplaces may still link to them), then removed.
"""
import hashlib
import sqlite3
import sys
import io
import json
import os
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from render_map import voxels  # noqa: E402

SIZE = 96            # nodes across a land
CARD = 800           # card size, pixels
TITLES = ["Croft", "Land", "Domain", "Fiefdom", "Barony", "Duchy", "Principality", "Kingdom",
          "Town", "City", "Metropolis", "Region", "District", "State", "Prefecture", "Nation"]

# Background ("bg-nft") and banner colours of the old token pictures, per realm
# (orthoverse-offline config/tiles-fantasy.js and tiles-futuristic.js)
FANTASY = [(0x034e15, 0x5bb859), (0x4e0315, 0xb85b59), (0x03154e, 0x5b59b8),
           (0x4f4100, 0xc1a231), (0x424242, 0xa6a6a6), (0x034e45, 0x4bb899)]
FUTURISTIC = [(0xa43795, 0xffff66), (0x4a87a2, 0xffef76), (0x6f52ab, 0xffdf86),
              (0xc25a30, 0xffcf96), (0xa66576, 0xffbfa6), (0xac3451, 0xffafb6)]


GROUND = 8          # mgflat_ground_level: the flat land surface
SOIL = np.array((120, 86, 52), dtype=np.float32)
ROCK = np.array((112, 112, 116), dtype=np.float32)


def rgb_of(c):
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255)


def isometric(top, h):
    """A land from the north-west, above: top is 96 x 96 x 3 (north up), h the
    height of each column. 2 pixels per node across, 2 per node of height."""
    base = int(h.min()) - 3
    lift = (h.astype(np.int32) - base) * 2
    margin = int(lift.max())
    width, height = SIZE * 4, SIZE * 2 + margin + 4
    img = np.zeros((height, width, 4), dtype=np.uint8)

    v, u = np.mgrid[0:SIZE, 0:SIZE]          # v southwards (rows), u eastwards
    order = np.argsort((u + v).ravel(), kind="stable")   # far to near
    u, v = u.ravel()[order], v.ravel()[order]
    lift = lift.ravel()[order]
    hs = h.ravel()[order].astype(np.int32)
    col = top.reshape(-1, 3)[order].astype(np.float32)
    sx = (u - v + SIZE - 1) * 2
    sy = (u + v) + margin - lift
    length = lift + 2                         # rows from the top face down to the base

    # Every pixel of every column, in drawing order; the last write wins
    cell = np.repeat(np.arange(u.size), length)
    k = np.arange(cell.size) - np.repeat(np.cumsum(length) - length, length)
    rows = sy[cell] + k
    # Sides: above the ground level, whatever is there (trees, mountains,
    # buildings) in its own colour; below it, the surface node, then soil, then
    # rock further down
    depth = (k - 2) // 2                      # nodes below the top
    y = hs[cell] - depth                      # world height of the pixel
    under = depth >= 1
    base = col[cell]
    base = np.where((under & (y < GROUND))[:, None], SOIL, base)
    base = np.where((under & (y < GROUND - 3))[:, None], ROCK, base)
    top_face = k < 2
    # All four pixel columns of every row at once, in drawing order, so that
    # where pixels overlap the nearest wins
    j = np.arange(4)
    side = np.array([0.78, 0.78, 0.6, 0.6], dtype=np.float32)
    f = np.where(top_face[:, None], 1.0, side[None, :])
    c = np.clip(base[:, None, :] * f[:, :, None], 0, 255).astype(np.uint8).reshape(-1, 3)
    rr = np.repeat(rows, 4)
    cc = (sx[cell][:, None] + j[None, :]).ravel()
    img[rr, cc, :3] = c
    img[rr, cc, 3] = 255
    return Image.fromarray(img, "RGBA")


def isometric_blocks(ids, colours, y0):
    """A land from the north-west, above, block by block: ids[y, v, u] colour
    indices (0: nothing), colours their RGB, y0 the world height of ids[0].
    Each block is a cube 4 pixels across: its top, and its south and east sides
    in two shades. Air stays air, so overhangs, arches and poles look as built."""
    solid = ids > 0
    if not solid.any():
        return Image.new("RGBA", (SIZE * 4, SIZE * 2), (0, 0, 0, 0))
    ny = ids.shape[0]
    has = solid.any(axis=0)
    tops = ny - 1 - np.argmax(solid[::-1], axis=0)
    base = max(0, int(tops[has].min()) - 3)       # a few layers below the lowest surface
    s, ids = solid[base:], ids[base:]
    up = np.zeros_like(s)
    up[:-1] = s[1:]
    south = np.zeros_like(s)
    south[:, :-1, :] = s[:, 1:, :]
    east = np.zeros_like(s)
    east[:, :, :-1] = s[:, :, 1:]
    yy, vv, uu = np.nonzero(s & ~(up & south & east))   # blocks with a face in view
    margin = int(yy.max()) * 2
    img = np.zeros((SIZE * 2 + margin + 4, SIZE * 4, 4), dtype=np.uint8)

    order = np.argsort((uu + vv) * 4096 + yy, kind="stable")   # far to near, low to high
    yy, vv, uu = yy[order], vv[order], uu[order]
    col = colours[ids[yy, vv, uu]]
    # A little lighter higher up, as on the map
    world_y = (yy + base + y0).astype(np.float32)
    col = col * np.clip(0.85 + (world_y - GROUND) * 0.025, 0.55, 1.3)[:, None]
    sx = (uu - vv + SIZE - 1) * 2
    sy = (uu + vv) + margin - yy * 2
    # The 16 pixels of each cube, all cubes in drawing order, written at once:
    # where pixels overlap the last (nearest) one wins
    r = np.repeat(np.arange(4), 4)
    c = np.tile(np.arange(4), 4)
    shade = np.where(r < 2, 1.0, np.where(c < 2, 0.78, 0.6)).astype(np.float32)
    rows = (sy[:, None] + r[None, :]).ravel()
    cols = (sx[:, None] + c[None, :]).ravel()
    rgb = np.clip(col[:, None, :] * shade[None, :, None], 0, 255).astype(np.uint8).reshape(-1, 3)
    img[rows, cols, :3] = rgb
    img[rows, cols, 3] = 255
    return Image.fromarray(img, "RGBA")


class Heraldry:
    def __init__(self, folder):
        with open(os.path.join(folder, "heraldry.json"), encoding="utf-8") as f:
            self.meta = json.load(f)
        self.sheet = Image.open(os.path.join(folder, "escutcheons.png")).convert("RGBA")
        self.gear = {r: Image.open(os.path.join(folder, r + ".png")).convert("RGBA")
                     for r in ("crown", "coronet", "baron")}

    def crest(self, n, castle):
        m = self.meta
        if n is None or n >= m["count"] or n in m["missing"]:
            return None
        w, h = m["width"], m["height"]
        x, y = (n % m["columns"]) * w, (n // m["columns"]) * h
        img = Image.new("RGBA", (w, h + 7), (0, 0, 0, 0))
        img.paste(self.sheet.crop((x, y, x + w, y + h)), (0, 7))
        rank = "crown" if castle >= 7 else "coronet" if castle >= 5 else "baron" if castle >= 4 else None
        if rank:
            g = self.gear[rank]
            img.alpha_composite(g, (0, 0))
        return img


# The Midnight font (Lords of Midnight, TrueType conversion by Simon
# Holdsworth): 8 x 8 pixels, crisp at multiples of 8 pixels
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts", "midnight.ttf")


def fitting(draw, texts, room, sizes):
    """The largest of sizes at which every text fits in room pixels."""
    for size in sizes:
        font = ImageFont.truetype(FONT, size)
        if all(draw.textlength(t, font=font) <= room for t in texts):
            return font
    return ImageFont.truetype(FONT, sizes[-1])


def card(land_img, name, level, key, crest, token):
    realm = FUTURISTIC if level >= 8 else FANTASY
    bg, banner = (rgb_of(c) for c in realm[int(token[-2:], 16) % len(realm)])
    canvas = Image.new("RGB", (CARD, CARD), bg)
    draw = ImageDraw.Draw(canvas)

    # Banner along the top, with the crest at its left
    draw.rectangle((0, 0, CARD, 150), fill=banner)
    draw.rectangle((0, 150, CARD, 156), fill=tuple(int(c * 0.7) for c in banner))
    text_x = 32
    if crest is not None:
        big = crest.resize((crest.width * 5, crest.height * 5), Image.NEAREST)
        canvas.paste(big, (28, 8), big)
        text_x = 28 + big.width + 24
    dark = (20, 20, 24)
    draw.fontmode = "1"     # the font's pixels as they are, no smoothing
    room = CARD - text_x - 24
    realm_name = "futuristic" if level >= 8 else "fantasy"
    lines = ["%s of the %s realm" % (TITLES[level] if level < 16 else "Land", realm_name), "Land " + key]
    name_font = fitting(draw, [name], room, (48, 40, 32, 24, 16))
    small_font = fitting(draw, lines, room, (24, 16, 8))
    draw.text((text_x, 22), name, fill=dark, font=name_font)
    y = 22 + name_font.size + 18
    for line in lines:
        draw.text((text_x, y), line, fill=dark, font=small_font)
        y += small_font.size + 8

    # The land, as large as fits below the banner
    room_w, room_h = CARD - 32, CARD - 156 - 32
    scale = max(1, min(room_w // land_img.width, room_h // land_img.height))
    big_land = land_img.resize((land_img.width * scale, land_img.height * scale), Image.NEAREST)
    x = (CARD - big_land.width) // 2
    y = 156 + (CARD - 156 - big_land.height) // 2
    canvas.paste(big_land, (x, y), big_land)
    return canvas


def card_inputs(land, tokens):
    """The level and crest a land's card shows: from the chain index, or the
    lands file until the chain service has run."""
    t = tokens.get(land["token"].lower()) or {}
    level = t["level"] if isinstance(t.get("level"), int) else int(land.get("level") or 0)
    crest_n = t.get("crest")
    if not isinstance(crest_n, int):
        c = land.get("crest") or ""
        crest_n = int(c[:-4]) if c.endswith(".png") and c[:-4].isdigit() else None
    return level, crest_n


# A card that is no longer a land's current one is kept this long after it was
# replaced: marketplaces (OpenSea) keep the picture address from the metadata
# they last read, and show nothing if the file has gone
KEEP_RETIRED = 30 * 24 * 3600


def retire(out_dir, current, now=None):
    """Note when each card stopped being current (retired.json) and remove the
    ones replaced more than KEEP_RETIRED ago. Returns how many were removed."""
    now = time.time() if now is None else now
    path = os.path.join(out_dir, "retired.json")
    try:
        with open(path, encoding="utf-8") as f:
            retired = json.load(f)
    except (FileNotFoundError, ValueError):
        retired = {}
    pngs = {f for f in os.listdir(out_dir) if f.endswith(".png")}
    out, removed = {}, 0
    for f in pngs - current:
        since = retired.get(f, now)
        if now - since > KEEP_RETIRED:
            os.remove(os.path.join(out_dir, f))
            removed += 1
        else:
            out[f] = since
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
    os.replace(tmp, path)
    return removed


def make_cards(rgb, heights, x_left, z_top, lands, tokens, heraldry_dir, out_dir, update=False, db=None):
    """lands: {"x:z": land}; tokens: the chain service's tokens.json "tokens"
    (level and crest), or {}. With update=True only these lands' cards are
    replaced; otherwise these are all the cards there are. With db (the
    world's map.sqlite), lands are drawn block by block; without, from the
    heights alone.

    Returns (cards, written, removed, {key: [level, crest]} drawn)."""
    os.makedirs(out_dir, exist_ok=True)
    heraldry = Heraldry(heraldry_dir)
    h_img, w_img = heights.shape
    con = sqlite3.connect(db, timeout=30) if db else None
    index_path = os.path.join(out_dir, "index.json")
    old_index = {}
    if update and os.path.exists(index_path):
        with open(index_path, encoding="utf-8") as f:
            old_index = json.load(f)
    index = {}
    drawn = {}
    written = 0
    for key, land in lands.items():
        lx, lz = (int(v) for v in key.split(":"))
        col = lx * SIZE - SIZE // 2 - x_left
        row = z_top - (-lz * SIZE - SIZE // 2 + SIZE - 1)
        if col < 0 or row < 0 or col + SIZE > w_img or row + SIZE > h_img:
            continue
        token = land["token"].lower()
        level, crest_n = card_inputs(land, tokens)
        drawn[key] = [level, crest_n]
        crest = heraldry.crest(crest_n, level % 8) if level % 8 > 0 else None
        if con is not None:
            west = lx * SIZE - SIZE // 2
            south = -lz * SIZE - SIZE // 2
            iso = isometric_blocks(*voxels(con, west, south, SIZE))
        else:
            iso = isometric(rgb[row:row + SIZE, col:col + SIZE], heights[row:row + SIZE, col:col + SIZE])
        img = card(iso, land["name"], level, key, crest, token)
        buf = io.BytesIO()
        img.save(buf, "PNG")
        data = buf.getvalue()
        name = "%d_%d-%s.png" % (lx, lz, hashlib.sha1(data).hexdigest()[:10])
        path = os.path.join(out_dir, name)
        if not os.path.exists(path):
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
            written += 1
        index[key] = name
    if update:
        # Only these lands' cards change; the rest of the index stays
        old_index.update(index)
        index = old_index
    tmp = os.path.join(out_dir, "index.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(index, f, separators=(",", ":"))
    os.replace(tmp, index_path)
    removed = retire(out_dir, set(index.values()))
    return len(index), written, removed, drawn
