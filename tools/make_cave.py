"""A cave wall from the game's own textures, for the map page's background:
stone with ores, a few torches, lit block by block as Luanti lights a cave
(each block one light level dimmer per step from a torch). The picture tiles
seamlessly: the torches' light wraps round its edges.

    make_cave.py MTG_DEFAULT_TEXTURES OUT.png
"""
import random
import sys

from PIL import Image

W, H = 32, 24            # blocks
# Ore veins: (ore, how many veins, blocks per vein)
VEINS = [("coal", 9, 6), ("iron", 5, 4), ("copper", 4, 4), ("tin", 3, 3),
         ("gold", 3, 3), ("mese", 2, 2), ("diamond", 2, 2)]
TORCHES = [(4, 5), (14, 3), (25, 7), (9, 16), (20, 14), (29, 20), (2, 21)]
TORCH_LIGHT = 13        # Luanti: default:torch gives light 12-13


def tex(folder, name):
    return Image.open(f"{folder}/default_{name}.png").convert("RGBA")


def main(folder, out):
    rng = random.Random(1987)
    stone = tex(folder, "stone")
    ore_at = {}
    for ore, veins, size in VEINS:
        for _ in range(veins):
            x, y = rng.randrange(W), rng.randrange(H)
            for _ in range(size):
                if (x, y) not in TORCHES:
                    ore_at[(x, y)] = ore
                x = (x + rng.choice((-1, 0, 1))) % W
                y = (y + rng.choice((-1, 0, 1))) % H
    img = Image.new("RGBA", (W * 16, H * 16))
    for by in range(H):
        for bx in range(W):
            block = stone.copy()
            if (bx, by) in ore_at:
                block.alpha_composite(tex(folder, "mineral_" + ore_at[(bx, by)]))
            img.paste(block, (bx * 16, by * 16))
    torch = tex(folder, "torch_on_floor")
    for (tx, ty) in TORCHES:
        img.alpha_composite(torch, (tx * 16, ty * 16))
    # Light: per block, the brightest torch's level minus the steps to it
    # (wrapping round, so the picture tiles), as a share of full daylight
    px = img.load()
    for by in range(H):
        for bx in range(W):
            level = 1
            for (tx, ty) in TORCHES:
                dx = min(abs(bx - tx), W - abs(bx - tx))
                dy = min(abs(by - ty), H - abs(by - ty))
                level = max(level, TORCH_LIGHT - dx - dy)
            # Luanti's light curve, roughly: each level ~80% of the one above
            f = 0.8 ** (14 - level)
            warm = (1.0, 0.86 + 0.1 * f, 0.62 + 0.3 * f)   # torchlight is warm
            for y in range(by * 16, by * 16 + 16):
                for x in range(bx * 16, bx * 16 + 16):
                    if (bx, by) in TORCHES and px[x, y][3] and \
                            torch.getpixel((x - bx * 16, y - by * 16))[3]:
                        continue            # the torch itself is not shaded
                    r, g, b, a = px[x, y]
                    px[x, y] = (round(r * f * warm[0]), round(g * f * warm[1]),
                                round(b * f * warm[2]), 255)
    img.convert("RGB").save(out, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
