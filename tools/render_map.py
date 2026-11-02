#!/usr/bin/env python3
"""Render a top-down overview of the Orthoverse straight from the map database.

    render_map.py MAP.sqlite OUT.png [STEP]

STEP is nodes per pixel (default 4: the whole map becomes 2808 x 2808).
Works offline, so it is safe for the whole map, unlike /orthomap in game which
loads every block into the server. Reads map format 29 (zstd).

Needs numpy, zstandard and Pillow; use a venv:
    python3 -m venv .venv && .venv/bin/pip install numpy zstandard pillow
"""
import sqlite3
import struct
import sys

import numpy as np
import zstandard
from PIL import Image

G = 8            # mgflat_ground_level
W = 1            # water_level
Y_LO, Y_HI = W - 16, G + 48

# Colours by node-name fragment, first match wins (same idea as the in-game renderer)
PALETTE = [
    ("world_edge", (20, 20, 40)), ("henge_portal", (60, 220, 120)),
    ("tarmac", (40, 40, 46)), ("water", (40, 90, 190)),
    ("leaves", (40, 120, 40)), ("needles", (30, 80, 50)), ("tree", (90, 60, 30)),
    ("snow", (240, 240, 250)), ("dirt_with_grass", (90, 160, 60)),
    ("coniferous", (80, 110, 60)), ("dry", (160, 150, 80)),
    ("desert_sand", (210, 170, 110)), ("silver_sand", (200, 200, 190)),
    ("sand", (225, 210, 150)), ("desert_stone", (170, 100, 70)),
    ("gravel", (130, 125, 120)), ("cobble", (110, 110, 110)),
    ("stonebrick", (150, 150, 155)), ("stone_block", (170, 170, 175)),
    ("obsidian", (30, 20, 40)), ("steel", (200, 200, 210)), ("tin", (180, 180, 190)),
    ("copper", (200, 120, 60)), ("bronze", (180, 110, 50)), ("glass", (190, 230, 240)),
    ("sandstone", (220, 200, 140)), ("meselamp", (250, 250, 150)),
    ("wool", (220, 80, 160)), ("cactus", (40, 140, 40)), ("flowers", (230, 90, 90)),
    ("grass", (110, 180, 70)), ("shrub", (140, 110, 60)), ("apple", (200, 40, 40)),
    ("stone", (125, 125, 125)),
]


def colour(name):
    for frag, col in PALETTE:
        if frag in name:
            return col
    return (255, 0, 255)


def decode(blob, dctx):
    if blob[0] < 29:
        raise SystemExit("map format %d not supported" % blob[0])
    d = dctx.decompress(blob[1:], max_output_size=1 << 20)
    p = 1 + 2 + 4 + 1
    (count,) = struct.unpack_from(">H", d, p)
    p += 2
    names = {}
    for _ in range(count):
        nid, ln = struct.unpack_from(">HH", d, p)
        p += 4
        names[nid] = d[p:p + ln].decode()
        p += ln
    p += 2
    param0 = np.frombuffer(d, dtype=">u2", count=4096, offset=p).reshape(16, 16, 16)  # z, y, x
    return param0, names


def main():
    db, out = sys.argv[1], sys.argv[2]
    step = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    con = sqlite3.connect(db)
    bylo, byhi = Y_LO >> 4, Y_HI >> 4
    xmin, xmax, zmin, zmax = con.execute(
        "SELECT min(x), max(x), min(z), max(z) FROM blocks WHERE y BETWEEN ? AND ?",
        (bylo, byhi)).fetchone()
    nx, nz = (xmax - xmin + 1) * 16, (zmax - zmin + 1) * 16
    top_y = np.full((nz, nx), -10_000, dtype=np.int32)
    top_name = np.zeros((nz, nx), dtype=np.int32)
    name_ids = {"": 0}
    dctx = zstandard.ZstdDecompressor()
    n = 0
    # Highest blocks first, so a column's first hit is its top
    for bx, by, bz, blob in con.execute(
            "SELECT x, y, z, data FROM blocks WHERE y BETWEEN ? AND ? ORDER BY y DESC",
            (bylo, byhi)):
        param0, names = decode(blob, dctx)
        solid = np.ones(param0.shape, dtype=bool)
        for nid, nm in names.items():
            if nm in ("air", "ignore"):
                solid &= param0 != nid
        has = solid.any(axis=1)                      # z, x
        if not has.any():
            continue
        # top-most solid y in each column of this block
        idx = 15 - np.argmax(solid[:, ::-1, :], axis=1)
        x0, z0 = (bx - xmin) * 16, (bz - zmin) * 16
        cur = top_y[z0:z0 + 16, x0:x0 + 16]
        world_y = by * 16 + idx
        better = has & (world_y > cur)
        if better.any():
            local = np.zeros(max(names) + 1, dtype=np.int32)
            for nid, nm in names.items():
                if nm not in name_ids:
                    name_ids[nm] = len(name_ids)
                local[nid] = name_ids[nm]
            zi, xi = np.meshgrid(np.arange(16), np.arange(16), indexing="ij")
            top_ids = local[param0[zi, idx, xi]]
            tn = top_name[z0:z0 + 16, x0:x0 + 16]
            tn[better] = top_ids[better]
            cur[better] = world_y[better]
        n += 1
        if n % 200000 == 0:
            print("%d blocks" % n, flush=True)

    lut = np.zeros((len(name_ids), 3), dtype=np.float32)
    for nm, i in name_ids.items():
        lut[i] = colour(nm) if nm else (0, 0, 0)
    # North (high z) at the top; sample every 'step' nodes before colouring
    names_s = top_name[::-1][::step, ::step]
    ys = top_y[::-1][::step, ::step]
    rgb = lut[names_s]
    shade = np.clip(0.85 + (ys - G) * 0.025, 0.55, 1.3)[..., None]
    rgb = np.clip(rgb * shade, 0, 255).astype(np.uint8)
    Image.fromarray(rgb).save(out)
    print("%d blocks -> %s (%dx%d)" % (n, out, rgb.shape[1], rgb.shape[0]))


if __name__ == "__main__":
    main()
