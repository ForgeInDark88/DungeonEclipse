#!/usr/bin/env python3
"""Decoration packs: ~44 extra props for each dungeon biome.

Writes assets/sprites/decor/pack/<biome>/<biome>_<family>_<n>.png and
data/decor/<biome>_pack.tres (a DecorPack of DecorData), and links the pack
from data/biomes/<biome>.tres (decor_pack = ...).

Every prop is a silhouette made of material regions (stone, wood, metal,
cloth, bone, organic, glow...), shaded by one renderer: light from the top
left (lit rim on the top/left edges, shade on the bottom/right), a sparse
dither for texture and a dark outline. Stone tones are sampled from the
biome's own tileset, so the props sit in their walls; cloth, glow and
organic colours come from the biome's theme (THEMES).

  python3 tools/art/gen_decor_pack.py              every biome in THEMES
  python3 tools/art/gen_decor_pack.py catacombs    one biome
Deterministic: each prop's shape comes from crc32(biome, family, n).
"""
import math
import os
import random
import re
import sys
import zlib

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TILES = os.path.join(ROOT, "assets", "sprites", "tiles")
OUT = os.path.join(ROOT, "assets", "sprites", "decor", "pack")
DATA = os.path.join(ROOT, "data", "decor")
BIOMES = os.path.join(ROOT, "data", "biomes")

FLOOR, CEILING, WALL = 0, 1, 2


# --------------------------------------------------------------- colours
def ramp(c, spread=0.38):
    """5 tones dark -> light around a base colour."""
    r, g, b = c
    out = []
    for k in (-2, -1, 0, 1, 2):
        f = 1.0 + k * spread * 0.5
        if k > 0:  # lighter tones drift a little toward warm white
            out.append(tuple(min(255, int(v * f + (255 - v) * 0.06 * k)) for v in (r, g, b)))
        else:
            out.append(tuple(max(0, min(255, int(v * f))) for v in (r, g, b)))
    return out


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def stone_ramp(biome):
    """5 tones from the biome's brick tiles (row 1), a bit more contrast."""
    path = os.path.join(TILES, "tiles_%s.png" % biome)
    im = Image.open(path).convert("RGBA")
    px = sorted((p[:3] for y in range(16, 32) for x in range(0, 32)
                 for p in [im.getpixel((x, y))] if p[3] > 0), key=lum)
    q = [px[int(len(px) * f)] for f in (0.04, 0.22, 0.5, 0.78, 0.96)]
    mid = q[2]
    out = []
    for i, c in enumerate(q):
        k = (i - 2) * 0.12
        out.append(tuple(max(0, min(255, int((v + (v - m) * 0.25 + 255 * k * 0.35) * 1.18 + 12)))
                         for v, m in zip(c, mid)))
    return out


# --------------------------------------------------------------- canvas
class Sprite:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cells = {}  # (x, y) -> (material, tone offset)
        self.marks = {}  # (x, y) -> (material, absolute tone) drawn after shading

    def put(self, x, y, mat, off=0):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[(x, y)] = (mat, off)

    def mark(self, x, y, mat, tone):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.marks[(x, y)] = (mat, tone)

    def erase(self, x, y):
        self.cells.pop((int(x), int(y)), None)

    def rect(self, x0, y0, x1, y1, mat, off=0):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, mat, off)

    def ellipse(self, cx, cy, rx, ry, mat, off=0):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if rx > 0 and ry > 0 and ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, mat, off)

    def line(self, x0, y0, x1, y1, mat, off=0, width=1):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for d in range(width):
                self.put(x + d, y, mat, off)

    def tri(self, cx, base_y, half, tip_y, mat, off=0, jag=None):
        """A spike from base_y (wide) to tip_y (point)."""
        steps = abs(tip_y - base_y)
        sgn = 1 if tip_y > base_y else -1
        for i in range(steps + 1):
            hw = half * (1 - i / max(1, steps))
            if jag:
                hw += jag.choice((0, 0, 0.6, -0.6))
            y = base_y + sgn * i
            for x in range(int(math.floor(cx - hw)), int(math.ceil(cx + hw)) + 1):
                if abs(x - cx) <= hw + 0.25:
                    self.put(x, y, mat, off)

    def render(self, pal, outline=True):
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = im.load()
        cells = self.cells
        for (x, y), (mat, off) in cells.items():
            r = pal[mat]
            t = 2 + off
            lit = (x - 1, y) not in cells or (x, y - 1) not in cells
            dark = (x + 1, y) not in cells or (x, y + 1) not in cells
            if lit and not dark:
                t += 1
            elif dark and not lit:
                t -= 1
            if mat not in GLOWS and (x * 7 + y * 13 + (x * y) % 5) % 11 == 0:
                t -= 1  # sparse dither: texture without noise
            px[x, y] = r[max(0, min(4, t))] + (255,)
        for (x, y), (mat, tone) in self.marks.items():
            px[x, y] = pal[mat][max(0, min(4, tone))] + (255,)
        if outline:
            edge = {}
            for (x, y), (mat, _o) in cells.items():
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (x + dx, y + dy)
                    if q not in cells and q not in self.marks and 0 <= q[0] < self.w and 0 <= q[1] < self.h:
                        if mat in GLOWS:
                            continue  # glowing things have no hard outline
                        edge[q] = mat
            for (x, y), mat in edge.items():
                c = pal[mat][0]
                px[x, y] = (int(c[0] * 0.45), int(c[1] * 0.42), int(c[2] * 0.48), 255)
        return im


GLOWS = {"glow", "fire", "flame"}


# --------------------------------------------------------------- families
# Each returns (sprite, placement, glow?, sway?). `r` is a seeded Random.

def f_urn(r, t):
    s = Sprite(16, 16)
    cx, cy = 8, 10 + r.choice((0, 1))
    rx, ry = r.choice((4, 5, 5, 6)), r.choice((4, 4, 5))
    s.ellipse(cx, cy, rx, ry, "clay")
    s.rect(cx - 1 - r.choice((0, 1)), cy - ry - 3, cx + 1, cy - ry, "clay")
    s.rect(cx - 2, cy - ry - 3, cx + 2, cy - ry - 3, "clay", 1)
    s.rect(cx - 2, 15, cx + 2, 15, "clay", -1)
    band = cy - r.choice((1, 0, -1))
    for x in range(cx - rx + 1, cx + rx):
        if (x, band) in s.cells:
            s.put(x, band, "cloth", 0)
    if r.random() < 0.5:
        s.line(cx - rx - 1, cy - 2, cx - rx, cy - ry - 1, "clay")
        s.line(cx + rx + 1, cy - 2, cx + rx, cy - ry - 1, "clay")
    if r.random() < 0.3:  # a chip
        s.erase(cx + rx - 1, cy - 2)
        s.erase(cx + rx - 2, cy - 3)
    return s, FLOOR, False, False


def f_amphora(r, t):
    s = Sprite(16, 24)
    cx = 8
    s.ellipse(cx, 14, r.choice((4, 5)), 7, "clay")
    s.tri(cx, 20, 3, 23, "clay")
    s.rect(cx - 1, 3, cx + 1, 7, "clay")
    s.rect(cx - 2, 2, cx + 2, 3, "clay", 1)
    s.line(cx - 4, 10, cx - 2, 4, "clay")
    s.line(cx + 4, 10, cx + 2, 4, "clay")
    for y in (12, 13) if r.random() < 0.6 else (15,):
        for x in range(0, 16):
            if (x, y) in s.cells:
                s.put(x, y, "cloth")
    return s, FLOOR, False, False


def f_rubble(r, t):
    s = Sprite(16, 16)
    for _ in range(r.randint(3, 6)):
        rx, ry = r.choice((1.5, 2, 2.5, 3)), r.choice((1.2, 1.5, 2))
        cx = r.uniform(2 + rx, 14 - rx)
        s.ellipse(cx, 15 - ry, rx, ry, "stone", r.choice((0, 0, -1, 1)))
    if r.random() < 0.5:
        s.ellipse(r.uniform(5, 11), 12, 2.5, 2.2, "stone", 1)
    return s, FLOOR, False, False


def f_stalagmite(r, t):
    h = r.choice((16, 24, 24, 32))
    s = Sprite(16, h)
    s.tri(8 + r.choice((-1, 0, 1)), h - 1, r.choice((3.5, 4.5, 5.5)), r.randint(1, 4), "stone", 0, r)
    if r.random() < 0.6:
        s.tri(r.choice((3, 13)), h - 1, 2, h - r.randint(5, 9), "stone", -1)
    return s, FLOOR, False, False


def f_stalactite(r, t):
    h = r.choice((16, 16, 24))
    s = Sprite(16, h)
    s.tri(8 + r.choice((-2, 0, 2)), 0, r.choice((3, 4, 5)), h - r.randint(1, 5), "stone", 0, r)
    if r.random() < 0.7:
        s.tri(r.choice((3, 12)), 0, 2, r.randint(4, 9), "stone", -1)
    if r.random() < 0.4:
        tip = max(y for (x, y) in s.cells)
        s.mark(max(x for (x, y) in s.cells if y == tip), tip + 2, "water", 3)
    return s, CEILING, False, False


def f_crystals(r, t):
    s = Sprite(16, r.choice((16, 24)))
    h = s.h
    for _ in range(r.randint(2, 5)):
        cx = r.uniform(3, 13)
        top = r.randint(1 if h == 16 else 2, h - 6)
        s.tri(cx, h - 1, r.choice((1.5, 2, 2.5)), top, "glow", r.choice((0, 0, 1, -1)))
    s.ellipse(8, h - 1, 5, 1.5, "stone")
    return s, FLOOR, True, False


def f_crystal_hang(r, t):
    s = Sprite(16, 16)
    for _ in range(r.randint(2, 4)):
        s.tri(r.uniform(3, 13), 0, r.choice((1.5, 2, 2.5)), r.randint(5, 14), "glow", r.choice((0, 1, -1)))
    s.rect(2, 0, 13, 0, "stone")
    return s, CEILING, True, False


def f_mushroom(r, t):
    s = Sprite(16, r.choice((16, 16, 24)))
    h = s.h
    for i in range(r.randint(1, 3)):
        cx = 8 if i == 0 else r.choice((3, 4, 12, 13))
        sh = r.randint(4, h - 6) if i == 0 else r.randint(2, 5)
        cr = r.choice((3, 4, 5)) if i == 0 else 2
        s.rect(cx - (1 if i == 0 else 0), h - sh, cx + (0 if i == 0 else 0), h - 1, "bone")
        s.ellipse(cx, h - sh, cr, max(1.5, cr * 0.6), t["cap"], 0)
        for _ in range(cr - 1):
            s.mark(cx + r.randint(-cr + 1, cr - 1), h - sh - r.randint(0, 1), t["cap"], 4)
    return s, FLOOR, t["cap"] == "glow", False


def f_bones(r, t):
    s = Sprite(16, 16)
    for _ in range(r.randint(2, 4)):
        y = r.randint(12, 14)
        x0 = r.randint(1, 7)
        x1 = x0 + r.randint(4, 7)
        s.line(x0, y, x1, y + r.choice((-1, 0, 1)), "bone")
        s.put(x0 - 1, y - 1, "bone", 1)
        s.put(x1 + 1, y - 1, "bone", 1)
    if r.random() < 0.6:
        cx = r.randint(5, 11)
        s.ellipse(cx, 11, 2.5, 2.2, "bone", 1)
        s.mark(cx - 1, 11, "stone", 0)
        s.mark(cx + 1, 11, "stone", 0)
    return s, FLOOR, False, False


def f_skulls(r, t):
    s = Sprite(16, 16)
    spots = r.sample([(4, 13), (8, 13), (12, 13), (6, 10), (10, 10), (8, 7)], r.randint(2, 5))
    for (x, y) in sorted(spots, key=lambda p: -p[1]):
        s.ellipse(x, y, 2.2, 2, "bone", r.choice((0, 1)))
        s.rect(x - 1, y + 2, x + 1, y + 2, "bone", -1)
    for (x, y) in spots:
        s.mark(x - 1, y, "stone", 0)
        s.mark(x + 1, y, "stone", 0)
    return s, FLOOR, False, False


def f_candles(r, t):
    s = Sprite(16, 16)
    for i in range(r.randint(1, 4)):
        x = 3 + i * 3 + r.choice((0, 1))
        top = r.randint(7, 12)
        s.rect(x, top, x + 1, 15, "wax")
        s.mark(x, top - 1, "fire", 3)
        s.mark(x, top - 2, "flame", 4)
        s.mark(x + 1, top - 1, "fire", 1)
        if r.random() < 0.5:
            s.put(x + 1, top + 1, "wax", 1)  # a drip
    s.rect(1, 15, 14, 15, "wax", -1) if r.random() < 0.4 else None
    return s, FLOOR, True, False


def f_crate(r, t):
    s = Sprite(16, 16)
    w = r.choice((10, 11, 12))
    h = r.choice((8, 9, 10))
    x0 = 8 - w // 2
    s.rect(x0, 16 - h, x0 + w - 1, 15, "wood")
    for y in range(16 - h + 3, 15, 3):
        for x in range(x0 + 1, x0 + w - 1):
            s.mark(x, y, "wood", 0)
    s.line(x0 + 1, 16 - h + 1, x0 + w - 2, 14, "wood", 1)
    for cx, cy in ((x0, 16 - h), (x0 + w - 1, 16 - h), (x0, 15), (x0 + w - 1, 15)):
        s.put(cx, cy, "metal", 1)
    if r.random() < 0.5:  # a second, smaller crate on top
        s.rect(x0 + 2, 16 - h - 5, x0 + 7, 16 - h - 1, "wood", 1)
    return s, FLOOR, False, False


def f_barrel(r, t):
    s = Sprite(16, 16)
    rx = r.choice((4, 5))
    for y in range(3, 16):
        bulge = rx + (1 if 6 <= y <= 12 else 0)
        s.rect(8 - bulge, y, 7 + bulge, y, "wood")
    for y in (5, 13) + ((9,) if r.random() < 0.5 else ()):
        for x in range(0, 16):
            if (x, y) in s.cells:
                s.put(x, y, "metal")
    s.ellipse(7.5, 3, rx - 0.5, 1, "wood", 1)
    return s, FLOOR, False, False


def f_sack(r, t):
    s = Sprite(16, 16)
    s.ellipse(8, 11.5, r.choice((4, 5)), 4.5, "cloth2")
    s.rect(7, 5, 9, 7, "cloth2", 1)
    s.put(8, 4, "cloth2", 1)
    s.line(6, 8, 10, 8, "wood", 0)
    if r.random() < 0.5:
        s.ellipse(12, 13, 3, 2.5, "cloth2", -1)
    return s, FLOOR, False, False


def f_books(r, t):
    s = Sprite(16, 16)
    y = 15
    for _ in range(r.randint(2, 4)):
        w = r.randint(6, 10)
        x0 = r.randint(2, 14 - w)
        mat = r.choice(("cloth", "cloth2", "wood"))
        s.rect(x0, y - 1, x0 + w, y, mat)
        s.mark(x0 + w, y - 1, "bone", 3)  # pages
        y -= 2
    if r.random() < 0.5:
        s.rect(11, y - 3, 13, y, "wax")
        s.mark(12, y - 4, "fire", 3)
        s.mark(12, y - 5, "flame", 4)
    return s, FLOOR, False, False


def f_column(r, t):
    h = r.choice((24, 32))
    s = Sprite(16, h)
    top = r.randint(2, 8)
    s.rect(4, top, 11, h - 3, "stone")
    s.rect(3, h - 3, 12, h - 1, "stone", -1)
    for x in (6, 9):
        for y in range(top + 1, h - 3):
            s.mark(x, y, "stone", 1)
    for x in range(4, 12):  # broken top
        for k in range(r.randint(0, 3)):
            s.erase(x, top + k)
    if r.random() < 0.5:
        s.ellipse(r.choice((2, 13)), h - 2, 2, 1.5, "stone", 1)
    return s, FLOOR, False, False


def f_bust(r, t):
    s = Sprite(16, 24)
    mat = t.get("statue", "stone")
    s.rect(4, 17, 11, 23, mat, -1)
    s.rect(3, 16, 12, 16, mat)
    s.ellipse(8, 13, 5, 3, mat)
    s.ellipse(8, 7, 3, 3.5, mat, 1)
    s.mark(7, 7, mat, 0)
    s.mark(9, 7, mat, 0)
    if r.random() < 0.5:  # broken shoulder / nose
        s.erase(12, 12)
        s.erase(12, 13)
        s.erase(11, 11)
    return s, FLOOR, False, False


def f_brazier(r, t):
    s = Sprite(16, 16)
    s.ellipse(8, 8, 5, 2.5, "metal")
    s.rect(4, 7, 12, 8, "metal", 1)
    s.line(5, 10, 3, 15, "metal")
    s.line(11, 10, 13, 15, "metal")
    s.line(8, 10, 8, 15, "metal", -1)
    for i in range(r.randint(3, 5)):
        x = r.randint(5, 11)
        top = r.randint(1, 4)
        for y in range(top, 7):
            s.put(x, y, "fire", 2 - (y - top) // 2)
    return s, FLOOR, True, False


def f_ferns(r, t):
    s = Sprite(16, 16)
    for _ in range(r.randint(4, 7)):
        x0 = r.uniform(4, 12)
        ang = r.uniform(-1.1, 1.1)
        ln = r.uniform(5, 11)
        s.line(x0, 15, x0 + math.sin(ang) * ln, 15 - math.cos(ang) * ln, "plant", r.choice((0, 1, -1)))
    return s, FLOOR, False, False


def f_puddle(r, t):
    s = Sprite(16, 16)
    w = r.choice((5, 6, 7))
    s.ellipse(8, 15, w, 1.2, t["liquid"])
    s.mark(8 - w // 2, 15, t["liquid"], 4)
    s.mark(8 + 1, 15, t["liquid"], 3)
    return s, FLOOR, t["liquid"] in GLOWS, False


def f_sword(r, t):
    s = Sprite(16, 16)
    x = 8 + r.choice((-2, 0, 2))
    s.line(x, 4, x, 13, "metal", 1)
    s.line(x - 3, 5, x + 3, 5, "gold")
    s.rect(x, 1, x, 4, "wood")
    s.put(x, 0, "gold", 1)
    s.ellipse(8, 14.5, 5, 1.5, "stone")
    return s, FLOOR, False, False


def f_chain(r, t):
    h = r.choice((16, 24))
    s = Sprite(16, h)
    x = 8 + r.choice((-3, 0, 3))
    for y in range(0, h - 3):
        if y % 4 in (0, 1):
            s.put(x - 1, y, "metal")
            s.put(x + 1, y, "metal")
        else:
            s.put(x, y, "metal", 1)
    end = r.choice(("hook", "ring", "cage"))
    if end == "hook":
        s.line(x, h - 3, x, h - 1, "metal")
        s.put(x - 1, h - 1, "metal")
        s.put(x - 2, h - 2, "metal")
    elif end == "ring":
        s.ellipse(x, h - 2, 2, 1.5, "metal")
        s.erase(x, h - 2)
    else:
        s.rect(x - 3, h - 6, x + 3, h - 1, "metal")
        for yy in range(h - 5, h - 1):
            for xx in (x - 2, x, x + 2):
                s.mark(xx, yy, "metal", 0)
    return s, CEILING, False, True


def f_roots(r, t):
    s = Sprite(16, r.choice((16, 24)))
    for _ in range(r.randint(2, 4)):
        x = r.uniform(2, 14)
        y = 0.0
        ln = r.randint(6, s.h - 2)
        while y < ln:
            s.put(x, y, "root", r.choice((0, 0, -1)))
            x += r.choice((-0.5, 0, 0, 0.5))
            y += 1
    s.rect(0, 0, 15, 0, "root", -1)
    return s, CEILING, False, True


def f_lantern(r, t):
    s = Sprite(16, r.choice((16, 24)))
    h = s.h
    for y in range(0, h - 8):
        s.put(8, y, "metal", 0 if y % 2 else 1)
    s.rect(5, h - 8, 11, h - 8, "metal", 1)
    s.rect(6, h - 7, 10, h - 2, "glow", 1)
    s.rect(5, h - 1, 11, h - 1, "metal")
    for y in range(h - 7, h - 1):
        s.put(5, y, "metal")
        s.put(11, y, "metal")
    return s, CEILING, True, True


def f_moss(r, t):
    s = Sprite(16, 16)
    for x in range(0, 16):
        ln = r.choice((1, 2, 2, 3, 4, 6, 8)) if r.random() < 0.8 else 0
        for y in range(ln):
            s.put(x, y, "plant", -1 if y > ln - 2 else 0)
    return s, CEILING, False, True


def f_banner(r, t):
    s = Sprite(16, 24)
    s.rect(2, 1, 13, 1, "wood", 1)
    s.rect(4, 2, 11, 19, "cloth")
    for x in range(4, 12):  # notched / torn bottom
        cut = abs(x - 7.5) < 1.5 if r.random() < 0.5 else (x % 3 == 0)
        if cut:
            s.erase(x, 19)
            s.erase(x, 18)
    for y in range(2, 19):
        s.put(4, y, "cloth", -1)
        s.put(11, y, "cloth", -1)
    emblem = t["emblem"]
    for (ex, ey) in EMBLEMS[emblem if r.random() < 0.7 else r.choice(list(EMBLEMS))]:
        s.mark(ex + 6, ey + 7, "gold", 3)
    return s, WALL, False, True


EMBLEMS = {
    "sun": [(1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (1, 3), (2, 3), (1, -1), (2, 4), (-1, 1), (4, 2)],
    "skull": [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (3, 1), (1, 2), (2, 2), (1, 3), (2, 3)],
    "tree": [(1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (1, 3), (1, 4), (2, 4)],
    "eye": [(0, 1), (1, 0), (2, 0), (3, 1), (1, 2), (2, 2), (1, 1), (2, 1)],
    "wave": [(0, 1), (1, 0), (2, 1), (3, 0), (0, 3), (1, 2), (2, 3), (3, 2)],
    "flame": [(1, 0), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (3, 3), (0, 3), (1, 3), (2, 3)],
}


def f_shield(r, t):
    s = Sprite(16, 16)
    for y in range(2, 14):
        hw = 5 if y < 9 else 5 - (y - 8)
        s.rect(8 - hw, y, 7 + hw, y, "cloth")
    for y in range(2, 14):
        for x in range(16):
            if (x, y) in s.cells and ((x - 1, y) not in s.cells or (x + 1, y) not in s.cells or y == 2):
                s.put(x, y, "metal", 1)
    if r.random() < 0.5:
        s.rect(7, 3, 8, 12, "gold")
        s.rect(4, 6, 11, 7, "gold")
    else:
        s.ellipse(7.5, 7, 2, 2, "gold")
    return s, WALL, False, False


def f_crossed(r, t):
    s = Sprite(16, 16)
    s.line(2, 13, 13, 2, "metal", 1)
    s.line(2, 2, 13, 13, "metal", 1)
    s.line(1, 11, 4, 14, "gold")
    s.line(11, 14, 14, 11, "gold")
    s.ellipse(8, 8, 3, 3, r.choice(("wood", "cloth")))
    return s, WALL, False, False


def f_relief(r, t):
    s = Sprite(16, 16)
    s.rect(2, 2, 13, 13, "stone", 1)
    s.rect(2, 2, 13, 2, "stone", 2)
    glyph = r.choice(list(EMBLEMS))
    for (ex, ey) in EMBLEMS[glyph]:
        s.mark(ex + 6, ey + 5, "stone", 0)
    if r.random() < 0.5:  # a crack through it
        x = r.randint(4, 11)
        for y in range(2, 14, 1):
            if r.random() < 0.6:
                s.mark(x, y, "stone", 0)
            x += r.choice((-1, 0, 1))
    return s, WALL, False, False


def f_mask(r, t):
    s = Sprite(16, 16)
    mat = r.choice(("gold", "bone", "metal"))
    s.ellipse(8, 8, 4.5, 5.5, mat)
    for (x, y) in ((6, 7), (10, 7), (7, 11), (8, 11), (9, 11)):
        s.mark(x, y, "stone", 0)
    if r.random() < 0.5:
        s.line(3, 3, 5, 5, mat, 1)
        s.line(12, 3, 10, 5, mat, 1)
    return s, WALL, False, False


def f_grate(r, t):
    s = Sprite(16, 16)
    s.rect(3, 4, 12, 13, "dark")
    for x in range(3, 13, 3):
        s.rect(x, 4, x, 13, "metal")
    s.rect(3, 4, 12, 4, "metal", 1)
    s.rect(3, 13, 12, 13, "metal", -1)
    if r.random() < 0.4:
        for y in range(5, 13):
            s.mark(r.choice((4, 5, 7, 8)), y, "glow", 1) if r.random() < 0.2 else None
    return s, WALL, False, False


def f_sconce(r, t):
    s = Sprite(16, 16)
    s.rect(7, 9, 8, 12, "metal")
    s.rect(5, 8, 10, 8, "metal", 1)
    s.rect(7, 5, 8, 7, "wax")
    s.mark(7, 4, "fire", 3)
    s.mark(8, 4, "fire", 2)
    s.mark(7, 3, "flame", 4)
    s.mark(7, 2, "flame", 3)
    return s, WALL, True, False


def f_shelf(r, t):
    s = Sprite(16, 16)
    s.rect(1, 11, 14, 12, "wood")
    s.line(2, 13, 4, 15, "wood", -1)
    s.line(13, 13, 11, 15, "wood", -1)
    x = 2
    while x < 13:
        kind = r.choice(("pot", "book", "skull", "bottle"))
        if kind == "pot":
            s.ellipse(x + 1.5, 8.5, 1.8, 2, "clay")
            x += 4
        elif kind == "book":
            s.rect(x, 6, x + 1, 10, r.choice(("cloth", "cloth2")))
            x += 2
        elif kind == "skull":
            s.ellipse(x + 1.5, 9, 1.8, 1.6, "bone")
            x += 4
        else:
            s.rect(x + 1, 6, x + 1, 7, "glass")
            s.rect(x, 8, x + 2, 10, "glass")
            x += 4
    return s, WALL, False, False


def f_ivy(r, t):
    s = Sprite(16, 16)
    x, y = r.uniform(4, 12), 0.0
    for _ in range(26):
        s.put(x, y, "plant", r.choice((0, -1)))
        if r.random() < 0.45:
            s.put(x + r.choice((-1, 1)), y, "plant", 1)
        x = min(14, max(1, x + r.choice((-1, 0, 1))))
        y += r.choice((0.5, 0.7, 1))
        if y > 15:
            break
    return s, WALL, False, True


def f_mirror(r, t):
    s = Sprite(16, 24)
    s.ellipse(8, 11, 5, 8, "gold")
    s.ellipse(8, 11, 3.6, 6.4, "glass", 1)
    s.line(6, 6, 9, 15, "glass", 2) if r.random() < 0.6 else None
    if r.random() < 0.4:  # cracked
        s.mark(9, 9, "dark", 1)
        s.mark(10, 10, "dark", 1)
        s.mark(8, 11, "dark", 1)
    return s, WALL, False, False


def f_coral(r, t):
    s = Sprite(16, 16)

    def branch(x, y, ang, ln, depth):
        for i in range(int(ln)):
            s.put(x, y, "coral", 1 if i == 0 else 0)
            x += math.sin(ang)
            y -= math.cos(ang)
        if depth > 0:
            branch(x, y, ang - 0.6, ln * 0.7, depth - 1)
            branch(x, y, ang + 0.6, ln * 0.7, depth - 1)

    branch(8, 15, r.uniform(-0.2, 0.2), r.randint(4, 6), 2)
    return s, FLOOR, False, False


def f_barnacles(r, t):
    s = Sprite(16, 16)
    for _ in range(r.randint(4, 8)):
        cx, cy = r.uniform(3, 13), r.uniform(3, 13)
        s.ellipse(cx, cy, 1.6, 1.4, "bone")
        s.mark(cx, cy, "dark", 1)
    return s, WALL, False, False


def f_anchor(r, t):
    s = Sprite(16, 16)
    s.rect(7, 2, 8, 13, "metal")
    s.ellipse(7.5, 2, 2, 1.5, "metal")
    s.rect(4, 5, 11, 5, "metal")
    s.line(2, 10, 7, 14, "metal")
    s.line(13, 10, 8, 14, "metal")
    s.put(2, 9, "metal", 1)
    s.put(13, 9, "metal", 1)
    return s, FLOOR, False, False


def f_spire(r, t):
    s = Sprite(16, 32)
    s.tri(8, 31, r.choice((4, 5)), r.randint(1, 6), t.get("spire", "dark"), 0, r)
    s.tri(r.choice((4, 12)), 31, 2, r.randint(16, 22), t.get("spire", "dark"), -1)
    for y in range(8, 28, r.choice((3, 4))):
        s.mark(7, y, "glow", 2) if r.random() < 0.5 else None
    return s, FLOOR, True, False


def f_ash(r, t):
    s = Sprite(16, 16)
    s.ellipse(8, 14.5, r.choice((5, 6)), r.choice((2, 2.5, 3)), "ash")
    for _ in range(r.randint(0, 3)):
        s.mark(r.randint(4, 12), 14, "fire", 2)
    if r.random() < 0.5:
        s.line(4, 13, 11, 11, "wood", -2)
    return s, FLOOR, False, False


def f_sigil(r, t):
    s = Sprite(16, 16)
    s.ellipse(8, 8, 6, 6, "glow", -1)
    s.ellipse(8, 8, 4.5, 4.5, "dark")
    s.ellipse(8, 8, 2.5, 2.5, "glow", 1)
    for a in range(0, 360, 45):
        s.mark(8 + math.cos(math.radians(a)) * 7, 8 + math.sin(math.radians(a)) * 7, "glow", 3)
    return s, WALL, True, False


def f_wheel(r, t):
    s = Sprite(16, 16)
    s.ellipse(8, 9, 6, 6, "wood")
    s.ellipse(8, 9, 4, 4, "wood", -1)
    for a in range(0, 180, 45):
        dx, dy = math.cos(math.radians(a)) * 5, math.sin(math.radians(a)) * 5
        s.line(8 - dx, 9 - dy, 8 + dx, 9 + dy, "wood", 1)
    s.ellipse(8, 9, 1.2, 1.2, "metal")
    return s, FLOOR, False, False


def f_pedestal(r, t):
    s = Sprite(16, 16)
    s.rect(5, 9, 10, 15, "stone")
    s.rect(4, 8, 11, 8, "stone", 1)
    s.rect(4, 15, 11, 15, "stone", -1)
    s.ellipse(7.5, 5, 2.5, 2.5, "glow", 1)
    return s, FLOOR, True, False


def f_ribcage(r, t):
    s = Sprite(16, 16)
    s.line(2, 14, 13, 14, "bone")
    for x in range(3, 13, 2):
        hgt = 6 - abs(x - 8) // 2
        s.line(x, 14, x + 1, 14 - hgt, "bone", 1)
    s.ellipse(14, 12, 1.8, 1.6, "bone")
    return s, FLOOR, False, False


FAMILIES = {name[2:]: fn for name, fn in globals().items() if name.startswith("f_")}

# --------------------------------------------------------------- themes
# Each biome: colours of its non-stone materials and how many props of each
# family (about 44 in all).
COMMON = {"metal": (120, 118, 124), "gold": (198, 156, 64), "wood": (122, 84, 52), "bone": (214, 204, 178),
          "wax": (226, 214, 180), "flame": (255, 196, 92), "fire": (255, 150, 60), "glass": (150, 190, 210),
          "dark": (30, 24, 34), "water": (70, 130, 170), "ash": (110, 104, 100), "coral": (214, 108, 120)}

THEMES = {
    "catacombs": dict(cloth=(132, 40, 40), cloth2=(126, 104, 78), clay=(150, 96, 66), glow=(255, 190, 110),
                      plant=(84, 110, 64), root=(92, 70, 52), cap="cloth2", liquid="water", emblem="skull",
                      mix=dict(urn=3, amphora=2, rubble=2, stalagmite=2, stalactite=3, bones=4, skulls=4, candles=4,
                               ribcage=2, chain=3, banner=3, relief=3, mask=1, grate=2, sconce=2, shelf=3, column=2, books=1)),
    "fungal": dict(cloth=(96, 70, 140), cloth2=(120, 100, 80), clay=(120, 90, 70), glow=(120, 230, 210),
                   plant=(80, 150, 100), root=(96, 82, 70), cap="glow", liquid="glow", emblem="eye",
                   mix=dict(mushroom=10, ferns=4, puddle=3, moss=4, roots=4, rubble=3, stalagmite=2, stalactite=2,
                            crystals=2, ivy=3, bones=2, lantern=2, sack=1, urn=2)),
    "ruins": dict(cloth=(52, 84, 140), cloth2=(140, 120, 90), clay=(170, 120, 80), glow=(255, 214, 140),
                  plant=(92, 132, 70), root=(100, 80, 58), cap="cloth2", liquid="water", emblem="sun", statue="stone",
                  mix=dict(column=4, bust=3, urn=3, amphora=2, rubble=4, banner=3, relief=4, shield=2, crossed=2,
                           books=2, ivy=3, ferns=2, sconce=2, pedestal=2, wheel=1, sword=2, mask=1)),
    "lava": dict(cloth=(150, 50, 30), cloth2=(90, 70, 60), clay=(110, 70, 50), glow=(255, 120, 40),
                 plant=(90, 60, 40), root=(70, 46, 36), cap="cloth2", liquid="fire", emblem="flame",
                 mix=dict(brazier=4, crystals=4, crystal_hang=2, rubble=4, stalagmite=3, stalactite=3, ash=4,
                          chain=3, grate=3, puddle=3, bones=2, skulls=2, banner=2, spire=2, sword=1, crate=1)),
    "mirror_halls": dict(cloth=(110, 60, 150), cloth2=(160, 140, 170), clay=(170, 150, 180), glow=(210, 180, 255),
                         plant=(120, 110, 150), root=(110, 100, 120), cap="glow", liquid="glow", emblem="eye",
                         statue="gold",
                         mix=dict(mirror=6, candles=4, sconce=3, bust=3, column=2, banner=3, crystals=4,
                                  crystal_hang=2, books=3, shelf=2, mask=3, pedestal=3, relief=2, urn=2)),
    "ashen_halls": dict(cloth=(90, 60, 50), cloth2=(100, 92, 86), clay=(110, 96, 90), glow=(255, 140, 70),
                        plant=(90, 86, 80), root=(70, 64, 60), cap="cloth2", liquid="fire", emblem="flame",
                        mix=dict(ash=6, column=4, brazier=3, rubble=4, bones=3, skulls=2, banner=3, chain=2, ribcage=2,
                                 sconce=1, relief=3, sword=2, shield=2, stalagmite=2, stalactite=2, crate=2, wheel=2, urn=2)),
    "crystal_depths": dict(cloth=(50, 90, 140), cloth2=(120, 130, 150), clay=(120, 130, 150), glow=(120, 200, 255),
                           plant=(90, 130, 150), root=(80, 96, 110), cap="glow", liquid="water", emblem="eye",
                           mix=dict(crystals=10, crystal_hang=6, stalagmite=4, stalactite=4, rubble=4, puddle=3,
                                    lantern=3, pedestal=2, spire=2, bones=2, mushroom=2, chain=2,
                                    relief=2, urn=1)),
    "drowned_vaults": dict(cloth=(40, 90, 100), cloth2=(100, 110, 100), clay=(110, 110, 90), glow=(120, 220, 200),
                           plant=(60, 120, 90), root=(60, 90, 80), cap="glow", liquid="water", emblem="wave",
                           mix=dict(coral=5, barnacles=4, anchor=2, chain=3, urn=3, amphora=2, puddle=4, moss=4,
                                    ivy=3, rubble=3, bones=2, skulls=2, lantern=2, banner=2, relief=2, grate=1)),
    "world_roots": dict(cloth=(90, 110, 60), cloth2=(120, 100, 70), clay=(130, 96, 66), glow=(255, 190, 80),
                        plant=(84, 140, 70), root=(110, 80, 52), cap="cloth2", liquid="water", emblem="tree",
                        mix=dict(roots=8, ferns=6, mushroom=5, moss=4, ivy=4, rubble=3, crystals=3, stalagmite=2,
                                 lantern=2, sack=2, wheel=1, puddle=2, pedestal=2)),
    "obsidian_abyss": dict(cloth=(70, 40, 100), cloth2=(70, 64, 80), clay=(70, 60, 80), glow=(190, 110, 255),
                           plant=(80, 70, 100), root=(60, 50, 70), cap="glow", liquid="glow", emblem="eye",
                           spire="dark",
                           mix=dict(spire=5, crystals=4, crystal_hang=3, chain=4, brazier=3, skulls=3, bones=2,
                                    rubble=4, sigil=3, grate=2, stalagmite=3, stalactite=3, mask=2, relief=2,
                                    urn=1)),
    "eclipse_heart": dict(cloth=(30, 24, 40), cloth2=(160, 130, 70), clay=(150, 120, 70), glow=(255, 210, 120),
                          plant=(110, 90, 60), root=(90, 70, 50), cap="glow", liquid="glow", emblem="sun",
                          statue="gold", spire="gold",
                          mix=dict(sigil=4, brazier=4, bust=3, column=3, banner=4, pedestal=3, crystals=3, mask=3,
                                   candles=3, chain=2, relief=3, shield=2, spire=2, urn=2, sconce=2,
                                   books=1)),
}

LIGHT_SCALE = 0.22


def palette(biome, theme):
    pal = {"stone": stone_ramp(biome)}
    for k, c in COMMON.items():
        pal[k] = ramp(c)
    for k in ("cloth", "cloth2", "clay", "glow", "plant", "root"):
        pal[k] = ramp(theme[k])
    pal["glow"] = ramp(theme["glow"], 0.3)
    pal["flame"] = ramp(COMMON["flame"], 0.25)
    pal["fire"] = ramp(COMMON["fire"], 0.3)
    # a tinted metal / clay per biome: a fifth of the stone mixed in
    st = pal["stone"][2]
    for k in ("metal", "clay", "wood"):
        base = tuple(int(a * 0.8 + b * 0.2) for a, b in zip((COMMON.get(k) or theme[k]), st))
        pal[k] = ramp(base)
    return pal


def hexc(c):
    return "Color(%.3f, %.3f, %.3f, 1)" % tuple(v / 255 for v in c)


def gen_biome(biome):
    theme = THEMES[biome]
    pal = palette(biome, theme)
    out_dir = os.path.join(OUT, biome)
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.endswith(".png"):
            os.remove(os.path.join(out_dir, f))
    entries = []
    for fam, n in theme["mix"].items():
        fn = FAMILIES[fam]
        for i in range(n):
            r = random.Random(zlib.crc32(("%s/%s/%d" % (biome, fam, i)).encode()))
            spr, place, glow, sway = fn(r, theme)
            img = spr.render(pal)
            name = "%s_%s_%d" % (biome, fam, i)
            img.save(os.path.join(out_dir, name + ".png"), optimize=True)
            entries.append((name, place, glow, sway))
    write_tres(biome, entries, theme)
    link_biome(biome)
    return len(entries)


def write_tres(biome, entries, theme):
    os.makedirs(DATA, exist_ok=True)
    hand = hand_weight(biome)
    # the pack in all weighs about as much as the hand-made list
    w = max(0.05, round(hand / max(1, len(entries)), 3))
    lines = ['[gd_resource type="Resource" script_class="DecorPack" load_steps=%d format=3]' % (len(entries) * 2 + 3), ""]
    lines.append('[ext_resource type="Script" path="res://scripts/data/decor_pack.gd" id="pack"]')
    lines.append('[ext_resource type="Script" path="res://scripts/data/decor_data.gd" id="decor"]')
    for name, *_ in entries:
        lines.append('[ext_resource type="Texture2D" path="res://assets/sprites/decor/pack/%s/%s.png" id="t_%s"]' % (biome, name, name))
    lines.append("")
    glow = hexc(theme["glow"])
    for name, place, is_glow, sway in entries:
        lines.append('[sub_resource type="Resource" id="d_%s"]' % name)
        lines.append('script = ExtResource("decor")')
        lines.append('texture = ExtResource("t_%s")' % name)
        lines.append("placement = %d" % place)
        lines.append("weight = %s" % w)
        if is_glow:
            lines.append("light_color = %s" % glow.replace(", 1)", ", 0.85)"))
            lines.append("light_scale = %s" % LIGHT_SCALE)
            lines.append("unshaded = true")
        if sway:
            lines.append("sway = true")
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("pack")')
    lines.append('id = &"%s_pack"' % biome)
    lines.append('decorations = Array[ExtResource("decor")]([%s])' % ", ".join('SubResource("d_%s")' % e[0] for e in entries))
    with open(os.path.join(DATA, "%s_pack.tres" % biome), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def hand_weight(biome):
    """Sum of the weights of the hand-made decorations of the biome (its
    sub-resources with a texture; DecorData.weight defaults to 1)."""
    with open(os.path.join(BIOMES, biome + ".tres"), encoding="utf-8") as fh:
        text = fh.read()
    total = 0.0
    for block in text.split("\n[sub_resource")[1:]:
        if "\ntexture = " in block:
            m = re.search(r"^weight = ([0-9.]+)", block, re.M)
            total += float(m.group(1)) if m else 1.0
    return total or 5.0


def link_biome(biome):
    """decor_pack = ExtResource(...) in data/biomes/<biome>.tres (once)."""
    path = os.path.join(BIOMES, biome + ".tres")
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    ref = 'path="res://data/decor/%s_pack.tres"' % biome
    if ref in text:
        return
    m = re.search(r"load_steps=(\d+)", text)
    text = text.replace(m.group(0), "load_steps=%d" % (int(m.group(1)) + 1), 1)
    first_sub = text.index("\n[sub_resource") if "\n[sub_resource" in text else text.index("\n[resource]")
    text = text[:first_sub] + '\n[ext_resource type="Resource" path="res://data/decor/%s_pack.tres" id="decor_pack"]' % biome + text[first_sub:]
    # after the script line: a property set before the script is dropped
    head, res = text.split("\n[resource]\n", 1)
    res = re.sub(r"^(script = .*)$", r'\1\ndecor_pack = ExtResource("decor_pack")', res, count=1, flags=re.M)
    text = head + "\n[resource]\n" + res
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def main():
    names = sys.argv[1:] or list(THEMES)
    total = 0
    for b in names:
        n = gen_biome(b)
        total += n
        print("decor pack %-16s %d props" % (b, n))
    print("total", total)


if __name__ == "__main__":
    main()
