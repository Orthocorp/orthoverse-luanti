"""Cut the crest sheet into one small PNG per crest, for the game's land
display (mods/orthoverse_landhud), which shows the crest of the land you are
on without sending the whole 1.9 MB sheet to every player.

    split_crests.py HERALDRY_DIR OUT_DIR

Writes OUT_DIR/<n>.png for every crest in heraldry.json. The server image runs
this at build time; for a server run straight from the repository, run it with
OUT_DIR mods/orthoverse_landhud/crests.
"""
import json
import os
import sys

from PIL import Image


def main(heraldry, out):
    with open(os.path.join(heraldry, "heraldry.json"), encoding="utf-8") as f:
        meta = json.load(f)
    sheet = Image.open(os.path.join(heraldry, "escutcheons.png")).convert("RGBA")
    w, h, cols = meta["width"], meta["height"], meta["columns"]
    missing = set(meta["missing"])
    os.makedirs(out, exist_ok=True)
    n = 0
    for i in range(meta["count"]):
        if i in missing:
            continue
        x, y = (i % cols) * w, (i // cols) * h
        sheet.crop((x, y, x + w, y + h)).save(os.path.join(out, "%d.png" % i), optimize=True)
        n += 1
    print("%d crests written to %s" % (n, out))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
