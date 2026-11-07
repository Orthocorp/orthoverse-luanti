"""A small pixel-art computer, its screen showing an Orthoverse land (sky,
hills, a castle with a gold flag), with a keyboard and mouse: for the page
that tells phone players the game needs a computer.

    make_desktop_art.py OUT.png

Drawn at 1 pixel per art pixel; show it enlarged with image-rendering:
pixelated.
"""
import sys

from PIL import Image, ImageDraw

W, H = 64, 52
OUTLINE = (28, 18, 8)
FRAME, FRAME_HI, FRAME_LO = (86, 92, 112), (128, 136, 160), (56, 60, 76)
SKY_TOP, SKY_LOW = (98, 160, 222), (150, 200, 240)
GRASS, GRASS_LO = (93, 155, 58), (60, 110, 36)
DIRT = (121, 85, 58)
STONE, STONE_LO = (122, 118, 112), (88, 84, 80)
GOLD = (245, 198, 74)
WATER = (40, 90, 190)
KEY, KEY_LO = (176, 180, 196), (120, 124, 140)


def main(out):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Monitor: outline, bevelled frame, screen
    d.rectangle((2, 0, 61, 37), fill=OUTLINE)
    d.rectangle((3, 1, 60, 36), fill=FRAME)
    d.line((3, 1, 60, 1), fill=FRAME_HI); d.line((3, 1, 3, 36), fill=FRAME_HI)
    d.line((3, 36, 60, 36), fill=FRAME_LO); d.line((60, 1, 60, 36), fill=FRAME_LO)
    sx0, sy0, sx1, sy1 = 6, 4, 57, 32
    d.rectangle((sx0 - 1, sy0 - 1, sx1 + 1, sy1 + 1), fill=OUTLINE)
    for y in range(sy0, sy1 + 1):   # sky, lighter towards the horizon
        t = (y - sy0) / (sy1 - sy0)
        c = tuple(round(SKY_TOP[i] + (SKY_LOW[i] - SKY_TOP[i]) * t) for i in range(3))
        d.line((sx0, y, sx1, y), fill=c)
    d.rectangle((48, 7, 51, 10), fill=GOLD)                      # sun
    # Hills
    for x in range(sx0, sx1 + 1):
        h = 24 + (2 if 10 < x < 22 else 0) + (1 if 40 < x < 50 else 0)
        d.line((x, h, x, sy1), fill=GRASS)
        d.point((x, h), fill=GRASS_LO if x % 3 == 0 else GRASS)
    d.rectangle((sx0, 29, sx1, sy1), fill=DIRT)
    d.line((sx0, 28, sx1, 28), fill=GRASS_LO)
    d.rectangle((38, 26, 45, 27), fill=WATER)                    # a lake
    # Castle: two towers with battlements, a wall, a gate, a gold flag
    d.rectangle((20, 15, 35, 25), fill=STONE)
    for x in range(20, 36, 2):
        d.point((x, 14), fill=STONE)
    d.rectangle((17, 11, 21, 25), fill=STONE_LO); d.rectangle((34, 11, 38, 25), fill=STONE_LO)
    for x in (17, 19, 21, 34, 36, 38):
        d.point((x, 10), fill=STONE_LO)
    d.rectangle((26, 20, 29, 25), fill=OUTLINE)                  # gate
    d.line((36, 4, 36, 9), fill=OUTLINE); d.rectangle((37, 4, 40, 6), fill=GOLD)
    # Stand
    d.rectangle((27, 37, 36, 40), fill=OUTLINE); d.rectangle((28, 37, 35, 39), fill=FRAME_LO)
    d.rectangle((22, 40, 41, 42), fill=OUTLINE); d.rectangle((23, 40, 40, 41), fill=FRAME)
    # Keyboard: rows of keys
    d.rectangle((4, 44, 49, 51), fill=OUTLINE)
    d.rectangle((5, 45, 48, 50), fill=KEY_LO)
    for row, y in enumerate((46, 48)):
        for x in range(6 + row, 47, 3):
            d.rectangle((x, y, x + 1, y), fill=KEY)
    d.rectangle((14, 50, 38, 50), fill=KEY)                      # space bar
    # Mouse
    d.rectangle((54, 44, 60, 51), fill=OUTLINE)
    d.rectangle((55, 45, 59, 50), fill=KEY)
    d.line((57, 45, 57, 47), fill=KEY_LO)
    img.save(out, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
