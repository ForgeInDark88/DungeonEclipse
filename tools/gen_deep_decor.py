#!/usr/bin/env python3
"""Unique decor for the two deep biomes — nothing reused from other biomes.

Ashen Halls: ember mounds, ash stalagmites, charred columns, ash falls.
Crystal Depths: crystal spires, frozen minerals, echo crystals, ice veins.
Run from tools/: python gen_deep_decor.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

DECOR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "decor")

# ------------------------------------------------------------------- helpers
def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def put(px, x, y, c, w, h):
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = c

def sh(c, f):
    return tuple(min(255, int(ch * f)) for ch in c[:3]) + (c[3] if len(c) > 3 else 255,)

def lit_blob(im, cx, cy, rx, ry, base, alpha=255, flat=0.0):
    """Ellipsoid volume light on a filled ellipse."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            nx = (x - cx) / max(rx, 0.5)
            ny = (y - cy) / max(ry, 0.5)
            d = nx * nx + ny * ny
            if d <= 1.0:
                nz = math.sqrt(max(0, 1 - d)) + flat
                ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
                dd = (nx * -0.55 + ny * -0.62 + nz * 0.56) / ln
                level = max(0, min(4, int((dd + 0.1) * 5)))
                tones = [0.4, 0.55, 0.75, 0.95, 1.25]
                px[x, y] = sh(base, tones[level])


# ========================================================== ASHEN HALLS
def ember_mound():
    """16x16: a heap of glowing ash with embers peeking through."""
    im = img(16, 16)
    d = ImageDraw.Draw(im)
    px = im.load()
    # base: dark ash heap
    lit_blob(im, 8, 12, 7, 5, (46, 38, 44))
    # embers: scattered hot dots
    rng = random.Random(41)
    for _ in range(6):
        x = rng.randint(3, 13)
        y = rng.randint(9, 14)
        c = rng.choice([(255, 120, 40, 255), (255, 170, 60, 255), (255, 90, 30, 255)])
        px[x, y] = c
        if x > 0: px[x - 1, y] = sh(c, 0.6)
    # a wisp of smoke
    for y in range(5, 9):
        put(px, 8 + (y % 3 - 1), y, (90, 80, 88, 120), 16, 16)
    return im


def ash_stalagmite():
    """16x24: a spike of compacted ash rising from the floor."""
    im = img(16, 24)
    d = ImageDraw.Draw(im)
    px = im.load()
    # base mound
    lit_blob(im, 8, 21, 6, 4, (52, 42, 48))
    # the spike: layered triangles getting thinner
    for i in range(14):
        w = max(1, 5 - i // 3)
        y = 20 - i
        base = (56, 46, 52)
        d.rectangle((8 - w, y, 8 + w, y), fill=sh(base, 1.1 - i * 0.03))
    # glowing crack
    d.line((8, 18, 6, 10), fill=(255, 100, 40, 180))
    d.line((8, 16, 10, 8), fill=(200, 80, 30, 140))
    # ember at tip
    d.point((8, 6), fill=(255, 140, 50, 255))
    return im


def charred_column():
    """16x32: a broken column of burnt stone, embers in the cracks."""
    im = img(16, 32)
    d = ImageDraw.Draw(im)
    px = im.load()
    # column shaft
    lit_blob(im, 8, 24, 5, 14, (48, 40, 44))
    # broken top
    d.polygon([(3, 8), (6, 3), (9, 5), (13, 7), (13, 12), (3, 12)], fill=(44, 36, 40, 255))
    d.line((4, 7, 12, 7), fill=(60, 50, 54, 255))
    # glowing cracks
    d.line((7, 26, 5, 18), fill=(255, 90, 35, 200))
    d.line((9, 22, 11, 14), fill=(200, 70, 25, 160))
    d.line((6, 14, 6, 8), fill=(255, 110, 40, 150))
    # base rubble
    d.ellipse((2, 28, 14, 32), fill=(40, 32, 36, 255))
    for x in (4, 7, 11):
        d.point((x, 29), fill=(255, 80, 30, 255))
    return im


def ash_fall():
    """16x16: drifting ash from the ceiling — a soft column of grey motes."""
    im = img(16, 16)
    px = im.load()
    rng = random.Random(43)
    for y in range(16):
        for x in range(16):
            if rng.random() < 0.15:
                a = rng.randint(40, 120)
                g = rng.randint(100, 140)
                px[x, y] = (g, g - 5, g, a)
    # a few brighter embers falling
    for _ in range(3):
        x = rng.randint(4, 12)
        y = rng.randint(2, 12)
        px[x, y] = (255, 120, 40, 200)
        if y + 1 < 16: px[x, y + 1] = (200, 80, 30, 100)
    return im


# ======================================================= CRYSTAL DEPTHS
def crystal_spire():
    """16x28: a tall crystal spike cluster, glowing from within."""
    im = img(16, 28)
    d = ImageDraw.Draw(im)
    # main spike
    d.polygon([(4, 27), (7, 3), (11, 27)], fill=(70, 190, 210, 255))
    d.line((7, 3, 7, 27), fill=(180, 250, 255, 255))
    d.line((4, 27, 7, 3), fill=(40, 120, 140, 255))
    # side spike
    d.polygon([(9, 27), (13, 12), (15, 27)], fill=(50, 160, 185, 255))
    d.line((13, 12, 13, 27), fill=(160, 240, 250, 200))
    # small spike
    d.polygon([(1, 27), (3, 18), (4, 27)], fill=(40, 130, 155, 255))
    # base
    d.ellipse((1, 25, 15, 28), fill=(30, 70, 85, 255))
    # inner glow dots
    d.point((7, 12), fill=(220, 255, 255, 255))
    d.point((12, 20), fill=(200, 250, 255, 255))
    d.point((3, 23), fill=(180, 240, 250, 255))
    return im


def frozen_mineral():
    """16x16: a chunk of ice with crystal veins and frozen bubbles."""
    im = img(16, 16)
    d = ImageDraw.Draw(im)
    px = im.load()
    # chunk
    lit_blob(im, 8, 10, 7, 6, (60, 130, 160))
    # crystal veins
    d.line((4, 6, 11, 12), fill=(150, 230, 250, 200))
    d.line((6, 4, 13, 10), fill=(120, 210, 240, 160))
    d.line((8, 8, 12, 5), fill=(180, 255, 255, 180))
    # frozen bubbles
    for x, y in ((6, 9), (9, 7), (11, 11)):
        d.point((x, y), fill=(255, 255, 255, 180))
        if x > 0: d.point((x - 1, y), fill=(200, 250, 255, 100))
    # rim shine
    d.point((4, 5), fill=(255, 255, 255, 220))
    d.point((5, 4), fill=(255, 255, 255, 180))
    return im


def echo_crystal():
    """16x16: a resonating crystal that pulses with inner light."""
    im = img(16, 16)
    d = ImageDraw.Draw(im)
    # outer crystal shell
    d.polygon([(3, 14), (8, 2), (13, 14)], fill=(40, 100, 130, 200))
    # inner glowing core
    d.polygon([(5, 12), (8, 5), (11, 12)], fill=(100, 220, 240, 255))
    # bright center
    d.point((8, 8), fill=(255, 255, 255, 255))
    d.point((7, 7), fill=(200, 255, 255, 255))
    d.point((9, 9), fill=(200, 255, 255, 255))
    # sound rings
    for r in (5, 7):
        for k in range(0, 360, 30):
            a = math.radians(k)
            x = round(8 + r * math.cos(a) * 0.6)
            y = round(10 + r * math.sin(a) * 0.5)
            if 0 <= x < 16 and 0 <= y < 16:
                d.point((x, y), fill=(120, 220, 240, 100))
    return im


def ice_vein():
    """16x16: a crack in the wall filled with glowing crystal."""
    im = img(16, 16)
    d = ImageDraw.Draw(im)
    # the crack
    d.line((2, 4, 8, 8, 14, 6), fill=(30, 70, 90, 255), width=2)
    d.line((3, 6, 8, 10, 13, 8), fill=(30, 70, 90, 200), width=1)
    # crystal fill
    d.line((3, 5, 8, 8, 13, 7), fill=(100, 220, 240, 220), width=1)
    d.line((4, 6, 8, 9, 12, 8), fill=(60, 160, 190, 180), width=1)
    # bright core
    d.point((8, 8), fill=(220, 255, 255, 255))
    d.point((7, 7), fill=(180, 250, 255, 220))
    d.point((9, 9), fill=(180, 250, 255, 220))
    # small satellite crystals
    d.point((5, 6), fill=(150, 230, 250, 200))
    d.point((11, 7), fill=(150, 230, 250, 200))
    return im


# -------------------------------------------------------------------- main
DECOR_MAP = {
    "ember_mound": ember_mound,
    "ash_stalagmite": ash_stalagmite,
    "charred_column": charred_column,
    "ash_fall": ash_fall,
    "crystal_spire": crystal_spire,
    "frozen_mineral": frozen_mineral,
    "echo_crystal": echo_crystal,
    "ice_vein": ice_vein,
}

if __name__ == "__main__":
    os.makedirs(DECOR, exist_ok=True)
    for name, fn in DECOR_MAP.items():
        fn().save(os.path.join(DECOR, name + ".png"))
        print("wrote", name)
