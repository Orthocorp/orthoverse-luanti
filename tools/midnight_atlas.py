"""The Midnight font as two 128 x 128 pictures of its 256 Latin-1 characters
(16 x 16 cells of 8 x 8), for drawing text on the game's screen: Luanti cannot
load a font for HUD text, but it can piece text together from a picture.

    midnight_atlas.py FONT.ttf OUT_DIR

The font has no accented letters (Latin-1 above 160 is mostly empty boxes), so
those are drawn as the plain letter, with the accent added above lower-case
ones (Finnish henge names have a and o with diaeresis).

Writes OUT_DIR/orthoverse_midnight.png (white letters) and
OUT_DIR/orthoverse_midnight_shadow.png (the same, dark, for a drop shadow).
"""
import os
import sys
import unicodedata

from PIL import Image, ImageDraw, ImageFont


# Accent pixels on the top row of a lower-case letter (columns 0-7)
ACCENTS = {
    "\u0308": (2, 3, 5, 6),     # diaeresis
    "\u0301": (4, 5),           # acute
    "\u0300": (2, 3),           # grave
    "\u0302": (3, 4),           # circumflex
    "\u030a": (3, 4),           # ring
    "\u0303": (2, 3, 4, 5),     # tilde
}


def main(font_path, out):
    font = ImageFont.truetype(font_path, 8)
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.fontmode = "1"          # no smoothing: whole pixels only
    white = (255, 255, 255, 255)
    for code in list(range(32, 127)) + [0xA3]:          # ASCII and the pound sign
        draw.text(((code % 16) * 8, (code // 16) * 8), chr(code), font=font, fill=white)
    for code in range(0xC0, 0x100):
        parts = unicodedata.normalize("NFD", chr(code))
        base, marks = parts[0], parts[1:]
        if len(parts) < 2 or not ("a" <= base.lower() <= "z"):
            continue
        x, y = (code % 16) * 8, (code // 16) * 8
        draw.text((x, y), base, font=font, fill=white)
        if base.islower():
            for mark in marks:
                for u in ACCENTS.get(mark, ()):
                    draw.point((x + u, y), fill=white)
    os.makedirs(out, exist_ok=True)
    img.save(os.path.join(out, "orthoverse_midnight.png"), optimize=True)
    alpha = img.getchannel("A")
    shadow = Image.new("RGBA", img.size, (20, 16, 10, 0))
    shadow.putalpha(alpha.point(lambda a: 190 if a else 0))
    shadow.save(os.path.join(out, "orthoverse_midnight_shadow.png"), optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
