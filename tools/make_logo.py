"""The Orthoverse logo and site icon, drawn from the Midnight font: every pixel
of the 8 x 8 letters becomes a gold block with a bevel, with a bronze 3D
extrusion and a dark outline, like a title in a block game.

    make_logo.py FONT.ttf OUT_DIR

Writes OUT_DIR/logo.png (show it at whole multiples of its size, with
image-rendering: pixelated) and OUT_DIR/icon.png (64 x 64).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FACE_TOP, FACE_BOTTOM = (255, 228, 122), (222, 150, 40)
HIGHLIGHT, SHADE = (255, 246, 196), (170, 104, 22)
SIDE_TOP, SIDE_BOTTOM = (120, 72, 22), (70, 40, 12)
OUTLINE = (28, 18, 8)


def bitmap(font, text):
    """The text's pixels, as a set of (x, y), and its size."""
    w = len(text) * 8
    img = Image.new("1", (w, 8), 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    d.text((0, 0), text, font=font, fill=1)
    return {(x, y) for x in range(w) for y in range(8) if img.getpixel((x, y))}, w


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_blocks(img, pixels, ox, oy, block, depth, height):
    """Gold letters made of blocks, extruded `depth` blocks down and right."""
    px = img.load()
    def fill(x0, y0, colour):
        for y in range(y0, y0 + block):
            for x in range(x0, x0 + block):
                px[x, y] = colour + (255,)
    # Outline: every block next to the letters or their extrusion
    solid = {(x + d, y + d) for (x, y) in pixels for d in range(depth + 1)}
    for (x, y) in solid:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                fill(ox + (x + dx) * block, oy + (y + dy) * block, OUTLINE)
    # Extrusion, back to front
    for d in range(depth, 0, -1):
        for (x, y) in pixels:
            t = (y + d) / (height + depth)
            fill(ox + (x + d) * block, oy + (y + d) * block, lerp(SIDE_TOP, SIDE_BOTTOM, t))
    # Faces: a vertical gold gradient, each block bevelled
    for (x, y) in pixels:
        x0, y0 = ox + x * block, oy + y * block
        fill(x0, y0, lerp(FACE_TOP, FACE_BOTTOM, y / max(1, height - 1)))
        b = max(1, block // 6)
        for i in range(block):
            for j in range(b):
                if (x, y - 1) not in pixels:
                    px[x0 + i, y0 + j] = HIGHLIGHT + (255,)
                if (x - 1, y) not in pixels:
                    px[x0 + j, y0 + i] = HIGHLIGHT + (255,)
                if (x, y + 1) not in pixels:
                    px[x0 + i, y0 + block - 1 - j] = SHADE + (255,)
                if (x + 1, y) not in pixels:
                    px[x0 + block - 1 - j, y0 + i] = SHADE + (255,)


def logo(font, out):
    block, depth = 6, 2
    big, bw = bitmap(font, "ORTHOVERSE")
    small, sw = bitmap(font, "THE")
    sblock = block // 2
    pad = block * 2
    width = bw * block + (depth + 2) * block + pad * 2
    top_h = 8 * sblock + (depth + 2) * sblock
    height = top_h + block + 8 * block + (depth + 2) * block + pad * 2
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_blocks(img, small, (width - sw * sblock) // 2, pad, sblock, depth, 8)
    draw_blocks(img, big, pad + block, pad + top_h + block, block, depth, 8)
    img = img.crop(img.getbbox())
    img.save(os.path.join(out, "logo.png"), optimize=True)
    return img.size


def icon(font, out):
    o, w = bitmap(font, "O")
    img = Image.new("RGBA", (64, 64), (20, 26, 51, 255))
    draw_blocks(img, o, 7, 7, 5, 1, 8)
    img.save(os.path.join(out, "icon.png"), optimize=True)


if __name__ == "__main__":
    f = ImageFont.truetype(sys.argv[1], 8)
    os.makedirs(sys.argv[2], exist_ok=True)
    print("logo", logo(f, sys.argv[2]))
    icon(f, sys.argv[2])
