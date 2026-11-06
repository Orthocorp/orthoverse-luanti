"""Average colour of every texture in the game's mods, for the map renderer:
blocks players build with (brick, planks, wool, glass and so on) come out in
roughly their real colour on the map and the token cards.

    texture_colours.py MODS_DIR > texture_colours.json

Writes {"texture name without .png": [r, g, b], ...}, from the opaque pixels.
"""
import json
import os
import sys

import numpy as np
from PIL import Image


def main(mods):
    out = {}
    for root, _, files in os.walk(mods):
        if os.path.basename(root) != "textures":
            continue
        for f in files:
            if not f.endswith(".png"):
                continue
            try:
                img = Image.open(os.path.join(root, f)).convert("RGBA")
            except OSError:
                continue
            a = np.asarray(img).reshape(-1, 4)
            px = a[a[:, 3] > 128, :3]
            if not len(px):
                continue
            out[f[:-4]] = [int(round(v)) for v in px.mean(axis=0)]
    json.dump(out, sys.stdout, sort_keys=True, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
