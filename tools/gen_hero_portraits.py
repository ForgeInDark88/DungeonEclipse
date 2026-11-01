#!/usr/bin/env python3
"""Hero portraits in a "heroic close-up" style (pixel art, 64x64): the head in
three-quarter view turned to the right, a warm key light from the front right,
cool shadows, a rim light in the class colour on the back edge, a tight crop.

Writes assets/sprites/portraits/:
  hero_<race>_<class>.png   sheet of FRAMES (64x64 each, transparent background);
  hero_<race>_<class>_f.png the heroine (RACES_F);
                            breathing, blink, glance, hurt, wounded, fierce
  bg_<class>.png            class background (glow, rays, fog, runes)
Body and head are separate layers: breathing lifts the shoulders, pain throws
the head back, plumes / long hair / hat tips sway. AnimatedPortrait (HUD)
plays the frames: background → class particles → hero → glints → flash.
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
# Face outline: the cheek on the right is smooth; the nose sits in the middle
# of the face, between and below the eyes (NOSE), and the mouth under it.
HEAD = [(17, 23), (18, 15), (22, 9), (29, 5), (37, 5), (43, 9), (46, 15), (47, 21), (47, 27), (47, 33), (46, 38),
        (45, 42), (43, 46), (39, 50), (33, 50), (24, 43), (20, 37), (18, 30)]
HC = (33, 26)  # ellipsoid centre for lighting
EYE_NEAR = (31, 27)
EYE_FAR = (41, 27)
NOSE = (38, 34)  # tip (the bridge starts higher and to the left, between the eyes)
MOUTH_X = -3  # mouth shift from the old profile layout

# Animation frames of one portrait sheet (left to right). AnimatedPortrait
# knows these names (AssetPaths.HERO_PORTRAIT_FRAMES).
FRAMES = [
    ("neutral0", dict()),
    ("neutral1", dict(breath=1, sway=1)),
    ("blink_half", dict(eye="half")),
    ("blink", dict(eye="closed")),
    ("glance", dict(look=-1)),
    ("hurt0", dict(eye="squeeze", mouth="grimace", knit=2, head=(-1, -1))),
    ("hurt1", dict(eye="squeeze", mouth="grimace", knit=2)),
    ("wounded0", dict(eye="tired", mouth="frown", knit=1, wounded=True)),
    ("wounded1", dict(eye="tired", mouth="open_small", knit=1, wounded=True, breath=1, sway=1)),
    ("fierce0", dict(eye="narrow", mouth="open_small", knit=1)),
    ("fierce1", dict(eye="narrow", mouth="roar", knit=2, head=(1, 0))),
    # v2: a four-step breath, joy, casting, a sip of a potion, resolve, death
    ("neutral2", dict(breath=1)),
    ("neutral3", dict(sway=-1)),
    ("smile0", dict(eye="happy", mouth="smile")),
    ("smile1", dict(eye="happy", mouth="smile", breath=1, sway=1)),
    ("cast0", dict(eye="narrow", knit=1, glow=True)),
    ("cast1", dict(eye="narrow", mouth="open_small", knit=1, glow=True, head=(0, -1))),
    ("drink", dict(eye="half", drink=True, head=(0, -1))),
    ("resolve", dict(eye="narrow", mouth="frown", knit=1, head=(1, 0))),
    ("dead", dict(eye="closed", mouth="open_small", knit=1, head=(0, 2))),
]


def head_mask(slim=False, wide=False):
    pts = HEAD
    if slim:
        pts = [(x - (1 if x > 40 and y > 38 else 0), y) for x, y in pts]
    if wide:
        pts = [(x + (1 if x > 40 and y > 36 else 0), y + (1 if y > 46 else 0)) for x, y in pts]
    return mask(lambda d: d.polygon(pts, fill=FULL))


def shift(im, dx, dy):
    out = new()
    out.alpha_composite(im, (int(dx), int(dy)))
    return out


# --------------------------------------------------------------------- races
RACES = {
    "human": dict(skin=(226, 176, 138), hair=(92, 58, 32), style="short", eyes=(70, 120, 175)),
    "dwarf": dict(skin=(212, 152, 112), hair=(150, 76, 36), style="short", eyes=(110, 80, 40), beard=(160, 82, 38), wide=True,
                  heavy=True),
    "elf": dict(skin=(240, 214, 184), hair=(236, 222, 160), style="long", eyes=(70, 190, 140), ears="long", slim=True),
    "orc": dict(skin=(108, 158, 80), hair=(30, 30, 34), style="mohawk", eyes=(230, 70, 40), tusks=True, heavy=True, scar=True,
                wide=True),
}

# Heroines: softer jaw, fuller lips, lashes, thinner arched brows, long hair
# that shows from under helmets and hoods (ponytail, braids, war braid).
RACES_F = {
    "human": dict(skin=(232, 184, 150), hair=(128, 54, 34), style="ponytail", eyes=(80, 140, 90), female=True),
    "dwarf": dict(skin=(218, 160, 122), hair=(176, 90, 40), style="braids", eyes=(110, 80, 40), female=True),
    "elf": dict(skin=(244, 220, 194), hair=(240, 232, 196), style="long", eyes=(110, 170, 230), ears="long", slim=True,
                female=True),
    "orc": dict(skin=(118, 166, 88), hair=(44, 34, 48), style="warbraid", eyes=(240, 150, 40), tusks="small", female=True),
}


# ------------------------------------------------------------------- classes
CLASSES = {
    "warrior": dict(rim=(255, 150, 70), shadow=(60, 40, 50), glow=(255, 120, 40), bg=(48, 22, 16), cloth=(120, 40, 36)),
    "paladin": dict(rim=(255, 230, 150), shadow=(60, 60, 90), glow=(255, 215, 120), bg=(40, 34, 24), cloth=(220, 216, 205)),
    "rogue": dict(rim=(110, 230, 190), shadow=(20, 50, 50), glow=(60, 180, 150), bg=(12, 26, 26), cloth=(44, 70, 50)),
    "mage": dict(rim=(190, 130, 255), shadow=(50, 30, 90), glow=(160, 90, 255), bg=(24, 14, 44), cloth=(66, 46, 140)),
    "necromancer": dict(rim=(120, 255, 160), shadow=(20, 40, 34), glow=(70, 220, 120), bg=(10, 22, 18), cloth=(46, 52, 50)),
}


# ---------------------------------------------------------------- body layer
def body_layer(r, cls_id, cfg):
    """Torso, neck and class shoulder gear (moves with breathing)."""
    sh = cfg["shadow"]
    skin = r["skin"]
    im = new()
    torso = mask(lambda d: d.polygon([(0, 63), (2, 54), (14, 48), (26, 50), (40, 52), (52, 50), (63, 56), (63, 63)], fill=FULL))
    lit(im, torso, cfg["cloth"], 30, 50, 40, 16, shadow=sh, flat=0.4)
    neck = mask(lambda d: d.polygon([(24, 38), (39, 42), (41, 56), (26, 58)], fill=FULL))
    lit(im, neck, tone(skin, 0.86, sh, True)[:3], 36, 46, 10, 10, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    d.line((35, 51, 36, 56), fill=tone(skin, 0.7, sh, True))  # tendon
    d.point((33, 54), fill=tone(skin, 1.1))  # collarbone light
    if cls_id == "warrior":
        metal = (124, 112, 100)
        pa = mask(lambda dd: dd.ellipse((-6, 46, 26, 72), fill=FULL))
        lit(im, pa, metal, 4, 52, 16, 12, shadow=sh, flat=0.3)
        d = ImageDraw.Draw(im)
        d.arc((-6, 46, 26, 72), 200, 340, fill=tone(metal, 1.5))
        d.arc((-2, 51, 22, 72), 200, 340, fill=tone(metal, 0.6, sh))
        for x, y in ((3, 51), (10, 49), (17, 50), (22, 53)):
            d.point((x, y), fill=tone(metal, 1.7))
            d.point((x + 1, y + 1), fill=tone(metal, 0.5, sh))
        d.line((6, 55, 9, 58), fill=tone(metal, 0.55, sh))  # scratch
        d.line((22, 63, 50, 52), fill=(86, 56, 32, 255), width=3)
        d.line((22, 62, 50, 51), fill=(128, 86, 50, 255))
        for x in range(25, 49, 4):
            d.point((x, 62 - (x - 22) * 11 // 28), fill=(70, 44, 26, 255))  # stitches
        d.rectangle((35, 55, 39, 59), fill=(210, 172, 80, 255))
        d.rectangle((36, 56, 38, 58), fill=(86, 56, 32, 255))
    elif cls_id == "paladin":
        steel = (196, 198, 214)
        gold = (226, 182, 64)
        tab = mask(lambda dd: dd.polygon([(30, 52), (46, 50), (48, 63), (30, 63)], fill=FULL))
        lit(im, tab, (222, 216, 200), 40, 52, 10, 8, shadow=sh, flat=0.25)
        d = ImageDraw.Draw(im)
        d.rectangle((38, 52, 39, 63), fill=c4(gold))
        d.rectangle((34, 56, 44, 57), fill=c4(gold))
        d.point((38, 56), fill=(255, 245, 190, 255))
        pa = mask(lambda dd: dd.ellipse((-6, 46, 28, 72), fill=FULL))
        lit(im, pa, steel, 8, 50, 16, 12, shadow=sh, flat=0.05)
        d = ImageDraw.Draw(im)
        d.arc((-6, 46, 28, 72), 195, 345, fill=c4(gold))
        d.arc((-3, 50, 25, 72), 200, 340, fill=tone(steel, 0.6, sh))
        d.line((4, 50, 10, 48), fill=tone(steel, 1.6))  # specular
    elif cls_id == "rogue":
        cloth = cfg["cloth"]
        cloak = mask(lambda dd: dd.polygon([(0, 63), (0, 50), (10, 44), (24, 46), (38, 56), (54, 50), (63, 52), (63, 63)], fill=FULL))
        lit(im, cloak, cloth, 20, 50, 40, 14, shadow=sh, flat=0.4)
        d = ImageDraw.Draw(im)
        for x0 in (8, 16, 50, 57):
            d.line((x0, 50, x0 + 2, 63), fill=tone(cloth, 0.6, sh))
            d.line((x0 + 1, 50, x0 + 3, 63), fill=tone(cloth, 1.15))
        d.ellipse((34, 52, 41, 59), fill=(186, 186, 198, 255), outline=(80, 80, 92, 255))
        d.ellipse((36, 54, 39, 57), fill=(140, 40, 50, 255))
        d.point((36, 54), fill=(255, 255, 255, 255))
    elif cls_id == "necromancer":
        robe = cfg["cloth"]
        bone = (222, 214, 190)
        col = mask(lambda dd: dd.polygon([(0, 63), (2, 52), (14, 44), (24, 50), (30, 58), (46, 50), (54, 44), (63, 50), (63, 63)],
                                         fill=FULL))
        lit(im, col, robe, 24, 50, 40, 14, shadow=sh, flat=0.4)
        d = ImageDraw.Draw(im)
        # a collar of ribs and a vertebrae chain over the robe
        for k in range(4):
            y = 52 + k * 3
            d.arc((26 - k, y - 4, 50 + k, y + 4), 20, 160, fill=tone(bone, 1.0 - k * 0.08))
        for y in range(46, 63, 3):
            d.rectangle((37, y, 39, y + 1), fill=c4(bone))
            d.point((37, y), fill=tone(bone, 1.25))
        # skull pauldron
        sk = mask(lambda dd: dd.ellipse((0, 44, 18, 60), fill=FULL))
        lit(im, sk, bone, 6, 47, 9, 8, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.rectangle((5, 51, 7, 53), fill=(20, 30, 24, 255))
        d.rectangle((11, 51, 13, 53), fill=(20, 30, 24, 255))
        d.point((6, 52), fill=(110, 255, 150, 255))
        d.point((12, 52), fill=(110, 255, 150, 255))
        d.line((6, 57, 12, 57), fill=tone(bone, 0.6, sh))
        d.ellipse((34, 57, 42, 64), fill=(70, 230, 120, 255), outline=c4(bone))  # soul gem
        d.ellipse((36, 59, 38, 61), fill=(210, 255, 220, 255))
    elif cls_id == "mage":
        robe = cfg["cloth"]
        gold = (224, 184, 74)
        col = mask(lambda dd: dd.polygon([(0, 63), (2, 52), (14, 44), (24, 50), (30, 58), (46, 50), (54, 44), (63, 50), (63, 63)],
                                         fill=FULL))
        lit(im, col, robe, 24, 50, 40, 14, shadow=sh, flat=0.4)
        d = ImageDraw.Draw(im)
        d.line((14, 44, 24, 50, 30, 58, 46, 50, 54, 44), fill=c4(gold), width=2)
        for x, y in ((6, 56), (9, 53), (58, 55)):
            d.point((x, y), fill=tone(gold, 1.2))  # embroidery
        d.ellipse((33, 56, 41, 64), fill=(80, 220, 255, 255), outline=c4(gold))
        d.ellipse((35, 58, 38, 61), fill=(200, 250, 255, 255))
    return im


# ---------------------------------------------------------------- head layer
def back_hair(r, cfg, sway):
    im = new()
    sh = cfg["shadow"]
    hair = r["hair"]
    if r["style"] in ("ponytail", "warbraid"):
        # A tail from the back of the head down behind the neck; it swings.
        top = (22, 8) if r["style"] == "ponytail" else (26, 4)
        tail = mask(lambda d: d.polygon([top, (top[0] + 5, top[1] + 2), (18, 22), (16 - sway, 40), (12 - sway, 54), (7 - sway, 52),
                                         (9 - sway, 38), (12, 20)], fill=FULL))
        lit(im, tail, tone(hair, 0.9)[:3], 14, 26, 8, 24, shadow=sh)
        d = ImageDraw.Draw(im)
        if r["style"] == "warbraid":
            for y in range(20, 52, 4):  # plaits and rings
                x = 15 - sway * (y - 20) // 32 - (y - 20) // 8
                d.line((x - 2, y, x + 2, y + 2), fill=tone(hair, 0.6, sh))
                d.line((x - 2, y + 2, x + 2, y), fill=tone(hair, 1.3))
            d.rectangle((11 - sway, 44, 15 - sway, 45), fill=(200, 170, 90, 255))
        else:
            for k in range(3):
                d.line((15 + k, 20, 10 + k - sway, 52), fill=tone(hair, 0.7 + 0.3 * (k % 2), sh))
            d.rectangle((14, 19, 18, 21), fill=(60, 40, 70, 255))  # hair tie
    if r["style"] == "braids":
        for bx in (15,):  # the braid behind (the front one is on the head layer)
            for y in range(24, 56, 4):
                x = bx - sway * (y - 24) // 32
                d = ImageDraw.Draw(im)
                d.ellipse((x - 3, y, x + 2, y + 4), fill=tone(hair, 0.85, sh), outline=tone(hair, 0.55, sh))
    if r["style"] == "long":
        sw = sway
        back = mask(lambda d: d.polygon([(14, 14), (24, 6), (30, 8), (26, 30), (30 - sw, 50), (22 - sw, 58), (12 - sw, 52), (10, 34)],
                                        fill=FULL))
        lit(im, back, tone(r["hair"], 0.85)[:3], 22, 22, 14, 26, shadow=cfg["shadow"])
        d = ImageDraw.Draw(im)
        for k in range(4):
            d.line((20 - k * 2, 20, 16 - k * 2 - sw, 54), fill=tone(r["hair"], 0.7 + 0.15 * (k % 2), cfg["shadow"]))
    return im


def eyes(d, im, r, skin, sh, eye, look, knit):
    ex1, ey = EYE_NEAR
    ex2, _ = EYE_FAR
    lid = (40, 26, 30)
    lid_c = tone(skin, 0.62, sh, True)
    if eye == "closed":
        d.arc((ex1 - 4, ey - 2, ex1 + 4, ey + 2), 15, 165, fill=c4(lid))
        d.point((ex1 - 4, ey + 1), fill=c4(lid))  # lashes
        d.line((ex1 - 3, ey - 1, ex1 + 3, ey - 1), fill=lid_c)
        d.line((ex2 - 2, ey + 1, ex2 + 2, ey + 1), fill=c4(lid))
        return
    if eye == "squeeze":
        d.line((ex1 - 4, ey - 1, ex1 + 3, ey + 1), fill=c4(lid))
        d.line((ex1 - 3, ey + 2, ex1 + 2, ey + 3), fill=lid_c)
        d.line((ex1 - 3, ey - 2, ex1 + 1, ey - 3), fill=lid_c)  # creases
        d.line((ex2 - 2, ey + 1, ex2 + 2, ey - 1), fill=c4(lid))
        return
    top = {"open": -1, "half": 1, "narrow": 0, "tired": 0, "happy": -1}[eye]
    # near eye: white, iris with a dark rim, pupil, glint, lid with a crease
    d.rectangle((ex1 - 3, ey + top, ex1 + 3, ey + 2), fill=(236, 230, 222, 255))
    d.line((ex1 - 3, ey + 2, ex1 + 3, ey + 2), fill=(196, 186, 182, 255))
    d.point((ex1 + 3, ey + 1), fill=(220, 150, 140, 255))  # tear duct
    ix = ex1 + 1 + look
    d.rectangle((ix - 1, ey + top, ix + 1, ey + 2), fill=c4(r["eyes"]))
    d.point((ix - 1, ey + 2), fill=tone(r["eyes"], 0.6))
    d.point((ix + 1, ey + 2), fill=tone(r["eyes"], 1.3))
    d.point((ix, ey + max(top, 0) + 1), fill=(12, 8, 12, 255))
    # depth: the upper lid shades the top of the iris and the inner white,
    # a soft lower lash line under the eye
    d.line((ix - 1, ey + top, ix + 1, ey + top), fill=tone(r["eyes"], 0.55))
    d.point((ex1 - 3, ey + max(top, 0)), fill=(196, 186, 182, 255))
    for x in range(ex1 - 2, ex1 + 3):
        put(im, x, ey + 3, tone(skin, 0.78, sh, True), 0.35)
    if top <= 0:
        d.point((ix, ey), fill=(12, 8, 12, 255))
        d.point((ix + 1, ey - 1 if top < 0 else ey), fill=(255, 255, 255, 255))
    d.line((ex1 - 4, ey - 2 + max(top, 0) + (1 if top == 1 else 0), ex1 + 3, ey - 2 + max(top, 0) + (1 if top == 1 else 0)), fill=c4(lid))
    d.point((ex1 - 4, ey - 1 + max(top, 0)), fill=c4(lid))
    if top < 0:
        d.line((ex1 - 3, ey - 3, ex1 + 2, ey - 3), fill=lid_c)  # lid crease
    if eye == "tired":
        d.line((ex1 - 3, ey + 3, ex1 + 2, ey + 3), fill=tone(skin, 0.72, sh, True))  # dark circles
    if eye == "happy":
        # Smiling eyes: the raised cheek covers the bottom of the eye in a
        # crescent (skin over the white and the iris, highest in the middle),
        # a soft lid shadow on its edge, laugh lines at the outer corner.
        cheek = tone(skin, 1.06, sh, True)
        edge = tone(skin, 0.74, sh, True)
        for x in range(ex1 - 3, ex1 + 4):
            lift = 1 if abs(x - ex1) <= 1 else 0
            d.point((x, ey + 2), fill=cheek)
            if lift:
                d.point((x, ey + 1), fill=cheek)
        d.line((ex1 - 2, ey + 1, ex1 + 2, ey + 1), fill=edge)
        for k in range(3):  # laugh lines (crow's feet) at the outer corner
            d.point((ex1 - 5, ey - 1 + k), fill=tone(skin, 0.72, sh, True))
        d.point((ex1 - 6, ey), fill=tone(skin, 0.78, sh, True))
        for x, y in ((ex1 - 2, ey + 4), (ex1 - 1, ey + 4), (ex1, ey + 4), (ex2, ey + 4), (ex2 + 1, ey + 4)):
            put(im, x, y, tone(skin, 1.15), 0.3)  # the cheek apples catch the light
    # far eye: foreshortened, partly behind the bridge
    d.rectangle((ex2 - 1, ey + top, ex2 + 2, ey + 1), fill=(226, 218, 210, 255))
    d.rectangle((ex2 + 1 + look, ey + top, ex2 + 2 + look, ey + 1), fill=c4(r["eyes"]))
    d.point((ex2 + 1 + look, ey + max(top, 0)), fill=(12, 8, 12, 255))
    d.line((ex2 - 2, ey - 2 + max(top, 0), ex2 + 2, ey - 2 + max(top, 0)), fill=c4(lid))
    if eye == "happy":  # the far eye smiles too (after it is drawn)
        for x in range(ex2 - 1, ex2 + 3):
            d.point((x, ey + 1), fill=tone(skin, 1.06, sh, True))
        d.line((ex2 - 1, ey + 1, ex2 + 2, ey + 1), fill=tone(skin, 0.74, sh, True))
    if r.get("female") and eye not in ("closed", "squeeze"):
        d.point((ex1 - 5, ey - 2), fill=c4(lid))  # lashes
        d.point((ex1 - 5, ey - 3), fill=c4(lid))
        d.point((ex1 - 3, ey - 3), fill=c4(lid))
        d.point((ex2 + 3, ey - 2), fill=c4(lid))
    if r.get("female"):
        # thin arched brows
        brow = tone(r["hair"], 0.75)
        d.line((ex1 - 5, ey - 4, ex1 - 2, ey - 6 + knit, ex1 + 3, ey - 5 + knit), fill=brow)
        d.line((ex2 - 2, ey - 5 + knit, ex2 + 1, ey - 6, ex2 + 3, ey - 5), fill=brow)
        return
    # brows
    brow = tone(r["hair"], 0.85) if not r.get("heavy") else tone(r["hair"], 0.7)
    th = 2 if r.get("heavy") else 1
    d.line((ex1 - 5, ey - 4, ex1 + 3, ey - 5 + knit), fill=brow, width=th)
    d.line((ex1 - 4, ey - 5, ex1 + 1, ey - 5 + knit // 2), fill=tone(brow, 1.3))
    d.line((ex2 - 2, ey - 5 + knit, ex2 + 3, ey - 4), fill=brow, width=th)


def nose_and_mouth(d, im, r, skin, sh, mouth):
    # The head is turned a little to the right, so the nose points that way:
    # the bridge starts between the eyes and runs down-right, the tip juts
    # toward the far eye. The left flank (facing us) is in soft shadow, the
    # near nostril shows, the far one hides behind the tip.
    nx, ny = NOSE
    wide = 1 if r.get("tusks") or r.get("wide") else 0
    for k in range(7):  # left flank: a diagonal soft shadow
        x, y = nx - 4 + k // 2, ny - 6 + k
        put(im, x - wide, y, tone(skin, 0.58, sh, True), 0.28 + 0.05 * k)
        put(im, x - 1 - wide, y, tone(skin, 0.7, sh, True), 0.12)
    for k in range(5):  # lit ridge, right of the flank
        put(im, nx - 2 + k // 2, ny - 6 + k, tone(skin, 1.2), 0.5)
    put(im, nx + 1, ny, tone(skin, 1.32), 0.95)  # tip
    put(im, nx, ny - 1, tone(skin, 1.2), 0.6)
    put(im, nx + 2, ny, tone(skin, 0.85, sh, True), 0.5)  # tip edge turning away
    d.point((nx - 2 - wide, ny), fill=tone(skin, 0.68, sh, True))  # near wing
    d.point((nx - 1 - wide, ny + 1), fill=tone(skin, 0.45, sh, True))  # near nostril
    d.point((nx + 2, ny + 1), fill=tone(skin, 0.62, sh, True))  # far nostril, half hidden
    for x in range(nx - 2 - wide, nx + 3):
        put(im, x, ny + 2, tone(skin, 0.62, sh, True), 0.45)  # under the nose
    d.point((nx, ny + 3), fill=tone(skin, 0.82, sh, True))  # philtrum
    m = MOUTH_X
    if mouth == "grimace":
        d.polygon([(38 + m, 40), (46 + m, 39), (46 + m, 42), (38 + m, 43)], fill=(60, 18, 22, 255))
        d.line((39 + m, 40, 45 + m, 40), fill=(238, 232, 214, 255))
        d.line((39 + m, 42, 45 + m, 41), fill=(220, 210, 196, 255))
        d.line((37 + m, 41, 38 + m, 40), fill=tone(skin, 0.5, sh, True))
        d.line((36 + m, 40, 37 + m, 38), fill=tone(skin, 0.7, sh, True))  # strained cheeks
        d.line((47 + m, 40, 46 + m, 38), fill=tone(skin, 0.7, sh, True))
    elif mouth == "roar":
        d.polygon([(37 + m, 39), (46 + m, 39), (46 + m, 45), (39 + m, 46)], fill=(52, 12, 18, 255))
        d.line((38 + m, 40, 45 + m, 40), fill=(240, 234, 216, 255))
        d.line((40 + m, 45, 45 + m, 44), fill=(224, 214, 198, 255))
        d.point((43 + m, 43), fill=(150, 40, 50, 255))  # tongue
        d.line((37 + m, 39, 46 + m, 39), fill=tone(skin, 0.5, sh, True))
        d.line((35 + m, 38, 36 + m, 36), fill=tone(skin, 0.68, sh, True))
    elif mouth == "open_small":
        d.polygon([(38 + m, 40), (45 + m, 40), (45 + m, 42), (39 + m, 42)], fill=(70, 22, 26, 255))
        d.line((39 + m, 40, 44 + m, 40), fill=(232, 226, 210, 255))
        d.line((38 + m, 39, 45 + m, 39), fill=(120, 52, 52, 255))
        d.line((39 + m, 43, 44 + m, 43), fill=(196, 104, 100, 255))
    elif mouth == "smile":
        x0, x1 = 37 + m, 46 + m  # mouth corners
        dark = tone(skin, 0.48, sh, True)
        lip = (150, 66, 64, 255) if not r.get("female") else (176, 78, 84, 255)
        lower = (206, 116, 110, 255) if not r.get("female") else (214, 112, 118, 255)
        # the curve: corners 2 px higher than the middle
        curve = {x0: 38, x0 + 1: 39, x1 - 1: 39, x1: 38}
        for x in range(x0, x1 + 1):
            y = curve.get(x, 40)
            d.point((x, y), fill=dark if x in (x0, x1) else lip)
        for x in range(x0 + 2, x1 - 1):  # open a little: teeth on top, shadow below
            d.point((x, 41), fill=(240, 234, 220, 255) if x0 + 2 < x < x1 - 2 else (190, 180, 170, 255))
        d.line((x0 + 2, 42, x1 - 2, 42), fill=(84, 26, 30, 255))
        d.line((x0 + 2, 43, x1 - 2, 43), fill=lower)  # lower lip
        d.point(((x0 + x1) // 2, 43), fill=(240, 170, 160, 255))  # its light
        d.line((x0 + 3, 44, x1 - 3, 44), fill=tone(skin, 0.82, sh, True))  # under the lip
        # nasolabial folds: nose wing -> mouth corner
        nx, ny = NOSE
        for k in range(4):
            put(im, x0 - 1 + (k // 3), ny + 1 + k, tone(skin, 0.62, sh, True), 0.55)
            put(im, x1 + 1, ny + 1 + k, tone(skin, 0.7, sh, True), 0.35)
        put(im, x0 - 1, 38, tone(skin, 0.6, sh, True), 0.6)  # dimple
        for x, y in ((x0 - 3, 35), (x0 - 2, 34), (x1 + 2, 35)):
            put(im, x, y, tone(skin, 1.22), 0.6)  # lifted cheeks
    else:
        frown = 1 if mouth == "frown" else 0
        d.line((37 + m, 41 + frown, 38 + m, 40), fill=tone(skin, 0.5, sh, True))
        d.line((38 + m, 40, 45 + m, 40), fill=(120, 52, 52, 255))
        d.line((45 + m, 40, 46 + m, 41 + frown), fill=tone(skin, 0.55, sh, True))
        d.line((39 + m, 41, 44 + m, 41), fill=(196, 104, 100, 255))
        d.point((41 + m, 41), fill=(225, 150, 140, 255))  # lip light
        d.line((40 + m, 42, 43 + m, 42), fill=tone(skin, 0.82, sh, True))
        if r.get("female"):
            d.line((39 + m, 39, 44 + m, 39), fill=(186, 92, 96, 255))  # fuller upper lip
            d.line((39 + m, 41, 44 + m, 41), fill=(206, 110, 112, 255))
            d.line((40 + m, 42, 43 + m, 42), fill=(196, 104, 104, 255))  # fuller lower lip
            d.point((41 + m, 42), fill=(236, 160, 160, 255))
    d.line((37, 47, 39, 47), fill=tone(skin, 1.12))  # chin light


def head_layer(r, cls_id, cfg, eye="open", look=0, mouth="neutral", knit=0, wounded=False, sway=0):
    sh = cfg["shadow"]
    skin = r["skin"]
    hair = r["hair"]
    im = new()
    # ---- ears
    if r.get("ears") == "long":
        ear = mask(lambda dd: dd.polygon([(21, 26), (6 - sway, 13), (10, 20), (19, 35)], fill=FULL))
    else:
        big = 1 if r.get("wide") else 0
        ear = mask(lambda dd: dd.ellipse((16 - big, 24 - big, 23 + big, 35 + big), fill=FULL))
    lit(im, ear, skin, 22, 26, 8, 10, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    if r.get("ears") == "long":
        d.line((18, 28, 10, 18), fill=tone(skin, 0.62, sh, True))
        d.point((8, 15), fill=tone(skin, 1.2))
    else:
        d.arc((17, 26, 22, 33), 100, 280, fill=tone(skin, 0.6, sh, True))
        d.point((20, 30), fill=tone(skin, 0.5, sh, True))  # ear canal
    # ---- head volume
    hm = head_mask(r.get("slim") or r.get("female"), r.get("wide"))
    lit(im, hm, skin, HC[0], HC[1], 17, 23, warm=True, shadow=sh)
    d = ImageDraw.Draw(im)
    for x in range(27, 36):
        put(im, x, 24, tone(skin, 0.8, sh, True), 0.45)  # eye sockets
    for x in range(38, 44):
        put(im, x, 24, tone(skin, 0.8, sh, True), 0.45)
    for x, y in ((40, 32), (41, 32), (39, 31)):
        put(im, x, y, tone(skin, 1.22), 0.7)  # cheekbone
    for x, y in ((27, 33), (28, 34), (29, 34), (28, 33)):
        put(im, x, y, (205, 105, 100), 0.22)  # blush
    for x, y in ((25, 37), (26, 39), (27, 41)):
        put(im, x, y, tone(skin, 0.65, sh, True), 0.35)  # under the cheekbone
    d.line((24, 43, 33, 49), fill=tone(skin, 0.68, sh, True))  # jaw
    if r.get("heavy"):
        d.line((27, 22, 46, 22), fill=tone(skin, 0.62, sh, True))
        d.line((28, 21, 45, 21), fill=tone(skin, 1.12))
    eyes(d, im, r, skin, sh, eye, look, knit)
    nose_and_mouth(d, im, r, skin, sh, mouth)
    if knit >= 2:
        put(im, 36, 22, tone(skin, 0.55, sh, True), 0.6)  # frown line
        put(im, 36, 23, tone(skin, 0.55, sh, True), 0.4)
    if r.get("scar"):
        d.line((27, 19, 33, 33), fill=tone(skin, 0.55, sh, True))
        d.line((28, 19, 34, 33), fill=tone(skin, 1.15))
        for y in (22, 26, 30):
            d.point((28 + (y - 19) // 2, y), fill=tone(skin, 0.45, sh, True))
    if r.get("tusks"):
        up = 1 if mouth in ("roar", "grimace") else 0
        tall = 3 if r.get("tusks") == "small" else 6
        for (bx, by, h) in ((31, 44, tall), (40, 44, tall)):
            d.polygon([(bx, by - up), (bx + 2, by - up), (bx + 2, by - h - up), (bx, by - h + 2 - up)], fill=(238, 232, 206, 255))
            d.point((bx + 2, by - h - up), fill=(255, 255, 248, 255))
            d.point((bx, by - 1 - up), fill=(190, 180, 150, 255))
    # ---- hair
    st = r["style"]
    if st in ("short", "long", "ponytail", "braids"):
        cap = mask(lambda dd: dd.polygon([(17, 24), (17, 15), (21, 8), (29, 3), (38, 3), (44, 7), (47, 13), (46, 16), (40, 13),
                                          (32, 13), (26, 16), (22, 22), (21, 30), (18, 31)], fill=FULL))
        lit(im, cap, hair, 30, 10, 16, 12, shadow=sh)
        d = ImageDraw.Draw(im)
        rnd = random.Random(str(hair))
        for k in range(14):
            x0 = 20 + k * 2
            d.line((x0, 5 + (k % 3), x0 - 3, 13 + (k % 4)), fill=tone(hair, 0.7, sh))
        for k in range(6):
            x0 = 30 + k * 2
            d.line((x0, 4, x0 + 2, 7), fill=tone(hair, 1.45))
        for x0 in (41, 44):
            d.polygon([(x0 + sway, 12), (x0 + 3 + sway, 12), (x0 + 2 + sway, 17 + rnd.randint(0, 1))], fill=c4(hair))
        d.polygon([(19, 22), (22, 22), (21, 30), (19, 31)], fill=tone(hair, 0.8, sh))
    elif st in ("mohawk", "warbraid"):
        mh = mask(lambda dd: dd.polygon([(20, 14), (25 - sway, 3), (33 - sway, -1), (41, 1), (44, 6), (36, 9), (28, 12), (23, 19)],
                                        fill=FULL))
        lit(im, mh, hair, 32, 4, 12, 8, shadow=sh)
        d = ImageDraw.Draw(im)
        for k in range(6):
            d.line((24 + k * 3 - sway, 4 + (k % 2), 22 + k * 3, 12), fill=tone(hair, 1.6 if k % 2 else 0.7, sh))
        for x, y in ((24, 20), (28, 16), (34, 12), (39, 11), (22, 26)):
            put(im, x, y, tone(skin, 0.75, sh, True), 0.7)
    if st == "braids":
        # A thick braid in front of the ear down over the shoulder, gold clasps.
        d = ImageDraw.Draw(im)
        for k, y in enumerate(range(28, 60, 4)):
            x = 21 - sway * k // 8
            d.ellipse((x - 3, y, x + 2, y + 4), fill=c4(hair), outline=tone(hair, 0.55, sh))
            d.point((x - 1, y + 1), fill=tone(hair, 1.35))
        for y in (40, 52):
            d.rectangle((17 - sway * (y - 28) // 32, y, 23 - sway * (y - 28) // 32, y + 1), fill=(228, 186, 72, 255))
    if r.get("female"):
        for x, y in ((27, 33), (28, 33), (28, 34), (29, 34), (40, 33), (41, 33)):
            put(im, x, y, (215, 105, 110), 0.3)  # blush
        if st in ("ponytail", "long", "warbraid"):
            # A lock framing the face from the temple down to the jaw.
            lock = mask(lambda dd: dd.polygon([(19, 18), (24, 17), (25, 28), (24 + sway, 40), (21 + sway, 44), (19, 34)], fill=FULL))
            lit(im, lock, hair, 20, 24, 5, 14, shadow=sh)
            d = ImageDraw.Draw(im)
            d.line((22, 19, 23 + sway, 40), fill=tone(hair, 1.35))
            d.line((20, 22, 20, 36), fill=tone(hair, 0.65, sh))
    # ---- beard (dwarf), mustache, braids with clasps
    if r.get("beard"):
        bd = r["beard"]
        bm = mask(lambda dd: dd.polygon([(22, 36), (27, 40), (36, 44), (46, 41), (46, 47), (42, 56), (36 - sway, 63), (26 - sway, 63),
                                         (22, 52), (20, 42)], fill=FULL))
        lit(im, bm, bd, 34, 44, 14, 16, shadow=sh)
        d = ImageDraw.Draw(im)
        for x0 in range(23, 45, 2):
            d.line((x0, 44 + (x0 % 3), x0 - 1 - sway, 60), fill=tone(bd, 0.7, sh))
            d.point((x0, 47), fill=tone(bd, 1.35))
        d.polygon([(30, 39), (37, 37), (44, 39), (42, 41), (37, 40), (31, 41)], fill=tone(bd, 1.12))
        d.line((32, 39, 42, 38), fill=tone(bd, 1.4))
        if mouth in ("roar", "grimace", "open_small"):
            d.polygon([(34, 41), (41, 41), (41, 43), (35, 43)], fill=(60, 18, 22, 255))
            d.line((35, 41, 40, 41), fill=(236, 230, 212, 255))
        for by in (54, 58):
            d.rectangle((30 - sway, by, 35 - sway, by + 1), fill=(228, 186, 72, 255))
            d.point((31 - sway, by), fill=(255, 242, 170, 255))
    if wounded:
        for x, y in ((29, 31), (30, 31), (30, 32), (31, 32), (28, 32)):
            put(im, x, y, (110, 60, 120), 0.45)
        d = ImageDraw.Draw(im)
        d.line((38, 15, 37, 23), fill=(170, 18, 24, 255))
        d.point((37, 24), fill=(130, 8, 14, 255))
        d.point((38, 16), fill=(225, 70, 70, 255))
        d.polygon([(47, 19), (48, 16), (49, 19), (48, 20)], fill=(205, 232, 255, 255))
        d.line((26, 36, 28, 38), fill=(170, 40, 40, 255))  # cut on the cheek
    head_gear(im, cls_id, cfg, r, sway)
    return im


def head_gear(im, cls_id, cfg, r, sway):
    sh = cfg["shadow"]
    if cls_id == "warrior":
        metal = (124, 112, 100)
        dome = mask(lambda dd: dd.polygon([(14, 19), (15, 10), (21, 4), (30, 0), (39, 1), (45, 6), (48, 12), (49, 15)], fill=FULL))
        lit(im, dome, metal, 28, 6, 18, 12, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.polygon([(12, 20), (50, 14), (51, 16), (13, 22)], fill=tone(metal, 0.85, sh))
        d.line((12, 20, 50, 14), fill=tone(metal, 1.4))
        d.line((13, 22, 51, 16), fill=tone(metal, 0.45, sh))
        d.line((29, 1, 33, 15), fill=tone(metal, 1.5))
        d.line((19, 8, 24, 4), fill=tone(metal, 1.6))  # specular
        for k in range(6):
            d.point((16 + k * 6, 20 - k), fill=tone(metal, 1.7))
        for x, y in ((22, 9), (37, 6)):
            d.line((x, y, x + 2, y + 2), fill=tone(metal, 0.55, sh))
        d.rectangle((40, 4, 47, 11), fill=(64, 54, 46, 255))
        d.ellipse((41, 5, 47, 11), fill=(255, 236, 160, 255))
        d.ellipse((43, 6, 45, 8), fill=(255, 255, 236, 255))
    elif cls_id == "paladin":
        steel = (196, 198, 214)
        gold = (226, 182, 64)
        s = sway
        plume = mask(lambda dd: dd.polygon([(28, 1), (20, -1), (9 - s, 3), (3 - s, 12 + s), (8 - s, 10), (13, 8), (20, 7), (29, 6)],
                                           fill=FULL))
        lit(im, plume, (196, 36, 44), 18, 3, 14, 6, shadow=sh)
        d = ImageDraw.Draw(im)
        for k in range(4):
            d.line((26 - k * 5, 2, 22 - k * 5 - s, 7), fill=(235, 90, 90, 255))
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
        d.line((20, 9, 25, 5), fill=tone(steel, 1.6))
        for x, y in ((20, 25), (20, 33)):
            d.point((x, y), fill=(255, 250, 220, 255))
    elif cls_id == "rogue":
        cloth = cfg["cloth"]
        hood = mask(lambda dd: dd.polygon([(10, 48), (10, 26), (14, 12), (22, 4), (32 - sway, 0), (42, 2), (49, 9), (51, 18), (46, 17),
                                           (42, 12), (34, 10), (26, 14), (22, 22), (22, 40), (26, 48)], fill=FULL))
        lit(im, hood, cloth, 28, 10, 22, 24, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.line((22, 22, 26, 14, 34, 10, 42, 12, 46, 17), fill=tone(cloth, 0.38, sh), width=2)
        d.line((23, 23, 23, 40), fill=tone(cloth, 0.4, sh))
        for y in range(18, 46, 4):
            d.point((13, y), fill=tone(cloth, 0.75, sh))
        d.line((14, 14, 20, 7), fill=tone(cloth, 1.25))  # fold light
        px = im.load()
        base = tuple(c4(cloth)[:3])
        for y in range(13, 25):  # hood shadow over the forehead
            for x in range(23, 48):
                r_, g_, b_, a_ = px[x, y]
                if a_ and (r_, g_, b_) != base:
                    k = 0.45 if y < 22 else 0.22
                    px[x, y] = (clamp(r_ * (1 - k)), clamp(g_ * (1 - k)), clamp(b_ * (1 - k) + 6), a_)
        mk = mask(lambda dd: dd.polygon([(24, 33), (37, 30), (45, 31), (49, 35), (46, 45), (40, 51), (28, 50), (24, 42)], fill=FULL))
        lit(im, mk, (40, 42, 48), 40, 36, 14, 10, shadow=sh, flat=0.5)
        d = ImageDraw.Draw(im)
        for x0 in (30, 35, 40, 45):
            d.line((x0, 35, x0 - 2, 49), fill=(28, 28, 34, 255))
        d.line((24, 33, 37, 30, 45, 31, 49, 35), fill=(82, 82, 96, 255))
    elif cls_id == "necromancer":
        cloth = cfg["cloth"]
        bone = (222, 214, 190)
        hood = mask(lambda dd: dd.polygon([(10, 50), (10, 26), (14, 11), (22, 3), (32 - sway, -1), (42, 1), (49, 8), (52, 18), (47, 17),
                                           (42, 12), (34, 10), (26, 14), (22, 22), (22, 42), (26, 50)], fill=FULL))
        lit(im, hood, cloth, 28, 10, 22, 24, shadow=sh, flat=0.2)
        d = ImageDraw.Draw(im)
        d.line((22, 22, 26, 14, 34, 10, 42, 12, 47, 17), fill=tone(cloth, 0.38, sh), width=2)
        d.line((14, 14, 20, 6), fill=tone(cloth, 1.25))
        # bone circlet across the hood's brow with a small skull
        d.line((24, 13, 34, 9, 44, 11), fill=c4(bone), width=1)
        sk = mask(lambda dd: dd.ellipse((30, 4, 38, 12), fill=FULL))
        lit(im, sk, bone, 32, 6, 4, 4, shadow=sh)
        d = ImageDraw.Draw(im)
        d.point((32, 8), fill=(20, 30, 24, 255))
        d.point((35, 8), fill=(20, 30, 24, 255))
        px = im.load()
        base = tuple(c4(cloth)[:3])
        for y in range(13, 52):  # hood shadow above, green soul-light from below
            for x in range(23, 50):
                r_, g_, b_, a_ = px[x, y]
                if a_ and (r_, g_, b_) != base:
                    if y < 22:
                        k = 0.45
                        px[x, y] = (clamp(r_ * (1 - k)), clamp(g_ * (1 - k)), clamp(b_ * (1 - k) + 6), a_)
                    elif y > 36:
                        k = 0.22 * (y - 36) / 15
                        px[x, y] = (clamp(r_ + (60 - r_) * k), clamp(g_ + (255 - g_) * k), clamp(b_ + (140 - b_) * k), a_)
    elif cls_id == "mage":
        robe = cfg["cloth"]
        gold = (224, 184, 74)
        s = sway
        cone = mask(lambda dd: dd.polygon([(18, 13), (44, 9), (38, 1), (30, -4), (18 - s, -6), (10 - s, -4 + s), (20, 0), (24, 4)],
                                          fill=FULL))
        lit(im, cone, robe, 30, 2, 14, 10, shadow=sh, flat=0.2)
        brim = mask(lambda dd: dd.polygon([(3, 20), (12, 13), (30, 9), (52, 8), (58, 11), (48, 15), (30, 17), (12, 21)], fill=FULL))
        lit(im, brim, tone(robe, 0.9)[:3], 30, 10, 26, 6, shadow=sh, flat=0.3)
        d = ImageDraw.Draw(im)
        d.line((3, 20, 12, 21, 30, 17, 48, 15, 58, 11), fill=tone(robe, 0.45, sh))
        d.line((12, 13, 30, 9, 52, 8), fill=tone(robe, 1.3))
        d.polygon([(19, 12), (43, 8), (43, 11), (19, 15)], fill=c4(gold))
        d.line((19, 12, 43, 8), fill=tone(gold, 1.4))
        d.ellipse((30, 8, 35, 13), fill=(255, 76, 96, 255), outline=(150, 30, 48, 255))
        d.point((31, 9), fill=(255, 225, 230, 255))
        for x, y in ((26, 4), (35, 2), (16 - s, -2)):
            d.point((x, y), fill=(255, 244, 170, 255))
        px = im.load()
        for y in range(36, 52):  # arcane light from the amulet below
            for x in range(24, 50):
                r_, g_, b_, a_ = px[x, y]
                if a_:
                    k = 0.18 * (1 - abs(y - 46) / 12)
                    px[x, y] = (clamp(r_ + (150 - r_) * k), clamp(g_ + (110 - g_) * k * 0.5), clamp(b_ + (255 - b_) * k), a_)


def frame(race_id, cls_id, breath=0, sway=0, head=(0, 0), female=False, glow=False, drink=False, **kw):
    r = (RACES_F if female else RACES)[race_id]
    cfg = CLASSES[cls_id]
    im = new()
    im.alpha_composite(shift(back_hair(r, cfg, sway), *head))
    im.alpha_composite(shift(body_layer(r, cls_id, cfg), 0, -breath))
    face = head_layer(r, cls_id, cfg, sway=sway, **kw)
    if glow:
        _eye_glow(face, cfg["rim"], kw.get("look", 0))
    im.alpha_composite(shift(face, *head))
    if drink:
        _flask(im, head)
    rim(im, cfg["rim"])
    return gp.outline(im, (14, 10, 16, 255))


def _eye_glow(im, col, look=0):
    """Casting: the eyes light up in the class colour, a soft halo around."""
    for (ex, ey), size in ((EYE_NEAR, 1), (EYE_FAR, 0)):
        cx = ex + 1 + look
        for dy in range(-3, 4):
            for dx in range(-4, 5):
                dd = math.hypot(dx, dy * 1.4)
                if dd < 4.2:
                    put(im, cx + dx, ey + 1 + dy, col, 0.75 * (1 - dd / 4.2))
        put(im, cx, ey + 1, (255, 255, 255), 1.0)
        if size:
            put(im, cx - 1, ey + 1, col, 0.9)
            put(im, cx + 1, ey + 1, col, 0.9)


def _flask(im, head):
    """Drinking: a small red potion raised to the lips."""
    d = ImageDraw.Draw(im)
    x, y = 37 + head[0], 41 + head[1]
    d.polygon([(x, y), (x + 6, y - 5), (x + 10, y - 1), (x + 4, y + 4)], fill=(190, 220, 230, 230))  # glass
    d.polygon([(x + 3, y + 1), (x + 7, y - 3), (x + 9, y - 1), (x + 5, y + 3)], fill=(200, 30, 40, 255))  # potion
    d.line((x + 6, y - 5, x + 8, y - 7), fill=(150, 110, 70, 255), width=2)  # cork
    d.point((x + 2, y), fill=(255, 255, 255, 255))


def sheet(race_id, cls_id, female=False):
    out = Image.new("RGBA", (S * len(FRAMES), S), (0, 0, 0, 0))
    for i, (_name, params) in enumerate(FRAMES):
        out.alpha_composite(frame(race_id, cls_id, female=female, **params), (i * S, 0))
    return out


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
    elif cls_id == "necromancer":  # green mist, floating skulls and souls
        for _ in range(7):
            x, y = rnd.randint(-8, 56), rnd.randint(24, 62)
            dr.ellipse((x, y, x + 20, y + 7), fill=c4((24, 60, 40)))
        for x, y in ((8, 10), (52, 16), (14, 40)):
            dr.ellipse((x, y, x + 6, y + 5), fill=c4((70, 110, 84)))
            dr.point((x + 2, y + 2), fill=(140, 255, 170, 255))
            dr.point((x + 4, y + 2), fill=(140, 255, 170, 255))
        for _ in range(12):
            x, y = rnd.randint(2, 62), rnd.randint(2, 62)
            dr.point((x, y), fill=(150, 255, 180, 255))
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
            gp.save(sheet(race_id, cls_id), OUT + "hero_%s_%s.png" % (race_id, cls_id), do_outline=False)
            gp.save(sheet(race_id, cls_id, True), OUT + "hero_%s_%s_f.png" % (race_id, cls_id), do_outline=False)
    print("hero portraits generated")


if __name__ == "__main__":
    main()
