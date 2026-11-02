#!/usr/bin/env python3
"""Inspect a Luanti sqlite map without running the server (debugging aid).

  mapslice.py MAP.sqlite count  X0 Z0 X1 Z1 Y0 Y1      node counts in a box
  mapslice.py MAP.sqlite slice  Z  X0 X1 Y0 Y1 OUT.png  vertical slice at z = Z

Reads map format 29 (zstd). Needs the 'zstandard' and 'Pillow' packages
(use a venv: python3 -m venv .venv && .venv/bin/pip install zstandard pillow).
"""
import sqlite3
import struct
import sys
from collections import Counter

import zstandard

_dctx = zstandard.ZstdDecompressor()


def read_block(con, bx, by, bz, cache={}):
    k = (bx, by, bz)
    if k in cache:
        return cache[k]
    row = con.execute("SELECT data FROM blocks WHERE x = ? AND y = ? AND z = ?",
                      (bx, by, bz)).fetchone()
    if row is None:
        cache[k] = None
        return None
    blob = row[0]
    version = blob[0]
    if version < 29:
        raise SystemExit("map format %d not supported" % version)
    d = _dctx.decompress(blob[1:], max_output_size=1 << 20)
    p = 0
    p += 1 + 2 + 4                         # flags, lighting_complete, timestamp
    p += 1                                 # name-id mapping version
    (count,) = struct.unpack_from(">H", d, p); p += 2
    names = {}
    for _ in range(count):
        nid, ln = struct.unpack_from(">HH", d, p); p += 4
        names[nid] = d[p:p + ln].decode(); p += ln
    p += 2                                 # content_width, params_width
    param0 = struct.unpack_from(">4096H", d, p)
    cache[k] = (param0, names)
    return cache[k]


def node(con, x, y, z):
    b = read_block(con, x >> 4, y >> 4, z >> 4)
    if b is None:
        return "ignore"
    param0, names = b
    i = (z & 15) * 256 + (y & 15) * 16 + (x & 15)
    return names[param0[i]]


def main():
    con = sqlite3.connect(sys.argv[1])
    cmd = sys.argv[2]
    a = [int(v) for v in sys.argv[3:9]] if cmd == "count" else None
    if cmd == "count":
        x0, z0, x1, z1, y0, y1 = a
        c = Counter()
        for x in range(x0, x1 + 1):
            for z in range(z0, z1 + 1):
                for y in range(y0, y1 + 1):
                    c[node(con, x, y, z)] += 1
        for name, n in c.most_common():
            print("%9d  %s" % (n, name))
    elif cmd == "slice":
        from PIL import Image
        z, x0, x1, y0, y1 = (int(v) for v in sys.argv[3:8])
        out = sys.argv[8]
        cols = {}
        im = Image.new("RGB", (x1 - x0 + 1, y1 - y0 + 1))
        px = im.load()
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                n = node(con, x, y, z)
                if n not in cols:
                    h = hash(n) & 0xffffff
                    cols[n] = {"air": (200, 230, 255), "ignore": (0, 0, 0),
                               "default:stone": (120, 120, 120),
                               "default:water_source": (40, 90, 200),
                               "default:stonebrick": (230, 230, 230),
                               "default:cobble": (90, 90, 90),
                               "default:mossycobble": (60, 130, 60),
                               "default:dirt": (120, 80, 40)}.get(
                        n, ((h >> 16) & 255, (h >> 8) & 255, h & 255))
                px[x - x0, y1 - y] = cols[n]
        im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
        im.save(out)
        print("wrote", out)


if __name__ == "__main__":
    main()
