#!/usr/bin/env python3
"""Detailed pixel glyph icons for skills (v2). 16x16, hand-drawn fidelity:
full ink outline, three-tone shading, highlights, small props (runes, wraps,
sparks). Palette derives from the skill's accent color.

Run from tools/: python gen_skill_icons.py <out.png> <glyph> <accent hex>
— or import draw(glyph, accent) from gen_skills_v2.
"""
from __future__ import annotations

import sys

from PIL import Image

INK = (18, 12, 26, 255)
STEEL = (198, 206, 220, 255)
STEEL_M = (150, 160, 180, 255)
STEEL_D = (96, 106, 128, 255)
WOOD = (154, 102, 58, 255)
WOOD_D = (104, 66, 36, 255)
BONE = (236, 230, 214, 255)
BONE_D = (176, 168, 148, 255)
WHITE = (255, 255, 255, 255)

S = 16


def _c(v, f):
    return tuple(min(255, int(ch * f)) for ch in v[:3]) + (255,)


class G:
    def __init__(self, accent):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.px = self.im.load()
        a = accent if len(accent) >= 3 else (220, 80, 80)
        self.a = tuple(a[:3]) + (255,)
        self.dark = _c(self.a, 0.42)
        self.mid = _c(self.a, 0.7)
        self.base = _c(self.a, 1.0)
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

    def frame(self, x, y, w, h, c):
        for xx in range(w):
            self.p(x + xx, y, c); self.p(x + xx, y + h - 1, c)
        for yy in range(h):
            self.p(x, y + yy, c); self.p(x + w - 1, y + yy, c)

    def disc(self, cx, cy, r, c):
        for y in range(S):
            for x in range(S):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.p(x, y, c)

    def ring(self, cx, cy, r, c):
        for y in range(S):
            for x in range(S):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if (r - 1) ** 2 < d <= r * r + r * 0.6:
                    self.p(x, y, c)

    def spark(self, x, y, c):
        self.p(x, y, c)
        self.p(x - 1, y, _c(c[:3], 0.8)); self.p(x + 1, y, _c(c[:3], 0.8))
        self.p(x, y - 1, _c(c[:3], 0.8)); self.p(x, y + 1, _c(c[:3], 0.8))


# ------------------------------------------------------------------ blades
def sword(g):
    # blade with a fuller, from tip (12,2) to guard (4,11)
    g.line(11, 2, 3, 11, STEEL_D, 3)
    g.line(11, 2, 4, 10, STEEL, 2)
    g.line(10, 3, 5, 9, WHITE, 1)      # edge shine
    g.line(9, 4, 5, 9, STEEL_M, 1)     # fuller
    g.p(12, 1, WHITE); g.p(11, 1, STEEL); g.p(12, 2, STEEL)
    # crossguard
    g.line(1, 9, 5, 13, g.mid, 2)
    g.line(2, 10, 4, 12, g.lite, 1)
    g.p(0, 8, INK); g.p(6, 14, INK)
    g.p(2, 12, g.dark)
    # wrapped grip + pommel
    g.line(2, 12, 1, 13, WOOD_D, 2)
    g.p(1, 14, g.dark); g.p(0, 15, INK)
    for yy in (12, 13):
        g.p(2, yy, WOOD)
    g.spark(13, 4, g.hot)


def greatsword(g):
    g.line(10, 1, 3, 12, STEEL_D, 4)
    g.line(10, 1, 4, 11, STEEL, 3)
    g.line(9, 2, 5, 8, WHITE, 1)
    g.line(8, 3, 5, 9, STEEL_M, 1)
    g.p(11, 0, WHITE); g.p(12, 1, g.hot)
    # wide ornate guard
    g.line(1, 10, 6, 14, g.dark, 1)
    g.line(1, 11, 6, 15, g.mid, 2)
    g.line(2, 12, 5, 14, g.lite, 1)
    g.p(0, 9, INK); g.p(7, 14, INK); g.p(7, 15, INK)
    # rune on the blade
    g.p(7, 5, g.lite); g.p(8, 4, g.hot)
    g.line(1, 13, 0, 14, WOOD, 2)
    g.p(0, 15, g.dark)


def axe(g):
    # shaft with grain
    g.line(3, 13, 9, 4, WOOD, 2)
    g.line(4, 13, 9, 5, WOOD_D, 1)
    g.p(2, 14, WOOD_D); g.p(2, 13, INK)
    # head: cheek + edge + binding
    g.disc(11, 4, 4, STEEL_D)
    g.disc(11, 4, 3, STEEL)
    g.disc(12, 3, 2, WHITE)
    g.line(13, 1, 15, 3, STEEL, 1)
    g.ring(11, 4, 4, INK)
    g.p(8, 1, INK); g.p(8, 7, INK)
    # binding where head meets shaft
    g.line(8, 4, 9, 3, g.mid, 1)
    g.p(9, 2, g.lite)
    g.spark(14, 5, g.hot)


def hammer(g):
    g.line(5, 13, 8, 7, WOOD, 2)
    g.line(6, 13, 8, 8, WOOD_D, 1)
    g.p(4, 14, INK)
    # head: face + top bevel + strap
    g.rect(5, 2, 8, 5, STEEL_D)
    g.rect(6, 3, 6, 3, STEEL)
    g.rect(6, 2, 6, 1, WHITE)
    g.frame(5, 2, 8, 5, INK)
    g.p(6, 3, WHITE); g.p(7, 3, STEEL_M)
    g.rect(4, 3, 1, 3, STEEL_M); g.rect(13, 3, 1, 3, STEEL_M)
    g.line(6, 7, 11, 7, g.dark, 1)
    g.spark(13, 1, g.hot)


def dagger(g):
    g.line(6, 9, 11, 3, STEEL_D, 2)
    g.line(6, 9, 10, 4, STEEL, 1)
    g.p(11, 2, WHITE); g.p(12, 2, g.hot)
    # small guard
    g.line(4, 10, 7, 12, g.mid, 1)
    g.p(3, 9, INK); g.p(8, 13, INK)
    # wrapped grip
    g.line(3, 11, 2, 12, WOOD, 2)
    g.p(2, 13, WOOD_D); g.p(1, 14, g.dark); g.p(1, 15, INK)
    g.p(3, 11, g.lite)
    # blood notch on the blade
    g.p(8, 7, g.dark)


def fan(g):
    for k, (dx, tip) in enumerate(((-5, 2), (0, 1), (5, 2))):
        g.line(8, 13, 8 + dx, tip + k, STEEL_D, 1)
        g.line(8, 13, 8 + dx, tip + k, STEEL, 1 if k % 2 else 1)
        g.p(8 + dx, tip + k - 1, WHITE)
        g.p(8 + dx + (1 if dx < 0 else -1), tip + k, STEEL_M)
    # grip hub
    g.disc(8, 13, 1, WOOD)
    g.p(8, 14, WOOD_D); g.p(7, 14, INK); g.p(9, 14, INK)
    g.spark(4, 1, g.hot); g.spark(12, 1, g.hot)


# ------------------------------------------------------------------ combat
def whirl(g):
    for k in range(3):
        c = [g.lite, g.base, g.mid][k]
        g.ring(8 - k, 8 + k, 5 - k, c)
        g.p(3 + k, 6 + k, INK)
    g.disc(8, 8, 2, g.hot)
    g.disc(7, 7, 1, WHITE)
    g.ring(8, 8, 2, INK)
    g.spark(14, 2, g.lite); g.spark(2, 13, g.lite)


def slash(g):
    g.line(2, 13, 13, 2, g.lite, 2)
    g.line(3, 12, 12, 3, WHITE, 1)
    g.line(1, 14, 4, 12, g.base, 1)
    g.line(6, 14, 14, 6, g.mid, 1)
    for x, y in ((13, 1), (14, 2), (12, 2)):
        g.p(x, y, g.hot)
    g.p(2, 13, g.dark)


def shield(g):
    for y in range(2, 14):
        w = 11 - max(0, y - 8) * 2
        x = 8 - w // 2
        c = g.base if y < 9 else g.mid
        g.rect(x, y, w, 1, c)
        g.p(x, y, g.dark); g.p(x + w - 1, y, g.dark)
    g.rect(7, 2, 3, 1, g.lite)
    g.rect(3, 2, 11, 1, INK)
    # boss + heraldic line
    g.disc(8, 7, 2, g.lite)
    g.disc(7, 6, 1, WHITE)
    g.ring(8, 7, 2, INK)
    g.line(8, 4, 8, 5, INK, 1); g.line(8, 9, 8, 11, INK, 1)
    # rivets
    g.p(4, 4, WHITE); g.p(12, 4, WHITE); g.p(5, 12, g.lite); g.p(11, 12, g.lite)
    g.p(3, 2, INK); g.p(13, 2, INK)


def wall(g):
    g.rect(3, 4, 10, 10, g.base)
    g.rect(3, 4, 10, 1, g.lite)
    g.rect(3, 13, 10, 1, g.dark)
    g.frame(3, 4, 10, 10, INK)
    # crenellation
    for x in (4, 7, 10):
        g.rect(x, 2, 2, 2, g.base); g.p(x, 2, g.lite)
    # mortar
    for yy in (7, 10):
        g.line(3, yy, 12, yy, INK, 1)
    g.line(7, 5, 7, 6, INK, 1); g.line(10, 8, 10, 9, INK, 1); g.line(5, 11, 5, 12, INK, 1)
    g.p(4, 5, g.hot); g.p(11, 5, WHITE)


def fist(g):
    g.rect(4, 4, 8, 7, g.base)
    g.rect(4, 4, 8, 1, g.lite)
    g.rect(4, 10, 8, 1, g.dark)
    g.frame(4, 4, 8, 7, INK)
    for x in (6, 8, 10):
        g.line(x, 5, x, 8, g.mid, 1)
    for x in (6, 8, 10):
        g.p(x, 5, WHITE)
    g.rect(2, 6, 2, 4, g.mid)
    g.frame(2, 6, 2, 4, INK)
    g.p(12, 5, g.hot); g.spark(13, 3, g.lite)


def chains(g):
    for yy in (3, 8, 13):
        for xx in (5, 10):
            g.ring(xx, yy + (0 if xx == 5 else 1), 2, g.base)
            g.ring(xx, yy + (0 if xx == 5 else 1), 1, g.dark)
            g.p(xx - 1, yy - 1 + (0 if xx == 5 else 1), g.lite)
    g.line(6, 4, 9, 9, g.mid, 1)
    g.line(7, 3, 10, 8, g.mid, 1)
    g.p(5, 3, g.hot); g.p(11, 15, g.hot)


# ------------------------------------------------------------------ body
def heart(g):
    g.disc(6, 6, 3, g.mid); g.disc(10, 6, 3, g.mid); g.disc(8, 8, 4, g.base)
    g.disc(8, 11, 2, g.base)
    g.disc(8, 7, 3, g.base)
    # shading + outline
    g.p(4, 5, INK); g.p(12, 5, INK); g.p(5, 4, INK); g.p(11, 4, INK)
    g.p(6, 13, INK); g.p(10, 13, INK); g.p(8, 14, INK); g.p(7, 14, g.dark); g.p(9, 14, g.dark)
    g.p(6, 12, g.dark); g.p(10, 12, g.dark)
    # aorta + shine
    g.line(8, 2, 8, 5, g.base, 1); g.p(7, 2, g.mid); g.p(9, 2, g.mid)
    g.p(6, 5, g.lite); g.p(7, 6, WHITE); g.p(5, 7, g.lite)
    g.p(8, 9, g.hot)


def cross(g):
    g.rect(6, 2, 3, 11, g.lite)
    g.rect(2, 5, 11, 3, g.lite)
    g.rect(6, 2, 1, 11, WHITE)
    g.rect(2, 5, 1, 3, WHITE)
    g.frame(6, 2, 3, 11, INK); g.frame(2, 5, 11, 3, INK)
    g.disc(8, 6, 1, g.hot)
    # halo rays
    for x, y in ((7, 0), (8, 0), (0, 6), (15, 6)):
        g.p(x, y, g.base)
    g.p(5, 3, g.mid); g.p(11, 7, g.mid)


def boot(g):
    g.rect(4, 1, 4, 9, g.base)
    g.rect(4, 1, 4, 1, g.lite)
    g.rect(4, 1, 1, 9, g.mid)
    g.rect(4, 9, 8, 4, g.base)
    g.rect(4, 9, 8, 1, g.dark)
    g.rect(4, 12, 9, 1, INK)
    g.frame(4, 1, 4, 12, INK)
    # buckle + strap
    g.line(9, 8, 12, 8, g.dark, 1)
    g.rect(10, 7, 1, 3, g.lite)
    g.p(10, 8, INK)
    # sole studs
    g.p(5, 12, WHITE); g.p(8, 12, WHITE); g.p(11, 12, WHITE)
    # speed puffs
    g.p(12, 4, g.hot); g.p(13, 5, g.lite); g.p(13, 3, g.lite); g.p(14, 4, g.base)


def wing(g):
    for k in range(4):
        c = g.lite if k % 2 else g.base
        g.line(8, 12 - k, 13 - k * 2, 3 + k * 2, c, 1)
        g.line(7, 12 - k, 2 + k * 2, 3 + k * 2, g.mid if k % 2 else g.base, 1)
        g.p(13 - k * 2, 3 + k * 2, WHITE)
        g.p(2 + k * 2, 3 + k * 2, g.lite)
    g.line(8, 13, 8, 4, g.dark, 1)
    g.p(8, 3, g.hot); g.p(7, 2, g.lite); g.p(9, 2, g.lite)
    g.p(8, 13, INK)


def cloak(g):
    for y in range(3, 14):
        w = 3 + (y - 3) // 2
        c = g.base if y < 10 else g.mid
        g.rect(8 - w, y, w * 2, 1, c)
        g.p(8 - w, y, g.dark); g.p(7 + w, y, g.dark)
    # hood
    g.rect(6, 2, 5, 3, g.mid)
    g.rect(7, 3, 3, 2, INK)
    g.rect(6, 2, 5, 1, g.lite)
    g.p(5, 2, INK); g.p(11, 2, INK); g.p(4, 13, INK); g.p(12, 13, INK)
    # fold lines + clasp
    g.line(6, 5, 5, 13, g.dark, 1)
    g.line(10, 5, 11, 13, g.dark, 1)
    g.disc(8, 5, 1, g.lite); g.p(8, 5, g.hot)
    g.p(3, 6, g.lite)


def skull(g):
    g.disc(8, 7, 5, BONE)
    g.disc(8, 12, 3, BONE)
    g.p(8, 3, BONE); g.p(7, 3, BONE_D)
    # sockets with depth
    g.disc(6, 6, 2, INK); g.disc(10, 6, 2, INK)
    g.p(5, 5, g.dark); g.p(11, 5, g.dark)
    g.p(6, 7, g.mid); g.p(10, 7, g.mid)
    # nose + teeth
    g.p(8, 9, INK); g.p(8, 10, INK)
    g.rect(6, 11, 5, 1, BONE_D)
    g.line(7, 11, 7, 12, INK, 1); g.line(9, 11, 9, 12, INK, 1)
    g.line(8, 12, 8, 14, INK, 1)
    # cracks + glow
    g.p(5, 3, BONE_D); g.p(11, 4, BONE_D)
    g.spark(4, 9, g.hot); g.spark(12, 9, g.hot)


def blood(g):
    for y in range(3, 14):
        w = 2 + (y - 3) // 3
        g.rect(8 - w // 2, y, w, 1, g.base)
    g.disc(8, 12, 2, g.base)
    g.disc(8, 8, 2, g.base)
    # shading + shine
    g.p(7, 4, g.lite); g.p(7, 5, WHITE); g.p(6, 7, g.lite)
    g.p(9, 10, g.mid); g.p(8, 12, g.dark)
    g.p(6, 13, INK); g.p(10, 13, INK); g.p(7, 3, g.dark)
    # drip
    g.p(11, 6, g.mid); g.p(11, 7, g.base)


def eye(g):
    g.disc(8, 8, 6, g.dark)
    g.disc(8, 8, 5, g.mid)
    g.ring(8, 8, 5, INK)
    # iris rings + slit pupil
    g.ring(8, 8, 3, g.base)
    g.disc(8, 8, 2, g.hot)
    g.line(8, 6, 8, 10, INK, 1)
    g.p(7, 7, WHITE)
    # lashes / rays
    for x, y in ((8, 1), (8, 14), (1, 8), (14, 8), (3, 3), (13, 3), (3, 13), (13, 13)):
        g.p(x, y, g.lite)
    g.p(6, 5, g.lite); g.p(10, 5, g.lite)


def star(g):
    pts = [(8, 1), (10, 6), (15, 6), (11, 9), (12, 14), (8, 11), (4, 14), (5, 9), (1, 6), (6, 6)]
    for i in range(len(pts)):
        g.line(8, 8, *pts[i], g.base, 1)
    for p in pts:
        g.p(*p, g.lite)
    g.disc(8, 8, 2, g.lite)
    g.disc(7, 7, 1, WHITE)
    g.p(8, 0, g.hot); g.p(7, 1, g.mid)


def hourglass(g):
    # wooden frame
    g.line(3, 2, 12, 2, WOOD, 1); g.line(3, 13, 12, 13, WOOD, 1)
    g.p(3, 1, WOOD_D); g.p(12, 1, WOOD_D); g.p(3, 14, WOOD_D); g.p(12, 14, WOOD_D)
    g.p(2, 2, INK); g.p(13, 13, INK)
    # glass bulbs
    g.line(5, 3, 8, 8, g.lite, 1); g.line(11, 3, 8, 8, g.lite, 1)
    g.line(5, 12, 8, 8, g.lite, 1); g.line(11, 12, 8, 8, g.lite, 1)
    g.line(6, 3, 8, 6, WHITE, 1)
    # sand
    g.line(6, 4, 10, 4, g.base, 1); g.p(7, 5, g.base); g.p(9, 5, g.base)
    g.rect(7, 11, 3, 1, g.base); g.rect(6, 12, 5, 1, g.base)
    g.p(8, 9, g.hot); g.p(8, 7, g.hot)


# ------------------------------------------------------------------ elements
def flame(g):
    # outer flame
    g.disc(8, 10, 4, g.base)
    g.disc(8, 12, 3, g.mid)
    g.line(8, 2, 6, 6, g.lite, 2)
    g.line(6, 6, 9, 9, g.lite, 1)
    g.p(9, 4, g.base); g.p(10, 6, g.base); g.p(5, 7, g.base)
    # inner hot core
    g.disc(8, 11, 2, g.hot)
    g.p(7, 10, WHITE)
    # sparks + outline
    g.p(4, 12, INK); g.p(12, 12, INK); g.p(8, 14, INK); g.p(5, 13, g.dark); g.p(11, 13, g.dark)
    g.spark(12, 3, g.lite); g.p(3, 8, g.lite)


def fireball(g):
    flame(g)


def snowflake(g):
    arms = [(0, -6), (5, 3), (-5, 3)]
    for dx, dy in arms:
        g.line(8, 8, 8 + dx, 8 + dy, g.lite, 1)
        tx, ty = 8 + dx, 8 + dy
        g.line(tx, ty, tx + (1 if dx >= 0 else -1), ty - 1, g.base, 1)
        g.line(tx, ty, tx - 1 if dx >= 0 else tx + 1, ty - 1, g.base, 1)
        g.p(tx, ty, WHITE)
        g.p(8 + dx // 2, 8 + dy//2, g.base)
    g.disc(8, 8, 2, WHITE)
    g.disc(7, 7, 1, g.hot)
    g.ring(8, 8, 6, g.mid)
    g.p(8, 1, g.hot); g.p(2, 11, g.lite); g.p(14, 11, g.lite)


def orb(g):
    g.disc(8, 8, 5, g.mid)
    g.disc(8, 8, 4, g.dark)
    g.disc(6, 6, 2, g.lite)
    g.p(6, 5, WHITE); g.p(10, 10, g.base)
    g.ring(8, 8, 5, INK)
    # orbit ring + satellite runes
    g.line(3, 11, 13, 5, g.base, 1)
    g.p(3, 11, g.lite); g.p(13, 5, g.lite)
    g.p(5, 9, g.hot); g.p(11, 7, g.hot)
    g.p(2, 12, g.lite); g.p(14, 4, g.lite)


def bolt(g):
    pts = [(9, 1), (4, 8), (7, 8), (5, 14), (12, 6), (9, 6), (11, 1)]
    for i in range(len(pts) - 1):
        g.line(*pts[i], *pts[i + 1], g.lite, 2)
    g.line(9, 2, 6, 7, WHITE, 1)
    g.line(6, 12, 10, 7, g.base, 1)
    # forks
    g.line(5, 14, 3, 13, g.base, 1); g.line(12, 6, 14, 5, g.base, 1)
    g.p(10, 2, g.hot); g.spark(13, 2, g.lite)


def sun(g):
    g.disc(8, 8, 4, g.base)
    g.disc(8, 8, 3, g.lite)
    g.p(7, 7, WHITE)
    g.ring(8, 8, 4, INK)
    import math
    for k in range(8):
        a = k * math.pi / 4
        x, y = round(8 + 6 * math.cos(a)), round(8 + 6 * math.sin(a))
        x2, y2 = round(8 + 5 * math.cos(a)), round(8 + 5 * math.sin(a))
        g.p(x, y, g.lite); g.p(x2, y2, g.base)
        g.p(round(8 + 7 * math.cos(a)), round(8 + 7 * math.sin(a)), g.hot if k % 2 else g.base)


def poison(g):
    g.disc(8, 9, 4, g.base)
    g.disc(8, 11, 3, g.dark)
    g.ring(8, 9, 4, INK)
    g.p(6, 7, g.lite); g.p(7, 8, WHITE)
    # bubbles rising
    g.line(8, 3, 8, 5, g.lite, 1)
    g.p(9, 4, g.base); g.p(7, 2, g.base); g.p(9, 1, g.mid)
    # skull dot mark
    g.p(8, 11, WHITE); g.p(7, 10, WHITE); g.p(9, 10, WHITE)


def bomb(g):
    g.disc(8, 10, 5, INK)
    g.disc(8, 10, 4, (58, 58, 70, 255))
    g.p(6, 8, (130, 130, 148, 255)); g.p(7, 8, (160, 160, 178, 255))
    g.p(6, 9, (110, 110, 126, 255))
    g.p(10, 12, (30, 30, 38, 255))
    # neck + fuse
    g.line(10, 6, 11, 5, (90, 70, 50, 255), 1)
    g.line(11, 5, 13, 3, (150, 120, 80, 255), 1)
    # spark
    g.disc(13, 2, 1, g.hot)
    g.p(14, 1, g.lite); g.p(12, 1, g.lite); g.p(14, 3, g.lite)


def arrow(g):
    g.line(3, 13, 12, 4, g.mid, 1)
    g.line(3, 13, 4, 12, g.base, 1)
    # broadhead
    g.line(12, 4, 8, 4, g.lite, 1); g.line(12, 4, 12, 8, g.lite, 1)
    g.line(11, 5, 12, 4, WHITE, 1)
    # fletching
    g.line(3, 12, 5, 14, g.base, 1); g.line(4, 11, 6, 13, g.base, 1)
    g.line(4, 13, 3, 14, g.dark, 1)
    g.p(13, 3, g.hot)


GLYPHS = {k: v for k, v in list(globals().items())
          if callable(v) and not k.startswith("_") and k not in ("G", "Image", "sys")}


def draw(glyph: str, accent) -> Image.Image:
    g = G(accent)
    GLYPHS[glyph](g)
    return g.im


if __name__ == "__main__":
    out, glyph, hexcol = sys.argv[1], sys.argv[2], sys.argv[3]
    accent = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    draw(glyph, accent).save(out)
    print("wrote", out)
