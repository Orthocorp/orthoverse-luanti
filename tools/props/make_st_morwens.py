#!/usr/bin/env python3
"""Paint the textures and make the sounds for St Morwen's: the church's
fittings (mods/orthoverse_props) and the undead (mods/orthoverse_monsters):
the zombie, the ghoul and the wight.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/props/make_st_morwens.py .

(run from the repository root; ffmpeg is needed for the sounds)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import math, os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "monsters"))
from esp32_mobs import h, jit, paint, HEAD, BODY, ARM, LEG  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
PROPS = os.path.join(ROOT, "mods/orthoverse_props/textures")
PSND = os.path.join(ROOT, "mods/orthoverse_props/sounds")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
MSND = os.path.join(ROOT, "mods/orthoverse_monsters/sounds")
for d in (PROPS, PSND, MON, MSND):
    os.makedirs(d, exist_ok=True)
CLEAR = (0, 0, 0, 0)


def tile(fn, size=16):
    img = Image.new("RGBA", (size, size), CLEAR)
    for v in range(size):
        for u in range(size):
            img.putpixel((u, v), fn(u, v))
    return img


def save(img, folder, name):
    img.save(os.path.join(folder, name))


# --- the church's fittings ---------------------------------------------------
BRONZE = (184, 140, 62)
GOLD = (214, 172, 58)
STONE = (128, 126, 122)


def bell(u, v):
    # bronze, darker at the rim and the crown, a bright streak where light falls
    if v in (0, 1) or v >= 14:
        return jit((96, 66, 30), u, v, 1, 6)
    if u in (4, 5) and 3 <= v <= 12:
        return jit((226, 190, 110), u, v, 2, 6)
    return jit(BRONZE, u, v, 3, 10)


save(tile(bell), PROPS, "orthoverse_props_bell.png")


def font_top(u, v):
    d = math.hypot(u - 7.5, v - 7.5)
    if d < 5.2:
        return jit((70, 110, 150), u, v, 4, 10) if h(u, v, 5) > 0.15 else (190, 220, 240, 255)
    return jit((190, 186, 176), u, v, 6, 8)


save(tile(font_top), PROPS, "orthoverse_props_font_top.png")
save(tile(lambda u, v: jit((190, 186, 176), u, v, 7, 8) if v not in (2, 13) else (150, 146, 138, 255)),
     PROPS, "orthoverse_props_font_side.png")


# The consecrated floor: pale flagstones, a gold cross set in each
def consecrated(u, v):
    if u in (0, 15) or v in (0, 15):
        return (150, 146, 138, 255)
    if (u in (7, 8) and 3 <= v <= 12) or (v in (6, 7) and 4 <= u <= 11):
        return jit(GOLD, u, v, 8, 10)
    return jit((214, 210, 200), u, v, 9, 7)


save(tile(consecrated), PROPS, "orthoverse_props_consecrated.png")

# The ossuary's walls: skulls packed among long bones
SKULL = ["..XXXX..",
         ".XXXXXX.",
         "XXXXXXXX",
         "XKKXXKKX",
         "XKKXXKKX",
         "XXXKKXXX",
         ".XXXXXX.",
         "..XKXK.."]


def bones(u, v):
    su, sv = u % 8, v % 8
    shift = (v // 8) % 2 * 4
    su = (u + shift) % 8
    ch = SKULL[sv][su]
    if ch == "X":
        return jit((224, 214, 186), u, v, 10, 10)
    if ch == "K":
        return (26, 20, 16, 255)
    return jit((150, 136, 108), u, v, 11, 14) if (u + v) % 3 else (60, 50, 40, 255)


save(tile(bones), PROPS, "orthoverse_props_bones.png")


# The crypt gate: black iron bars, see-through
def crypt_gate(u, v):
    if u % 4 in (1, 2) or v in (1, 2, 13, 14):
        return jit((46, 44, 48), u, v, 12, 8)
    if v == 0 and u % 4 == 1:
        return (90, 88, 92, 255)
    return CLEAR


save(tile(crypt_gate), PROPS, "orthoverse_props_crypt_gate.png")


def reliquary(u, v):
    if u in (0, 15) or v in (0, 15):
        return jit((140, 100, 30), u, v, 13, 6)
    if (u, v) in {(4, 5), (11, 5), (7, 9), (8, 9)}:
        return (190, 30, 40, 255)
    if (u + v) % 6 == 0:
        return (250, 226, 140, 255)
    return jit(GOLD, u, v, 14, 12)


save(tile(reliquary), PROPS, "orthoverse_props_reliquary.png")


# A flask of holy water (the item)
def flask(u, v):
    if 6 <= u <= 9 and 1 <= v <= 3:
        return (120, 80, 40, 255)                 # the cork
    if 6 <= u <= 9 and 4 <= v <= 6:
        return (200, 220, 230, 200)               # the neck
    d = math.hypot(u - 7.5, v - 10.5)
    if d < 4.8:
        if d > 3.9:
            return (200, 220, 230, 220)
        return (150, 200, 255, 230) if v > 8 else (220, 236, 250, 160)
    return CLEAR


save(tile(flask), PROPS, "orthoverse_props_holy_water.png")


# A puff of fog: soft, pale, see-through
def fog(u, v):
    d = math.hypot(u - 7.5, v - 7.5) / 7.5
    a = max(0, 1 - d) ** 1.6 * 110 * (0.8 + 0.4 * h(u, v, 15))
    return (220, 224, 230, int(min(255, a)))


save(tile(fog), PROPS, "orthoverse_props_fog.png")


# A headstone's face: weathered grey, with lines cut in it
def headstone(u, v):
    if v in (4, 6, 8) and 4 <= u <= 11 and h(u, v, 16) > 0.2:
        return (70, 70, 68, 255)
    if v == 2 and u in (7, 8) or (u in (7, 8) and v == 1):
        return (80, 80, 78, 255)
    c = jit(STONE, u, v, 17, 12)
    if h(u, v, 18) > 0.85:
        c = jit((90, 110, 70), u, v, 19, 10)       # lichen
    return c


save(tile(headstone), PROPS, "orthoverse_props_headstone.png")

# --- the undead --------------------------------------------------------------


def skin(head, face, torso, arm, leg, pal, seed):
    """A 64x32 character skin. head/torso/arm/leg: fn(part, u, v, w, hh)
    giving a colour for each face of that part; face: 8 rows of 8 letters
    drawn over the head's front with `pal`."""
    img = Image.new("RGBA", (64, 32), CLEAR)
    for part, rects, fn in (("head", HEAD, head), ("body", BODY, torso), ("arm", ARM, arm), ("leg", LEG, leg)):
        for side, rect in rects.items():
            x, y = rect[0], rect[1]
            paint(img, rect, lambda u, v, w, hh, side=side, fn=fn, x=x, y=y: fn(side, u + x, v + y, u, v, w, hh))
    x, y, w, hh = HEAD["front"]
    for v, row in enumerate(face):
        for u, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x + u, y + v), jit(pal[ch], u, v, seed, 6))
    return img


# The zombie: grey-green rotting flesh, sunken black eyes, a torn brown
# shirt, ragged blue breeches
ROT = (110, 128, 96)


def z_head(side, X, Y, u, v, w, hh):
    if side == "top" and h(X, Y, 20) > 0.6:
        return jit((60, 50, 40), X, Y, 21, 8)     # a few clumps of hair
    return jit(ROT, X, Y, 22, 18) if h(X, Y, 23) > 0.2 else jit((80, 60, 60), X, Y, 24, 10)


def z_torso(side, X, Y, u, v, w, hh):
    if h(X, Y, 25) > 0.78:
        return jit(ROT, X, Y, 26, 14)               # holes in the shirt
    return jit((104, 78, 50), X, Y, 27, 14)


def z_arm(side, X, Y, u, v, w, hh):
    if side not in ("top", "bottom") and v < 4 and h(X, Y, 28) > 0.3:
        return jit((104, 78, 50), X, Y, 29, 12)
    return jit(ROT, X, Y, 30, 18)


def z_leg(side, X, Y, u, v, w, hh):
    if side not in ("top", "bottom") and v > 8 and h(X, Y, 31) > 0.4:
        return jit(ROT, X, Y, 32, 16)               # the breeches torn at the shin
    return jit((52, 62, 96), X, Y, 33, 12)


Z_FACE = ["........",
          "........",
          ".KK..KK.",
          ".KR..KK.",
          "........",
          "...MM...",
          "..MTTM..",
          "........"]
save(skin(z_head, Z_FACE, z_torso, z_arm, z_leg,
          {"K": (20, 18, 16, 255), "R": (150, 30, 20, 255), "M": (50, 30, 30, 255), "T": (200, 196, 160, 255)}, 34),
     MON, "orthoverse_monsters_zombie.png")

# The ghoul: hairless, livid grey-blue, red eyes, a long mouth of teeth,
# black claws, a rag about its loins
LIVID = (150, 158, 170)


def gh_head(side, X, Y, u, v, w, hh):
    return jit(LIVID, X, Y, 35, 14)


def gh_torso(side, X, Y, u, v, w, hh):
    if side in ("front", "back", "right", "left") and Y >= 20 + 9:
        return jit((70, 60, 50), X, Y, 36, 10)     # the rag
    if side in ("front", "back") and v in (3, 5, 7) and u % 2 == 0:
        return jit((110, 116, 128), X, Y, 37, 6)   # ribs showing
    return jit(LIVID, X, Y, 38, 14)


def gh_arm(side, X, Y, u, v, w, hh):
    if side == "bottom" or (side not in ("top",) and v >= 10):
        return (30, 26, 26, 255)                    # claws
    return jit(LIVID, X, Y, 39, 14)


def gh_leg(side, X, Y, u, v, w, hh):
    if side not in ("top", "bottom") and v < 2:
        return jit((70, 60, 50), X, Y, 40, 10)
    return jit(LIVID, X, Y, 41, 14)


GH_FACE = ["........",
           "........",
           ".RR..RR.",
           "........",
           "...KK...",
           ".KTTTTK.",
           ".KTKTKK.",
           "..KKKK.."]
save(skin(gh_head, GH_FACE, gh_torso, gh_arm, gh_leg,
          {"R": (240, 40, 30, 255), "K": (30, 20, 22, 255), "T": (230, 226, 200, 255)}, 42),
     MON, "orthoverse_monsters_ghoul.png")

# The wight: a dead lord. A dark skull-like face with cold blue eyes, a
# corroded circlet, rusted mail under a black cloak.
CLOAK = (34, 32, 40)
MAIL = (96, 92, 84)


def w_head(side, X, Y, u, v, w, hh):
    if side not in ("top", "bottom") and v == 1:
        return jit((90, 140, 110), X, Y, 43, 10)   # the circlet, gone green
    if side == "top":
        return jit((40, 36, 40), X, Y, 44, 8)
    return jit((84, 80, 76), X, Y, 45, 12)


def w_torso(side, X, Y, u, v, w, hh):
    if side == "front" and 2 <= u <= 5:
        return jit(MAIL, X, Y, 46, 10) if (u + v) % 2 else jit((70, 50, 36), X, Y, 47, 8)
    return jit(CLOAK, X, Y, 48, 8)


def w_arm(side, X, Y, u, v, w, hh):
    if v >= 10 and side not in ("top",):
        return jit((84, 80, 76), X, Y, 49, 10)    # bony hands
    return jit(CLOAK, X, Y, 50, 8) if v < 6 else jit(MAIL, X, Y, 51, 10)


def w_leg(side, X, Y, u, v, w, hh):
    return jit(CLOAK, X, Y, 52, 8) if v < 8 else jit((50, 46, 44), X, Y, 53, 8)


W_FACE = ["........",
          "........",
          ".KB..BK.",
          ".KK..KK.",
          "...KK...",
          "........",
          "..KTTK..",
          "........"]
save(skin(w_head, W_FACE, w_torso, w_arm, w_leg,
          {"K": (16, 14, 18, 255), "B": (140, 220, 255, 255), "T": (190, 182, 160, 255)}, 54),
     MON, "orthoverse_monsters_wight.png")

# --- sounds ------------------------------------------------------------------
RATE = 44100
rng = np.random.default_rng(23)


def write_ogg(folder, name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(folder, name)], check=True)
    os.unlink(path)


def lowpass(x, a):
    y = np.zeros_like(x)
    acc = 0.0
    for i, s in enumerate(x):
        acc += a * (s - acc)
        y[i] = acc
    return y


# The great bell: a church bell's partials (hum, prime, tierce, quint,
# nominal...), each dying away at its own pace, and the strike
t = np.arange(int(RATE * 5.0)) / RATE
F = 146.0
bellx = np.zeros_like(t)
for ratio, amp, decay in ((0.5, 0.6, 3.5), (1.0, 1.0, 2.6), (1.183, 0.6, 1.8), (1.506, 0.35, 1.4),
                          (2.0, 0.7, 1.2), (2.514, 0.3, 0.8), (2.662, 0.25, 0.7), (3.011, 0.2, 0.5), (4.166, 0.15, 0.3)):
    bellx += amp * np.sin(2 * np.pi * F * ratio * t + ratio) * np.exp(-t / decay)
bellx += rng.standard_normal(len(t)) * np.exp(-t / 0.01) * 0.6
write_ogg(PSND, "orthoverse_props_bell.ogg", bellx * np.minimum(1, t / 0.002), 0.9)

# Holy water: a soft chime and a splash
t = np.arange(int(RATE * 1.0)) / RATE
chime = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, d in ((880, 0.5), (1320, 0.35), (1760, 0.25)))
splash = lowpass(rng.standard_normal(len(t)), 0.3) * np.exp(-t / 0.08)
write_ogg(PSND, "orthoverse_props_bless.ogg", chime * 0.6 + splash, 0.6)

# The zombie's groan: a low buzz through a mouth that opens and shuts
t = np.arange(int(RATE * 1.4)) / RATE
f0 = 80 + 12 * np.sin(2 * np.pi * 0.9 * t)
src = np.sign(np.sin(2 * np.pi * np.cumsum(f0) / RATE)) + rng.standard_normal(len(t)) * 0.3
groan = lowpass(src, 0.04) * np.clip(np.sin(np.pi * t / t[-1]), 0, None) ** 0.7
write_ogg(MSND, "orthoverse_monsters_zombie_groan.ogg", groan, 0.7)

# The ghoul's screech: harsh noise, rising
t = np.arange(int(RATE * 0.7)) / RATE
f0 = 600 + 900 * t
scr = np.sin(2 * np.pi * np.cumsum(f0) / RATE) * (0.5 + rng.standard_normal(len(t)) * 0.5)
write_ogg(MSND, "orthoverse_monsters_ghoul_screech.ogg", scr * np.clip(np.sin(np.pi * t / t[-1]), 0, None), 0.55)

# The wight's breath: a long cold whisper
t = np.arange(int(RATE * 2.0)) / RATE
wh = rng.standard_normal(len(t)) - lowpass(rng.standard_normal(len(t)), 0.05) * 3
wh = wh * (0.6 + 0.4 * np.sin(2 * np.pi * 1.3 * t)) * np.clip(np.sin(np.pi * t / t[-1]), 0, None)
write_ogg(MSND, "orthoverse_monsters_wight_breath.ogg", wh + np.sin(2 * np.pi * 110 * t) * 0.15 * np.clip(np.sin(np.pi * t / t[-1]), 0, None), 0.5)
print("ok")
