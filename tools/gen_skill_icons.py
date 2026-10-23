#!/usr/bin/env python3
"""Pixel glyph icons for skills: every icon is drawn from scratch (no more
hue-shifted recolors). A glyph is a shape function; the palette is derived
from the skill's accent color (outline - dark base - base - light - sparkle).

Glyphs draw into a 16x16 RGBA canvas with helpers (px, line, disc, rect).
Run from tools/: python gen_skill_icons.py <out.png> <glyph> <accent hex>
— or import and use draw(glyph, accent) from the skill generator.
"""
from __future__ import annotations

import sys

from PIL import Image

INK = (22, 14, 30, 255)
STEEL = (196, 202, 214, 255)
STEEL_D = (120, 128, 145, 255)
WOOD = (150, 100, 58, 255)
BONE = (232, 226, 210, 255)
WHITE = (255, 255, 255, 255)

S = 16


def _c(v, f):
    return tuple(min(255, int(ch * f)) for ch in v[:3]) + (255,)


class G:
    """16x16 drawing surface with an accent-derived palette."""

    def __init__(self, accent):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.px = self.im.load()
        self.a = accent + (255,) if len(accent) == 3 else accent
        self.dark = _c(self.a, 0.45)
        self.base = _c(self.a, 0.9)
        self.lite = _c(self.a, 1.35)
        self.hot = _c(self.a, 1.8)

    def p(self, x, y, c):
        if 0 <= x < S and 0 <= y < S:
            self.px[int(x), int(y)] = c

    def line(self, x0, y0, x1, y1, c, w=1):
        dx, dy = x1 - x0, y1 - y0
        n = max(abs(dx), abs(dy), 1)
        for i in range(n + 1):
            x, y = x0 + dx * i / n, y0 + dy * i / n
            for ox in range(w):
                for oy in range(w):
                    self.p(round(x) + ox, round(y) + oy, c)

    def rect(self, x, y, w, h, c):
        for yy in range(h):
            for xx in range(w):
                self.p(x + xx, y + yy, c)

    def disc(self, cx, cy, r, c):
        for y in range(S):
            for x in range(S):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.p(x, y, c)

    def ring(self, cx, cy, r, c):
        for y in range(S):
            for x in range(S):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if (r - 1) ** 2 < d <= r * r + r:
                    self.p(x, y, c)

    def out(self, dots):
        """Dark outline pixel run around a point list."""
        for x, y in dots:
            self.p(x, y, INK)


# ------------------------------------------------------------------ glyphs
def sword(g):
    g.line(3, 12, 11, 3, STEEL, 2)
    g.line(4, 11, 10, 4, WHITE, 1)
    g.line(2, 10, 6, 12, WOOD, 2)
    g.p(2, 9, INK); g.p(7, 13, INK)
    g.line(2, 13, 4, 13, g.dark, 1)


def greatsword(g):
    g.line(4, 13, 12, 2, STEEL, 3)
    g.line(5, 12, 11, 4, WHITE, 1)
    g.rect(2, 11, 5, 2, WOOD)
    g.p(1, 10, INK); g.p(8, 14, INK)
    g.line(12, 1, 13, 2, g.hot, 1)


def axe(g):
    g.line(4, 14, 10, 4, WOOD, 2)
    g.disc(11, 4, 4, STEEL)
    g.disc(11, 4, 4 - 1, STEEL)
    g.disc(12, 3, 2, WHITE)
    g.ring(11, 4, 4, INK)
    g.p(7, 2, g.hot)


def hammer(g):
    g.line(5, 14, 9, 6, WOOD, 2)
    g.rect(6, 2, 7, 4, STEEL)
    g.rect(6, 2, 7, 1, INK)
    g.line(7, 3, 8, 3, WHITE, 1)
    g.p(6, 6, INK); g.p(12, 6, INK)
    g.p(13, 3, g.hot)


def whirl(g):
    for k in range(3):
        a0 = (3 + k, 3 + k)
        g.line(8, 8, 14 - k * 2, 4 + k * 3, g.base if k % 2 else g.lite, 1)
        g.line(8, 8, 2 + k * 2, 12 - k * 3, g.lite if k % 2 else g.base, 1)
    g.disc(8, 8, 2, g.hot)
    g.ring(8, 8, 2, INK)


def slash(g):
    g.line(2, 13, 13, 2, g.lite, 2)
    g.line(3, 12, 12, 3, WHITE, 1)
    g.line(5, 14, 14, 5, g.base, 1)
    g.p(14, 2, g.hot); g.p(13, 3, g.hot)


def shield(g):
    for y in range(2, 13):
        w = 10 - max(0, y - 8) * 2
        x = 8 - w // 2
        g.rect(x, y, w, 1, g.base if y < 9 else g.dark)
    g.rect(5, 3, 6, 1, INK)
    g.line(8, 4, 8, 10, g.lite, 1)
    g.line(5, 6, 11, 6, g.lite, 1)
    g.p(3, 2, INK); g.p(12, 2, INK)


def wall(g):
    g.rect(3, 5, 10, 8, g.base)
    g.rect(3, 5, 10, 1, g.lite)
    g.rect(3, 12, 10, 1, g.dark)
    for yy in (8, 11):
        g.line(3, yy, 12, yy, INK, 1)
    g.line(7, 5, 7, 8, INK, 1); g.line(10, 8, 10, 11, INK, 1); g.line(5, 11, 5, 12, INK, 1)
    g.p(4, 6, g.hot); g.p(11, 6, g.hot)


def heart(g):
    g.disc(6, 6, 3, g.base); g.disc(10, 6, 3, g.base); g.disc(8, 8, 4, g.base)
    g.disc(8, 11, 2, g.base)
    g.p(5, 4, g.lite); g.p(6, 5, WHITE)
    g.p(4, 5, INK); g.p(12, 5, INK); g.p(8, 14, INK)
    g.line(8, 3, 8, 5, g.lite, 1)


def cross(g):
    g.rect(7, 3, 3, 10, g.lite)
    g.rect(3, 6, 11, 3, g.lite)
    g.rect(7, 3, 1, 10, WHITE)
    g.p(7, 3, INK); g.p(9, 3, INK); g.p(7, 12, INK); g.p(9, 12, INK)
    g.p(3, 6, INK); g.p(3, 8, INK); g.p(13, 6, INK); g.p(13, 8, INK)
    g.disc(8, 7, 1, g.hot)


def boot(g):
    g.rect(4, 2, 4, 8, g.base)
    g.rect(4, 9, 8, 4, g.base)
    g.rect(4, 12, 9, 1, INK)
    g.line(5, 3, 5, 8, g.lite, 1)
    g.rect(9, 8, 3, 2, g.dark)
    g.p(11, 5, g.hot); g.p(12, 6, g.hot); g.p(12, 4, g.hot)


def wing(g):
    for k in range(4):
        g.line(8, 12 - k, 13 - k * 2, 3 + k * 2, g.base if k % 2 else g.lite, 1)
        g.line(7, 12 - k, 2 + k * 2, 3 + k * 2, g.base if k % 2 else g.lite, 1)
    g.line(8, 13, 8, 5, g.dark, 1)
    g.p(8, 4, g.hot); g.p(8, 3, g.hot)


def flame(g):
    g.disc(8, 10, 4, g.base)
    g.disc(8, 12, 3, g.dark)
    g.line(8, 2, 6, 6, g.lite, 2)
    g.line(6, 6, 9, 9, g.lite, 1)
    g.p(9, 4, g.base); g.p(10, 6, g.base)
    g.p(8, 9, g.hot); g.p(7, 10, WHITE)
    g.p(4, 12, INK); g.p(12, 12, INK); g.p(8, 14, INK)


def snowflake(g):
    for k in range(3):
        dx, dy = [(0, -6), (5, 3), (-5, 3)][k]
        g.line(8, 8, 8 + dx, 8 + dy, g.lite, 1)
        g.line(8 + dx, 8 + dy, 8 + dx + (1 if dx else -1), 8 + dy - 1, g.base, 1)
        g.line(8 + dx, 8 + dy, 8 + dx - 1, 8 + dy - 1, g.base, 1)
    g.disc(8, 8, 2, WHITE)
    g.p(8, 1, g.hot); g.p(2, 12, g.hot); g.p(14, 12, g.hot)


def orb(g):
    g.disc(8, 8, 5, g.base)
    g.disc(8, 8, 4, g.dark)
    g.disc(7, 7, 2, g.lite)
    g.p(6, 6, WHITE)
    g.ring(8, 8, 5, INK)
    g.p(13, 4, g.hot); g.p(2, 12, g.hot)


def eye(g):
    g.disc(8, 8, 6, g.dark)
    g.disc(8, 8, 5, g.base)
    g.disc(8, 8, 2, INK)
    g.p(7, 7, g.hot)
    g.line(8, 1, 8, 4, g.lite, 1); g.line(8, 11, 8, 14, g.lite, 1)
    g.line(1, 8, 4, 8, g.lite, 1); g.line(11, 8, 14, 8, g.lite, 1)
    g.ring(8, 8, 6, INK)


def bolt(g):
    pts = [(9, 1), (4, 8), (7, 8), (5, 14), (12, 6), (9, 6), (11, 1)]
    for i in range(len(pts) - 1):
        g.line(*pts[i], *pts[i + 1], g.lite, 2)
    g.line(9, 2, 6, 7, WHITE, 1)
    g.p(10, 2, g.hot)


def dagger(g):
    g.line(5, 11, 11, 4, STEEL, 2)
    g.line(6, 10, 10, 5, WHITE, 1)
    g.line(3, 13, 6, 10, WOOD, 2)
    g.p(2, 14, INK)
    g.line(11, 2, 12, 3, g.hot, 1)


def fan(g):
    for k, dx in enumerate((-5, 0, 5)):
        g.line(8, 13, 8 + dx, 3 + k, g.base, 1)
        g.line(8 + dx, 3 + k, 8 + dx + (1 if dx < 0 else -1), 2 + k, g.lite, 1)
    g.disc(8, 13, 2, WOOD)
    g.p(3, 2, g.hot); g.p(13, 2, g.hot); g.p(8, 2, g.hot)


def cloak(g):
    for y in range(3, 14):
        w = 3 + (y - 3) // 2
        g.rect(8 - w, y, w * 2, 1, g.base if y < 10 else g.dark)
    g.rect(6, 2, 5, 2, g.dark)
    g.line(5, 4, 5, 13, g.lite, 1)
    g.p(4, 13, INK); g.p(12, 13, INK); g.p(6, 2, INK)
    g.p(10, 6, g.hot)


def poison(g):
    g.disc(8, 9, 4, g.base)
    g.disc(8, 11, 3, g.dark)
    g.p(6, 7, g.lite); g.p(7, 8, WHITE)
    g.ring(8, 9, 4, INK)
    g.line(8, 3, 8, 5, g.lite, 1)
    g.p(9, 4, g.base); g.p(7, 2, g.base)


def bomb(g):
    g.disc(8, 10, 5, INK)
    g.disc(8, 10, 4, (60, 60, 70, 255))
    g.p(6, 8, (120, 120, 135, 255))
    g.line(10, 6, 12, 3, WOOD, 1)
    g.disc(13, 2, 1, g.hot)
    g.p(14, 3, g.lite); g.p(12, 1, g.lite)


def sun(g):
    g.disc(8, 8, 4, g.base)
    g.disc(8, 8, 3, g.lite)
    g.p(7, 7, WHITE)
    for k in range(8):
        import math
        a = k * math.pi / 4
        x, y = round(8 + 6 * math.cos(a)), round(8 + 6 * math.sin(a))
        g.p(x, y, g.lite)
        g.p(round(8 + 5 * math.cos(a)), round(8 + 5 * math.sin(a)), g.base)
    g.ring(8, 8, 4, INK)


def fist(g):
    g.rect(4, 5, 8, 6, g.base)
    g.rect(4, 5, 8, 1, g.lite)
    for x in (6, 8, 10):
        g.line(x, 6, x, 9, g.dark, 1)
    g.rect(3, 7, 2, 3, g.dark)
    g.p(4, 4, INK); g.p(12, 4, INK)
    g.p(11, 6, g.hot)


def skull(g):
    g.disc(8, 7, 5, BONE)
    g.disc(6, 6, 1, INK); g.disc(10, 6, 1, INK)
    g.rect(7, 8, 2, 2, INK)
    g.rect(6, 12, 5, 2, BONE)
    g.line(8, 12, 8, 14, INK, 1)
    g.p(6, 3, g.hot); g.p(11, 4, g.hot)


def blood(g):
    for y in range(4, 14):
        w = 2 + (y - 4) // 3
        g.rect(8 - w // 2, y, w, 1, g.base)
    g.disc(8, 12, 2, g.base)
    g.p(7, 5, g.lite); g.p(8, 6, WHITE)
    g.p(6, 13, INK); g.p(10, 13, INK)


def star(g):
    pts = [(8, 1), (10, 6), (15, 6), (11, 9), (12, 14), (8, 11), (4, 14), (5, 9), (1, 6), (6, 6)]
    for i in range(len(pts)):
        g.line(8, 8, *pts[i], g.base, 1)
    g.disc(8, 8, 2, g.lite)
    g.p(8, 8, WHITE)
    g.p(8, 0, g.hot)


def chains(g):
    for yy in (3, 8, 13):
        g.ring(5, yy, 2, g.base)
        g.ring(11, yy + 1, 2, g.base)
        g.line(6, yy + 1, 10, yy + 1, g.dark, 1)
    g.p(5, 3, g.hot); g.p(11, 14, g.hot)


def arrow(g):
    g.line(3, 13, 12, 4, g.base, 1)
    g.line(12, 4, 8, 4, g.lite, 1)
    g.line(12, 4, 12, 8, g.lite, 1)
    g.line(4, 12, 3, 13, g.dark, 1)
    g.p(13, 3, g.hot)


def hourglass(g):
    g.line(4, 2, 12, 2, g.base, 1); g.line(4, 13, 12, 13, g.base, 1)
    g.line(5, 3, 8, 8, g.lite, 1); g.line(11, 3, 8, 8, g.lite, 1)
    g.line(5, 12, 8, 8, g.lite, 1); g.line(11, 12, 8, 8, g.lite, 1)
    g.disc(8, 10, 1, g.hot); g.p(8, 6, g.hot)
    g.p(4, 2, INK); g.p(12, 13, INK)


GLYPHS = {k: v for k, v in list(globals().items()) if callable(v) and not k.startswith("_") and k not in ("G", "Image", "sys")}


def draw(glyph: str, accent) -> Image.Image:
    g = G(accent)
    GLYPHS[glyph](g)
    return g.im


if __name__ == "__main__":
    out, glyph, hexcol = sys.argv[1], sys.argv[2], sys.argv[3]
    accent = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    draw(glyph, accent).save(out)
    print("wrote", out)
