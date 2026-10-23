#!/usr/bin/env python3
"""Fungal biome decorations: glowing mushrooms, puffballs, wall brackets.

Drawn pixel by pixel — dome caps with rim shading and top light, gills under
the cap, shaded stalks, glowing spots — instead of the old flat pieslices.
Run from tools/ (or import from gen_biomes): python gen_mushrooms.py
writes the five PNGs into ../assets/sprites/decor/.
"""
from __future__ import annotations

import os

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "decor")

TEAL = (70, 230, 200, 255)
CYAN = (90, 205, 235, 255)
PURPLE = (200, 125, 240, 255)
AMBER = (225, 150, 80, 255)
STALK = (218, 226, 206, 255)
PALE = (243, 255, 250, 255)


def shade(c, f: float):
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), c[3])


_BOUNDS = (0, 0)


def img(w, h):
    globals()["_BOUNDS"] = (w, h)
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(px, x, y, c):
    bw, bh = _BOUNDS
    if 0 <= x < bw and 0 <= y < bh:
        px[x, y] = c


def cap(px, cx: int, cy: int, r: int, col, dim: float = 1.0):
    """Dome cap with the flat side down at row `cy`: dark silhouette rim,
    lighter band on top, brightest crown, 1px gill shadow under the edge."""
    base = shade(col, dim)
    dark, mid = shade(base, 0.55), shade(base, 0.78)
    lite, glow = shade(base, 1.35), shade(base, 1.65)
    rr = r + 0.5
    for y in range(cy - r, cy + 1):
        for x in range(cx - r - 1, cx + r + 2):
            dx = (x - cx) / rr
            dy = (y - cy) / rr
            d = (dx * dx + dy * dy) ** 0.5
            if d > 1.0:
                continue
            if d > 0.84:
                c = dark
            elif dy < -0.30 and abs(dx) < 0.66:
                c = glow if d < 0.45 else lite
            elif d > 0.62:
                c = mid
            else:
                c = base
            put(px, x, y, c)
    # gills: a darker fringe right under the cap rim
    for x in range(cx - r + 1, cx + r):
        put(px, x, cy + 1, shade(base, 0.45))
    for x in range(cx - r + 2, cx + r - 1, 2):
        put(px, x, cy + 1, shade(base, 0.7))


def stalk(px, x0: int, y0: int, y1: int, w: int = 2, col=STALK):
    dark = shade(col, 0.68)
    for y in range(y0, y1 + 1):
        for k in range(w):
            put(px, x0 + k, y, dark if k == w - 1 else col)
    # little flare at the base
    put(px, x0 - 1, y1, dark)
    put(px, x0 + w, y1, dark)


def spots(px, coords, col=PALE):
    for x, y in coords:
        put(px, x, y, col)
        put(px, x + 1, y, shade(col, 0.85))


def grass(px, coords, col=(52, 96, 78, 255)):
    for x, y in coords:
        put(px, x, y, col)
        put(px, x, y - 1, shade(col, 1.3))


def spores(px, coords, col, alpha: int = 150):
    c = (col[0], col[1], col[2], alpha)
    for x, y in coords:
        put(px, x, y, c)


def mushrooms():
    """16x16: a trio of small glow shrooms at different heights."""
    im = img(16, 16)
    px = im.load()
    # the purple runt first (behind), then the tall cyan, then the teal
    cap(px, 14, 12, 2, PURPLE, 0.85)
    stalk(px, 13, 12, 15, 2)
    cap(px, 10, 7, 4, CYAN)
    stalk(px, 9, 8, 15, 2)
    spots(px, [(9, 5), (12, 7)])
    cap(px, 4, 10, 3, TEAL)
    stalk(px, 3, 11, 15, 2)
    spots(px, [(3, 9)])
    grass(px, [(1, 15), (7, 15), (12, 15)])
    spores(px, [(6, 3), (13, 5)], CYAN)
    return im


def big_mushroom():
    """16x32: one tall mushroom — the fungal biome landmark."""
    im = img(16, 32)
    px = im.load()
    cap(px, 8, 12, 7, TEAL)
    spots(px, [(4, 8), (10, 9), (7, 6), (12, 11), (3, 11)])
    stalk(px, 6, 13, 31, 4)
    # wide base with a shadowed foot
    for x in range(5, 11):
        put(px, x, 30, shade(STALK, 0.6))
        put(px, x, 31, shade(STALK, 0.45))
    for y in (28, 29):
        put(px, 5, y, STALK)
        put(px, 10, y, shade(STALK, 0.68))
    grass(px, [(3, 31), (12, 31), (4, 31)])
    spores(px, [(2, 2), (13, 3), (6, 1), (11, 1)], TEAL)
    return im


def mushroom_cluster():
    """32x32: three glow shrooms of different hue and a tiny sprout."""
    im = img(32, 32)
    px = im.load()
    # tall cyan in the back, teal mid, purple runt in front
    cap(px, 20, 9, 8, CYAN, 0.92)
    stalk(px, 19, 10, 31, 3)
    spots(px, [(17, 6), (23, 7), (20, 4), (24, 10)])
    cap(px, 8, 13, 7, TEAL)
    stalk(px, 7, 14, 31, 3)
    spots(px, [(5, 10), (11, 11), (8, 8)])
    cap(px, 27, 19, 4, PURPLE)
    stalk(px, 26, 20, 31, 2)
    spots(px, [(26, 17)])
    cap(px, 14, 27, 2, TEAL, 0.85)
    stalk(px, 13, 28, 31, 2)
    grass(px, [(3, 31), (17, 31), (24, 31), (30, 31)])
    spores(px, [(14, 4), (26, 2), (5, 5)], CYAN)
    return im


def puffball():
    """16x16: round spore sacs with speckles and a drift of spores."""
    im = img(16, 16)
    px = im.load()

    def ball(cx, cy, r):
        rr = r + 0.5
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r - 1, cx + r + 2):
                dx = (x - cx) / rr
                dy = (y - cy) / rr
                d = (dx * dx + dy * dy) ** 0.5
                if d > 1.0:
                    continue
                if d > 0.82:
                    c = shade(PURPLE, 0.55)
                elif dx < -0.1 and dy < 0.0:
                    c = shade(PURPLE, 1.4)
                elif d > 0.6:
                    c = shade(PURPLE, 0.8)
                else:
                    c = PURPLE
                put(px, x, y, c)

    ball(10, 10, 4)
    ball(4, 11, 3)
    spots(px, [(11, 9), (9, 12), (12, 12), (3, 10)], (245, 200, 255, 255))
    grass(px, [(7, 15), (14, 15)])
    spores(px, [(6, 5), (12, 4), (14, 7), (2, 7)], PURPLE, 140)
    return im


def wall_fungi():
    """16x16: bracket shelves on the wall, amber with growth rings."""
    im = img(16, 16)
    px = im.load()

    def shelf(y0: int, w: int, col=AMBER):
        cy = y0
        h = 3
        for y in range(cy - h, cy + h + 1):
            for x in range(0, w + 2):
                dx = x / (w + 0.5)
                dy = (y - cy) / (h + 0.5)
                d = (dx * dx + dy * dy) ** 0.5
                if d > 1.0 or x == 0:
                    continue
                if d > 0.85:
                    c = shade(col, 0.55)
                elif d > 0.6:
                    c = shade(col, 0.8)
                elif d < 0.32:
                    c = shade(col, 1.25)
                else:
                    c = col
                put(px, x, y, c)
        # darker underside line
        for x in range(1, w):
            put(px, x, cy + h, shade(col, 0.45))

    shelf(4, 7)
    shelf(8, 9)
    shelf(12, 6)
    for x, y in ((3, 3), (6, 7), (4, 11), (8, 10)):
        put(px, x, y, (255, 235, 170, 255))
    return im


ALL = {
    "mushrooms": mushrooms,
    "big_mushroom": big_mushroom,
    "mushroom_cluster": mushroom_cluster,
    "puffball": puffball,
    "wall_fungi": wall_fungi,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ALL.items():
        path = os.path.normpath(os.path.join(OUT, name + ".png"))
        fn().save(path)
        print("wrote", path)
