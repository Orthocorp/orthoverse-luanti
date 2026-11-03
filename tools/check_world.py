#!/usr/bin/env python3
"""Sanity checks on a generated map (debugging aid).

    check_world.py MAP.sqlite X0 Z0 X1 Z1

Reports leaves that are not connected to any trunk through other leaves
(floating leaves), within the box and y between ground and ground + 40.
Uses tools/mapslice.py's block reader; needs zstandard.
"""
import os
import sqlite3
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapslice import node  # noqa: E402

G = 8
LEAVES = ("leaves", "needles")
TRUNKS = ("default:tree", "default:aspen_tree", "default:pine_tree",
          "default:jungletree", "default:acacia_tree")


def main():
    con = sqlite3.connect(sys.argv[1])
    x0, z0, x1, z1 = (int(v) for v in sys.argv[2:6])
    y0, y1 = G - 2, G + 40
    leaf, trunk = set(), set()
    for x in range(x0, x1 + 1):
        for z in range(z0, z1 + 1):
            for y in range(y0, y1 + 1):
                n = node(con, x, y, z)
                if any(t in n for t in LEAVES):
                    leaf.add((x, y, z))
                elif n in TRUNKS:
                    trunk.add((x, y, z))
    # Leaves reachable from a trunk through 26-connected leaves
    seen = set()
    q = deque()
    for (x, y, z) in trunk:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    p = (x + dx, y + dy, z + dz)
                    if p in leaf and p not in seen:
                        seen.add(p)
                        q.append(p)
    while q:
        x, y, z = q.popleft()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    p = (x + dx, y + dy, z + dz)
                    if p in leaf and p not in seen:
                        seen.add(p)
                        q.append(p)
    floating = leaf - seen
    print("trunk nodes %d, leaf nodes %d, floating leaves %d"
          % (len(trunk), len(leaf), len(floating)))
    for p in sorted(floating)[:10]:
        print("  floating at", p)


if __name__ == "__main__":
    main()
