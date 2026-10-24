#!/usr/bin/env python3
"""Skill icons v4: 32x32 volume-lit mini-illustrations.

Every subject is drawn with ellipsoid shading (the monsters' `lit` pass),
crisp hand details on top (fullers, gems, cracks, runes), a soft backdrop
filling the cell, then the item-icon detail pass. Same spec API as v3:
draw(spec, accent), spec = {"bg", "s": (subject, params), "fx"}.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import icon_detail
from gen_placeholders import shade as sh

S = 32
CX = CY = 15.5

INK = (14, 9, 20, 255)
STEEL = (198, 206, 220, 255)
GOLD = (236, 196, 64, 255)
WOOD = (158, 104, 58, 255)
BONE = (238, 232, 216, 255)
WHITE = (255, 255, 255, 255)


def _c(v, f):
    return tuple(min(255, int(ch * f)) for ch in v[:3]) + (255,)


class G:
    def __init__(self, accent):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.px = self.im.load()
        self.d = ImageDraw.Draw(self.im)
        self.gd = ImageDraw.Draw(self.glow)
        a = accent if len(accent) >= 3 else (220, 80, 80)
        self.a = tuple(a[:3]) + (255,)
        self.dark = _c(self.a, 0.30)
        self.mid = _c(self.a, 0.55)
        self.base = _c(self.a, 0.85)
        self.lite = _c(self.a, 1.25)
        self.hot = _c(self.a, 1.7)

    def p(self, x, y, c):
        if 0 <= x < S and 0 <= y < S:
            self.px[int(x), int(y)] = c

    def line(self, x0, y0, x1, y1, c, w=1):
        dx, dy = x1 - x0, y1 - y0
        n = max(int(abs(dx)), int(abs(dy)), 1)
        for i in range(n + 1):
            x, y = x0 + dx * i / n, y0 + dy * i / n
            for ox in range(w):
                for oy in range(w):
                    self.p(round(x) + ox, round(y) + oy, c)

    def rect(self, x, y, w, h, c):
        self.d.rectangle((x, y, x + w - 1, y + h - 1), fill=c)

    def frame(self, x, y, w, h, c):
        self.d.rectangle((x, y, x + w - 1, y + h - 1), outline=c)

    def disc(self, cx, cy, r, c):
        self.d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c)

    def ring(self, cx, cy, r, c):
        self.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=c)

    def poly(self, pts, c):
        self.d.polygon(pts, fill=c)

    def glowdot(self, cx, cy, r, col, strength=1.0):
        gp = self.glow.load()
        for y in range(max(0, int(cy - r)), min(S, int(cy + r + 1))):
            for x in range(max(0, int(cx - r)), min(S, int(cx + r + 1))):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    a = int(110 * strength * (1 - d / r))
                    cur = gp[x, y]
                    if a > cur[3]:
                        gp[x, y] = (col[0], col[1], col[2], a)

    def spark(self, x, y, c):
        self.p(x, y, c)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            self.p(x + dx, y + dy, _c(c, 0.7))

    def litmask(self, fn, base, cx, cy, rx, ry, alpha=255, flat=0.0):
        """Fill a mask region with ellipsoid volume light (monsters' pass)."""
        import gen_monsters as gm
        m = gm.mask(S, S, fn)
        gm.lit(self.im, m, base, cx, cy, rx, ry, alpha, flat=flat)
        self.px = self.im.load()


# ----------------------------------------------------------------- backdrops
def bg_wash(g):
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - CX, y - CY) / 21.0
            if d < 0.5:
                g.p(x, y, _c(g.dark, 1.35))
            elif d < 0.8:
                g.p(x, y, g.dark if (x + y) % 2 else _c(g.dark, 0.85))
            else:
                g.p(x, y, _c(g.dark, 0.55) if (x * 2 + y) % 3 else _c(g.dark, 0.4))


def _ring_dots(g, r, col, step=2):
    for k in range(0, 360, 30):
        a = math.radians(k)
        g.p(round(CX + r * math.cos(a)), round(CY + r * math.sin(a)), col if k % step == 0 else _c(col, 0.7))


def bg_rays(g):
    bg_wash(g)
    for k in range(8):
        a = k * math.pi / 4 + 0.4
        for r in range(9, 15):
            g.p(round(CX + r * math.cos(a)), round(CY + r * math.sin(a)), g.mid if r % 2 else _c(g.mid, 0.65))


def bg_orbit(g):
    bg_wash(g)
    g.ring(CX, CY, 13, g.mid)
    g.ring(CX, CY, 12, _c(g.dark, 0.7))
    g.p(2, 8, g.lite)
    g.p(29, 22, g.lite)


def bg_particles(g):
    bg_wash(g)
    for x, y in ((4, 5), (26, 7), (8, 25), (22, 27), (28, 18), (3, 17)):
        g.p(x, y, g.mid)
        g.p(x, y - 1, _c(g.mid, 1.3))
        g.p(x + 1, y, _c(g.mid, 1.15))


def bg_storm(g):
    bg_wash(g)
    for x, y in ((2, 3), (10, 2), (20, 4), (28, 7), (6, 12), (25, 14)):
        g.p(x, y, g.lite)
    for yy in range(0, S, 6):
        g.line(0, yy + 3, S - 1, yy, _c(g.dark, 1.5), 1)


def bg_runes(g):
    bg_wash(g)
    for x, y, w in ((3, 3, 2), (26, 3, 1), (3, 26, 1), (26, 26, 2), (14, 1, 1), (16, 29, 1)):
        g.rect(x, y, w, 1, g.mid)


def bg_glowline(g):
    bg_wash(g)
    g.line(0, 26, 31, 4, _c(g.mid, 1.2), 1)
    g.line(0, 28, 31, 6, g.mid, 1)


def bg_dark(g):
    for y in range(S):
        for x in range(S):
            g.p(x, y, (12, 8, 18, 255) if (x + y) % 5 else (17, 11, 24, 255))


BGS = dict(wash=bg_wash, rays=bg_rays, orbit=bg_orbit, particles=bg_particles,
           storm=bg_storm, runes=bg_runes, glowline=bg_glowline, dark=bg_dark)


# ------------------------------------------------------------------ subjects
def s_blade(g, p):
    ln = p.get("len", "long")
    x1 = 26 if ln == "long" else 21
    # клинок: маска-полоса + объёмный свет
    ang = -0.65
    def _m(dd):
        for t in range(0, 100):
            f = t / 99.0
            x = 5 + (x1 - 5) * f
            y = 27 + (2 - 26) * f
            wdt = 3 if f < 0.15 else 2
            for o in range(-wdt, wdt + 1):
                xx, yy = x + o * math.sin(ang), y + o * math.cos(ang)
                dd.point((round(xx), round(yy)), fill=(255, 255, 255, 255))
    g.litmask(_m, STEEL, (5 + x1) / 2, 14, (x1 - 5) / 2, 4.5)
    g.line(6, 26, x1 - 1, 4, WHITE, 1)
    g.p(x1 + 1, 2, WHITE)
    g.p(x1, 3, STEEL)
    if p.get("guard") != "none":
        g.line(2, 23, 8, 29, g.mid, 2)
        g.line(3, 24, 7, 28, g.lite, 1)
        g.p(1, 22, INK)
        g.p(9, 30, INK)
    g.line(3, 29, 1, 31, WOOD, 2)
    g.p(1, 30, _c(WOOD, 0.6))
    g.p(0, 31, g.dark)
    if p.get("edge"):
        e = {"flame": g.lite, "frost": (200, 240, 255, 255), "blood": (200, 50, 60, 255),
             "gold": (255, 220, 120, 255), "void": (200, 150, 255, 255), "poison": (150, 230, 90, 255)}[p["edge"]]
        for k in range(5):
            g.p(x1 - k * 2, 5 + k * 4, e)
            g.p(x1 - k * 2 - 1, 6 + k * 4, _c(e, 0.65))
        g.glowdot(x1, 4, 4, e[:3], 0.5)


def s_axe(g, p):
    g.line(6, 29, 17, 12, WOOD, 3)
    g.line(7, 29, 17, 13, _c(WOOD, 0.7), 1)
    g.p(5, 30, _c(WOOD, 0.6))
    def _head(dd):
        dd.polygon([(14, 6), (25, 8), (27, 15), (20, 18), (13, 14)], fill=(255, 255, 255, 255))
    g.litmask(_head, STEEL, 21, 12, 7, 6)
    g.line(16, 8, 25, 13, WHITE, 1)
    g.line(14, 13, 22, 17, _c(STEEL, 0.6), 1)
    g.p(26, 8, WHITE)
    if p.get("double"):
        g.poly([(13, 12), (8, 15), (13, 19)], _c(STEEL, 0.75))
    if p.get("spike"):
        g.line(20, 6, 20, 2, _c(STEEL, 0.8), 1)
    g.p(15, 10, g.lite)


def s_hammer(g, p):
    g.line(9, 30, 15, 16, WOOD, 3)
    g.line(10, 30, 15, 17, _c(WOOD, 0.7), 1)
    w = p.get("w", 14)
    def _head(dd):
        dd.rectangle((16 - w // 2, 4, 16 + w // 2, 12), fill=(255, 255, 255, 255))
    g.litmask(_head, STEEL, 16, 8, w // 2, 5)
    g.line(16 - w // 2 + 1, 5, 16 + w // 2 - 1, 5, WHITE, 1)
    g.line(16 - w // 2 + 1, 11, 16 + w // 2 - 1, 11, _c(STEEL, 0.55), 1)
    g.rect(16 - w // 2 - 1, 6, 1, 5, _c(STEEL, 0.7))
    g.rect(16 + w // 2, 6, 1, 5, _c(STEEL, 0.7))
    if p.get("glow"):
        g.p(14, 8, g.hot)
        g.p(18, 8, g.hot)
        g.glowdot(16, 8, 4, g.a, 0.6)


def s_dagger(g, p):
    if p.get("twin"):
        for dx in (-6, 6):
            g.line(16 + dx, 20, 24 + dx, 6, _c(STEEL, 0.85), 2)
            g.line(16 + dx, 20, 23 + dx, 7, WHITE, 1)
            g.p(25 + dx, 4, WHITE)
        g.line(8, 22, 24, 22, g.mid, 1)
        g.p(6, 22, INK)
        g.p(26, 22, INK)
        g.p(16, 24, g.dark)
        g.p(16, 25, INK)
        return
    g.line(11, 22, 24, 7, _c(STEEL, 0.85), 2)
    g.line(11, 22, 23, 8, WHITE, 1)
    g.p(25, 5, WHITE)
    g.p(26, 4, g.hot)
    g.line(8, 24, 14, 27, g.mid, 1)
    g.line(6, 26, 4, 29, WOOD, 2)
    g.p(3, 30, g.dark)
    g.p(16, 16, g.hot)


def s_blades(g, p):
    import random as _r
    rng = _r.Random(3)
    for k in range(7):
        a = math.tau * k / 7 + rng.random() * 0.3
        tipx = CX + 13 * math.cos(a)
        tipy = CY + 13 * math.sin(a)
        g.line(CX, CY, tipx, tipy, _c(STEEL, 0.8), 1)
        g.p(round(tipx), round(tipy), WHITE)
    g.disc(16, 16, 3, g.hot)
    g.p(15, 15, WHITE)
    g.glowdot(16, 16, 6, g.a, 0.5)


def s_whirl(g, p):
    arms = p.get("arms", 3)
    for k in range(arms):
        c = [g.lite, g.base, g.mid, _c(g.mid, 0.6)][k % 4]
        g.ring(15 - k, 16 + k, 13 - k * 2, c)
    g.disc(16, 16, 4, g.hot)
    g.disc(15, 15, 2, WHITE)
    g.ring(16, 16, 4, INK)
    g.spark(29, 2, g.lite)
    g.spark(2, 29, g.lite)


def s_slash(g, p):
    g.line(3, 29, 28, 4, g.lite, 3)
    g.line(4, 28, 27, 5, WHITE, 1)
    if p.get("double"):
        g.line(11, 30, 30, 11, g.mid, 2)
        g.line(2, 27, 6, 31, g.mid, 1)
    for x, y in ((29, 3), (30, 4), (28, 4), (27, 2)):
        g.p(x, y, g.hot)
    g.spark(30, 6, g.lite)


def s_impact(g, p):
    rays = p.get("rays", 8)
    for k in range(rays):
        a = k * 2 * math.pi / rays
        r1, r2 = (6, 14) if k % 2 == 0 else (8, 12)
        g.line(CX + r1 * math.cos(a), CY + r1 * math.sin(a),
               CX + r2 * math.cos(a), CY + r2 * math.sin(a), g.lite if k % 2 == 0 else g.base, 2 if k % 2 == 0 else 1)
    g.ring(16, 16, 6, g.base)
    g.disc(16, 16, 4, WHITE)
    g.disc(15, 15, 2, g.hot)


def s_nova(g, p):
    g.ring(16, 16, 13, g.base)
    g.ring(16, 16, 12, _c(g.mid, 0.7))
    g.ring(16, 16, 8, g.lite)
    g.ring(16, 16, 7, _c(g.mid, 0.7))
    g.disc(16, 16, 4, g.hot)
    g.disc(15, 15, 2, WHITE)
    for x, y in ((2, 16), (30, 16), (16, 2), (16, 30)):
        g.p(x, y, _c(g.lite, 0.85))
    g.glowdot(16, 16, 7, g.a, 0.6)


def s_shield(g, p):
    def _m(dd):
        dd.polygon([(5, 5), (27, 5), (27, 18), (16, 29), (5, 18)], fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 10, 13, 12)
    g.frame(5, 5, 23, 14, INK)
    h = p.get("herald", "boss")
    if h == "boss":
        g.disc(16, 13, 5, g.lite)
        g.disc(15, 12, 2, WHITE)
        g.ring(16, 13, 5, INK)
    elif h == "cross":
        g.line(16, 8, 16, 24, g.lite, 2)
        g.line(10, 12, 22, 12, g.lite, 2)
    elif h == "wings":
        g.line(11, 12, 4, 8, g.lite, 1)
        g.line(21, 12, 28, 8, g.lite, 1)
    for x, y in ((8, 7), (24, 7), (8, 16), (24, 16)):
        g.p(x, y, WHITE)


def s_wall(g, p):
    def _m(dd):
        dd.rectangle((4, 8, 27, 29), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 14, 14, 12)
    if p.get("cren", 1):
        for x in (6, 13, 20):
            g.rect(x, 4, 4, 4, g.base)
            g.p(x, 4, g.lite)
            g.litmask(lambda dd, xx=x: dd.rectangle((xx, 4, xx + 3, 7), fill=(255, 255, 255, 255)), g.base, xx := x, 5, 3, 2)
    for yy in (14, 21, 28):
        g.line(4, yy, 27, yy, INK, 1)
    g.line(13, 9, 13, 13, INK, 1)
    g.line(20, 15, 20, 20, INK, 1)
    g.line(9, 22, 9, 27, INK, 1)
    g.p(7, 10, g.hot)
    g.p(24, 10, WHITE)


def s_heart(g, p):
    def _m(dd):
        dd.ellipse((5, 7, 18, 19), fill=(255, 255, 255, 255))
        dd.ellipse((14, 7, 27, 19), fill=(255, 255, 255, 255))
        dd.ellipse((8, 12, 24, 28), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 14, 12, 11)
    g.line(16, 5, 16, 10, g.base, 2)
    g.p(14, 5, g.mid)
    g.p(18, 5, g.mid)
    g.p(11, 12, g.lite)
    g.p(13, 14, WHITE)
    g.p(16, 18, g.hot)
    g.p(10, 24, g.dark)
    g.p(22, 24, g.dark)
    if p.get("pulse"):
        g.line(1, 15, 5, 15, g.lite, 1)
        g.p(0, 14, g.mid)
        g.p(0, 16, g.mid)
        g.line(31, 15, 27, 15, g.lite, 1)
        g.p(31, 14, g.mid)
        g.p(31, 16, g.mid)


def s_cross(g, p):
    def _m(dd):
        dd.rectangle((12, 4, 20, 28), fill=(255, 255, 255, 255))
        dd.rectangle((4, 10, 28, 18), fill=(255, 255, 255, 255))
    g.litmask(_m, g.lite, 16, 16, 13, 13)
    g.line(13, 5, 13, 27, WHITE, 1)
    g.line(5, 11, 27, 11, WHITE, 1)
    g.frame(11, 3, 10, 26, INK)
    g.frame(3, 9, 26, 10, INK)
    g.disc(16, 14, 2, g.hot)
    if p.get("halo"):
        g.ring(16, 16, 14, g.base)
    for x, y in ((15, 0), (16, 0), (0, 14), (31, 14)):
        g.p(x, y, g.base)


def s_boot(g, p):
    def _m(dd):
        dd.rectangle((9, 2, 17, 19), fill=(255, 255, 255, 255))
        dd.rectangle((9, 20, 24, 28), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 15, 14, 9, 13)
    g.line(10, 3, 10, 18, g.lite, 1)
    g.line(10, 21, 23, 21, g.dark, 1)
    g.rect(9, 27, 17, 1, INK)
    g.line(19, 19, 25, 19, g.dark, 1)
    g.rect(21, 16, 2, 6, g.lite)
    g.p(22, 19, INK)
    for x in (11, 16, 22):
        g.p(x, 27, WHITE)
    if p.get("wings"):
        for k in range(4):
            g.p(27 - k, 4 + k * 3, g.lite)
            g.p(28 - k, 4 + k * 3, g.mid)
    else:
        g.spark(27, 6, g.hot)
        g.p(28, 10, g.lite)
        g.p(26, 12, g.lite)


def s_wing(g, p):
    for k in range(6):
        c = g.lite if k % 2 else g.base
        g.line(16, 26 - k * 2, 29 - k * 2, 4 + k * 3, c, 2)
        g.line(15, 26 - k * 2, 3 + k * 2, 4 + k * 3, g.mid if k % 2 else g.base, 2)
        g.p(29 - k * 2, 4 + k * 3, WHITE)
    g.line(16, 28, 16, 6, g.dark, 2)
    g.p(16, 4, g.hot)
    g.p(14, 3, g.lite)
    g.p(18, 3, g.lite)


def s_cloak(g, p):
    def _m(dd):
        dd.polygon([(8, 6), (25, 6), (29, 29), (3, 29)], fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 18, 13, 12)
    g.rect(11, 4, 11, 5, g.mid)
    g.rect(13, 6, 7, 3, INK)
    g.rect(11, 4, 11, 1, g.lite)
    g.line(9, 9, 6, 28, g.dark, 1)
    g.line(23, 9, 26, 28, g.dark, 1)
    g.line(16, 9, 16, 28, g.dark, 1)
    g.disc(16, 8, 2, g.lite)
    g.p(16, 8, g.hot)


def s_flame(g, p):
    big = 2 if p.get("big") else 0
    def _m(dd):
        dd.polygon([(16 - 5 - big, 28), (16 - 2, 14), (16, 8), (18, 15), (16 + 5 + big, 28)], fill=(255, 255, 255, 255))
        dd.ellipse((16 - 6 - big, 20, 16 + 6 + big, 29), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 24, 10, 8)
    g.line(16, 3, 13, 11, g.lite, 2)
    g.line(13, 11, 17, 18, g.lite, 1)
    if p.get("twin"):
        g.line(23, 7, 25, 14, g.base, 1)
        g.p(24, 5, g.mid)
    g.p(21, 8, g.base)
    g.p(23, 13, g.base)
    g.disc(16, 24, 4, g.hot)
    g.p(14, 22, WHITE)
    g.p(11, 27, _c(g.base, 0.6))
    g.p(21, 27, _c(g.base, 0.6))
    g.glowdot(16, 20, 8, g.a, 0.55)
    g.spark(27, 6, g.lite)


def s_snowflake(g, p):
    dirs = [(0, -13), (11, 7), (-11, 7)] if p.get("arms", 6) == 6 else [(0, -13), (9, 9), (9, -9), (-9, 9), (-9, -9), (0, 13)]
    for dx, dy in dirs:
        g.line(16, 16, 16 + dx, 16 + dy, g.lite, 1)
        tx, ty = 16 + dx, 16 + dy
        for sgn in (-1, 1):
            bx = tx - (3 if dx == 0 else (2 if dx > 0 else -2))
            by = ty - (3 if dy == 0 else (2 if dy > 0 else -2))
            g.line(tx, ty, bx + sgn * 2, by - 2, g.base, 1)
        g.p(tx, ty, WHITE)
        g.p(16 + dx // 2, 16 + dy//2, g.base)
    g.disc(16, 16, 4, WHITE)
    g.disc(15, 15, 2, g.hot)
    g.ring(16, 16, 13, g.mid)
    g.glowdot(16, 16, 8, g.a, 0.4)


def s_orb(g, p):
    def _m(dd):
        dd.ellipse((5, 5, 27, 27), fill=(255, 255, 255, 255))
    g.litmask(_m, g.mid, 16, 16, 11, 11)
    g.disc(16, 16, 8, g.dark)
    g.disc(13, 13, 4, g.lite)
    g.disc(12, 12, 2, WHITE)
    g.ring(16, 16, 11, INK)
    g.p(20, 20, g.base)
    if p.get("ring"):
        g.line(4, 22, 28, 10, g.base, 1)
        g.p(4, 22, g.lite)
        g.p(28, 10, g.lite)
    if p.get("stars"):
        g.p(2, 8, g.hot)
        g.p(29, 23, g.hot)
    g.glowdot(16, 16, 9, g.a, 0.5)


def s_eye(g, p):
    def _m(dd):
        dd.ellipse((3, 8, 29, 24), fill=(255, 255, 255, 255))
    g.litmask(_m, g.mid, 16, 16, 14, 9)
    g.disc(16, 16, 7, g.dark)
    g.ring(16, 16, 5, g.base)
    g.disc(16, 16, 3, g.hot)
    g.line(16, 13, 16, 19, INK, 1)
    g.p(15, 15, WHITE)
    g.line(16, 6, 16, 9, g.lite, 1)
    g.line(16, 23, 16, 26, g.lite, 1)
    g.line(4, 16, 8, 16, g.lite, 1)
    g.line(24, 16, 28, 16, g.lite, 1)
    if p.get("lashes"):
        for x, y in ((5, 7), (27, 7), (5, 25), (27, 25)):
            g.p(x, y, g.lite)


def s_bolt(g, p):
    pts = [(19, 2), (8, 16), (15, 16), (10, 30), (25, 12), (18, 12), (23, 2)]
    for i in range(len(pts) - 1):
        g.line(*pts[i], *pts[i + 1], g.lite, 3)
    for i in range(len(pts) - 1):
        g.line(*pts[i], *pts[i + 1], WHITE, 1)
    if p.get("fork"):
        g.line(10, 30, 5, 27, g.base, 1)
        g.line(25, 12, 29, 9, g.base, 1)
    g.spark(28, 4, g.lite)
    g.glowdot(16, 16, 8, g.a, 0.5)


def s_arrow(g, p):
    n = p.get("count", 1)
    for k in range(n):
        oy = k * 4 - (n - 1) * 2
        g.line(6, 27 - oy, 24, 7 - (oy if oy < 0 else 0), g.mid, 1)
    g.line(26, 8, 21, 6, g.lite, 2)
    g.line(26, 8, 27, 13, g.lite, 2)
    g.p(27, 6, g.hot)
    g.line(6, 24, 9, 30, g.base, 1)
    g.line(8, 23, 11, 29, g.base, 1)


def s_fan(g, p):
    cnt = p.get("count", 3)
    for k in range(cnt):
        t = k / max(1, cnt - 1) - 0.5
        dx = round(t * 24)
        ty = 3 + abs(k - (cnt - 1) / 2) * (0 if cnt < 6 else 1)
        g.line(16, 28, 16 + dx, ty + 2, _c(STEEL, 0.85), 1)
        g.p(16 + dx, ty, WHITE)
        if cnt <= 5:
            g.line(16, 28, 16 + dx // 2, ty + 7, STEEL, 1)
    g.disc(16, 28, 2, WOOD)
    g.p(16, 29, _c(WOOD, 0.6))
    g.p(14, 29, INK)
    g.p(18, 29, INK)


def s_poison(g, p):
    n = p.get("drops", 1)
    spots = [(16, 18)] + ([(26, 16)] if n > 1 else []) + ([(7, 19)] if n > 2 else [])
    for cx, cy in spots:
        def _m(dd, ccx=cx, ccy=cy):
            dd.ellipse((ccx - 6, ccy - 7, ccx + 6, ccy + 7), fill=(255, 255, 255, 255))
        g.litmask(_m, g.base, cx, cy - 1, 6, 7)
        g.p(cx - 3, cy - 4, g.lite)
        g.p(cx - 2, cy - 3, WHITE)
        g.p(cx + 2, cy + 3, g.mid)
    g.line(16, 5, 16, 10, g.lite, 1)
    g.p(18, 8, g.base)
    g.p(14, 3, g.base)
    g.p(19, 2, g.mid)


def s_bomb(g, p):
    def _m(dd):
        dd.ellipse((4, 10, 27, 30), fill=(255, 255, 255, 255))
    g.litmask(_m, (58, 58, 70, 255), 16, 20, 12, 10)
    g.p(10, 14, (130, 130, 148, 255))
    g.p(12, 13, (160, 160, 178, 255))
    g.p(13, 15, (100, 100, 116, 255))
    g.line(21, 11, 24, 7, (90, 70, 50, 255), 2)
    g.line(24, 7, 28, 4, (150, 120, 80, 255), 1)
    g.disc(28, 3, 2, g.hot)
    g.p(30, 1, g.lite)
    g.p(27, 1, g.lite)
    if p.get("smoke"):
        g.p(6, 8, g.mid)
        g.p(4, 5, _c(g.mid, 1.3))
        g.p(8, 3, g.mid)


def s_sun(g, p):
    g.disc(16, 16, 8, g.base)
    g.disc(16, 16, 7, g.lite)
    g.disc(14, 14, 3, WHITE)
    g.ring(16, 16, 8, INK)
    for k in range(8):
        a = k * math.pi / 4
        x, y = round(16 + 12 * math.cos(a)), round(16 + 12 * math.sin(a))
        x2, y2 = round(16 + 10 * math.cos(a)), round(16 + 10 * math.sin(a))
        g.line(x2, y2, x, y, g.lite, 1)
        if p.get("wave"):
            g.p(round(16 + 14 * math.cos(a)), round(16 + 14 * math.sin(a)), g.hot if k % 2 else g.base)
    g.glowdot(16, 16, 11, g.a, 0.5)


def s_fist(g, p):
    def _m(dd):
        dd.rectangle((7, 8, 25, 21), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 14, 10, 8)
    g.frame(6, 7, 20, 15, INK)
    for x in (11, 16, 21):
        g.line(x, 10, x, 19, g.mid, 1)
        g.p(x, 9, WHITE)
    g.rect(2, 10, 4, 9, g.mid)
    g.frame(1, 9, 6, 11, INK)
    if p.get("burst"):
        g.spark(28, 5, g.hot)
        g.spark(3, 3, g.lite)
    else:
        g.p(27, 10, g.hot)


def s_skull(g, p):
    """Three distinct identities:
    - executioner: crowned skull, jaw clenched, axe behind
    - assassin: hooded shadow, only burning eyes visible
    - child_of_dark: horned, crystals growing from the skull
    - default: plain skull (for any other skill that uses it)
    """
    ident = p.get("id", "")
    if ident == "executioner":
        _skull_executioner(g)
        return
    if ident == "assassin":
        _skull_assassin(g)
        return
    if ident == "child_of_dark":
        _skull_child_of_dark(g)
        return
    _skull_plain(g)


def _skull_plain(g):
    def _m(dd):
        dd.ellipse((7, 5, 25, 21), fill=(255, 255, 255, 255))
        dd.rectangle((10, 18, 22, 27), fill=(255, 255, 255, 255))
    g.litmask(_m, BONE, 16, 12, 10, 10)
    g.disc(12, 13, 3, INK)
    g.disc(20, 13, 3, INK)
    g.p(16, 17, INK)
    g.line(11, 22, 21, 22, _c(BONE, 0.75), 1)
    for x in (13, 16, 19):
        g.line(x, 21, x, 24, INK, 1)
    g.spark(6, 18, g.hot)
    g.spark(26, 18, g.hot)


def _skull_executioner(g):
    """A crowned skull with an axe blade rising behind it."""
    # the axe behind
    g.line(4, 28, 10, 8, _c(GOLD, 0.7), 3)
    g.line(5, 28, 10, 9, GOLD, 1)
    def _blade(dd):
        dd.polygon([(10, 4), (18, 6), (19, 14), (13, 17), (9, 12)], fill=(255, 255, 255, 255))
    g.litmask(_blade, STEEL, 14, 10, 5, 6)
    g.line(11, 6, 17, 11, WHITE, 1)
    # the skull — volume lit, jaw clenched (no gap)
    def _m(dd):
        dd.ellipse((10, 10, 26, 24), fill=(255, 255, 255, 255))
        dd.rectangle((13, 21, 23, 28), fill=(255, 255, 255, 255))
    g.litmask(_m, BONE, 18, 16, 9, 9)
    # burning sockets
    g.disc(15, 16, 2, INK)
    g.disc(21, 16, 2, INK)
    g.p(15, 16, g.hot)
    g.p(21, 16, g.hot)
    # nose + tight teeth
    g.p(18, 19, INK)
    g.line(15, 24, 21, 24, _c(BONE, 0.6), 1)
    for x in (16, 18, 20):
        g.line(x, 23, x, 27, INK, 1)
    # the crown: iron, three heavy spikes
    g.line(12, 7, 24, 7, _c(GOLD, 0.8), 2)
    for x in (13, 18, 23):
        g.line(x, 2, x, 7, GOLD, 2)
        g.p(x, 1, g.hot)
    # crack
    g.line(24, 12, 26, 16, _c(BONE, 0.5), 1)


def _skull_assassin(g):
    """A hood of shadow: only two burning eyes in the dark."""
    # the hood: a dark cone
    def _m(dd):
        dd.polygon([(8, 28), (10, 8), (16, 4), (22, 8), (24, 28)], fill=(255, 255, 255, 255))
    g.litmask(_m, (30, 22, 38, 255), 16, 18, 10, 14, flat=0.3)
    # the rim catches light
    g.line(10, 8, 16, 4, g.mid, 1)
    g.line(16, 4, 22, 8, g.dark, 1)
    # fold lines
    g.line(12, 12, 13, 26, g.dark, 1)
    g.line(20, 12, 19, 26, g.dark, 1)
    # the face: pure shadow, two burning slits
    g.rect(12, 14, 8, 6, (14, 10, 18, 255))
    g.line(13, 16, 16, 16, g.hot, 1)
    g.line(18, 16, 20, 16, g.hot, 1)
    g.p(14, 15, _c(g.hot, 0.6))
    g.p(19, 15, _c(g.hot, 0.6))
    # a dagger tip peeks from under the hood
    g.line(16, 28, 16, 31, STEEL, 1)
    g.p(16, 31, WHITE)
    # wisps of shadow
    g.p(7, 20, _c(g.mid, 0.5))
    g.p(25, 18, _c(g.mid, 0.5))
    g.p(9, 26, _c(g.mid, 0.4))


def _skull_child_of_dark(g):
    """A horned skull with violet crystals growing from it."""
    # crystals growing from behind
    for bx, by, w, h in ((6, 6, 3, 8), (24, 5, 4, 10), (10, 3, 3, 6), (20, 2, 3, 7)):
        g.poly([(bx, by + h), (bx + w // 2, by), (bx + w, by + h)], (150, 100, 230, 220))
        g.line(bx + w // 2, by, bx + w // 2, by + h, (220, 180, 255, 180))
        g.glowdot(bx + w // 2, by + h // 2, 3, (150, 100, 230), 0.5)
    # the skull — slightly tilted, one horn broken
    def _m(dd):
        dd.ellipse((9, 8, 25, 22), fill=(255, 255, 255, 255))
        dd.rectangle((12, 19, 22, 27), fill=(255, 255, 255, 255))
    g.litmask(_m, _c(BONE, 0.9), 17, 14, 9, 9)
    # horns: left tall and curved, right broken
    g.line(9, 8, 4, 2, BONE, 2)
    g.line(4, 2, 3, 5, BONE, 1)
    g.line(25, 8, 28, 4, BONE, 2)
    g.p(28, 4, _c(BONE, 0.5))  # broken tip
    # glowing sockets: violet, one brighter
    g.disc(14, 14, 2, INK)
    g.disc(20, 14, 2, INK)
    g.p(14, 14, (180, 130, 255))
    g.p(20, 14, (230, 180, 255))
    g.glowdot(14, 14, 2.5, (150, 100, 230), 0.6)
    # crystal in the forehead
    g.poly([(16, 9), (17, 6), (18, 9)], (180, 130, 255, 200))
    g.p(17, 7, WHITE)
    # teeth
    g.line(14, 22, 20, 22, _c(BONE, 0.6), 1)
    for x in (15, 17, 19):
        g.line(x, 21, x, 25, INK, 1)


def s_blood(g, p):
    def _m(dd):
        dd.polygon([(16 - 3, 4), (16 + 3, 4), (16 + 6, 18), (16, 29), (16 - 6, 18)], fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 16, 7, 12)
    g.p(14, 8, g.lite)
    g.p(15, 10, WHITE)
    g.p(13, 15, g.lite)
    g.p(18, 20, g.mid)
    g.p(16, 25, g.dark)
    if p.get("splashes"):
        g.disc(6, 12, 2, g.mid)
        g.p(7, 13, g.base)
        g.disc(26, 17, 2, g.mid)
        g.p(25, 18, g.base)


def s_star(g, p):
    pts = [(16, 1), (19, 11), (30, 12), (22, 19), (25, 30), (16, 23), (7, 30), (10, 19), (2, 12), (13, 11)]
    for i in range(len(pts)):
        g.line(16, 16, *pts[i], g.base, 1)
    for pt in pts:
        g.p(*pt, g.lite)
    g.disc(16, 16, 3, g.lite)
    g.disc(15, 15, 1, WHITE)
    if p.get("twinkle"):
        g.spark(24, 4, g.hot)


def s_chains(g, p):
    for yy in (6, 16, 26):
        for xx in (9, 21):
            cy = yy + (0 if xx == 9 else 2)
            def _m(dd, xxx=xx, cyy=cy):
                dd.ellipse((xxx - 4, cyy - 4, xxx + 4, cyy + 4), fill=(255, 255, 255, 255))
            g.litmask(_m, g.base, xx, cy, 4, 4)
            g.ring(xx, cy, 3, g.dark)
            g.p(xx - 2, cy - 2, g.lite)
    g.line(12, 8, 18, 18, g.mid, 1)
    g.line(13, 6, 20, 17, g.mid, 1)
    if p.get("break"):
        g.p(16, 12, INK)
        g.p(17, 13, INK)
        g.spark(16, 12, g.hot)


def s_hourglass(g, p):
    g.line(6, 3, 26, 3, WOOD, 2)
    g.line(6, 29, 26, 29, WOOD, 2)
    g.line(6, 3, 6, 5, _c(WOOD, 0.6), 1)
    g.line(26, 3, 26, 5, _c(WOOD, 0.6), 1)
    g.line(9, 6, 16, 16, g.lite, 1)
    g.line(23, 6, 16, 16, g.lite, 1)
    g.line(9, 26, 16, 16, g.lite, 1)
    g.line(23, 26, 16, 16, g.lite, 1)
    g.line(11, 7, 15, 12, WHITE, 1)
    g.line(10, 8, 21, 8, g.base, 1)
    g.rect(13, 22, 7, 1, g.base)
    g.rect(11, 25, 11, 1, g.base)
    g.p(16, 18, g.hot)
    g.p(16, 13, g.hot)
    if p.get("hold"):
        g.ring(16, 16, 14, g.mid)


def s_figure(g, p):
    def _m(dd):
        dd.ellipse((13, 4, 19, 10), fill=(255, 255, 255, 255))      # голова
        dd.polygon([(9, 12), (23, 12), (25, 27), (7, 27)], fill=(255, 255, 255, 255))  # торс
    g.litmask(_m, g.base, 16, 18, 9, 10)
    g.ring(16, 7, 3, INK)
    g.disc(16, 7, 2, BONE)
    g.p(15, 6, INK)
    g.p(17, 6, INK)
    g.line(11, 14, 11, 25, g.mid, 1)
    g.line(21, 14, 21, 25, g.mid, 1)
    g.p(16, 2, g.hot)
    if p.get("aura"):
        g.ring(16, 16, 13, g.mid)
        g.p(2, 16, g.lite)
        g.p(30, 16, g.lite)


def s_meteor(g, p):
    def _m(dd):
        dd.ellipse((14, 14, 28, 28), fill=(255, 255, 255, 255))
    g.litmask(_m, (110, 84, 70, 255), 21, 21, 7, 7)
    g.disc(20, 20, 4, (150, 118, 96, 255))
    g.p(19, 19, WHITE)
    g.line(4, 4, 12, 12, g.lite, 3)
    g.line(2, 2, 5, 5, g.base, 2)
    g.p(1, 1, g.hot)
    for x, y in ((5, 10), (10, 5)):
        g.p(x, y, g.mid)
    g.glowdot(21, 21, 8, g.a, 0.6)


def s_thorns(g, p):
    g.ring(16, 16, 8, g.base)
    g.disc(16, 16, 7, g.dark)
    g.disc(15, 15, 2, g.hot)
    for k in range(8):
        a = k * math.pi / 4
        g.line(16 + 8 * math.cos(a), 16 + 8 * math.sin(a),
               16 + 14 * math.cos(a), 16 + 14 * math.sin(a), g.mid, 2)
        g.p(round(16 + 14 * math.cos(a)), round(16 + 14 * math.sin(a)), g.lite)


def s_frenzy(g, p):
    def _m(dd):
        dd.ellipse((5, 5, 27, 27), fill=(255, 255, 255, 255))
    g.litmask(_m, g.base, 16, 16, 12, 12)
    g.disc(11, 14, 2, INK)
    g.disc(21, 14, 2, INK)
    g.p(10, 13, g.dark)
    g.p(22, 13, g.dark)
    g.rect(11, 20, 10, 5, INK)
    g.line(14, 20, 14, 24, WHITE, 1)
    g.line(18, 20, 18, 24, WHITE, 1)
    g.line(16, 2, 16, 6, g.lite, 1)
    g.spark(2, 5, g.hot)
    g.spark(30, 26, g.hot)


def s_hat(g, p):
    g.rect(5, 22, 22, 4, g.base)
    g.rect(5, 22, 22, 1, g.lite)
    g.frame(4, 21, 24, 6, INK)
    for i in range(12):
        w = max(1, 13 - i)
        g.rect(8 + i // 2, 20 - i * 1.5 // 1, w, 1, g.mid if i % 2 else g.base)
    g.p(22, 4, g.base)
    g.p(24, 3, g.lite)
    g.p(22, 2, INK)
    g.p(14, 12, g.hot)
    g.p(15, 10, g.lite)
    g.p(5, 25, g.dark)
    g.p(26, 25, g.dark)


def s_execution(g, p):
    s_axe(g, {"spike": 1})
    g.line(27, 28, 31, 28, g.dark, 1)
    g.disc(29, 25, 1, INK)
    g.p(26, 27, INK)
    g.spark(29, 22, g.hot)


SUBJECTS = {k[2:]: v for k, v in list(globals().items()) if k.startswith("s_")}


# ------------------------------------------------------------------- fx
def fx_sparks(g):
    g.spark(2, 4, g.lite)
    g.spark(29, 27, g.lite)


def fx_runes(g):
    g.p(4, 27, g.hot)
    g.p(27, 4, g.hot)
    g.p(29, 27, g.mid)


def fx_speed(g):
    g.line(0, 8, 5, 8, g.mid, 1)
    g.line(26, 24, 31, 24, g.mid, 1)


def fx_drips(g):
    g.p(6, 27, g.mid)
    g.p(6, 29, _c(g.mid, 0.7))
    g.p(25, 5, g.mid)


FX = dict(sparks=fx_sparks, runes=fx_runes, speed=fx_speed, drips=fx_drips)


def _edge_dark(im):
    px = im.load()
    for i in range(S):
        for x, y in ((i, 0), (i, S - 1), (0, i), (S - 1, i)):
            r, gg, b, a = px[x, y]
            if a > 0:
                px[x, y] = (int(r * 0.55), int(gg * 0.55), int(b * 0.55), a)
    return im


def draw(spec, accent) -> Image.Image:
    g = G(accent)
    BGS[spec.get("bg", "wash")](g)
    subj, p = spec["s"] if isinstance(spec["s"], tuple) else (spec["s"], {})
    SUBJECTS[subj](g, p)
    for f in spec.get("fx", []):
        FX[f](g)
    g.im.alpha_composite(g.glow)
    im = icon_detail.detail(g.im)
    return _edge_dark(im)


if __name__ == "__main__":
    import gen_skill_icons as old
    os.makedirs("_preview32", exist_ok=True)
    from PIL import Image as I
    sheet = I.new("RGB", (10 * 34, 10 * 34), (24, 16, 36))
    for i, (sid, (spec, accent)) in enumerate(old.ICON_TABLE_PREVIEW.items() if hasattr(old, "ICON_TABLE_PREVIEW") else []):
        pass
    print("use via gen_skills_v2")
