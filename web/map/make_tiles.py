#!/usr/bin/env python3
"""Make the web map: map tiles from the world database, plus the land list.

    make_tiles.py MAP.sqlite LANDS.json OUT_DIR

Writes OUT_DIR/tiles/{z}/{x}/{y}.png (zoom 0 to 6; at zoom 6 one pixel is one
node) and OUT_DIR/lands.json (the land names, levels and token IDs the map
shows). Takes a few minutes for the whole Orthoverse.

Coordinates: the map is a 16384-node square centred on the origin. At zoom 6,
pixel (px, py) is node x = px - 8192, z = 8192 - py (north up). The page uses
Leaflet's CRS.Simple with that transformation, so map lat/lng are node z/x.

Needs numpy, zstandard and Pillow (see tools/render_map.py for a venv).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from render_map import render  # noqa: E402

TILE = 256
MAX_Z = 6
HALF = 8192          # half the side of the pyramid, in nodes
SEA = (40, 90, 190)  # same colour as water in the renderer


def tile_path(out, z, x, y):
    return os.path.join(out, "tiles", str(z), str(x), "%d.png" % y)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def main():
    db, lands_path, out = sys.argv[1:4]
    rgb, x_left, z_top = render(db)
    h, w = rgb.shape[:2]
    # Where the rendered image sits in zoom-6 pixel space
    off_x = x_left + HALF
    off_y = HALF - z_top
    print("image %dx%d at pixel offset (%d, %d)" % (w, h, off_x, off_y), flush=True)

    n = 1 << MAX_Z
    made = {}
    count = 0
    for ty in range(n):
        for tx in range(n):
            px0, py0 = tx * TILE, ty * TILE
            # overlap of this tile with the image
            ix0, iy0 = max(px0, off_x), max(py0, off_y)
            ix1, iy1 = min(px0 + TILE, off_x + w), min(py0 + TILE, off_y + h)
            if ix0 >= ix1 or iy0 >= iy1:
                continue
            tile = np.empty((TILE, TILE, 3), dtype=np.uint8)
            tile[:] = SEA
            tile[iy0 - py0:iy1 - py0, ix0 - px0:ix1 - px0] = \
                rgb[iy0 - off_y:iy1 - off_y, ix0 - off_x:ix1 - off_x]
            save(Image.fromarray(tile), tile_path(out, MAX_Z, tx, ty))
            made[(tx, ty)] = True
            count += 1
    print("zoom %d: %d tiles" % (MAX_Z, count), flush=True)
    del rgb

    # Lower zooms: each tile is its four children, halved
    for z in range(MAX_Z - 1, -1, -1):
        parents = {}
        for (tx, ty) in made:
            parents[(tx // 2, ty // 2)] = True
        for (px, py) in parents:
            canvas = Image.new("RGB", (TILE * 2, TILE * 2), SEA)
            for dx in (0, 1):
                for dy in (0, 1):
                    c = (px * 2 + dx, py * 2 + dy)
                    if c in made:
                        with Image.open(tile_path(out, z + 1, *c)) as child:
                            canvas.paste(child, (dx * TILE, dy * TILE))
            save(canvas.resize((TILE, TILE), Image.LANCZOS), tile_path(out, z, px, py))
        made = parents
        print("zoom %d: %d tiles" % (z, len(parents)), flush=True)

    # The land list the page needs (no owners: those come from the chain later)
    with open(lands_path, encoding="utf-8") as f:
        data = json.load(f)
    lands = []
    for key, land in data["lands"].items():
        lx, lz = (int(v) for v in key.split(":"))
        entry = {"x": lx, "z": lz, "n": land["name"], "l": land["level"], "t": land["token"]}
        if key in data.get("henges", {}):
            entry["h"] = data["henges"][key]["name"]
        lands.append(entry)
    with open(os.path.join(out, "lands.json"), "w", encoding="utf-8") as f:
        # Node area the tiles cover, so the page only asks for tiles that exist
        drawn = {"west": x_left, "east": x_left + w, "north": z_top, "south": z_top - h}
        json.dump({"land_size": data["land_size"], "drawn": drawn, "lands": lands}, f,
                  ensure_ascii=False, separators=(",", ":"))
    print("lands.json: %d lands" % len(lands))


if __name__ == "__main__":
    main()
