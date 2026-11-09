#!/usr/bin/env python3
"""Make the web map: map tiles from the world database, the land pictures, the
token cards and the land list.

    make_tiles.py draw   MAP.sqlite LANDS.json NEW_LANDS.json TOKENS.json HERALDRY_DIR OUT_DIR
    make_tiles.py update MAP.sqlite LANDS.json NEW_LANDS.json TOKENS.json HERALDRY_DIR OUT_DIR CHANGES.json

draw: the whole map, a few minutes. Writes OUT_DIR/tiles/<version>/{z}/{x}/{y}.png
(zoom 0 to 6; at zoom 6 one pixel is one node), OUT_DIR/lands/{x}_{z}.png (each
land from above, 384 pixels square), OUT_DIR/cards/ (the token pictures, see
cards.py) and OUT_DIR/lands.json (the land names, levels and token IDs the map
shows, including lands placed later for new tokens: the chain service's
new-lands.json, and which tiles version is current). <version> comes from
MAP_VERSION.

update: only what changed since it was drawn: the lands the game has reported
changed (CHANGES.json, written by orthoverse_lands: blocks placed or dug, lands
made again or added) and the lands whose card would show another level or crest.
For each, its map tiles (and the zoomed-out tiles above them), its picture and
its card are drawn again, into a new tiles version made of hard links to the
current one. Seconds per land. Does nothing if nothing changed.

OUT_DIR/.drawn.json remembers when each land was drawn, and with which level
and crest.

Coordinates: the map is a 16384-node square centred on the origin. At zoom 6,
pixel (px, py) is node x = px - 8192, z = 8192 - py (north up). The page uses
Leaflet's CRS.Simple with that transformation, so map lat/lng are node z/x.

Needs numpy, zstandard and Pillow (see tools/render_map.py for a venv).
"""
import json
import os
import shutil
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from render_map import render  # noqa: E402
from cards import make_cards, card_inputs  # noqa: E402

TILE = 256
MAX_Z = 6
HALF = 8192          # half the side of the pyramid, in nodes
SEA = (40, 90, 190)  # same colour as water in the renderer
SIZE = 96            # nodes across a land
QUIET = 60           # seconds a land must be left alone before it is drawn again
KEEP_VERSIONS = 2    # tiles versions kept (the current one and the one before)


def tile_path(root, z, x, y):
    return os.path.join(root, str(z), str(x), "%d.png" % y)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # A new file, never written over: in an update the old one is a hard link
    # into the previous version
    if os.path.exists(path):
        os.remove(path)
    img.save(path, optimize=True)


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, value):
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(path + ".tmp", path)


def all_lands(lands_path, new_lands_path):
    data = read_json(lands_path, None)
    lands = dict(data["lands"])
    for key, land in read_json(new_lands_path, {}).get("lands", {}).items():
        lands.setdefault(key, land)
    return data, lands


def land_box(key):
    """A land's nodes: west x, east x, south z, north z."""
    lx, lz = (int(v) for v in key.split(":"))
    x0 = lx * SIZE - SIZE // 2
    zn = -lz * SIZE - SIZE // 2 + SIZE - 1
    return x0, x0 + SIZE - 1, zn - SIZE + 1, zn


def land_picture(rgb, x_left, z_top, key, out):
    h, w = rgb.shape[:2]
    x0, _, _, zn = land_box(key)
    col, row = x0 - x_left, z_top - zn
    if col < 0 or row < 0 or col + SIZE > w or row + SIZE > h:
        return False
    lx, lz = key.split(":")
    path = os.path.join(out, "lands", "%s_%s.png" % (lx, lz))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = Image.fromarray(rgb[row:row + SIZE, col:col + SIZE]).resize((SIZE * 4, SIZE * 4), Image.NEAREST)
    if os.path.exists(path):
        os.remove(path)
    img.save(path)
    return True


def zoom6_tile(rgb, x_left, z_top, drawn, tx, ty):
    """Tile (tx, ty) at zoom 6 from the image, sea outside the drawn world."""
    h, w = rgb.shape[:2]
    off_x, off_y = x_left + HALF, HALF - z_top
    px0, py0 = tx * TILE, ty * TILE
    # The part of the tile both in the image and in the drawn world
    wx0, wx1 = drawn["west"] + HALF, drawn["east"] + HALF
    wy0, wy1 = HALF - drawn["north"], HALF - drawn["south"]
    ix0, iy0 = max(px0, off_x, wx0), max(py0, off_y, wy0)
    ix1, iy1 = min(px0 + TILE, off_x + w, wx1), min(py0 + TILE, off_y + h, wy1)
    tile = np.empty((TILE, TILE, 3), dtype=np.uint8)
    tile[:] = SEA
    if ix0 < ix1 and iy0 < iy1:
        tile[iy0 - py0:iy1 - py0, ix0 - px0:ix1 - px0] = \
            rgb[iy0 - off_y:iy1 - off_y, ix0 - off_x:ix1 - off_x]
    return Image.fromarray(tile)


def lower_zooms(root, made):
    """Each tile below zoom 6 is its four children, halved: (re)make the
    parents of the tiles in made, up to zoom 0."""
    for z in range(MAX_Z - 1, -1, -1):
        parents = {(tx // 2, ty // 2) for (tx, ty) in made}
        for (px, py) in parents:
            canvas = Image.new("RGB", (TILE * 2, TILE * 2), SEA)
            for dx in (0, 1):
                for dy in (0, 1):
                    child = tile_path(root, z + 1, px * 2 + dx, py * 2 + dy)
                    if os.path.exists(child):
                        with Image.open(child) as c:
                            canvas.paste(c, (dx * TILE, dy * TILE))
            save(canvas.resize((TILE, TILE), Image.LANCZOS), tile_path(root, z, px, py))
        made = parents
        print("zoom %d: %d tiles" % (z, len(parents)), flush=True)


def land_list(data, lands, tokens):
    """The land list the page needs (no owners: those come from the chain)."""
    out = []
    for key, land in lands.items():
        lx, lz = (int(v) for v in key.split(":"))
        level = (tokens.get(land["token"].lower()) or {}).get("level")
        entry = {"x": lx, "z": lz, "n": land["name"],
                 "l": level if isinstance(level, int) else land["level"], "t": land["token"]}
        if key in data.get("henges", {}):
            entry["h"] = data["henges"][key]["name"]
        out.append(entry)
    return out


def prune_versions(out):
    tiles = os.path.join(out, "tiles")
    versions = sorted(d for d in os.listdir(tiles) if d.isdigit() and len(d) > 2)
    for d in versions[:-KEEP_VERSIONS]:
        shutil.rmtree(os.path.join(tiles, d), ignore_errors=True)


def draw(db, lands_path, new_lands_path, tokens_path, heraldry_dir, out):
    """The whole map, into OUT_DIR as make-map.sh expects (tiles/ in a fresh
    folder it moves into place)."""
    started = time.time()
    data, lands = all_lands(lands_path, new_lands_path)
    tokens = read_json(tokens_path, {}).get("tokens", {})
    rgb, x_left, z_top, heights = render(db, heights=True)
    h, w = rgb.shape[:2]
    drawn = {"west": x_left, "east": x_left + w, "north": z_top, "south": z_top - h}
    off_x, off_y = x_left + HALF, HALF - z_top
    print("image %dx%d at pixel offset (%d, %d)" % (w, h, off_x, off_y), flush=True)

    root = os.path.join(out, "tiles")
    made = set()
    for ty in range(off_y // TILE, (off_y + h - 1) // TILE + 1):
        for tx in range(off_x // TILE, (off_x + w - 1) // TILE + 1):
            save(zoom6_tile(rgb, x_left, z_top, drawn, tx, ty), tile_path(root, MAX_Z, tx, ty))
            made.add((tx, ty))
    print("zoom %d: %d tiles" % (MAX_Z, len(made)), flush=True)

    pictures = sum(land_picture(rgb, x_left, z_top, key, out) for key in lands)
    print("land pictures: %d" % pictures, flush=True)

    cards_dir = os.environ.get("CARDS_DIR")
    state = {"drawn_at": started, "lands": {}}
    if cards_dir:
        n, written, removed, inputs = make_cards(rgb, heights, x_left, z_top, lands, tokens,
                                                 heraldry_dir, cards_dir, db=db)
        print("token pictures: %d (%d new or changed, %d old ones removed)" % (n, written, removed), flush=True)
        state["lands"] = {k: {"at": started, "card": v} for k, v in inputs.items()}
    del rgb, heights

    lower_zooms(root, made)

    out_json = {"land_size": data["land_size"], "drawn": drawn, "lands": land_list(data, lands, tokens)}
    if os.environ.get("MAP_VERSION"):
        out_json["version"] = os.environ["MAP_VERSION"]
    write_json(os.path.join(out, "lands.json"), out_json)
    state_dir = os.environ.get("STATE_DIR", out)
    write_json(os.path.join(state_dir, ".drawn.json"), state)
    print("lands.json: %d lands" % len(out_json["lands"]))


def update(db, lands_path, new_lands_path, tokens_path, heraldry_dir, out, changes_path):
    """Only what changed (see the module's description). Returns the number of
    lands drawn again."""
    now = time.time()
    current = read_json(os.path.join(out, "lands.json"), None)
    if not current or not current.get("version"):
        print("No versioned map yet: draw the whole map first (make-map).")
        return 0
    state = read_json(os.path.join(out, ".drawn.json"), {"drawn_at": 0, "lands": {}})
    data, lands = all_lands(lands_path, new_lands_path)
    tokens = read_json(tokens_path, {}).get("tokens", {})
    changes = read_json(changes_path, {}).get("lands", {})

    todo = set()
    for key, at in changes.items():
        seen = max(state.get("drawn_at", 0), (state["lands"].get(key) or {}).get("at", 0))
        if at > seen and now - at >= QUIET:
            todo.add(key)
    # Cards whose level or crest has changed on the chain
    for key, land in lands.items():
        card = (state["lands"].get(key) or {}).get("card")
        if card is not None and list(card_inputs(land, tokens)) != card:
            todo.add(key)
    if not todo:
        # Nothing to draw, but the names may have changed (the henges'
        # English names, a land renamed): keep the list up to date
        lands_now = land_list(data, lands, tokens)
        if lands_now != current.get("lands"):
            current["lands"] = lands_now
            write_json(os.path.join(out, "lands.json"), current)
            print("lands.json: names and levels brought up to date", flush=True)
        return 0

    version = os.environ.get("MAP_VERSION") or time.strftime("%Y%m%d%H%M%S", time.gmtime())
    old_root = os.path.join(out, "tiles", current["version"])
    root = os.path.join(out, "tiles", version)
    # The new version starts as hard links to the current one
    for d, _, files in os.walk(old_root):
        nd = os.path.join(root, os.path.relpath(d, old_root))
        os.makedirs(nd, exist_ok=True)
        for f in files:
            os.link(os.path.join(d, f), os.path.join(nd, f))

    drawn = current["drawn"]
    made = set()
    cards_dir = os.path.join(out, "cards")
    for key in sorted(todo):
        x0, x1, zs, zn = land_box(key)
        # The zoom-6 tiles this land touches, and the nodes they cover
        tiles = [(tx, ty)
                 for tx in range((x0 + HALF) // TILE, (x1 + HALF) // TILE + 1)
                 for ty in range((HALF - zn) // TILE, (HALF - zs) // TILE + 1)]
        nx0 = min(tx for tx, _ in tiles) * TILE - HALF
        nx1 = (max(tx for tx, _ in tiles) + 1) * TILE - 1 - HALF
        nzn = HALF - min(ty for _, ty in tiles) * TILE
        nzs = HALF - ((max(ty for _, ty in tiles) + 1) * TILE - 1)
        rgb, x_left, z_top, heights = render(db, quiet=True, heights=True,
                                             area=(nx0 >> 4, nx1 >> 4, nzs >> 4, nzn >> 4))
        for tx, ty in tiles:
            save(zoom6_tile(rgb, x_left, z_top, drawn, tx, ty), tile_path(root, MAX_Z, tx, ty))
            made.add((tx, ty))
        entry = state["lands"].setdefault(key, {})
        entry["at"] = now
        if key in lands:
            land_picture(rgb, x_left, z_top, key, out)
            _, _, _, inputs = make_cards(rgb, heights, x_left, z_top, {key: lands[key]}, tokens,
                                         heraldry_dir, cards_dir, update=True, db=db)
            if key in inputs:
                entry["card"] = inputs[key]
        print("drawn again: %s" % key, flush=True)
    lower_zooms(root, made)

    current["version"] = version
    current["lands"] = land_list(data, lands, tokens)
    write_json(os.path.join(out, "lands.json"), current)
    write_json(os.path.join(out, ".drawn.json"), state)
    prune_versions(out)
    print("Map updated (version %s): %d lands drawn again." % (version, len(todo)), flush=True)
    return len(todo)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "draw" and len(sys.argv) == 8:
        draw(*sys.argv[2:8])
    elif mode == "update" and len(sys.argv) == 9:
        update(*sys.argv[2:9])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
