#!/usr/bin/env python3
"""Hero portraits in a "heroic close-up" style (pixel art, 64x64): the head in
three-quarter view turned to the right, a warm key light from the front right,
cool shadows, a rim light in the class colour on the back edge, a tight crop.

Writes assets/sprites/portraits/:
  hero_<race>_<class>.png            neutral (transparent background)
  hero_<race>_<class>_<expr>.png     blink, glance, hurt, wounded, fierce
  bg_<class>.png                     class background (glow, rays, fog, runes)
AnimatedPortrait (HUD) layers: background → class particles → hero → flash.
Run:  python3 tools/gen_hero_portraits.py
"""
from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw

import gen_placeholders as gp

S = 64
OUT = "sprites/portraits/"
EXPRS = ("neutral", "blink", "glance", "hurt", "wounded", "fierce")
LIGHT = np.array([0.62, -0.5, 0.6])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
FULL = (255, 255, 255, 255)
LEVELS = (1.32, 1.12, 0.9, 0.68, 0.5)
CUTS = (0.8, 0.58, 0.32, 0.05)


def c4(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


def clamp(v):
    return max(0, min(255, int(v)))


def tone(c, f, shadow=(40, 50, 90), warm=False):
    """Light (f > 1) or shade a colour; shadows lean to `shadow` (cool), skin
    shadows also warm up a little (subsurface)."""
    r, g, b = c[0] * f, c[1] * f, c[2] * f
    if f < 1.0:
        k = (1.0 - f) * 0.45
        r, g, b = r + (shadow[0] - r) * k, g + (shadow[1] - g) * k, b + (shadow[2] - b) * k
        if warm:
            r += (1.0 - f) * 40
    else:
        k = (f - 1.0) * 0.5
        r, g, b = r + (255 - r) * k * 0.4, g + (230 - g) * k * 0.3, b + (190 - b) * k * 0.2
    return (clamp(r), clamp(g), clamp(b), 255)


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def mask(fn):
    m = new()
    fn(ImageDraw.Draw(m))
    return m


def lit(im, m, base, cx, cy, rx, ry, warm=False, shadow=(40, 50, 90), flat=0.0, bias=0.0):
    """Fills mask `m` with `base` lit like an ellipsoid centred at (cx, cy):
    5 tones with dithered borders. flat > 0 flattens the volume (cloth, metal plates)."""
    px = im.load()
    mp = m.load()
    for y in range(S):
        for x in range(S):
            if mp[x, y][3] == 0:
                continue
            nx, ny = (x - cx) / rx, (y - cy) / ry
            r2 = nx * nx + ny * ny
            nz = math.sqrt(max(0.0, 1.0 - min(r2, 1.0))) + flat
            n = np.array([nx, ny, nz])
            d = float(np.dot(n / (np.linalg.norm(n) + 1e-9), LIGHT)) + bias
            i = 0
            while i < len(CUTS) and d <= CUTS[i]:
                i += 1
            if 0 < i and d > CUTS[i - 1] - 0.05 and (x + y) % 2 == 0:
                i -= 1
            px[x, y] = tone(base, LEVELS[i], shadow, warm)


def put(im, x, y, c, a=1.0):
    if not (0 <= x < S and 0 <= y < S):
        return
    px = im.load()
    r, g, b, al = px[x, y]
    if al == 0 and a < 1.0:
        px[x, y] = c4(c)
        return
    px[x, y] = (clamp(r + (c[0] - r) * a), clamp(g + (c[1] - g) * a), clamp(b + (c[2] - b) * a), max(al, 255))


def rim(im, color, strength=0.85):
    """Rim light on the back (left) edge of the silhouette and the top."""
    a = np.array(im)[:, :, 3] > 0
    px = im.load()
    for y in range(S):
        for x in range(S):
            if not a[y, x]:
                continue
            left = x == 0 or not a[y, x - 1]
            left2 = x > 1 and not a[y, x - 2]
            top = y > 0 and not a[y - 1, x] and x < 34
            if left:
                put(im, x, y, color, strength)
            elif left2:
                put(im, x, y, color, strength * 0.45)
            elif top:
                put(im, x, y, color, strength * 0.5)


# ------------------------------------------------------------------ geometry
HEAD = [(17, 23), (18, 15), (22, 9), (29, 5), (37, 5), (43, 9), (46, 15), (47, 21), (46, 25), (45, 27), (46, 29), (50, 35),
        (48, 37), (46, 38), (46, 40), (45, 43), (44, 47), (40, 51), (33, 50), (24, 43), (20, 37), (18, 30)]
HC = (33, 26)  # ellipsoid centre for lighting
EYE_NEAR = (31, 27)
EYE_FAR = (41, 27)


def head_mask(slim=False, wide=False):
    pts = HEAD
    if slim:
        pts = [(x - (1 if x > 40 and y > 38 else 0), y) for x, y in pts]
    if wide:
        pts = [(x + (1 if x > 40 and y > 36 else 0), y + (1 if y > 46 else 0)) for x, y in pts]
    return mask(lambda d: d.polygon(pts, fill=FULL))


# --------------------------------------------------------------------- races
RACES = {
    "human": dict(skin=(226, 176, 138), hair=(92, 58, 32), style="short", eyes=(70, 120, 175)),
    "dwarf": dict(skin=(212, 152, 112), hair=(150, 76, 36), style="short", eyes=(110, 80, 40), beard=(160, 82, 38), wide=True,
                  heavy=True),
    "elf": dict(skin=(240, 214, 184), hair=(236, 222, 160), style="long", eyes=(70, 190, 140), ears="long", slim=True),
    "orc": dict(skin=(108, 158, 80), hair=(30, 30, 34), style="mohawk", eyes=(230, 70, 40), tusks=True, heavy=True, scar=True,
                wide=True),
}

# ------------------------------------------------------------------- classes
CLASSES = {
    "warrior": dict(rim=(255, 150, 70), shadow=(60, 40, 50), glow=(255, 120, 40), bg=(48, 22, 16)),
    "paladin": dict(rim=(255, 230, 150), shadow=(60, 60, 90), glow=(255, 215, 120), bg=(40, 34, 24)),
    "rogue": dict(rim=(110, 230, 190), shadow=(20, 50, 50), glow=(60, 180, 150), bg=(12, 26, 26)),
    "mage": dict(rim=(190, 130, 255), shadow=(50, 30, 90), glow=(160, 90, 255), bg=(24, 14, 44)),
}


def draw_body(im, cls, cfg, tunic):
    """Neck and shoulders (near shoulder big, bottom left; far one cut by the frame)."""
    sh = cfg["shadow"]
    neck = mask(lambda d: d.polygon([(25, 42), (40, 46), (41, 56), (27, 58)], fill=FULL))
    return neck


def figure(race_id, cls_id, expr):
    r = RACES[race_id]
    cfg = CLASSES[cls_id]
    sh = cfg["shadow"]
    skin = r["skin"]
    hair = r["hair"]
    im = new()
    # ---- torso / shoulders (cloth base, class gear drawn later)
    cloth = {"warrior": (120, 40, 36), "paladin": (220, 216, 205), "rogue": (44, 70, 50), "mage": (66, 46, 140)}[cls_id]
    torso = mask(lambda d: d.polygon([(0, 63), (2, 54), (14, 48), (26, 50), (40, 52), (52, 50), (63, 56), (63, 63)], fill=FULL))
    lit(im, torso, cloth, 30, 50, 40, 16, shadow=sh, flat=0.4)
    # ---- long hair behind (elf)
    if r["style"] == "long":
        back = mask(lambda d: d.polygon([(14, 14), (24, 6), (30, 8), (26, 30), (30, 50), (22, 58), (12, 52), (10, 34)], fill=FULL))
        lit(im, back, tone(hair, 0.85)[:3], 22, 22, 14, 26, shadow=sh)
    # ---- neck
    neck = mask(lambda d: d.polygon([(24, 40), (39, 44), (41, 56), (26, 58)], fill=FULL))
    lit(im, neck, tone(skin, 0.86, sh, True)[:3], 36, 46, 10, 10, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    d.line((26, 47, 39, 50), fill=tone(skin, 0.55, sh, True))  # jaw shadow on the neck
    d.line((35, 51, 36, 56), fill=tone(skin, 0.7, sh, True))  # tendon
    # ---- ears (near ear at the back of the head)
    if r.get("ears") == "long":
        ear = mask(lambda dd: dd.polygon([(21, 26), (6, 13), (10, 20), (19, 35)], fill=FULL))
    else:
        big = 1 if r.get("wide") else 0
        ear = mask(lambda dd: dd.ellipse((16 - big, 24 - big, 23 + big, 35 + big), fill=FULL))
    lit(im, ear, skin, 22, 26, 8, 10, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    if r.get("ears") == "long":
        d.line((18, 28, 10, 18), fill=tone(skin, 0.62, sh, True))
    else:
        d.arc((17, 26, 22, 33), 100, 280, fill=tone(skin, 0.6, sh, True))
    # ---- head
    hm = head_mask(r.get("slim"), r.get("wide"))
    lit(im, hm, skin, HC[0], HC[1], 17, 23, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    # Eye sockets (occlusion), cheekbone light, jaw line, chin.
    for x in range(27, 36):
        put(im, x, 24, tone(skin, 0.8, sh, True), 0.5)
    for x in range(38, 44):
        put(im, x, 24, tone(skin, 0.8, sh, True), 0.5)
    for x, y in ((40, 33), (41, 33), (42, 34), (41, 32)):
        put(im, x, y, tone(skin, 1.25), 0.8)
    for x, y in ((28, 34), (29, 35), (27, 33)):
        put(im, x, y, (200, 100, 95), 0.25)  # blush in the shadow
    d.line((24, 43, 33, 49), fill=tone(skin, 0.68, sh, True))
    d.line((40, 49, 43, 46), fill=tone(skin, 1.15))
    if r.get("heavy"):
        d.line((27, 22, 46, 22), fill=tone(skin, 0.62, sh, True))
        d.line((28, 21, 45, 21), fill=tone(skin, 1.12))
    # ---- eyes
    ex1, ey = EYE_NEAR
    ex2, _ = EYE_FAR
    lid = (40, 26, 30)
    if expr == "blink":
        d.arc((ex1 - 4, ey - 2, ex1 + 4, ey + 2), 15, 165, fill=tone(skin, 0.45, sh, True))
        d.line((ex1 - 4, ey, ex1 + 3, ey), fill=c4(lid))
        d.line((ex2 - 2, ey, ex2 + 2, ey), fill=c4(lid))
    elif expr == "hurt":
        d.line((ex1 - 4, ey - 1, ex1 + 3, ey + 1), fill=c4(lid))
        d.line((ex1 - 3, ey + 2, ex1 + 2, ey + 3), fill=tone(skin, 0.6, sh, True))
        d.line((ex2 - 2, ey + 1, ex2 + 2, ey - 1), fill=c4(lid))
    else:
        narrow = 1 if expr == "fierce" else 0
        look = -1 if expr == "glance" else 0
        # near eye: white, iris, pupil, glint, heavy upper lid
        d.rectangle((ex1 - 3, ey - 1 + narrow, ex1 + 3, ey + 2), fill=(236, 230, 222, 255))
        d.line((ex1 - 3, ey + 2, ex1 + 3, ey + 2), fill=(196, 186, 182, 255))
        ix = ex1 + 1 + look
        d.rectangle((ix - 1, ey - 1 + narrow, ix + 1, ey + 2), fill=c4(r["eyes"]))
        d.line((ix - 1, ey - 1 + narrow, ix + 1, ey - 1 + narrow), fill=tone(r["eyes"], 0.55))
        d.point((ix, ey + 1), fill=(12, 8, 12, 255))
        d.point((ix, ey), fill=(12, 8, 12, 255))
        d.point((ix + 1, ey - 1 + narrow), fill=(255, 255, 255, 255))
        d.line((ex1 - 4, ey - 2 + narrow, ex1 + 3, ey - 2 + narrow), fill=c4(lid))
        d.point((ex1 - 4, ey - 1 + narrow), fill=c4(lid))
        # far eye: foreshortened (3 px), next to the nose bridge
        d.rectangle((ex2 - 1, ey - 1 + narrow, ex2 + 2, ey + 1), fill=(226, 218, 210, 255))
        d.rectangle((ex2 + 1 + look, ey - 1 + narrow, ex2 + 2 + look, ey + 1), fill=c4(r["eyes"]))
        d.point((ex2 + 1 + look, ey), fill=(12, 8, 12, 255))
        d.line((ex2 - 2, ey - 2 + narrow, ex2 + 2, ey - 2 + narrow), fill=c4(lid))
    # brows: knitted when fierce / hurt / wounded
    knit = 1 if expr in ("fierce", "hurt", "wounded") else 0
    brow = tone(hair, 0.85) if not r.get("heavy") else tone(hair, 0.7)
    th = 2 if r.get("heavy") else 1
    d.line((ex1 - 5, ey - 4, ex1 + 3, ey - 5 + knit * 2), fill=brow, width=th)
    d.line((ex2 - 2, ey - 5 + knit * 2, ex2 + 3, ey - 4), fill=brow, width=th)
    # ---- nose: bridge light, shadow side, tip, nostril, cast shadow
    d.line((44, 25, 48, 34), fill=tone(skin, 1.22))
    d.line((42, 27, 45, 35), fill=tone(skin, 0.72, sh, True))
    d.point((49, 35), fill=tone(skin, 1.3))
    d.point((45, 36), fill=tone(skin, 0.45, sh, True))
    d.line((42, 37, 46, 38), fill=tone(skin, 0.6, sh, True))
    # ---- mouth
    if expr in ("hurt", "fierce"):
        d.polygon([(37, 40), (45, 39), (45, 43), (38, 44)], fill=(60, 18, 22, 255))
        d.line((38, 41, 44, 40), fill=(238, 232, 214, 255))
        d.line((38, 43, 44, 42), fill=(220, 210, 196, 255))
        d.line((37, 40, 45, 39), fill=tone(skin, 0.5, sh, True))
    else:
        frown = 1 if expr == "wounded" else 0
        d.line((37, 41 + frown, 38, 40), fill=tone(skin, 0.5, sh, True))
        d.line((38, 40, 45, 40), fill=(120, 52, 52, 255))
        d.line((39, 41, 44, 41), fill=(196, 104, 100, 255))
        d.line((40, 42, 43, 42), fill=tone(skin, 0.82, sh, True))
    if r.get("scar"):
        d.line((27, 19, 33, 33), fill=tone(skin, 0.55, sh, True))
        d.line((28, 19, 34, 33), fill=tone(skin, 1.15))
        for y in (22, 26, 30):
            d.point((28 + (y - 19) // 2, y), fill=tone(skin, 0.45, sh, True))
    if r.get("tusks"):
        for (bx, by, h) in ((35, 44, 6), (44, 44, 5)):
            d.polygon([(bx, by), (bx + 2, by), (bx + 2, by - h), (bx, by - h + 2)], fill=(238, 232, 206, 255))
            d.point((bx + 2, by - h), fill=(255, 255, 248, 255))
            d.point((bx, by - 1), fill=(190, 180, 150, 255))
    # ---- hair
    st = r["style"]
    if st in ("short", "long"):
        cap = mask(lambda dd: dd.polygon([(17, 24), (17, 15), (21, 8), (29, 3), (38, 3), (44, 7), (47, 13), (46, 16), (40, 13),
                                          (32, 13), (26, 16), (22, 22), (21, 30), (18, 31)], fill=FULL))
        lit(im, cap, hair, 30, 10, 16, 12, shadow=sh)
        d = ImageDraw.Draw(im)
        rnd = random.Random(race_id)
        for k in range(14):
            x0 = 20 + k * 2
            d.line((x0, 5 + (k % 3), x0 - 3, 13 + (k % 4)), fill=tone(hair, 0.7, sh))
        for k in range(6):
            x0 = 30 + k * 2
            d.line((x0, 4, x0 + 2, 7), fill=tone(hair, 1.45))
        for x0 in (41, 44):  # fringe locks over the forehead
            d.polygon([(x0, 12), (x0 + 3, 12), (x0 + 2, 17 + rnd.randint(0, 1))], fill=c4(hair))
        d.polygon([(19, 22), (22, 22), (21, 30), (19, 31)], fill=tone(hair, 0.8, sh))  # sideburn
        if st == "long":
            for k in range(4):
                d.line((19 - k, 24, 15 - k * 2, 50), fill=tone(hair, 0.9 + 0.2 * (k % 2), sh))
    elif st == "mohawk":
        mh = mask(lambda dd: dd.polygon([(20, 14), (25, 3), (33, -1), (41, 1), (44, 6), (36, 9), (28, 12), (23, 19)], fill=FULL))
        lit(im, mh, hair, 32, 4, 12, 8, shadow=sh)
        d = ImageDraw.Draw(im)
        for k in range(6):
            d.line((24 + k * 3, 4 + (k % 2), 22 + k * 3, 12), fill=tone(hair, 1.6 if k % 2 else 0.7, sh))
        for x, y in ((24, 20), (28, 16), (34, 12), (39, 11), (22, 26)):
            put(im, x, y, tone(skin, 0.75, sh, True), 0.7)  # shaved stubble
    # ---- beard (dwarf)
    if r.get("beard"):
        bm = mask(lambda dd: dd.polygon([(22, 36), (27, 40), (36, 44), (46, 41), (46, 47), (42, 56), (36, 63), (26, 63), (22, 52),
                                         (20, 42)], fill=FULL))
        lit(im, bm, r["beard"], 34, 44, 14, 16, shadow=sh)
        d = ImageDraw.Draw(im)
        for x0 in range(23, 45, 2):
            d.line((x0, 44 + (x0 % 3), x0 - 1, 60), fill=tone(r["beard"], 0.7, sh))
            d.point((x0, 47), fill=tone(r["beard"], 1.35))
        d.polygon([(36, 38), (44, 37), (48, 39), (46, 41), (40, 40), (34, 41)], fill=tone(r["beard"], 1.12))  # mustache
        d.line((37, 39, 46, 38), fill=tone(r["beard"], 1.4))
        for by in (54, 58):
            d.rectangle((30, by, 35, by + 1), fill=(228, 186, 72, 255))
            d.point((31, by), fill=(255, 242, 170, 255))
    # ---- expression extras
    if expr == "wounded":
        for x, y in ((29, 31), (30, 31), (30, 32), (31, 32), (28, 32)):
            put(im, x, y, (110, 60, 120), 0.45)
        d = ImageDraw.Draw(im)
        d.line((38, 15, 37, 23), fill=(170, 18, 24, 255))
        d.point((37, 24), fill=(130, 8, 14, 255))
        d.polygon([(47, 19), (48, 16), (49, 19), (48, 20)], fill=(205, 232, 255, 255))
    if expr == "hurt":
        put(im, 36, 22, (120, 60, 60), 0.5)
    # ---- class gear on top
    gear(im, cls_id, cfg, r)
    rim(im, cfg["rim"])
    return gp.outline(im, (14, 10, 16, 255))


def gear(im, cls_id, cfg, r):
    sh = cfg["shadow"]
    d = ImageDraw.Draw(im)
    if cls_id == "warrior":
        metal = (124, 112, 100)
        # Big riveted pauldron on the near shoulder, leather strap, buckle.
        pa = mask(lambda dd: dd.ellipse((-6, 46, 26, 72), fill=FULL))
        lit(im, pa, metal, 4, 52, 16, 12, shadow=sh, flat=0.3)
        d = ImageDraw.Draw(im)
        d.arc((-6, 46, 26, 72), 200, 340, fill=tone(metal, 1.5))
        d.arc((-2, 51, 22, 72), 200, 340, fill=tone(metal, 0.6, sh))
        for x, y in ((3, 51), (10, 49), (17, 50), (22, 53)):
            d.point((x, y), fill=tone(metal, 1.7))
            d.point((x + 1, y + 1), fill=tone(metal, 0.5, sh))
        d.line((22, 63, 50, 52), fill=(86, 56, 32, 255), width=3)
        d.line((22, 62, 50, 51), fill=(128, 86, 50, 255))
        d.rectangle((35, 55, 39, 59), fill=(210, 172, 80, 255))
        # Miner helmet: dome, ridge, riveted brim, the lamp.
        dome = mask(lambda dd: dd.polygon([(14, 19), (15, 10), (21, 4), (30, 0), (39, 1), (45, 6), (48, 12), (49, 15)], fill=FULL))
        lit(im, dome, metal, 28, 6, 18, 12, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.polygon([(12, 20), (50, 14), (51, 16), (13, 22)], fill=tone(metal, 0.85, sh))
        d.line((12, 20, 50, 14), fill=tone(metal, 1.4))
        d.line((13, 22, 51, 16), fill=tone(metal, 0.45, sh))
        d.line((29, 1, 33, 15), fill=tone(metal, 1.5))
        for k in range(6):
            x = 16 + k * 6
            d.point((x, 20 - k), fill=tone(metal, 1.7))
        for x, y in ((22, 8), (37, 5)):
            d.line((x, y, x + 2, y + 2), fill=tone(metal, 0.55, sh))  # dents
        d.rectangle((40, 4, 47, 11), fill=(64, 54, 46, 255))
        d.ellipse((41, 5, 47, 11), fill=(255, 236, 160, 255))
        d.ellipse((43, 6, 45, 8), fill=(255, 255, 236, 255))
    elif cls_id == "paladin":
        steel = (196, 198, 214)
        gold = (226, 182, 64)
        tab = mask(lambda dd: dd.polygon([(30, 52), (46, 50), (48, 63), (30, 63)], fill=FULL))
        lit(im, tab, (222, 216, 200), 40, 52, 10, 8, shadow=sh, flat=0.25)
        d = ImageDraw.Draw(im)
        d.rectangle((38, 52, 39, 63), fill=c4(gold))
        d.rectangle((34, 56, 44, 57), fill=c4(gold))
        pa = mask(lambda dd: dd.ellipse((-6, 46, 28, 72), fill=FULL))
        lit(im, pa, steel, 8, 50, 16, 12, shadow=sh, flat=0.05)
        d = ImageDraw.Draw(im)
        d.arc((-6, 46, 28, 72), 195, 345, fill=c4(gold))
        d.arc((-3, 50, 25, 72), 200, 340, fill=tone(steel, 0.6, sh))
        # Plume flowing back, helm dome with gold band and cross, cheek guard.
        plume = mask(lambda dd: dd.polygon([(28, 1), (20, -1), (9, 3), (3, 12), (8, 10), (13, 8), (20, 7), (29, 6)], fill=FULL))
        lit(im, plume, (196, 36, 44), 18, 3, 14, 6, shadow=sh)
        dome = mask(lambda dd: dd.polygon([(15, 22), (15, 12), (21, 5), (30, 1), (40, 2), (46, 7), (49, 14), (48, 18), (40, 17),
                                           (26, 19)], fill=FULL))
        lit(im, dome, steel, 30, 8, 18, 12, shadow=sh, flat=0.15)
        guard = mask(lambda dd: dd.polygon([(16, 20), (24, 20), (27, 34), (25, 44), (19, 40), (16, 30)], fill=FULL))
        lit(im, guard, steel, 22, 28, 6, 12, shadow=sh, flat=0.3)
        d = ImageDraw.Draw(im)
        d.line((15, 19, 48, 15), fill=c4(gold), width=2)
        d.line((15, 18, 48, 14), fill=tone(gold, 1.4))
        d.line((31, 2, 34, 15), fill=c4(gold), width=2)
        d.line((27, 8, 39, 6), fill=c4(gold))
        d.line((24, 21, 26, 40), fill=c4(gold))
        for x, y in ((20, 25), (20, 33)):
            d.point((x, y), fill=(255, 250, 220, 255))
    elif cls_id == "rogue":
        cloth = (46, 74, 54)
        cloak = mask(lambda dd: dd.polygon([(0, 63), (0, 50), (10, 44), (24, 46), (38, 56), (54, 50), (63, 52), (63, 63)], fill=FULL))
        lit(im, cloak, cloth, 20, 50, 40, 14, shadow=sh, flat=0.4)
        d = ImageDraw.Draw(im)
        for x0 in (8, 16, 50, 57):
            d.line((x0, 50, x0 + 2, 63), fill=tone(cloth, 0.6, sh))
        d.ellipse((34, 52, 41, 59), fill=(186, 186, 198, 255), outline=(80, 80, 92, 255))
        d.point((36, 54), fill=(255, 255, 255, 255))
        # Hood: shell around the skull, deep shadow over the brow.
        hood = mask(lambda dd: dd.polygon([(10, 48), (10, 26), (14, 12), (22, 4), (32, 0), (42, 2), (49, 9), (51, 18), (46, 17),
                                           (42, 12), (34, 10), (26, 14), (22, 22), (22, 40), (26, 48)], fill=FULL))
        lit(im, hood, cloth, 28, 10, 22, 24, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.line((22, 22, 26, 14, 34, 10, 42, 12, 46, 17), fill=tone(cloth, 0.38, sh), width=2)
        d.line((23, 23, 23, 40), fill=tone(cloth, 0.4, sh))
        for y in range(18, 46, 4):
            d.point((13, y), fill=tone(cloth, 0.75, sh))
        px = im.load()
        for y in range(13, 25):  # hood shadow over the forehead
            for x in range(23, 48):
                r_, g_, b_, a_ = px[x, y]
                if a_ and (r_, g_, b_) != tuple(c4(cloth)[:3]):
                    k = 0.45 if y < 22 else 0.25
                    px[x, y] = (clamp(r_ * (1 - k)), clamp(g_ * (1 - k)), clamp(b_ * (1 - k) + 6), a_)
        # Cloth mask over nose and mouth.
        mk = mask(lambda dd: dd.polygon([(24, 34), (44, 32), (51, 36), (47, 46), (40, 52), (28, 50), (24, 42)], fill=FULL))
        lit(im, mk, (40, 42, 48), 40, 36, 14, 10, shadow=sh, flat=0.5)
        d = ImageDraw.Draw(im)
        for x0 in (30, 35, 40, 45):
            d.line((x0, 35, x0 - 2, 49), fill=(28, 28, 34, 255))
        d.line((24, 34, 44, 32, 51, 36), fill=(82, 82, 96, 255))
    elif cls_id == "mage":
        robe = (68, 48, 148)
        gold = (224, 184, 74)
        col = mask(lambda dd: dd.polygon([(0, 63), (2, 52), (14, 44), (24, 50), (30, 58), (46, 50), (54, 44), (63, 50), (63, 63)],
                                         fill=FULL))
        lit(im, col, robe, 24, 50, 40, 14, shadow=sh, flat=0.4)
        d = ImageDraw.Draw(im)
        d.line((14, 44, 24, 50, 30, 58, 46, 50, 54, 44), fill=c4(gold), width=2)
        d.ellipse((33, 56, 41, 64), fill=(80, 220, 255, 255), outline=c4(gold))
        d.ellipse((35, 58, 38, 61), fill=(200, 250, 255, 255))
        # Hat: brim in perspective, cone bent back, band with a gem, stars.
        cone = mask(lambda dd: dd.polygon([(18, 13), (44, 9), (38, 1), (30, -4), (18, -6), (10, -4), (20, 0), (24, 4)], fill=FULL))
        lit(im, cone, robe, 30, 2, 14, 10, shadow=sh, flat=0.2)
        brim = mask(lambda dd: dd.polygon([(3, 20), (12, 13), (30, 9), (52, 8), (58, 11), (48, 15), (30, 17), (12, 21)], fill=FULL))
        lit(im, brim, tone(robe, 0.9)[:3], 30, 10, 26, 6, shadow=sh, flat=0.3)
        d = ImageDraw.Draw(im)
        d.line((3, 20, 12, 21, 30, 17, 48, 15, 58, 11), fill=tone(robe, 0.45, sh))
        d.polygon([(19, 12), (43, 8), (43, 11), (19, 15)], fill=c4(gold))
        d.line((19, 12, 43, 8), fill=tone(gold, 1.4))
        d.ellipse((30, 8, 35, 13), fill=(255, 76, 96, 255), outline=(150, 30, 48, 255))
        d.point((31, 9), fill=(255, 225, 230, 255))
        for x, y in ((26, 4), (35, 2), (16, -2)):
            d.point((x, y), fill=(255, 244, 170, 255))
        # Arcane under-light on the face from the amulet.
        px = im.load()
        for y in range(36, 52):
            for x in range(24, 50):
                r_, g_, b_, a_ = px[x, y]
                if a_:
                    k = 0.18 * (1 - abs(y - 46) / 12)
                    px[x, y] = (clamp(r_ + (150 - r_) * k), clamp(g_ + (110 - g_) * k * 0.5), clamp(b_ + (255 - b_) * k), a_)


# --------------------------------------------------------------- backgrounds
def background(cls_id):
    cfg = CLASSES[cls_id]
    base = np.array(cfg["bg"], dtype=float)
    glow = np.array(cfg["glow"], dtype=float)
    img = np.zeros((S, S, 3))
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.sqrt((xx - 40) ** 2 + (yy - 20) ** 2) / 40.0
    g = np.clip(1.0 - d, 0, 1) ** 1.6
    img[:] = base
    img += (glow - base) * g[:, :, None] * 0.75
    vign = np.clip(1.15 - np.sqrt((xx - 32) ** 2 + (yy - 32) ** 2) / 40.0, 0.35, 1)
    img *= vign[:, :, None]
    # quantise to a few bands with dithering (pixel art, not a smooth gradient)
    q = 18.0
    dith = (((xx + yy) % 2) * 0.5)[:, :, None]
    img = np.floor(img / q + dith) * q
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    dr = ImageDraw.Draw(im)
    rnd = random.Random(cls_id)
    if cls_id == "warrior":  # smoke shapes and sparks
        for _ in range(5):
            x, y = rnd.randint(0, 50), rnd.randint(30, 60)
            dr.ellipse((x, y, x + 16, y + 8), fill=c4((70, 34, 26)))
        for _ in range(14):
            x, y = rnd.randint(2, 62), rnd.randint(2, 62)
            dr.point((x, y), fill=(255, 170 + rnd.randint(0, 60), 60, 255))
    elif cls_id == "paladin":  # rays from the top right
        for k in range(7):
            a = math.radians(110 + k * 14)
            dr.line((44, -4, 44 + math.cos(a) * 90, -4 + math.sin(a) * 90), fill=c4(np.clip(glow * 0.75 + base * 0.25, 0, 255)), width=3)
        for _ in range(10):
            x, y = rnd.randint(2, 62), rnd.randint(2, 62)
            dr.point((x, y), fill=(255, 245, 200, 255))
    elif cls_id == "rogue":  # fog swirls
        for _ in range(7):
            x, y = rnd.randint(-8, 56), rnd.randint(10, 60)
            dr.arc((x, y, x + 22, y + 10), 180, 360, fill=c4((40, 90, 80)), width=2)
    elif cls_id == "mage":  # rune circle
        dr.ellipse((14, 2, 62, 50), outline=c4((110, 70, 200)), width=1)
        dr.ellipse((19, 7, 57, 45), outline=c4((90, 56, 170)), width=1)
        for k in range(8):
            a = k * math.tau / 8
            x, y = 38 + math.cos(a) * 21.5, 26 + math.sin(a) * 21.5
            dr.rectangle((x - 1, y - 1, x + 1, y + 1), fill=c4((210, 170, 255)))
        for _ in range(10):
            x, y = rnd.randint(2, 62), rnd.randint(2, 62)
            dr.point((x, y), fill=(220, 190, 255, 255))
    return im


def main():
    for cls_id in CLASSES:
        gp.save(background(cls_id), OUT + "bg_%s.png" % cls_id, do_outline=False)
    for race_id in RACES:
        for cls_id in CLASSES:
            for expr in EXPRS:
                suffix = "" if expr == "neutral" else "_" + expr
                gp.save(figure(race_id, cls_id, expr), OUT + "hero_%s_%s%s.png" % (race_id, cls_id, suffix), do_outline=False)
    print("hero portraits generated")


if __name__ == "__main__":
    main()
