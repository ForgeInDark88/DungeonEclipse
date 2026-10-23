#!/usr/bin/env python3
"""Skill icons v3: full-cell art with effect backdrops, unique subjects per
skill, then the SAME detail pass the item icons get (tools/icon_detail.py):
volume light, dithered gradients, rim light, glints - plus a final sparkle.

draw(spec, accent) where spec = {"bg": ..., "s": (subject, params), "fx": [...]}
Run from tools/.
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import icon_detail

INK = (16, 10, 24, 255)
STEEL = (200, 208, 222, 255)
STEEL_M = (150, 160, 182, 255)
STEEL_D = (98, 108, 130, 255)
WOOD = (158, 104, 58, 255)
WOOD_D = (106, 66, 36, 255)
BONE = (238, 232, 216, 255)
WHITE = (255, 255, 255, 255)

S = 16
CX = CY = 7.5


def _c(v, f):
    return tuple(min(255, int(ch * f)) for ch in v[:3]) + (255,)


class G:
    def __init__(self, accent):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.px = self.im.load()
        a = accent if len(accent) >= 3 else (220, 80, 80)
        self.a = tuple(a[:3]) + (255,)
        self.dark = _c(self.a, 0.35)
        self.mid = _c(self.a, 0.6)
        self.base = _c(self.a, 0.95)
        self.lite = _c(self.a, 1.3)
        self.hot = _c(self.a, 1.75)

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
                if (r - 1) ** 2 < d <= r * r + r * 0.7:
                    self.p(x, y, c)

    def spark(self, x, y, c):
        self.p(x, y, c)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            self.p(x + dx, y + dy, _c(c[:3], 0.75))


# ------------------------------------------------------------- backdrops
def bg_wash(g):
    """Radial accent wash filling the whole cell (dithered two-step)."""
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - CX, y - CY) / 10.5
            if d < 0.45:
                g.p(x, y, _c(g.dark, 1.25))
            elif d < 0.8:
                g.p(x, y, g.dark if (x + y) % 2 else _c(g.dark, 0.8))
            else:
                g.p(x, y, _c(g.dark, 0.55) if (x * 2 + y) % 3 else _c(g.dark, 0.4))


def bg_rays(g):
    bg_wash(g)
    for k in range(8):
        a = k * math.pi / 4 + 0.4
        for r in range(5, 9):
            g.p(round(CX + r * math.cos(a)), round(CY + r * math.sin(a)), g.mid if r % 2 else _c(g.mid, 0.7))


def bg_orbit(g):
    bg_wash(g)
    g.ring(CX, CY, 7, g.mid)
    g.ring(CX, CY, 6, _c(g.dark, 0.7))


def bg_particles(g):
    bg_wash(g)
    for x, y in ((2, 3), (13, 4), (4, 12), (11, 13), (14, 9), (1, 8)):
        g.p(x, y, g.mid)
        g.p(x, y - 1, _c(g.mid, 1.3))


def bg_storm(g):
    bg_wash(g)
    for x, y in ((1, 2), (5, 1), (10, 2), (14, 4), (3, 6), (12, 7)):
        g.p(x, y, g.lite)
    for yy in range(0, S, 4):
        g.line(0, yy + 2, S - 1, yy, _c(g.dark, 1.4), 1)


def bg_runes(g):
    bg_wash(g)
    for x, y, w in ((2, 2, 1), (13, 2, 2), (2, 12, 2), (12, 13, 1), (7, 1, 1), (8, 14, 1)):
        g.rect(x, y, w, 1, g.mid)


def bg_glowline(g):
    bg_wash(g)
    g.line(0, 13, 15, 2, _c(g.mid, 1.15), 1)
    g.line(0, 14, 15, 3, g.mid, 1)


def bg_dark(g):
    for y in range(S):
        for x in range(S):
            g.p(x, y, (14, 9, 20, 255) if (x + y) % 5 else (20, 13, 28, 255))


BGS = dict(wash=bg_wash, rays=bg_rays, orbit=bg_orbit, particles=bg_particles,
           storm=bg_storm, runes=bg_runes, glowline=bg_glowline, dark=bg_dark)


# --------------------------------------------------------------- subjects
def s_blade(g, p):
    ln = p.get("len", "long")
    x1 = 12 if ln == "long" else 10
    g.line(x1, 2, 3, 11, STEEL_D, 3)
    g.line(x1 - 1, 2, 4, 10, STEEL, 2)
    g.line(x1 - 2, 3, 5, 9, WHITE if p.get("shine", 1) else STEEL_M, 1)
    g.p(x1 + 1, 1, WHITE)
    if p.get("guard") != "none":
        g.line(1, 9, 5, 13, g.mid, 2)
        g.p(1, 8, INK); g.p(6, 14, INK)
        g.p(2, 10, g.lite)
    g.line(2, 12, 1, 13, WOOD_D, 2)
    g.p(1, 14, g.dark)
    if p.get("edge"):
        e = {"flame": g.lite, "frost": (200, 240, 255, 255), "blood": (200, 50, 60, 255), "gold": (255, 220, 120, 255), "void": (200, 150, 255, 255), "poison": (150, 230, 90, 255)}[p["edge"]]
        for k in range(4):
            g.p(x1 - k, 3 + k * 2, e)
            g.p(x1 - k - 1, 4 + k * 2, _c(e[:3], 0.7))


def s_axe(g, p):
    g.line(3, 13, 9, 4, WOOD, 2)
    g.line(4, 13, 9, 5, WOOD_D, 1)
    g.disc(11, 4, 4, STEEL_D)
    g.disc(11, 4, 3, STEEL)
    g.disc(12, 3, 2, WHITE)
    g.ring(11, 4, 4, INK)
    if p.get("double"):
        g.disc(5, 6, 2, STEEL_M)
        g.ring(5, 6, 2, INK)
    if p.get("spike"):
        g.line(11, 0, 11, 2, STEEL_M, 1)
    g.p(8, 4, g.lite)


def s_hammer(g, p):
    g.line(5, 13, 8, 7, WOOD, 2)
    g.line(6, 13, 8, 8, WOOD_D, 1)
    w = p.get("w", 8)
    g.rect(8 - w // 2, 2, w, 5, STEEL_D)
    g.rect(8 - w // 2 + 1, 3, w - 2, 3, STEEL)
    g.rect(8 - w // 2 + 1, 2, w - 2, 1, WHITE)
    g.frame(8 - w // 2, 2, w, 5, INK)
    if p.get("glow"):
        g.p(7, 4, g.hot); g.p(9, 4, g.hot)


def s_dagger(g, p):
    if p.get("twin"):
        for dx in (-3, 3):
            g.line(8 + dx, 9, 11 + dx, 3, STEEL_D, 1)
            g.line(8 + dx, 9, 10 + dx, 4, STEEL, 1)
            g.p(11 + dx, 2, WHITE)
        g.line(5, 11, 10, 11, g.mid, 1)
        g.p(4, 11, INK); g.p(11, 11, INK)
        g.p(8, 12, g.dark); g.p(8, 13, INK)
        return
    g.line(6, 9, 11, 3, STEEL_D, 2)
    g.line(6, 9, 10, 4, STEEL, 1)
    g.p(11, 2, WHITE)
    g.line(4, 10, 7, 12, g.mid, 1)
    g.line(3, 11, 2, 12, WOOD, 2)
    g.p(1, 13, g.dark)
    g.p(8, 7, g.hot)


def s_whirl(g, p):
    arms = p.get("arms", 3)
    for k in range(arms):
        c = [g.lite, g.base, g.mid, _c(g.mid, 0.7)][k % 4]
        g.ring(8 - k, 8 + k, 6 - k, c)
    g.disc(8, 8, 2, g.hot)
    g.disc(7, 7, 1, WHITE)
    g.ring(8, 8, 2, INK)
    g.spark(14, 1, g.lite); g.spark(1, 14, g.lite)


def s_slash(g, p):
    g.line(2, 13, 13, 2, g.lite, 2)
    g.line(3, 12, 12, 3, WHITE, 1)
    if p.get("double"):
        g.line(6, 14, 14, 6, g.mid, 1)
        g.line(1, 12, 3, 14, g.mid, 1)
    g.p(14, 1, g.hot); g.p(13, 2, g.hot); g.p(12, 2, g.hot)


def s_impact(g, p):
    rays = p.get("rays", 8)
    for k in range(rays):
        a = k * 2 * math.pi / rays
        r1, r2 = (3, 7) if k % 2 == 0 else (4, 6)
        g.line(CX + r1 * math.cos(a), CY + r1 * math.sin(a),
               CX + r2 * math.cos(a), CY + r2 * math.sin(a), g.lite if k % 2 == 0 else g.base, 1)
    g.disc(8, 8, 2, WHITE)
    g.disc(8, 8, 1, g.hot)
    g.ring(8, 8, 3, g.base)


def s_nova(g, p):
    g.ring(8, 8, 6, g.base)
    g.ring(8, 8, 4, g.lite)
    g.ring(8, 8, 4, g.lite)
    g.disc(8, 8, 2, g.hot)
    g.disc(7, 7, 1, WHITE)
    for x, y in ((1, 8), (14, 8), (8, 1), (8, 14)):
        g.p(x, y, _c(g.lite, 0.8))


def s_shield(g, p):
    for y in range(2, 14):
        w = 11 - max(0, y - 8) * 2
        x = 8 - w // 2
        g.rect(x, y, w, 1, g.base if y < 9 else g.mid)
        g.p(x, y, g.dark); g.p(x + w - 1, y, g.dark)
    g.rect(3, 2, 11, 1, INK)
    h = p.get("herald", "boss")
    if h == "boss":
        g.disc(8, 7, 2, g.lite); g.disc(7, 6, 1, WHITE); g.ring(8, 7, 2, INK)
    elif h == "cross":
        g.line(8, 4, 8, 11, g.lite, 1); g.line(5, 6, 11, 6, g.lite, 1)
    elif h == "wings":
        g.line(5, 6, 2, 4, g.lite, 1); g.line(11, 6, 14, 4, g.lite, 1)
    for x, y in ((4, 4), (12, 4), (5, 12), (11, 12)):
        g.p(x, y, WHITE)


def s_wall(g, p):
    g.rect(3, 4, 10, 10, g.base)
    g.rect(3, 4, 10, 1, g.lite)
    g.rect(3, 13, 10, 1, g.dark)
    g.frame(3, 4, 10, 10, INK)
    if p.get("cren", 1):
        for x in (4, 7, 10):
            g.rect(x, 2, 2, 2, g.base); g.p(x, 2, g.lite)
    for yy in (7, 10):
        g.line(3, yy, 12, yy, INK, 1)
    g.line(7, 5, 7, 6, INK, 1); g.line(10, 8, 10, 9, INK, 1); g.line(5, 11, 5, 12, INK, 1)
    g.p(4, 5, g.hot); g.p(11, 5, WHITE)


def s_heart(g, p):
    g.disc(6, 6, 3, g.mid); g.disc(10, 6, 3, g.mid); g.disc(8, 8, 4, g.base)
    g.disc(8, 11, 2, g.base)
    for x, y in ((4, 5), (12, 5), (5, 4), (11, 4), (6, 13), (10, 13), (8, 14)):
        g.p(x, y, INK)
    g.p(6, 12, g.dark); g.p(10, 12, g.dark)
    g.line(8, 2, 8, 5, g.base, 1)
    g.p(7, 2, g.mid); g.p(9, 2, g.mid)
    g.p(6, 5, g.lite); g.p(7, 6, WHITE)
    g.p(8, 9, g.hot)
    if p.get("pulse"):
        g.line(1, 7, 3, 7, g.lite, 1); g.p(0, 6, g.mid); g.p(0, 8, g.mid)
        g.line(14, 7, 12, 7, g.lite, 1); g.p(15, 6, g.mid); g.p(15, 8, g.mid)


def s_cross(g, p):
    g.rect(6, 2, 3, 11, g.lite)
    g.rect(2, 5, 11, 3, g.lite)
    g.rect(6, 2, 1, 11, WHITE)
    g.rect(2, 5, 1, 3, WHITE)
    g.frame(6, 2, 3, 11, INK); g.frame(2, 5, 11, 3, INK)
    g.disc(8, 6, 1, g.hot)
    if p.get("halo"):
        g.ring(8, 8, 7, g.base)
    for x, y in ((7, 0), (8, 0), (0, 6), (15, 6)):
        g.p(x, y, g.base)


def s_boot(g, p):
    g.rect(4, 1, 4, 9, g.base)
    g.rect(4, 1, 4, 1, g.lite)
    g.rect(4, 1, 1, 9, g.mid)
    g.rect(4, 9, 8, 4, g.base)
    g.rect(4, 12, 9, 1, INK)
    g.frame(4, 1, 4, 12, INK)
    g.line(9, 8, 12, 8, g.dark, 1)
    g.rect(10, 7, 1, 3, g.lite); g.p(10, 8, INK)
    for x in (5, 8, 11):
        g.p(x, 12, WHITE)
    if p.get("wings"):
        for k in range(3):
            g.p(13 - k, 3 + k * 2, g.lite); g.p(14 - k, 3 + k * 2, g.mid)
    else:
        g.p(12, 4, g.hot); g.p(13, 5, g.lite); g.p(13, 3, g.lite)


def s_wing(g, p):
    for k in range(4):
        c = g.lite if k % 2 else g.base
        g.line(8, 12 - k, 13 - k * 2, 3 + k * 2, c, 1)
        g.line(7, 12 - k, 2 + k * 2, 3 + k * 2, g.mid if k % 2 else g.base, 1)
        g.p(13 - k * 2, 3 + k * 2, WHITE)
    g.line(8, 13, 8, 4, g.dark, 1)
    g.p(8, 3, g.hot); g.p(7, 2, g.lite); g.p(9, 2, g.lite)


def s_cloak(g, p):
    for y in range(3, 14):
        w = 3 + (y - 3) // 2
        g.rect(8 - w, y, w * 2, 1, g.base if y < 10 else g.mid)
        g.p(8 - w, y, g.dark); g.p(7 + w, y, g.dark)
    g.rect(6, 2, 5, 3, g.mid)
    g.rect(7, 3, 3, 2, INK)
    g.rect(6, 2, 5, 1, g.lite)
    for x, y in ((5, 2), (11, 2), (4, 13), (12, 13)):
        g.p(x, y, INK)
    g.line(6, 5, 5, 13, g.dark, 1)
    g.line(10, 5, 11, 13, g.dark, 1)
    g.disc(8, 5, 1, g.lite); g.p(8, 5, g.hot)


def s_flame(g, p):
    big = p.get("big", 0)
    g.disc(8, 10, 4 + big, g.base)
    g.disc(8, 12, 3, g.mid)
    g.line(8, 2, 6, 6, g.lite, 2)
    g.line(6, 6, 9, 9, g.lite, 1)
    if p.get("twin"):
        g.line(11, 4, 12, 7, g.base, 1); g.p(12, 3, g.mid)
    g.p(9, 4, g.base); g.p(10, 6, g.base); g.p(5, 7, g.base)
    g.disc(8, 11, 2, g.hot)
    g.p(7, 10, WHITE)
    for x, y in ((4, 12), (12, 12), (8, 14)):
        g.p(x, y, INK)
    g.spark(13, 3, g.lite)


def s_snowflake(g, p):
    arms = p.get("arms", 6)
    dirs = [(0, -6), (5, 3), (-5, 3)] if arms == 6 else [(0, -6), (4, 4), (4, -4), (-4, 4), (-4, -4), (0, 6)]
    for dx, dy in dirs:
        g.line(8, 8, 8 + dx, 8 + dy, g.lite, 1)
        tx, ty = 8 + dx, 8 + dy
        g.line(tx, ty, tx + (1 if dx >= 0 else -1), ty - 1, g.base, 1)
        g.line(tx, ty, tx - 1 if dx >= 0 else tx + 1, ty - 1, g.base, 1)
        g.p(tx, ty, WHITE)
    g.disc(8, 8, 2, WHITE)
    g.disc(7, 7, 1, g.hot)
    if p.get("shards"):
        g.p(2, 3, g.lite); g.p(13, 12, g.lite)


def s_orb(g, p):
    g.disc(8, 8, 5, g.mid)
    g.disc(8, 8, 4, g.dark)
    g.disc(6, 6, 2, g.lite)
    g.p(6, 5, WHITE); g.p(10, 10, g.base)
    g.ring(8, 8, 5, INK)
    if p.get("ring"):
        g.line(3, 11, 13, 5, g.base, 1)
        g.p(3, 11, g.lite); g.p(13, 5, g.lite)
    if p.get("stars"):
        g.p(1, 4, g.hot); g.p(14, 11, g.hot)


def s_eye(g, p):
    g.disc(8, 8, 6, g.dark)
    g.disc(8, 8, 5, g.mid)
    g.ring(8, 8, 5, INK)
    g.ring(8, 8, 3, g.base)
    g.disc(8, 8, 2, g.hot)
    g.line(8, 6, 8, 10, INK, 1)
    g.p(7, 7, WHITE)
    for x, y in ((8, 1), (8, 14), (1, 8), (14, 8)):
        g.p(x, y, g.lite)
    if p.get("lashes"):
        for x, y in ((3, 3), (13, 3), (3, 13), (13, 13)):
            g.p(x, y, g.lite)


def s_bolt(g, p):
    pts = [(9, 1), (4, 8), (7, 8), (5, 14), (12, 6), (9, 6), (11, 1)]
    for i in range(len(pts) - 1):
        g.line(*pts[i], *pts[i + 1], g.lite, 2)
    g.line(9, 2, 6, 7, WHITE, 1)
    g.line(6, 12, 10, 7, g.base, 1)
    if p.get("fork"):
        g.line(5, 14, 3, 13, g.base, 1); g.line(12, 6, 14, 5, g.base, 1)
    g.spark(13, 2, g.lite)


def s_fan(g, p):
    cnt = p.get("count", 3)
    for k in range(cnt):
        t = k / max(1, cnt - 1) - 0.5
        dx = round(t * 10)
        ty = 2 + abs(k - (cnt - 1) / 2) * (0 if cnt < 5 else 1)
        g.line(8, 13, 8 + dx, ty + 1, STEEL_D, 1)
        g.p(8 + dx, ty, WHITE)
        if cnt <= 4:
            g.line(8, 13, 8 + dx // 2, ty + 3, STEEL, 1)
    g.disc(8, 13, 1, WOOD)
    g.p(8, 14, WOOD_D); g.p(7, 14, INK); g.p(9, 14, INK)


def s_poison(g, p):
    n = p.get("drops", 1)
    spots = [(8, 9)] + ([(12, 8)] if n > 1 else []) + ([(4, 10)] if n > 2 else [])
    for cx, cy in spots:
        g.disc(cx, cy, 3, g.base)
        g.disc(cx, cy + 2, 2, g.dark)
        g.ring(cx, cy, 3, INK)
        g.p(cx - 2, cy - 2, g.lite); g.p(cx - 1, cy - 1, WHITE)
    g.line(8, 3, 8, 5, g.lite, 1)
    g.p(9, 4, g.base); g.p(7, 2, g.base); g.p(9, 1, g.mid)


def s_bomb(g, p):
    g.disc(8, 10, 5, INK)
    g.disc(8, 10, 4, (58, 58, 70, 255))
    g.p(6, 8, (130, 130, 148, 255)); g.p(7, 8, (160, 160, 178, 255))
    g.line(10, 6, 11, 5, (90, 70, 50, 255), 1)
    g.line(11, 5, 13, 3, (150, 120, 80, 255), 1)
    g.disc(13, 2, 1, g.hot)
    g.p(14, 1, g.lite); g.p(12, 1, g.lite)
    if p.get("smoke"):
        g.p(3, 5, g.mid); g.p(2, 4, _c(g.mid, 1.3)); g.p(4, 3, g.mid)


def s_sun(g, p):
    g.disc(8, 8, 4, g.base)
    g.disc(8, 8, 3, g.lite)
    g.p(7, 7, WHITE)
    g.ring(8, 8, 4, INK)
    for k in range(8):
        a = k * math.pi / 4
        g.p(round(8 + 6 * math.cos(a)), round(8 + 6 * math.sin(a)), g.lite)
        g.p(round(8 + 5 * math.cos(a)), round(8 + 5 * math.sin(a)), g.base)
        if p.get("wave"):
            g.p(round(8 + 7 * math.cos(a)), round(8 + 7 * math.sin(a)), g.hot if k % 2 else g.base)


def s_fist(g, p):
    g.rect(4, 4, 8, 7, g.base)
    g.rect(4, 4, 8, 1, g.lite)
    g.rect(4, 10, 8, 1, g.dark)
    g.frame(4, 4, 8, 7, INK)
    for x in (6, 8, 10):
        g.line(x, 5, x, 8, g.mid, 1)
        g.p(x, 5, WHITE)
    g.rect(2, 6, 2, 4, g.mid)
    g.frame(2, 6, 2, 4, INK)
    if p.get("burst"):
        g.spark(13, 3, g.hot); g.spark(2, 2, g.lite)
    else:
        g.p(12, 5, g.hot)


def s_skull(g, p):
    g.disc(8, 7, 5, BONE)
    g.disc(8, 12, 3, BONE)
    g.p(8, 3, BONE)
    g.disc(6, 6, 2, INK); g.disc(10, 6, 2, INK)
    g.p(5, 5, g.dark); g.p(11, 5, g.dark)
    g.p(8, 9, INK); g.p(8, 10, INK)
    g.rect(6, 11, 5, 1, (176, 168, 148, 255))
    g.line(7, 11, 7, 12, INK, 1); g.line(9, 11, 9, 12, INK, 1)
    g.line(8, 12, 8, 14, INK, 1)
    if p.get("crown"):
        for x in (5, 8, 11):
            g.line(x, 1, x, 2, g.lite, 1)
        g.line(5, 3, 11, 3, g.base, 1)
    g.spark(4, 9, g.hot); g.spark(12, 9, g.hot)


def s_blood(g, p):
    for y in range(3, 14):
        w = 2 + (y - 3) // 3
        g.rect(8 - w // 2, y, w, 1, g.base)
    g.disc(8, 12, 2, g.base)
    g.p(7, 4, g.lite); g.p(7, 5, WHITE); g.p(6, 7, g.lite)
    g.p(9, 10, g.mid); g.p(8, 12, g.dark)
    g.p(6, 13, INK); g.p(10, 13, INK)
    if p.get("splashes"):
        g.p(2, 6, g.mid); g.p(3, 7, g.base); g.p(13, 9, g.mid); g.p(12, 10, g.base)


def s_star(g, p):
    pts = [(8, 1), (10, 6), (15, 6), (11, 9), (12, 14), (8, 11), (4, 14), (5, 9), (1, 6), (6, 6)]
    for i in range(len(pts)):
        g.line(8, 8, *pts[i], g.base, 1)
    for pt in pts:
        g.p(*pt, g.lite)
    g.disc(8, 8, 2, g.lite)
    g.disc(7, 7, 1, WHITE)
    if p.get("twinkle"):
        g.spark(12, 2, g.hot)


def s_chains(g, p):
    for yy in (3, 8, 13):
        for xx in (5, 10):
            cy = yy + (0 if xx == 5 else 1)
            g.ring(xx, cy, 2, g.base)
            g.ring(xx, cy, 1, g.dark)
            g.p(xx - 1, cy - 1, g.lite)
    g.line(6, 4, 9, 9, g.mid, 1)
    g.line(7, 3, 10, 8, g.mid, 1)
    if p.get("break"):
        g.p(8, 6, INK); g.p(9, 7, INK); g.spark(8, 6, g.hot)


def s_arrow(g, p):
    n = p.get("count", 1)
    for k in range(n):
        oy = k * 3 - (n - 1)
        g.line(3, 13 - oy, 11, 4 - (oy if oy < 0 else 0), g.mid, 1)
    g.line(12, 4, 8, 4, g.lite, 1); g.line(12, 4, 12, 8, g.lite, 1)
    g.line(3, 12, 5, 14, g.base, 1); g.line(4, 11, 6, 13, g.base, 1)
    g.p(13, 3, g.hot)


def s_hourglass(g, p):
    g.line(3, 2, 12, 2, WOOD, 1); g.line(3, 13, 12, 13, WOOD, 1)
    for x, y in ((3, 1), (12, 1), (3, 14), (12, 14)):
        g.p(x, y, WOOD_D)
    g.line(5, 3, 8, 8, g.lite, 1); g.line(11, 3, 8, 8, g.lite, 1)
    g.line(5, 12, 8, 8, g.lite, 1); g.line(11, 12, 8, 8, g.lite, 1)
    g.line(6, 3, 8, 6, WHITE, 1)
    g.line(6, 4, 10, 4, g.base, 1)
    g.rect(7, 11, 3, 1, g.base); g.rect(6, 12, 5, 1, g.base)
    g.p(8, 9, g.hot)
    if p.get("hold"):
        g.ring(8, 8, 7, g.mid)


def s_figure(g, p):
    """Stylised hero bust for self-buffs."""
    g.disc(8, 5, 2, BONE)                      # head
    g.rect(5, 7, 7, 6, g.base)                 # torso
    g.rect(5, 7, 7, 1, g.lite)
    g.line(6, 8, 6, 12, g.mid, 1); g.line(9, 8, 9, 12, g.mid, 1)
    g.frame(5, 7, 7, 6, INK); g.ring(8, 5, 2, INK)
    g.p(8, 3, g.hot)
    if p.get("aura"):
        g.ring(8, 9, 6, g.mid)
        g.p(2, 9, g.lite); g.p(14, 9, g.lite)


def s_meteor(g, p):
    g.disc(9, 9, 4, (110, 84, 70, 255))
    g.disc(8, 8, 3, (150, 118, 96, 255))
    g.p(7, 7, WHITE)
    g.ring(9, 9, 4, INK)
    g.line(3, 3, 6, 6, g.lite, 2)
    g.line(1, 1, 3, 3, g.base, 1)
    g.p(0, 0, g.hot)
    for x, y in ((2, 5), (5, 2)):
        g.p(x, y, g.mid)


def s_thorns(g, p):
    g.ring(8, 8, 4, g.base)
    g.disc(8, 8, 3, g.dark)
    g.disc(7, 7, 1, g.hot)
    for k in range(8):
        a = k * math.pi / 4
        g.line(8 + 4 * math.cos(a), 8 + 4 * math.sin(a),
               8 + 7 * math.cos(a), 8 + 7 * math.sin(a), g.mid, 1)
        g.p(round(8 + 7 * math.cos(a)), round(8 + 7 * math.sin(a)), g.lite)


def s_frenzy(g, p):
    """Screaming face."""
    g.disc(8, 8, 5, g.base)
    g.disc(8, 8, 5, g.base)
    g.ring(8, 8, 5, INK)
    g.disc(6, 7, 1, INK); g.disc(10, 7, 1, INK)
    g.p(5, 6, g.dark); g.p(11, 6, g.dark)
    g.rect(6, 10, 5, 3, INK)                    # open shout
    g.line(7, 10, 7, 12, WHITE, 1); g.line(9, 10, 9, 12, WHITE, 1)
    g.line(8, 2, 8, 4, g.lite, 1)
    g.spark(1, 3, g.hot); g.spark(15, 12, g.hot)


def s_hat(g, p):
    """Wizard hat: brim, bent cone, star pin."""
    g.rect(3, 10, 10, 2, g.base)                  # brim
    g.rect(3, 10, 10, 1, g.lite)
    g.frame(3, 10, 10, 2, INK)
    for i in range(7):                            # bent cone
        w = 7 - i
        g.rect(5 + i // 2, 9 - i, max(1, w), 1, g.mid if i % 2 else g.base)
    g.p(11, 2, g.base); g.p(12, 1, g.lite); g.p(11, 1, INK)
    g.p(7, 6, g.hot); g.p(8, 5, g.lite)           # star pin
    g.p(3, 12, g.dark); g.p(12, 12, g.dark)


def s_execution(g, p):
    """Axe falling onto a kneeling silhouette."""
    s_axe(g, {"spike": 1})
    g.line(13, 13, 15, 13, g.dark, 1)
    g.disc(14, 11, 1, INK)
    g.p(12, 12, INK)


SUBJECTS = {k[2:]: v for k, v in list(globals().items()) if k.startswith("s_")}


# ------------------------------------------------------------------- fx
def fx_sparks(g):
    g.spark(1, 2, g.lite); g.spark(14, 12, g.lite)


def fx_runes(g):
    g.p(2, 13, g.hot); g.p(13, 2, g.hot); g.p(14, 13, g.mid)


def fx_speed(g):
    g.line(0, 4, 3, 4, g.mid, 1); g.line(13, 11, 15, 11, g.mid, 1)


def fx_drips(g):
    g.p(3, 12, g.mid); g.p(3, 13, _c(g.mid, 0.7)); g.p(12, 4, g.mid)


FX = dict(sparks=fx_sparks, runes=fx_runes, speed=fx_speed, drips=fx_drips)


def _edge_dark(im):
    """Seat the icon into its frame: darken the outermost pixels a touch."""
    px = im.load()
    for i in range(16):
        for x, y in ((i, 0), (i, 15), (0, i), (15, i)):
            r, gg, b, a = px[x, y]
            if a > 0:
                px[x, y] = (int(r * 0.6), int(gg * 0.6), int(b * 0.6), a)
    return im


def draw(spec, accent) -> Image.Image:
    g = G(accent)
    BGS[spec.get("bg", "wash")](g)
    subj, p = spec["s"] if isinstance(spec["s"], tuple) else (spec["s"], {})
    SUBJECTS[subj](g, p)
    for f in spec.get("fx", []):
        FX[f](g)
    im = icon_detail.detail(g.im)  # the same pass the item icons get
    return _edge_dark(im)


if __name__ == "__main__":
    out, subj, hexcol = sys.argv[1], sys.argv[2], sys.argv[3]
    accent = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    draw({"bg": "wash", "s": subj}, accent).save(out)
    print("wrote", out)
