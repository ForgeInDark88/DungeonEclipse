#!/usr/bin/env python3
"""Trees of the open surface, 48x80, drawn like the dungeon's monsters
(tools/gen_monsters.py): volume lit from the top left in four dithered
tones, a dark outline in the tree's own darkest colour.

  tree_oak     a broad crown of leaf clusters (back clusters darker), a
               tapered trunk with bark grooves, knots, moss and roots
  tree_pine    tiers of drooping boughs with needle streaks
  tree_willow  a round crown and long hanging strands
  tree_birch   white bark with black marks, a light airy crown
  tree_dead    a gnarled leafless tree, forked branches

The crown fills the top of the sprite: a climbable tree's crown ledge is
80 px over the ground (SurfaceGenerator._trees). The game bends the trees
a pixel in the wind (assets/shaders/foliage_sway.gdshader).
Run from the project root:  python3 tools/gen_trees.py
"""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_monsters as gm  # noqa: E402

W, H = 48, 80
OUT = "assets/sprites/surface"
blank, mask, lit, sh, rgba, FULL = gm.blank, gm.mask, gm.lit, gm.sh, gm.rgba, gm.FULL


def outline(im, col):
    """A 1 px outline in `col` around everything opaque."""
    px = im.load()
    out = im.copy()
    po = out.load()
    for y in range(H):
        for x in range(W):
            if px[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < W and 0 <= yy < H and px[xx, yy][3] > 128:
                    po[x, y] = rgba(col)
                    break
    return out


def h(x, y, s=0):
    return ((x * 73856093) ^ (y * 19349663) ^ (s * 83492791)) % 1000 / 1000.0


# ------------------------------------------------------------------ trunks
def trunk(im, cx, top, bottom, w_top, w_bot, bark, seed, birch=False, moss=None):
    """A tapered trunk lit from the left: grooves, knots, root flare."""
    px = im.load()
    for y in range(top, bottom + 1):
        t = (y - top) / max(1, bottom - top)
        hw = w_top + (w_bot - w_top) * t ** 1.6
        if y > bottom - 4:  # root flare
            hw += (y - (bottom - 4)) * 1.2
        for x in range(int(cx - hw), int(cx + hw) + 1):
            u = (x - (cx - hw)) / max(1.0, 2 * hw)  # 0 left .. 1 right
            f = 1.3 if u < 0.22 else (1.08 if u < 0.5 else (0.86 if u < 0.8 else 0.66))
            if 0.18 < u < 0.26 and (x + y) % 2:
                f = 1.08
            if birch:
                c = (232, 228, 214)
                if h(x // 2, y // 3, seed) < 0.14:
                    c = (40, 38, 36)  # the birch's black marks
                elif h(x, y, seed + 1) < 0.08:
                    c = (190, 184, 170)
            else:
                c = bark
                # vertical grooves that wander a little
                g = (x - cx + math.sin(y * 0.35 + seed) * 1.2)
                if abs(g % 3.0) < 0.7:
                    f *= 0.72
                if h(x, y, seed) < 0.05:
                    f *= 1.2
            if moss and u > 0.6 and h(x, y // 2, seed + 3) < 0.35 and y > top + 6:
                c = moss
            px[x, y] = sh(c, f)
    d = ImageDraw.Draw(im)
    if not birch:
        # knots
        rnd = random.Random(seed)
        for _ in range(2):
            ky = rnd.randint(top + 4, bottom - 8)
            kx = cx + rnd.uniform(-0.5, 0.5) * w_top
            d.ellipse((kx - 1, ky - 1, kx + 1, ky + 1), fill=sh(bark, 0.55))
            d.point((kx - 1, ky - 1), fill=sh(bark, 1.3))
    # roots spreading into the ground
    for side in (-1, 1):
        for k in range(2):
            x0 = cx + side * (w_bot + 1)
            d.line((x0, bottom - 1 - k, x0 + side * (3 + k * 2), bottom), fill=sh(bark if not birch else (200, 196, 184), 0.85 - 0.1 * k))


def branch(d, a, b, col, width=1):
    d.line((a[0], a[1], b[0], b[1]), fill=sh(col, 0.9), width=width)
    d.line((a[0], a[1] - 1, b[0], b[1] - 1), fill=sh(col, 1.2))


# ------------------------------------------------------------------ crowns
def leaf_crown(im, clusters, leaf, seed, airy=False):
    """Leaf clusters: back ones darker, each lit from the top left; leaf
    texture (speckles, ragged rim, sunlit tips)."""
    rnd = random.Random(seed)
    clusters = sorted(clusters, key=lambda c: c[1])  # top first, so lower ones overlap
    back = [c for c in clusters if c[3]]
    front = [c for c in clusters if not c[3]]
    for group, k in ((back, 0.72), (front, 1.0)):
        for (cx, cy, r, _b) in group:
            m = mask(W, H, lambda dd, cx=cx, cy=cy, r=r: dd.ellipse((cx - r, cy - r * 0.86, cx + r, cy + r * 0.86), fill=FULL))
            lit(im, m, sh(leaf, k)[:3], cx - r * 0.3, cy - r * 0.35, r * 1.25, r * 1.1)
    px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a == 0 or (g < r and g < 60):
                continue
            v = h(x, y, seed)
            if v < 0.07:
                px[x, y] = sh((r, g, b), 0.68)
            elif v > 0.95:
                px[x, y] = sh((r, g, b), 1.32)
            # ragged rim: notches where open sky is above
            if y > 0 and px[x, y - 1][3] == 0 and v < (0.3 if airy else 0.18):
                px[x, y] = (0, 0, 0, 0)
    # leaf tips catching the light on the upper rim
    for y in range(1, H):
        for x in range(W):
            if px[x, y][3] and px[x, y - 1][3] == 0 and px[x, y][1] > 60 and h(x, y, seed + 9) < 0.6:
                px[x, y] = sh(px[x, y], 1.25)


def oak():
    rnd = random.Random(31)
    im = blank(W, H)
    bark = (104, 72, 46)
    trunk(im, 24, 34, 79, 2.5, 4.5, bark, 3, moss=(86, 120, 60))
    d = ImageDraw.Draw(im)
    branch(d, (24, 44), (15, 30), bark, 2)
    branch(d, (25, 40), (34, 27), bark, 2)
    branch(d, (24, 36), (24, 22), bark, 1)
    clusters = []
    for _ in range(14):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0, 1) ** 0.7
        x = 24 + math.cos(a) * rr * 15
        y = 24 + math.sin(a) * rr * 13
        clusters.append((x, y, rnd.uniform(6, 9), y < 22 and rnd.random() < 0.5))
    clusters += [(14, 30, 7, False), (34, 30, 7, False), (24, 12, 8, False), (24, 32, 7, False)]
    leaf_crown(im, clusters, (74, 138, 58), 31)
    return outline(im, (22, 40, 20))


def birch():
    rnd = random.Random(41)
    im = blank(W, H)
    trunk(im, 24, 26, 79, 1.5, 3.0, (230, 226, 212), 7, birch=True)
    d = ImageDraw.Draw(im)
    for a, b in (((24, 40), (16, 28)), ((24, 34), (32, 22)), ((24, 30), (20, 16))):
        d.line((a[0], a[1], b[0], b[1]), fill=(70, 62, 56, 255))
    clusters = []
    for _ in range(22):
        a = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0, 1) ** 0.6
        x = 24 + math.cos(a) * rr * 12
        y = 20 + math.sin(a) * rr * 15
        clusters.append((x, y, rnd.uniform(4.5, 6.5), rnd.random() < 0.35))
    clusters += [(24, 8, 6, False), (24, 32, 6, False)]
    leaf_crown(im, clusters, (138, 184, 74), 41)
    # the white trunk shows between airy leaves
    return outline(im, (36, 52, 24))


def pine():
    im = blank(W, H)
    bark = (96, 64, 42)
    trunk(im, 24, 10, 79, 1.5, 3.5, bark, 5)
    needle = (46, 104, 70)
    px = im.load()
    tiers = 6
    for k in range(tiers):
        top = 2 + k * 10
        hw = 6 + k * 3.2
        bottom = top + 15
        m = mask(W, H, lambda dd, top=top, hw=hw, bottom=bottom: dd.polygon(
            [(24 - hw, bottom), (24 - hw * 0.5, bottom - 3), (24, top), (24 + hw * 0.5, bottom - 3), (24 + hw, bottom),
             (24 + hw * 0.6, bottom - 1), (24, bottom + 1), (24 - hw * 0.6, bottom - 1)], fill=FULL))
        layer = blank(W, H)
        lit(layer, m, needle, 24 - hw * 0.35, top + 4, hw * 1.1, 12, flat=0.15)
        lp = layer.load()
        for y in range(H):
            for x in range(W):
                r, g, b, a = lp[x, y]
                if not a:
                    continue
                # needle streaks slanting down to the tips
                if (x * 2 + y * (1 if x > 24 else -1)) % 5 == 0:
                    lp[x, y] = sh((r, g, b), 0.78)
                elif h(x, y, 5) > 0.93:
                    lp[x, y] = sh((r, g, b), 1.3)
        im.alpha_composite(layer)
    return outline(im, (16, 36, 26))


def willow():
    rnd = random.Random(61)
    im = blank(W, H)
    bark = (86, 70, 50)
    trunk(im, 24, 30, 79, 2.5, 5.0, bark, 9, moss=(96, 128, 64))
    d = ImageDraw.Draw(im)
    branch(d, (24, 40), (12, 26), bark, 2)
    branch(d, (24, 38), (36, 24), bark, 2)
    leaf = (104, 140, 74)
    clusters = [(24 + rnd.uniform(-14, 14), 18 + rnd.uniform(-10, 8), rnd.uniform(6, 9), rnd.random() < 0.4) for _ in range(12)]
    leaf_crown(im, clusters, leaf, 61)
    # long hanging strands, irregular: curtains of leaves with gaps, each
    # strand a curve, lit on the left, darker inside the curtain
    x = 5.0
    while x < 44:
        y0 = 18 + int(abs(x - 24) * 0.3) + rnd.randint(0, 5)
        ln = rnd.randint(16, 44)
        sway = rnd.uniform(-0.6, 0.6)
        for k in range(ln):
            y = y0 + k
            if y >= H - 6:
                break
            xx = int(round(x + sway * (k / 10) ** 1.5))
            f = (1.18 if x < 22 else (0.98 if x < 30 else 0.82)) * (1.0 - k / ln * 0.3)
            if h(xx, y, 61) < 0.12:
                continue  # leaves thin out: little gaps
            d.point((xx, y), fill=sh(leaf, f))
            if k % 4 == 1:
                d.point((xx + (1 if x > 24 else -1), y), fill=sh(leaf, f * 0.85))  # a leaf
        x += rnd.choice((1.5, 2.0, 2.0, 3.0, 4.0))
    return outline(im, (30, 46, 26))


def dead():
    rnd = random.Random(71)
    im = blank(W, H)
    bark = (110, 94, 80)
    trunk(im, 24, 22, 79, 2.0, 4.5, bark, 13)
    d = ImageDraw.Draw(im)

    def fork(x, y, a, ln, w, depth):
        if depth == 0 or ln < 3:
            return
        x2, y2 = x + math.cos(a) * ln, y + math.sin(a) * ln
        branch(d, (x, y), (x2, y2), bark, max(1, w))
        for s in (-1, 1):
            if rnd.random() < 0.85:
                fork(x2, y2, a + s * rnd.uniform(0.3, 0.7), ln * rnd.uniform(0.55, 0.75), w - 1, depth - 1)

    fork(24, 30, -math.pi / 2 - 0.5, 12, 2, 4)
    fork(24, 34, -math.pi / 2 + 0.6, 11, 2, 4)
    fork(24, 24, -math.pi / 2, 12, 2, 4)
    # a crow's nest and a hollow
    d.ellipse((30, 14, 35, 17), fill=(88, 66, 44, 255))
    d.line((30, 15, 35, 15), fill=(130, 100, 70, 255))
    d.ellipse((23, 50, 26, 55), fill=(30, 22, 20, 255))
    return outline(im, (36, 30, 26))


TREES = {"tree_oak": oak, "tree_birch": birch, "tree_pine": pine, "tree_willow": willow, "tree_dead": dead}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in TREES.items():
        fn().save(os.path.join(OUT, name + ".png"))
    print("trees: ok")


if __name__ == "__main__":
    main()
