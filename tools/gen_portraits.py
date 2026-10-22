#!/usr/bin/env python3
"""Detailed 64x64 hero portraits: a race face layer and a class overlay
(headgear, collar, shoulders) drawn over it (UIStyle.portrait / AnimatedPortrait
stack them).

Every race face also has expression variants for the animated HUD portrait:
  race_<id>_blink.png   eyes closed
  race_<id>_glance.png  looks aside
  race_<id>_hurt.png    eyes squeezed, teeth clenched (taking damage)
  race_<id>_wounded.png bruise, blood and sweat (low HP)
Shading: light from the top left, warm shadows on skin, 4-5 tones per material.
Writes assets/sprites/portraits/race_*.png and class_*.png.
Run:  python3 tools/gen_portraits.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp

S = 64
CX = 31.5
OUT_DIR = "sprites/portraits/"
EXPRESSIONS = ("neutral", "blink", "glance", "hurt", "wounded")
FULL = (255, 255, 255, 255)


def c4(rgb, a=255):
    return (int(rgb[0]), int(rgb[1]), int(rgb[2]), a)


def tone(c, f, warm=False):
    """Lighter (f > 1) or darker; warm=True pushes shadows to red (skin)."""
    r, g, b = c[0] * f, c[1] * f, c[2] * f
    if warm and f < 1.0:
        k = (1.0 - f) * 60
        r, g, b = r + k * 0.9, g + k * 0.15, b + k * 0.05
    return (max(0, min(255, int(r))), max(0, min(255, int(g))), max(0, min(255, int(b))), 255)


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def mask(fn):
    m = new()
    fn(ImageDraw.Draw(m))
    return m


LEVELS = (1.22, 1.08, 0.94, 0.8, 0.66)


def shade_region(im, m, base, cx, cy, rx, ry, warm=False, levels=LEVELS, dither=True):
    """Fills the opaque pixels of mask `m` with `base` in bands lit from the
    top left; band borders are dithered (checker) for a softer pixel look."""
    px = im.load()
    mp = m.load()
    cuts = (0.5, 0.12, -0.28, -0.62)
    for y in range(S):
        for x in range(S):
            if mp[x, y][3] == 0:
                continue
            nx = (x - cx) / max(rx, 1)
            ny = (y - cy) / max(ry, 1)
            light = -0.55 * nx - 0.65 * ny + 0.3 * (1 - min(1.0, nx * nx + ny * ny))
            i = 0
            while i < len(cuts) and light <= cuts[i]:
                i += 1
            if dither and i > 0 and light > cuts[i - 1] - 0.06 and (x + y) % 2 == 0:
                i -= 1
            px[x, y] = tone(base, levels[i], warm)


def blend(im, x, y, c, a):
    """Mixes colour c over the pixel with opacity a (0..1)."""
    if not (0 <= x < S and 0 <= y < S):
        return
    px = im.load()
    r, g, b, al = px[x, y]
    if al == 0:
        return
    px[x, y] = (int(r + (c[0] - r) * a), int(g + (c[1] - g) * a), int(b + (c[2] - b) * a), al)


# --------------------------------------------------------------------- faces
def face(skin, hair, style, eyes=(70, 110, 160), beard=None, ears="round", tusks=False, tunic=(95, 75, 55),
         brow=None, scar=False, slim=False, heavy_brow=False, expr="neutral", seed=1):
    rnd = random.Random(seed)
    im = new()
    # Shoulders and tunic with a collar (class overlays draw armour on top).
    torso = mask(lambda d: d.polygon([(2, 63), (6, 53), (20, 47), (43, 47), (57, 53), (61, 63)], fill=FULL))
    shade_region(im, torso, tunic, 22, 50, 30, 12)
    d = ImageDraw.Draw(im)
    for fx in (14, 22, 41, 49):
        d.line((fx, 55, fx + 1, 63), fill=tone(tunic, 0.72))
    d.line((24, 47, 31, 55, 39, 47), fill=tone(tunic, 0.5), width=2)
    # Neck with the shadow under the jaw.
    neck = mask(lambda dd: dd.rectangle((24, 38, 39, 51), fill=FULL))
    shade_region(im, neck, skin, 28, 42, 9, 9, warm=True, levels=(1.0, 0.92, 0.84, 0.76, 0.68))
    d = ImageDraw.Draw(im)
    d.line((25, 41, 38, 41), fill=tone(skin, 0.62, True))
    d.line((26, 42, 37, 42), fill=tone(skin, 0.72, True))
    d.line((33, 44, 34, 49), fill=tone(skin, 0.78, True))  # throat
    # Long hair behind the head.
    if style in ("long", "braids"):
        back = mask(lambda dd: dd.polygon([(14, 18), (49, 18), (52, 44), (47, 54), (17, 54), (11, 44)], fill=FULL))
        shade_region(im, back, tone(hair, 0.78)[:3], 24, 26, 20, 22)
    # Ears.
    if ears == "long":
        for sx in (-1, 1):
            bx = CX + sx * 13.5
            ear = mask(lambda dd, sx=sx, bx=bx: dd.polygon(
                [(bx, 23), (bx + sx * 13, 12), (bx + sx * 10, 19), (bx + sx * 3, 34)], fill=FULL))
            shade_region(im, ear, skin, bx + sx * 5, 20, 8, 10, warm=True)
            d = ImageDraw.Draw(im)
            d.line((bx + sx * 2, 26, bx + sx * 8, 19), fill=tone(skin, 0.68, True))
            d.point((bx + sx * 11, 14), fill=tone(skin, 1.15))
    else:
        big = 1 if ears == "big" else 0
        for sx in (-1, 1):
            ex = CX + sx * 14
            ear = mask(lambda dd, ex=ex: dd.ellipse((ex - 3 - big, 22 - big, ex + 3 + big, 33 + big), fill=FULL))
            shade_region(im, ear, skin, ex, 26, 4, 6, warm=True)
            d = ImageDraw.Draw(im)
            d.arc((ex - 2, 24, ex + 2, 31), 90 if sx < 0 else 270, 270 if sx < 0 else 90, fill=tone(skin, 0.66, True))
    # Head and jaw.
    w = 13 if slim else 14
    head = mask(lambda dd: dd.ellipse((CX - w, 9, CX + w, 45), fill=FULL))
    jaw = mask(lambda dd: dd.polygon([(CX - w + 1, 30), (CX + w - 1, 30), (CX + w - 3, 41), (CX + 4, 47),
                                      (CX - 4, 47), (CX - w + 3, 41)], fill=FULL))
    head.alpha_composite(jaw)
    shade_region(im, head, skin, CX - 5, 20, 16, 20, warm=True)
    d = ImageDraw.Draw(im)
    # Cheekbones, blush, jaw line, chin.
    for x, y in ((21, 33), (22, 34), (42, 33), (41, 34)):
        blend(im, x, y, (220, 110, 100), 0.28)
    d.point((21, 31), fill=tone(skin, 1.18))
    d.line((CX - w + 4, 41, CX - 4, 46), fill=tone(skin, 0.78, True))
    d.line((CX + 4, 46, CX + w - 4, 41), fill=tone(skin, 0.7, True))
    d.point((30, 45), fill=tone(skin, 1.12))
    d.point((31, 45), fill=tone(skin, 1.12))
    # Eyes.
    brow_c = brow or tone(hair, 0.8)[:3]
    ey = 27
    for k, ex in enumerate((24, 39)):
        if expr == "blink":
            d.arc((ex - 3, ey - 2, ex + 3, ey + 2), 20, 160, fill=tone(skin, 0.45, True))
            d.line((ex - 3, ey, ex + 3, ey), fill=tone(skin, 0.55, True))
            d.point((ex - 3 if k == 0 else ex + 3, ey - 1), fill=(30, 20, 20, 255))
        elif expr == "hurt":
            d.line((ex - 3, ey - 1, ex + 3, ey + 1) if k == 0 else (ex - 3, ey + 1, ex + 3, ey - 1),
                   fill=(40, 25, 25, 255))
            d.line((ex - 3, ey + 2, ex + 2, ey + 3) if k == 0 else (ex - 2, ey + 3, ex + 3, ey + 2),
                   fill=tone(skin, 0.6, True))
        else:
            look = 1 if expr == "glance" else 0
            d.rectangle((ex - 3, ey - 1, ex + 3, ey + 2), fill=(242, 238, 230, 255))
            d.line((ex - 3, ey + 2, ex + 3, ey + 2), fill=(205, 195, 190, 255))
            ix = ex + look
            d.rectangle((ix - 1, ey - 1, ix + 1, ey + 2), fill=c4(eyes))
            d.line((ix - 1, ey - 1, ix + 1, ey - 1), fill=tone(eyes, 0.6))
            d.point((ix, ey), fill=(15, 10, 15, 255))
            d.point((ix, ey + 1), fill=(15, 10, 15, 255))
            d.point((ix - 1, ey), fill=(255, 255, 255, 255))
            d.point((ix + 1, ey + 2), fill=tone(eyes, 1.35))
            # Upper lid with lashes, lower lid, eye bag.
            d.line((ex - 4, ey - 2, ex + 3, ey - 2), fill=(45, 30, 30, 255))
            d.point((ex - 4 if k == 0 else ex + 3, ey - 3), fill=(45, 30, 30, 255))
            d.line((ex - 2, ey + 4, ex + 2, ey + 4), fill=tone(skin, 0.84, True))
        # Brows (raised in pain, knitted when wounded).
        lift = -1 if expr == "hurt" else 0
        knit = 1 if expr in ("wounded", "hurt") else 0
        thick = 2 if heavy_brow else 1
        if k == 0:
            pts = (ex - 5, ey - 5 + lift, ex + 3, ey - 6 + lift + knit * 2)
        else:
            pts = (ex - 3, ey - 6 + lift + knit * 2, ex + 5, ey - 5 + lift)
        d.line(pts, fill=c4(brow_c), width=thick + 1)
        d.line((pts[0], pts[1] - 1, pts[2], pts[3] - 1), fill=tone(brow_c, 1.25))
    if heavy_brow:
        d.line((19, 23, 44, 23), fill=tone(skin, 0.7, True))
    # Nose: bridge highlight, shadow side, tip, nostrils.
    nw = 2 if tusks else 1
    d.line((31, 27, 31, 34), fill=tone(skin, 1.14))
    d.line((33, 27, 33 + nw - 1, 35), fill=tone(skin, 0.74, True))
    d.point((31, 35), fill=tone(skin, 1.2))
    d.line((29 - nw, 36, 34 + nw, 36), fill=tone(skin, 0.7, True))
    d.point((29 - nw, 36), fill=tone(skin, 0.52, True))
    d.point((34 + nw, 36), fill=tone(skin, 0.52, True))
    d.point((31, 37), fill=tone(skin, 0.82, True))  # philtrum
    # Mouth.
    if expr == "hurt":
        d.rectangle((27, 39, 36, 42), fill=(70, 25, 30, 255))
        d.line((28, 40, 35, 40), fill=(240, 235, 220, 255))
        d.line((28, 41, 35, 41), fill=(225, 215, 200, 255))
        d.line((27, 39, 36, 39), fill=tone(skin, 0.5, True))
    else:
        frown = 1 if expr == "wounded" else 0
        d.line((27, 40 + frown, 28, 39), fill=tone(skin, 0.55, True))
        d.line((28, 39, 35, 39), fill=(130, 60, 60, 255))
        d.line((35, 39, 36, 40 + frown), fill=tone(skin, 0.55, True))
        d.line((29, 40, 34, 40), fill=tone((200, 110, 105), 1.0))
        d.line((30, 41, 33, 41), fill=tone(skin, 0.86, True))
    if scar:
        d.line((40, 18, 43, 33), fill=tone(skin, 0.62, True))
        d.line((41, 19, 44, 32), fill=tone(skin, 1.12))
        for y in (22, 26, 30):
            d.point((41 + (y - 18) // 5, y), fill=tone(skin, 0.5, True))
    if tusks:
        for tx in (26, 36):
            d.polygon([(tx, 41), (tx + 2, 41), (tx + 2, 35), (tx, 37)], fill=(240, 235, 210, 255))
            d.point((tx + 2, 35), fill=(255, 255, 248, 255))
            d.point((tx, 40), fill=(200, 190, 160, 255))
    # Hair on top.
    if style != "bald":
        if style == "mohawk":
            top = mask(lambda dd: dd.polygon([(27, 1), (36, 1), (37, 16), (26, 16)], fill=FULL))
        else:
            top = mask(lambda dd: dd.chord((15, 6, 48, 32), 180, 360, fill=FULL))
            side = mask(lambda dd: dd.polygon([(16, 16), (21, 13), (19, 26), (16, 28)], fill=FULL))
            top.alpha_composite(side)
        shade_region(im, top, hair, 24, 10, 16, 10)
        d = ImageDraw.Draw(im)
        if style != "mohawk":
            # Strands, a sheen band, a fringe that breaks the line.
            for x0 in range(17, 47, 2):
                d.line((x0, 9 + (x0 % 3), x0 + 1, 15 + (x0 % 4)), fill=tone(hair, 0.72))
            for x0 in range(19, 38, 3):
                d.line((x0, 8, x0 + 2, 11), fill=tone(hair, 1.4))
            for x0 in (20, 25, 30, 36, 41):
                d.polygon([(x0, 16), (x0 + 3, 16), (x0 + 1, 19 + rnd.randint(0, 2))], fill=c4(hair))
        else:
            for y0 in range(2, 16, 2):
                d.line((29, y0, 34, y0), fill=tone(hair, 1.3 if y0 % 4 else 0.75))
            d.point((24, 20), fill=tone(hair, 0.6))  # shaved sides stubble
            d.point((39, 20), fill=tone(hair, 0.6))
        if style in ("long", "braids"):
            for sx, x0 in ((-1, 16), (1, 47)):
                for k in range(3):
                    d.line((x0 + sx * k, 18, x0 - sx + sx * k, 48), fill=tone(hair, 0.7 + 0.25 * k))
            if style == "braids":
                for bx in (16, 47):
                    for by in range(34, 55, 4):
                        d.ellipse((bx - 3, by, bx + 1, by + 3), fill=c4(hair), outline=tone(hair, 0.6))
    # Dwarf beard: mustache, braided beard with gold clasps.
    if beard:
        bm = mask(lambda dd: dd.polygon([(17, 31), (46, 31), (46, 41), (40, 52), (32, 62), (24, 52), (17, 41)], fill=FULL))
        hole = mask(lambda dd: dd.ellipse((26, 36, 37, 43), fill=FULL))
        bp, hp = bm.load(), hole.load()
        for y in range(S):
            for x in range(S):
                if hp[x, y][3]:
                    bp[x, y] = (0, 0, 0, 0)
        shade_region(im, bm, beard, 26, 37, 15, 16)
        d = ImageDraw.Draw(im)
        for x0 in range(19, 45, 2):
            d.line((x0, 42, x0 + (1 if x0 < 32 else -1), 51), fill=tone(beard, 0.7))
            d.point((x0, 44), fill=tone(beard, 1.3))
        d.polygon([(21, 35), (30, 33), (32, 36), (41, 33), (43, 36), (32, 38), (20, 37)], fill=tone(beard, 1.1))
        d.line((22, 36, 30, 34), fill=tone(beard, 1.35))
        d.line((28, 40, 35, 40), fill=tone(skin, 0.45, True))
        for by in (52, 56):
            d.rectangle((29, by, 34, by + 1), fill=(225, 185, 70, 255))
            d.point((30, by), fill=(255, 240, 160, 255))
    # Expression extras.
    if expr == "wounded":
        for x, y, a in ((40, 31, 0.45), (41, 31, 0.45), (40, 32, 0.4), (41, 32, 0.35), (42, 31, 0.3), (39, 31, 0.3)):
            blend(im, x, y, (110, 60, 120), a)  # bruise
        d = ImageDraw.Draw(im)
        d.line((22, 17, 21, 24), fill=(170, 20, 25, 255))  # blood from the forehead
        d.point((21, 25), fill=(140, 10, 15, 255))
        d.point((22, 18), fill=(220, 60, 60, 255))
        d.polygon([(45, 24), (46, 21), (47, 24), (46, 25)], fill=(200, 230, 255, 255))  # sweat drop
    if expr == "hurt":
        for y in (25, 26):
            blend(im, 32, y, (120, 60, 60), 0.4)  # wrinkle between the brows
    return gp.outline(im)


# ----------------------------------------------------------------- overlays
def metal_specular(d, x0, y0, x1, y1, c):
    d.line((x0, y0, x1, y1), fill=tone(c, 1.55))


def pauldrons(im, metal, trim=None, rivets=True):
    for sx in (-1, 1):
        cx = CX + sx * 20
        p = mask(lambda dd, cx=cx: dd.ellipse((cx - 13, 46, cx + 13, 70), fill=FULL))
        shade_region(im, p, metal, cx - 4, 50, 13, 10)
        d = ImageDraw.Draw(im)
        d.arc((cx - 13, 46, cx + 13, 70), 180, 360, fill=c4(trim) if trim else tone(metal, 1.35))
        d.arc((cx - 9, 51, cx + 9, 70), 190, 350, fill=tone(metal, 0.66))
        d.arc((cx - 9, 52, cx + 9, 71), 200, 340, fill=tone(metal, 1.15))
        metal_specular(d, cx - 8, 50, cx - 3, 48, metal)
        if rivets:
            for rx in (-7, 0, 7):
                ry = 50 + abs(rx) // 3
                d.point((cx + rx, ry), fill=tone(metal, 1.6))
                d.point((cx + rx + 1, ry + 1), fill=tone(metal, 0.55))


def warrior():
    im = new()
    metal = (118, 108, 98)
    pauldrons(im, metal)
    d = ImageDraw.Draw(im)
    # Crossed leather straps and a buckle; scratches on the plates.
    d.line((18, 53, 45, 63), fill=(85, 55, 32, 255), width=3)
    d.line((18, 54, 45, 64), fill=(120, 80, 48, 255))
    d.rectangle((29, 56, 34, 60), fill=(205, 170, 80, 255))
    d.rectangle((30, 57, 33, 59), fill=(85, 55, 32, 255))
    for x, y in ((8, 56), (51, 57), (54, 60)):
        d.line((x, y, x + 3, y + 1), fill=tone(metal, 0.6))
    # Miner's helmet: dome, ridge, riveted brim, lamp with a glow.
    dome = mask(lambda dd: dd.chord((14, 0, 49, 34), 180, 360, fill=FULL))
    shade_region(im, dome, metal, 24, 6, 18, 13)
    brim = mask(lambda dd: dd.rectangle((11, 16, 52, 20), fill=FULL))
    shade_region(im, brim, tone(metal, 0.85)[:3], 24, 16, 20, 4)
    d = ImageDraw.Draw(im)
    d.line((12, 20, 51, 20), fill=tone(metal, 0.5))
    d.line((12, 16, 51, 16), fill=tone(metal, 1.35))
    d.line((31, 2, 31, 15), fill=tone(metal, 1.45))
    d.line((32, 2, 32, 15), fill=tone(metal, 0.72))
    metal_specular(d, 19, 9, 24, 5, metal)
    for rx in (15, 21, 27, 36, 42, 48):
        d.point((rx, 18), fill=tone(metal, 1.65))
        d.point((rx + 1, 19), fill=tone(metal, 0.5))
    for x, y in ((40, 8), (44, 12)):
        d.line((x, y, x + 2, y + 2), fill=tone(metal, 0.6))  # dents
    d.rectangle((26, 4, 37, 13), fill=(65, 56, 48, 255))
    d.rectangle((27, 5, 36, 12), fill=(110, 95, 70, 255))
    d.ellipse((28, 5, 35, 12), fill=(255, 232, 150, 255))
    d.ellipse((30, 6, 33, 9), fill=(255, 255, 230, 255))
    glow = new()
    gd = ImageDraw.Draw(glow)
    gd.ellipse((21, -2, 42, 19), fill=(255, 230, 140, 45))
    gd.ellipse((25, 1, 38, 15), fill=(255, 235, 160, 55))
    im = Image.alpha_composite(glow, im)
    return gp.outline(im)


def paladin():
    im = new()
    steel = (214, 214, 226)
    gold = (226, 182, 62)
    tab = mask(lambda dd: dd.polygon([(22, 49), (41, 49), (42, 63), (21, 63)], fill=FULL))
    shade_region(im, tab, (236, 230, 214), 26, 52, 10, 8)
    d = ImageDraw.Draw(im)
    d.line((22, 49, 41, 49), fill=c4(gold))
    d.rectangle((31, 51, 32, 63), fill=c4(gold))
    d.rectangle((26, 55, 37, 56), fill=c4(gold))
    d.point((31, 51), fill=(255, 245, 180, 255))
    for fx in (24, 39):
        d.line((fx, 52, fx, 63), fill=(205, 198, 182, 255))  # folds
    pauldrons(im, steel, trim=gold, rivets=False)
    # Great helm with an open face: plume, dome, gold band and cross, cheek guards.
    plume = mask(lambda dd: dd.polygon([(28, 0), (34, 0), (43, -2), (46, 4), (36, 8), (27, 8)], fill=FULL))
    shade_region(im, plume, (190, 38, 44), 32, 1, 8, 4)
    dome = mask(lambda dd: dd.chord((14, 3, 49, 38), 180, 360, fill=FULL))
    shade_region(im, dome, steel, 24, 9, 18, 13)
    for sx in (-1, 1):
        cheek = mask(lambda dd, sx=sx: dd.polygon(
            [(CX + sx * 17, 18), (CX + sx * 12, 18), (CX + sx * 12, 36), (CX + sx * 15, 41), (CX + sx * 17, 38)],
            fill=FULL))
        shade_region(im, cheek, steel, CX + sx * 13, 24, 4, 11)
    d = ImageDraw.Draw(im)
    d.rectangle((14, 17, 49, 20), fill=c4(gold))
    d.line((14, 17, 49, 17), fill=tone(gold, 1.35))
    d.line((14, 20, 49, 20), fill=tone(gold, 0.66))
    d.line((31, 4, 31, 17), fill=c4(gold))
    d.line((32, 4, 32, 17), fill=tone(gold, 0.7))
    d.line((27, 9, 36, 9), fill=c4(gold))
    metal_specular(d, 19, 12, 25, 6, steel)
    for rx in (17, 46):
        d.point((rx, 18), fill=(255, 250, 220, 255))
    for plume_x in range(30, 44, 3):
        d.point((plume_x, 2), fill=(240, 90, 90, 255))
    return gp.outline(im)


def rogue():
    im = new()
    cloth = (54, 80, 56)
    cloak = mask(lambda dd: dd.polygon([(1, 63), (5, 51), (19, 44), (44, 44), (58, 51), (62, 63)], fill=FULL))
    shade_region(im, cloak, cloth, 20, 48, 30, 12)
    d = ImageDraw.Draw(im)
    for x0 in (10, 17, 44, 51):
        d.line((x0, 53, x0 + 1, 63), fill=tone(cloth, 0.62))
        d.line((x0 + 1, 53, x0 + 2, 63), fill=tone(cloth, 1.15))
    d.ellipse((28, 50, 35, 57), fill=(190, 190, 200, 255), outline=(85, 85, 95, 255))
    d.ellipse((30, 52, 33, 55), fill=(140, 40, 50, 255))
    d.point((29, 51), fill=(255, 255, 255, 255))
    # Hood with the dark opening, seams; a mask over the lower face.
    hood = mask(lambda dd: dd.polygon([(10, 48), (11, 22), (17, 8), (31, 1), (45, 8), (52, 22), (53, 48), (45, 46),
                                        (45, 24), (38, 15), (25, 15), (18, 24), (18, 46)], fill=FULL))
    shade_region(im, hood, cloth, 22, 13, 20, 22)
    d = ImageDraw.Draw(im)
    d.line((18, 24, 25, 15, 38, 15, 45, 24), fill=tone(cloth, 0.4), width=2)
    d.line((19, 25, 19, 45), fill=tone(cloth, 0.42))
    d.line((44, 25, 44, 45), fill=tone(cloth, 0.42))
    d.line((31, 2, 30, 14), fill=tone(cloth, 1.3))
    for y in range(20, 46, 4):
        d.point((13, y), fill=tone(cloth, 0.7))  # stitches
        d.point((50, y + 2), fill=tone(cloth, 0.7))
    shadow = new()
    sd = ImageDraw.Draw(shadow)
    sd.rectangle((19, 16, 44, 23), fill=(0, 0, 0, 70))  # hood shadow over the brow
    im = Image.alpha_composite(im, shadow)
    mk = mask(lambda dd: dd.polygon([(19, 34), (44, 34), (43, 44), (31, 48), (20, 44)], fill=FULL))
    shade_region(im, mk, (42, 42, 48), 26, 36, 12, 8)
    d = ImageDraw.Draw(im)
    for x0 in (23, 28, 33, 38):
        d.line((x0, 35, x0 - 1, 45), fill=(30, 30, 36, 255))
    d.line((19, 34, 44, 34), fill=(78, 78, 90, 255))
    return gp.outline(im)


def mage():
    im = new()
    robe = (70, 50, 150)
    gold = (222, 182, 72)
    collar = mask(lambda dd: dd.polygon([(2, 63), (6, 52), (16, 44), (24, 49), (39, 49), (47, 44), (57, 52), (61, 63)],
                                        fill=FULL))
    shade_region(im, collar, robe, 20, 50, 30, 13)
    d = ImageDraw.Draw(im)
    d.line((16, 44, 24, 49, 31, 57, 39, 49, 47, 44), fill=c4(gold), width=2)
    d.line((31, 57, 31, 63), fill=c4(gold))
    for x0 in (10, 52):
        for y0 in range(54, 63, 3):
            d.point((x0, y0), fill=tone(gold, 1.2))  # embroidery
    d.ellipse((27, 55, 36, 63), fill=(70, 210, 255, 255), outline=c4(gold))
    d.ellipse((29, 57, 32, 60), fill=(190, 245, 255, 255))
    # Pointed hat: bent cone with a patch, wide brim, band with a gem, stars.
    cone = mask(lambda dd: dd.polygon([(17, 17), (46, 17), (39, 8), (42, 2), (50, -1), (40, -1), (32, 2), (24, 8)],
                                      fill=FULL))
    shade_region(im, cone, robe, 27, 7, 14, 10)
    brim = mask(lambda dd: dd.ellipse((4, 13, 59, 25), fill=FULL))
    shade_region(im, brim, tone(robe, 0.9)[:3], 22, 15, 26, 6)
    d = ImageDraw.Draw(im)
    d.arc((4, 13, 59, 25), 0, 180, fill=tone(robe, 0.5))
    d.arc((4, 12, 59, 24), 190, 350, fill=tone(robe, 1.3))
    d.rectangle((18, 13, 45, 16), fill=c4(gold))
    d.line((18, 13, 45, 13), fill=tone(gold, 1.35))
    d.ellipse((29, 11, 35, 17), fill=(255, 75, 90, 255), outline=(150, 30, 45, 255))
    d.point((30, 12), fill=(255, 220, 225, 255))
    d.rectangle((36, 5, 40, 9), fill=tone(robe, 0.72))  # patch
    d.point((38, 5), fill=tone(gold, 1.0))
    d.point((38, 9), fill=tone(gold, 1.0))
    for sx, sy in ((25, 7), (34, 10), (41, 2), (22, 11)):
        d.point((sx, sy), fill=(255, 242, 160, 255))
        d.point((sx + 1, sy), fill=(255, 220, 120, 150))
        d.point((sx - 1, sy), fill=(255, 220, 120, 150))
    return gp.outline(im)


RACES = {
    "human": dict(skin=(232, 186, 148), hair=(95, 60, 32), style="short", eyes=(70, 110, 160), seed=1),
    "dwarf": dict(skin=(214, 158, 118), hair=(140, 70, 35), style="short", eyes=(90, 70, 40),
                  beard=(150, 78, 38), ears="big", tunic=(110, 70, 45), heavy_brow=True, seed=2),
    "elf": dict(skin=(242, 218, 190), hair=(235, 220, 150), style="long", eyes=(60, 170, 120), ears="long",
                tunic=(70, 100, 70), slim=True, seed=3),
    "orc": dict(skin=(112, 162, 82), hair=(35, 35, 35), style="mohawk", eyes=(200, 60, 40), tusks=True,
                ears="big", tunic=(80, 60, 45), scar=True, brow=(40, 50, 30), heavy_brow=True, seed=4),
}


def main():
    for name, kw in RACES.items():
        for expr in EXPRESSIONS:
            suffix = "" if expr == "neutral" else "_" + expr
            gp.save(face(expr=expr, **kw), OUT_DIR + "race_%s%s.png" % (name, suffix), do_outline=False)
    for name, fn in (("warrior", warrior), ("paladin", paladin), ("rogue", rogue), ("mage", mage)):
        gp.save(fn(), OUT_DIR + "class_%s.png" % name, do_outline=False)
    # Heroic close-ups per race x class (preferred when present): gen_hero_portraits.py.
    import gen_hero_portraits
    gen_hero_portraits.main()
    print("portraits generated")


if __name__ == "__main__":
    main()
