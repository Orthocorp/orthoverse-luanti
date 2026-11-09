#!/usr/bin/env python3
"""Paint the textures for The Fallen Star: the ship's blocks
(mods/orthoverse_scifi), the locker (mods/orthoverse_loot) and the robots
(mods/orthoverse_monsters), and synthesise the ship's sounds.

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow numpy
    /tmp/venv/bin/python tools/scifi/make_textures.py .

(run from the repository root; ffmpeg is needed for the sounds)

By Keir Finlow-Bates; the textures and sounds are CC BY-SA 3.0, the code MIT."""
import os, subprocess, sys, tempfile, wave
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "monsters"))
from esp32_mobs import h, jit, paint, HEAD, BODY, ARM, LEG  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SCIFI = os.path.join(ROOT, "mods/orthoverse_scifi/textures")
LOOT = os.path.join(ROOT, "mods/orthoverse_loot/textures")
MON = os.path.join(ROOT, "mods/orthoverse_monsters/textures")
SOUNDS = os.path.join(ROOT, "mods/orthoverse_scifi/sounds")
for d in (SCIFI, LOOT, MON, SOUNDS):
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


# --- the ship's blocks ---------------------------------------------------------
STEEL = (96, 102, 112)
STEEL_D = (66, 70, 78)
STEEL_L = (132, 138, 148)


def hull(u, v, s=1, scorch=0.0):
    seam = u in (0, 15) or v in (0, 7, 8, 15) and not (v in (7, 8) and 4 < u < 11)
    rivet = (u in (2, 13) and v in (2, 5, 10, 13))
    c = STEEL_D if seam else (STEEL_L if rivet else STEEL)
    c = jit(c, u, v, s, 6)
    if scorch:
        k = h(u // 2, v // 2, s + 9)
        if k < scorch:
            f = 0.35 + 0.4 * k / max(scorch, 0.01)
            c = tuple(int(x * f) for x in c[:3]) + (255,)
    return c


save(tile(lambda u, v: hull(u, v)), SCIFI, "orthoverse_scifi_hull.png")
save(tile(lambda u, v: hull(u, v, 2, 0.55)), SCIFI, "orthoverse_scifi_hull_scorched.png")


def deck(u, v):
    if u % 4 == 0 or v % 4 == 0:
        return jit((84, 88, 96), u, v, 3, 5)
    return jit((34, 36, 40), u, v, 4, 4)


save(tile(deck), SCIFI, "orthoverse_scifi_deck.png")


def panel_light(u, v):
    if 1 <= v <= 14 and 5 <= u <= 10:
        return (210, 240, 255, 255) if 6 <= u <= 9 else (150, 200, 230, 255)
    return hull(u, v, 5)


save(tile(panel_light), SCIFI, "orthoverse_scifi_panel_light.png")


def glass(u, v):
    if u in (0, 15) or v in (0, 15):
        return (120, 140, 160, 255)
    if (u + v) % 11 == 0 and 3 < u < 13:
        return (220, 240, 255, 150)
    return (140, 190, 230, 70)


save(tile(glass), SCIFI, "orthoverse_scifi_glass.png")


def crate(u, v, top=False):
    if u in (0, 15) or v in (0, 15):
        return jit((60, 64, 44), u, v, 6, 5)
    if not top and (u == v or u == 15 - v):
        return jit((70, 74, 50), u, v, 7, 4)
    if not top and 6 <= v <= 9 and 3 <= u <= 12 and (u + v) % 2 == 0:
        return (220, 150, 40, 255)
    return jit((96, 104, 66), u, v, 8, 6)


save(tile(crate), SCIFI, "orthoverse_scifi_crate.png")
save(tile(lambda u, v: crate(u, v, True)), SCIFI, "orthoverse_scifi_crate_top.png")


def console(u, v):
    if 2 <= u <= 13 and 2 <= v <= 9:
        if v in (4, 6, 8) and h(u, v, 11) > 0.35:
            return (80, 255, 160, 255)
        return (10, 40, 30, 255)
    if v >= 11 and u % 3 == 1 and v % 2 == 1:
        return [(240, 60, 50, 255), (250, 200, 40, 255), (60, 160, 250, 255)][(u // 3) % 3]
    return hull(u, v, 12)


save(tile(console), SCIFI, "orthoverse_scifi_console.png")


def reactor(u, v):
    d = abs(u - 7.5) / 8
    core = 1 - d
    k = h(u, v // 2, 13)
    g = int(150 + 105 * core * (0.7 + 0.3 * k))
    return (int(60 * core), g, int(200 + 55 * core), 255)


save(tile(reactor), SCIFI, "orthoverse_scifi_reactor.png")


def relay(on):
    def fn(u, v):
        if 4 <= u <= 11 and 3 <= v <= 12:
            lever_v = 4 if on else 11
            if 7 <= u <= 8 and min(lever_v, 8) <= v <= max(lever_v, 8):
                return (220, 220, 220, 255)
            if 6 <= u <= 9 and v == lever_v:
                return (240, 60, 40, 255) if not on else (60, 240, 90, 255)
            return (30, 32, 36, 255)
        if v == 14 and 5 <= u <= 10:
            return (60, 240, 90, 255) if on else (120, 20, 20, 255)
        return jit((180, 150, 40), u, v, 14, 6) if (u + v) % 6 < 3 and (u < 2 or u > 13) else hull(u, v, 15)
    return fn


save(tile(relay(False)), SCIFI, "orthoverse_scifi_relay_off.png")
save(tile(relay(True)), SCIFI, "orthoverse_scifi_relay_on.png")


def plate(live):
    def fn(u, v):
        edge = u in (0, 15) or v in (0, 15)
        if edge:
            return (40, 120, 220, 255) if not live else (200, 240, 255, 255)
        if live:
            k = h(u, v, 16)
            zig = abs((u * 3 + v * 5) % 9 - 4) < 1
            return (230, 250, 255, 255) if zig or k > 0.85 else (70, 160, 255, 255)
        return deck(u, v)
    return fn


save(tile(plate(False)), SCIFI, "orthoverse_scifi_plate.png")
save(tile(plate(True)), SCIFI, "orthoverse_scifi_plate_live.png")


def medbay(u, v):
    if (6 <= u <= 9 and 3 <= v <= 12) or (3 <= u <= 12 and 6 <= v <= 9):
        return (210, 40, 40, 255)
    if u in (0, 15) or v in (0, 15):
        return (170, 176, 182, 255)
    return jit((228, 232, 236), u, v, 17, 4)


save(tile(medbay), SCIFI, "orthoverse_scifi_medbay.png")


def door(colour):
    def fn(u, v):
        if u in (0, 15):
            return jit(STEEL_D, u, v, 18, 4)
        if 6 <= v <= 9 and 5 <= u <= 10:
            return colour + (255,) if (u + v) % 2 else tuple(int(x * 0.7) for x in colour) + (255,)
        if u == 7 or u == 8:
            return (40, 42, 46, 255)
        return jit(STEEL, u, v, 19, 5)
    return fn


save(tile(door((60, 120, 240))), SCIFI, "orthoverse_scifi_door_blue.png")
save(tile(door((220, 50, 40))), SCIFI, "orthoverse_scifi_door_red.png")


def blast(u, v):
    if v in (0, 15) or u in (0, 15):
        return jit(STEEL_D, u, v, 20, 4)
    if 2 <= v <= 4 or 11 <= v <= 13:
        return (230, 190, 30, 255) if (u + v) % 6 < 3 else (30, 30, 30, 255)
    return jit((110, 114, 120), u, v, 21, 6)


save(tile(blast), SCIFI, "orthoverse_scifi_blast_door.png")


def locker_card(u, v):
    if u in (0, 15) or v in (0, 15):
        return jit(STEEL_D, u, v, 22, 4)
    if 3 <= u <= 12 and v in (3, 5, 7):
        return (40, 44, 50, 255)
    if 6 <= u <= 9 and 10 <= v <= 12:
        return (240, 220, 80, 255) if v == 11 else (90, 92, 96, 255)
    return jit((140, 146, 154), u, v, 23, 5)


save(tile(locker_card), SCIFI, "orthoverse_scifi_locker.png")
save(tile(locker_card), LOOT, "orthoverse_loot_locker_front.png")
save(tile(lambda u, v: jit((140, 146, 154), u, v, 24, 5) if 0 < u < 15 and 0 < v < 15 else jit(STEEL_D, u, v, 25, 4)),
     LOOT, "orthoverse_loot_locker_side.png")


def card(colour):
    def fn(u, v):
        if 2 <= u <= 13 and 4 <= v <= 11:
            if u in (2, 13) or v in (4, 11):
                return tuple(int(x * 0.6) for x in colour) + (255,)
            if 4 <= u <= 6 and 6 <= v <= 8:
                return (230, 200, 60, 255)
            if 8 <= u <= 12 and v in (6, 8):
                return (240, 240, 240, 255)
            return colour + (255,)
        return CLEAR
    return fn


save(tile(card((60, 120, 240))), SCIFI, "orthoverse_scifi_card_blue.png")
save(tile(card((220, 50, 40))), SCIFI, "orthoverse_scifi_card_red.png")


def black_box(u, v):
    if u in (0, 15) or v in (0, 15):
        return (240, 120, 20, 255)
    if 5 <= v <= 10 and 3 <= u <= 12 and (u - 3) % 3 != 2:
        return (240, 120, 20, 255) if v in (5, 10) else (30, 30, 30, 255)
    return jit((40, 40, 44), u, v, 26, 4)


save(tile(black_box), SCIFI, "orthoverse_scifi_black_box.png")

# --- the robots -------------------------------------------------------------
def skin(base, dark, light, eye, seed, visor=True, chest=None):
    img = Image.new("RGBA", (64, 32), CLEAR)

    def metal(u, v, w, hh, s=seed):
        c = dark if (u == 0 or v == 0 or u == w - 1 or v == hh - 1) else base
        if h(u, v, s) > 0.92:
            c = light
        return jit(c, u, v, s + 1, 5)

    for part in (HEAD, BODY, ARM, LEG):
        for face, rect in part.items():
            paint(img, rect, lambda u, v, w, hh, f=face: metal(u, v, w, hh, seed + sum(map(ord, f)) % 97))
    x, y, w, hh = HEAD["front"]
    for u in range(1, 7):
        for v in (3, 4):
            img.putpixel((x + u, y + v), eye if visor else (20, 20, 24, 255))
    if not visor:
        img.putpixel((x + 2, y + 3), eye)
        img.putpixel((x + 5, y + 3), eye)
    x, y, w, hh = BODY["front"]
    if chest:
        for u in range(2, 6):
            for v in range(2, 6):
                img.putpixel((x + u, y + v), chest if (u + v) % 2 == 0 else tuple(int(c * 0.6) for c in chest[:3]) + (255,))
    for u in range(w):
        img.putpixel((x + u, y + 8), dark)
    return img


save(skin((150, 156, 166, 255), (70, 74, 82, 255), (210, 214, 220, 255), (255, 60, 40, 255), 300,
          chest=(240, 190, 30, 255)), MON, "orthoverse_monsters_secbot.png")
save(skin((60, 62, 70, 255), (30, 30, 36, 255), (120, 124, 134, 255), (255, 140, 30, 255), 400, visor=False,
          chest=(220, 50, 40, 255)), MON, "orthoverse_monsters_warden.png")


def drone(u, v):
    d = ((u - 7.5) ** 2 + (v - 7.5) ** 2) ** 0.5
    if d < 2.2:
        return (255, 80, 60, 255)
    if d < 5.5:
        return jit((120, 126, 136), u, v, 27, 8)
    if 5.5 <= d < 7.5 and (u in (1, 2, 13, 14) or v in (1, 2, 13, 14)):
        return (60, 64, 72, 255)
    return CLEAR


save(tile(drone), MON, "orthoverse_monsters_drone.png")


def turret(face):
    def fn(u, v):
        if face == "front" and 5 <= u <= 10 and 5 <= v <= 10:
            d = ((u - 7.5) ** 2 + (v - 7.5) ** 2) ** 0.5
            return (255, 60, 40, 255) if d < 1.8 else (20, 20, 24, 255)
        if face == "top":
            return (230, 190, 30, 255) if (u + v) % 6 < 3 and (u < 2 or u > 13 or v < 2 or v > 13) else jit(STEEL, u, v, 28, 5)
        return hull(u, v, 29)
    return fn


for f in ("front", "side", "top"):
    save(tile(turret(f)), MON, "orthoverse_monsters_turret_%s.png" % f)


def bolt(u, v):
    d = ((u - 7.5) ** 2 + (v - 7.5) ** 2) ** 0.5
    if d < 2:
        return (255, 255, 255, 255)
    if d < 4:
        return (255, 90, 60, 220)
    if d < 6:
        return (255, 60, 40, 90)
    return CLEAR


save(tile(bolt), MON, "orthoverse_monsters_bolt.png")

# --- sounds -----------------------------------------------------------------
RATE = 44100
rng = np.random.default_rng(11)


def write_ogg(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) or 1) * gain
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(SOUNDS, name)], check=True)
    os.unlink(path)


t = np.arange(int(RATE * 0.35)) / RATE
crackle = rng.standard_normal(len(t)) * (rng.random(len(t)) > 0.7)
buzz = np.sign(np.sin(2 * np.pi * 120 * t)) * 0.4
write_ogg("orthoverse_scifi_zap.ogg", (crackle + buzz) * np.exp(-t / 0.12), 0.7)
t = np.arange(int(RATE * 0.25)) / RATE
write_ogg("orthoverse_scifi_spark.ogg", rng.standard_normal(len(t)) * (rng.random(len(t)) > 0.9) * np.exp(-t / 0.06), 0.4)
t = np.arange(int(RATE * 0.9)) / RATE
f = 60 + 40 * t
hiss = np.convolve(rng.standard_normal(len(t)), np.ones(30) / 30, "same")
write_ogg("orthoverse_scifi_door.ogg", (np.sin(2 * np.pi * np.cumsum(f) / RATE) * 0.7 + hiss * 2) * np.minimum(1, t / 0.05) * np.exp(-t / 0.5), 0.8)
t = np.arange(int(RATE * 0.3)) / RATE
write_ogg("orthoverse_scifi_relay.ogg", np.sin(2 * np.pi * 900 * t) * np.exp(-t / 0.03) + rng.standard_normal(len(t)) * np.exp(-t / 0.01) * 0.5, 0.6)
t = np.arange(int(RATE * 0.6)) / RATE
write_ogg("orthoverse_scifi_heal.ogg", np.sin(2 * np.pi * (500 + 400 * t) * t) * np.exp(-t / 0.3), 0.5)
t = np.arange(int(RATE * 0.25)) / RATE
write_ogg("orthoverse_monsters_bolt.ogg", np.sin(2 * np.pi * np.cumsum(1400 - 3000 * t) / RATE) * np.exp(-t / 0.08), 0.6)
os.replace(os.path.join(SOUNDS, "orthoverse_monsters_bolt.ogg"), os.path.join(ROOT, "mods/orthoverse_monsters/sounds/orthoverse_monsters_bolt.ogg"))
print("ok")
