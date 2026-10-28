#!/usr/bin/env python3
"""Weapon icons redrawn at 32x32 (were 16x16): real little weapons.

Each weapon type has its own painter (sword, axe, spear, dagger, bow, staff,
mace, crossbow, wand) that draws it along the icon's axis (up-right, through
the grip pixel the item's .tres names - doubled), with materials lit from the
top left: steel with a lit and a shaded half, a fuller and a honed edge;
leather-wrapped grips; wood with grain; gold fittings; gems with a glint;
magic (the item's damage type) as a glowing core. Per-item variants (saber
curve, kris waves, trident prongs, morning-star spikes, the bell of the
bell hammer...) keep every weapon recognisable; its colours are taken from
the old 16x16 icon (kept in tools/weapon_src16/).

The game draws the icons at the old world size (HeroVisual / ItemPickup /
Fx scale by 16 / width), so the hand and the floor show twice the detail.
Run from tools/:  python3 gen_weapon_hd.py
"""
from __future__ import annotations

import colorsys
import glob
import math
import os
import re
import shutil
from collections import Counter

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "weapon_src16")
S = 32
INK = (20, 13, 18, 255)

STEEL = [(56, 62, 80), (104, 112, 132), (160, 168, 188), (212, 218, 232), (252, 252, 255)]
GOLD = [(98, 60, 22), (164, 110, 36), (218, 166, 56), (250, 214, 104), (255, 248, 206)]
WOOD = [(58, 36, 22), (94, 60, 34), (130, 86, 50), (166, 116, 70), (200, 154, 100)]
LEATHER = [(40, 24, 20), (70, 42, 32), (102, 62, 44), (136, 88, 62), (170, 120, 90)]
BONE = [(112, 98, 80), (160, 146, 120), (206, 196, 170), (236, 230, 210), (255, 252, 240)]
IRON = [(36, 34, 42), (62, 60, 70), (90, 88, 100), (128, 126, 140), (176, 174, 190)]
MAGIC = {0: None, 1: (255, 120, 44), 2: (120, 210, 255), 3: (130, 230, 80), 4: (190, 110, 255)}


def ramp(c):
    """Five tones of a colour (deep .. white-hot)."""
    c = c[:3]
    return [tuple(int(v * 0.36) for v in c), tuple(int(v * 0.62) for v in c), c,
            tuple(min(255, int(v + (255 - v) * 0.35)) for v in c), tuple(min(255, int(v + (255 - v) * 0.75)) for v in c)]


# ------------------------------------------------------------- the canvas
class W:
    def __init__(self, grip, axis_deg=-45.0):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.o = grip
        a = math.radians(axis_deg)
        self.u = (math.cos(a), math.sin(a))  # along the weapon (towards the tip)
        self.n = (-self.u[1], self.u[0])  # across: positive = down-right (shadow side)

    def P(self, t, s=0.0):
        return (self.o[0] + self.u[0] * t + self.n[0] * s, self.o[1] + self.u[1] * t + self.n[1] * s)

    def reach(self, margin=1.5):
        """How far along the axis the canvas goes from the grip."""
        t = 0.0
        while True:
            x, y = self.P(t + 0.5)
            if not (margin <= x <= S - 1 - margin and margin <= y <= S - 1 - margin):
                return t
            t += 0.5

    def px(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < S and 0 <= y < S:
            self.im.putpixel((x, y), tuple(c[:3]) + (255,) if len(c) == 3 else c)

    def poly(self, pts, c):
        self.d.polygon([(round(x), round(y)) for x, y in pts], fill=tuple(c[:3]) + (255,))

    def line(self, pts, c, w=1):
        self.d.line([(round(x), round(y)) for x, y in pts], fill=tuple(c[:3]) + (255,), width=w)

    def lpoly(self, local, c):
        self.poly([self.P(t, s) for t, s in local], c)

    def lline(self, local, c, w=1):
        self.line([self.P(t, s) for t, s in local], c, w)

    def halves(self, t0, t1, w0, w1, mat, tip=0.0, curve=0.0):
        """A tapered two-tone bar (blade / shaft) from t0 to t1: lit half on
        the upper-left side, shaded half below, bright lit edge."""
        def s_at(t):
            return curve * ((t - t0) / max(1.0, t1 - t0)) ** 2 * 4.0
        steps = max(2, int(t1 - t0))
        top, bot = [], []
        for k in range(steps + 1):
            t = t0 + (t1 - t0) * k / steps
            w = w0 + (w1 - w0) * k / steps
            if tip and t > t1 - tip:
                w *= max(0.0, (t1 - t) / tip)
            c = s_at(t)
            top.append((t, c - w))
            bot.append((t, c + w))
        mid = [(t, s_at(t)) for t, _ in top]
        self.lpoly(top + mid[::-1], mat[3])
        self.lpoly(mid + bot[::-1], mat[1])
        self.lline(mid, mat[2])
        self.lline(top, mat[4])
        self.lline(bot, mat[0])
        return mid

    def vpoly(self, local, mat, bias=0.0):
        """A shape filled with volume light: tones by position towards the
        top-left light, a lit rim on the top-left edges, a dark one below."""
        pts = [self.P(t, s) for t, s in local]
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).polygon([(round(x), round(y)) for x, y in pts], fill=255)
        mp = m.load()
        cells = [(x, y) for y in range(S) for x in range(S) if mp[x, y]]
        if not cells:
            return
        cx = sum(c[0] for c in cells) / len(cells)
        cy = sum(c[1] for c in cells) / len(cells)
        ext = max(2.0, max(abs((x - cx) + (y - cy)) for x, y in cells))

        def inside(x, y):
            return 0 <= x < S and 0 <= y < S and mp[x, y]
        for x, y in cells:
            l = -((x - cx) + (y - cy)) / ext + bias + (0.08 if (x + y) % 2 else -0.08)
            i = 3 if l > 0.45 else 2 if l > -0.2 else 1
            if not inside(x - 1, y) or not inside(x, y - 1):
                i = min(4, i + 1)
            elif not inside(x + 1, y) or not inside(x, y + 1):
                i = max(0, i - 1)
            self.px(x, y, mat[i])

    def disc(self, cx, cy, r, mat):
        """A ball lit from the top left (four tones)."""
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy)
                if d > r + 0.3:
                    continue
                l = (-dx * 0.6 - dy * 0.7) / max(r, 0.5) + 0.25 * (1 - d / max(r, 0.5))
                i = 4 if l > 0.95 else 3 if l > 0.45 else 2 if l > -0.1 else 1 if l > -0.55 else 0
                self.px(x, y, mat[i])

    def glowdot(self, cx, cy, r, col, strength=1.0):
        g = self.glow.load()
        for y in range(max(0, int(cy - r)), min(S, int(cy + r + 1))):
            for x in range(max(0, int(cx - r)), min(S, int(cx + r + 1))):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    a = int(110 * strength * (1 - d / r) ** 1.4)
                    if a > g[x, y][3]:
                        g[x, y] = (col[0], col[1], col[2], a)

    def spark(self, x, y, col):
        self.px(x, y, (255, 255, 255))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            self.px(x + dx, y + dy, col)

    def grip(self, t0, t1, mat=LEATHER, w=1.6):
        """A wrapped grip: alternating bands with a lit edge."""
        mat = mat or LEATHER
        self.halves(t0, t1, w, w, mat)
        k = t0
        while k < t1:
            self.lline([(k, -w), (k + 0.8, w)], mat[0])
            k += 2.0

    def pommel(self, t, mat, gem=None):
        x, y = self.P(t)
        self.disc(x, y, 2.0, mat)
        if gem:
            self.px(x, y, gem[3])
            self.px(x - 1, y - 1, gem[4])

    def finish(self):
        """Outline outside the shape (shadow side tinted), then the glow."""
        src = self.im.load()
        out = self.im.copy()
        o = out.load()
        for y in range(S):
            for x in range(S):
                if src[x, y][3]:
                    continue
                for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and src[nx, ny][3]:
                        c = src[nx, ny]
                        o[x, y] = (max(14, c[0] // 4), max(9, c[1] // 4), max(16, c[2] // 4), 255) if dx < 0 or dy < 0 else INK
                        break
        glow = self.glow.copy()
        gp = glow.load()
        for y in range(S):
            for x in range(S):
                if o[x, y][3]:
                    gp[x, y] = (0, 0, 0, 0)  # the glow only around, not over the weapon
        glow.alpha_composite(out)
        return glow


# ------------------------------------------------------------- colours
def palette(path, dtype):
    """metal / handle / accent colours from the old 16x16 icon."""
    im = Image.open(path).convert("RGBA")
    cnt = Counter(c for c in im.getdata() if c[3] > 0)
    metal = handle = accent = None
    for c, _n in cnt.most_common():
        h, s, v = colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)
        if v < 0.2:
            continue
        if metal is None and s < 0.25 and v > 0.5:
            metal = c
        elif handle is None and 0.02 < h < 0.13 and 0.3 < s and v < 0.72:
            handle = c
        elif accent is None and s > 0.5 and v > 0.55 and not (0.02 < h < 0.13 and v < 0.75):
            accent = c
    mg = MAGIC.get(dtype)
    if accent is None and mg:
        accent = mg
    return metal, handle, accent


def metal_ramp(metal):
    if metal is None:
        return STEEL
    # keep the icon's tint, but on a full steel range
    r = ramp(metal)
    return [tuple(int(a * 0.5 + b * 0.5) for a, b in zip(r[i], STEEL[i])) for i in range(5)]


# ------------------------------------------------------------- painters
def sword(w, wid, M, H, A, rarity, dtype):
    L = w.reach()
    blade = M
    if wid == "sun_blade":
        blade = GOLD
    if wid == "heart_shard":
        blade = ramp(A or (120, 220, 255))
    if wid == "rusty_sword":
        blade = [tuple(int(v * 0.95) for v in c) for c in STEEL]
    guard_w = 5.5 if rarity < 2 else 6.5
    w.grip(-5, 2.5, H, 2.0)
    w.pommel(-6, GOLD if rarity >= 1 else IRON, ramp(A) if A and rarity >= 2 else None)
    gm = GOLD if rarity >= 1 else IRON
    w.lpoly([(2.5, -guard_w), (5, -guard_w - 1), (5, guard_w + 1), (2.5, guard_w)], gm[2])
    w.lline([(2.5, -guard_w), (2.5, guard_w)], gm[4])
    w.lline([(4.5, -guard_w), (4.5, guard_w)], gm[0])
    if rarity >= 2 and A:
        x, y = w.P(3.5)
        w.disc(x, y, 1.3, ramp(A))
    curve = 1.2 if wid in ("steel_saber",) else 0.0
    width = 3.0 if wid not in ("runeblade", "eclipse_blade") else 3.4
    mid = w.halves(5, L, width, width * 0.85, blade, tip=5.0, curve=curve)
    if wid != "heart_shard":
        w.lline([(7, 0), (L - 6, 0)], blade[0])  # fuller
    if wid == "rusty_sword":
        for t, s in ((9, -1), (13, 1), (16, 0), (19, -1)):
            x, y = w.P(t, s)
            w.px(x, y, (130, 74, 40))
    if A and (rarity >= 2 or dtype):
        for t in range(9, int(L) - 5, 3):  # runes / magic along the fuller
            x, y = w.P(t, 0)
            w.px(x, y, ramp(A)[4] if t % 2 else ramp(A)[3])
            w.glowdot(x, y, 3, A, 0.8)
    x, y = w.P(L - 3, -1)
    w.spark(x, y, blade[3])


def dagger(w, wid, M, H, A, rarity, dtype):
    L = min(w.reach(), 17)
    if wid == "venom_fang":
        w.grip(-4, 2, LEATHER)
        mid = w.halves(3, L, 2.2, 1.0, BONE, tip=5.0, curve=1.6)
        for t in (8, 12):
            x, y = w.P(t, 2)
            w.px(x, y, ramp(A or (130, 230, 80))[3])
            w.glowdot(x, y, 3, A or (130, 230, 80), 0.8)
        return
    w.grip(-4, 2, H if wid != "shadow_dagger" else [(30, 20, 40), (50, 36, 66), (72, 54, 96), (100, 80, 130), (140, 120, 170)])
    w.pommel(-5, GOLD if rarity >= 1 else IRON)
    gm = GOLD if rarity >= 1 else IRON
    w.lpoly([(2, -3.5), (3.5, -3.5), (3.5, 3.5), (2, 3.5)], gm[2])
    w.lline([(2, -3.5), (2, 3.5)], gm[4])
    blade = M
    if wid == "mirror_dagger":
        blade = [(120, 130, 160), (180, 190, 214), (220, 228, 244), (244, 248, 255), (255, 255, 255)]
    if wid == "shadow_dagger":
        blade = [(40, 30, 60), (70, 56, 100), (110, 90, 150), (160, 140, 200), (220, 210, 255)]
    if wid == "stiletto":
        w.halves(4, L, 1.4, 0.8, blade, tip=6.0)
    elif wid == "kris":
        top, bot, mid = [], [], []
        for k in range(int(L - 4) * 2 + 1):
            t = 4 + k * 0.5
            wv = 2.0 * max(0.0, min(1.0, (L - t) / 4.0))
            c = math.sin((t - 4) * 1.1) * 1.0
            top.append((t, c - wv))
            bot.append((t, c + wv))
            mid.append((t, c))
        w.lpoly(top + mid[::-1], blade[3])
        w.lpoly(mid + bot[::-1], blade[1])
        w.lline(top, blade[4])
        w.lline(bot, blade[0])
    else:
        w.halves(4, L, 2.8, 2.0, blade, tip=5.0)
    if A and (rarity >= 2 or dtype or wid == "mirror_dagger"):
        x, y = w.P(L * 0.55, 0)
        w.px(x, y, ramp(A)[4])
        w.glowdot(x, y, 4, A, 0.9)
    x, y = w.P(L - 3, -1)
    w.spark(x, y, blade[3])


def axe(w, wid, M, H, A, rarity, dtype):
    L = w.reach() - 1
    w.halves(-6, L - 1, 1.8, 1.8, H or WOOD)  # haft
    for t in range(-4, int(L) - 3, 4):
        w.lline([(t, -1), (t + 1.5, -1)], (H or WOOD)[1])  # grain
    w.grip(-6, 0, LEATHER)
    head_t = L - 7
    big = 1.3 if wid in ("executioner_axe", "bloodthirster") else 0.8 if wid == "hatchet" else 1.05
    blade = M
    if wid == "frost_axe":
        blade = ramp((150, 220, 250))
    if wid == "bloodthirster":
        blade = [(70, 20, 26), (120, 30, 40), (170, 50, 60), (210, 100, 100), (250, 190, 190)]
    # the head: a crescent on the shadow side, a cheek around the haft
    b = 8.5 * big
    pts = [(head_t - 3 * big, 1.5), (head_t - 5 * big, b * 0.7), (head_t - 3 * big, b), (head_t + 1, b + 0.5),
           (head_t + 4 * big, b), (head_t + 5 * big, b * 0.6), (head_t + 3 * big, 1.5)]
    w.vpoly(pts, blade)
    # the bevel: a bright honed strip along the cutting edge
    bev = [(head_t - 4 * big, b * 0.75), (head_t - 3 * big, b - 0.5), (head_t + 1, b), (head_t + 4 * big, b - 0.5),
           (head_t + 4.5 * big, b * 0.68), (head_t + 3 * big, b * 0.62), (head_t + 1, b * 0.72), (head_t - 3 * big, b * 0.66)]
    w.vpoly(bev, blade, bias=0.5)
    w.lline([(head_t - 3 * big, b), (head_t + 1, b + 0.5), (head_t + 4 * big, b)], blade[4])  # honed edge
    w.lline([(head_t - 3 * big, b * 0.62), (head_t + 3 * big, b * 0.6)], blade[0])  # where the bevel starts
    w.lpoly([(head_t - 2, -2), (head_t - 2, 2.5), (head_t + 2, 2.5), (head_t + 2, -2)], IRON[2])  # the eye collar
    w.lline([(head_t - 2, -2), (head_t + 2, -2)], IRON[4])
    if wid == "bearded_axe":
        w.lpoly([(head_t - 3, b), (head_t - 7, b + 1), (head_t - 4, b * 0.6)], blade[2])
    if wid in ("war_axe", "executioner_axe"):  # second bit / back spike
        w.vpoly([(head_t - 2, -1.5), (head_t - 3 * big, -b * 0.8), (head_t + 3 * big, -b * 0.8), (head_t + 2, -1.5)],
                blade)
        w.lline([(head_t - 3 * big, -b * 0.8), (head_t + 3 * big, -b * 0.8)], blade[4])
    elif wid != "hatchet":
        w.lpoly([(head_t - 1, -1.5), (head_t, -4.5), (head_t + 1, -1.5)], blade[1])
    if wid == "bloodthirster":
        for t in range(int(head_t - 3), int(head_t + 4), 2):
            x, y = w.P(t, b + 1)
            w.px(x, y, (200, 30, 40))
    for t in (head_t - 1, head_t + 1):
        x, y = w.P(t, 0)
        w.px(x, y, GOLD[3] if rarity >= 1 else IRON[4])  # rivets
    if A and (rarity >= 2 or dtype):
        x, y = w.P(head_t, b * 0.45)
        w.disc(x, y, 1.4, ramp(A))
        w.glowdot(x, y, 5, A, 0.9)
    x, y = w.P(head_t + 3 * big, b - 0.5)
    w.spark(x, y, blade[3])


def spear(w, wid, M, H, A, rarity, dtype):
    L = w.reach()
    shaft = H or WOOD
    head = 8.0 if wid != "glaive" else 11.0
    w.halves(-9, L - head + 1, 1.5, 1.5, shaft)
    w.grip(-2, 3, LEATHER, 1.3)
    blade = M if wid != "dragon_lance" else GOLD
    t0 = L - head
    if wid == "wooden_spear":
        w.lpoly([(t0, -1.4), (L, 0), (t0, 1.4)], WOOD[3])
        w.lline([(t0, -1.4), (L, 0)], WOOD[4])
        w.lline([(t0 + 1, 0.6), (L - 2, 0.2)], WOOD[1])
        return
    w.lpoly([(t0 - 1, -1.6), (t0 + 1, -1.6), (t0 + 1, 1.6), (t0 - 1, 1.6)], (GOLD if rarity >= 1 else IRON)[2])  # socket
    if wid == "trident":
        for s in (-4, 0, 4):
            w.halves(t0 + 1, L - (0 if s == 0 else 2), 0.9, 0.7, blade, tip=2.5)
        w.lpoly([(t0 + 1, -4.5), (t0 + 2.5, -4.5), (t0 + 2.5, 4.5), (t0 + 1, 4.5)], blade[2])
        w.lline([(t0 + 1, -4.5), (t0 + 1, 4.5)], blade[4])
    elif wid == "glaive":
        w.halves(t0 + 1, L, 1.6, 1.0, blade, tip=3.0, curve=-1.2)
        w.lpoly([(t0 + 2, 1.5), (t0 + 6, 3.5), (t0 + 4, 1.5)], blade[1])  # back hook
    else:
        # a leaf blade
        pts_top, pts_bot = [], []
        for k in range(int(head * 2)):
            t = t0 + 1 + k * 0.5
            wv = 3.2 * math.sin(min(math.pi, (t - t0 - 1) / (head - 1) * math.pi) ** 0.9) + 0.4
            pts_top.append((t, -wv))
            pts_bot.append((t, wv))
        pts_top.append((L, 0))
        mid = [(t, 0) for t, _ in pts_top]
        w.lpoly(pts_top + mid[::-1], blade[3])
        w.lpoly(mid + pts_bot[::-1], blade[1])
        w.lline(pts_top, blade[4])
        w.lline(mid[:-2], blade[0])
    if wid == "dragon_lance" or (A and (rarity >= 2 or dtype)):
        col = A or (255, 120, 44)
        x, y = w.P(t0 - 2, 0)
        w.disc(x, y, 1.3, ramp(col))
        w.glowdot(x, y, 5, col, 0.9)
        if wid == "dragon_lance":
            for k in range(3):
                x, y = w.P(t0 - 1 - k * 2, -2 - k % 2)
                w.px(x, y, ramp(col)[3])  # ribbon of flame
    x, y = w.P(L - 2, -0.5)
    w.spark(x, y, blade[3])


def mace(w, wid, M, H, A, rarity, dtype):
    L = w.reach() - 1
    handle = H or WOOD
    head = M
    if wid == "club":
        w.halves(-6, L - 1, 1.6, 4.4, WOOD)
        for t, s in ((6, -1), (10, 1), (14, -2), (L - 4, 0)):
            x, y = w.P(t, s)
            w.px(x, y, WOOD[0])  # knots
        w.grip(-6, -1, LEATHER, 1.4)
        return
    w.halves(-6, L - 6, 1.6, 1.6, handle if wid not in ("iron_mace", "flanged_mace") else IRON)
    w.grip(-6, 0, LEATHER, 1.4)
    x, y = w.P(L - 5.5)
    if wid == "bell_hammer":
        bronze = [(90, 56, 26), (140, 96, 44), (190, 140, 70), (226, 186, 110), (250, 230, 180)]
        w.vpoly([(L - 9, -3), (L - 1, -4.5), (L - 1, 4.5), (L - 9, 3)], bronze)
        w.lline([(L - 9, -3), (L - 1, -4.5)], bronze[4])
        w.lline([(L - 1, -4.5), (L - 1, 4.5)], bronze[0])
        w.lline([(L - 3, -4), (L - 3, 4)], bronze[3])
        bx, by = w.P(L + 0.5, 0)
        w.disc(bx, by, 1.2, bronze)
        w.glowdot(x, y, 7, (160, 255, 220), 0.6)
        return
    if wid == "holy_hammer":
        w.vpoly([(L - 9, -5), (L - 2, -5), (L - 2, 5), (L - 9, 5)], STEEL)
        w.lline([(L - 9, -5), (L - 2, -5)], STEEL[4])
        w.lline([(L - 9, 5), (L - 2, 5)], STEEL[0])
        for s in (-3, 3):
            w.lline([(L - 9, s), (L - 2, s)], GOLD[2])
        cx_, cy_ = w.P(L - 5.5, 0)
        w.px(cx_, cy_, GOLD[4])
        w.glowdot(cx_, cy_, 7, (255, 220, 120), 0.9)
        return
    r = 5.0 if wid != "morning_star" else 4.2
    w.disc(x, y, r, head)
    if wid == "flanged_mace":
        for k in range(6):
            a = k * math.pi / 3
            fx, fy = x + math.cos(a) * (r + 0.5), y + math.sin(a) * (r + 0.5)
            w.line([(x + math.cos(a) * 1.5, y + math.sin(a) * 1.5), (fx, fy)], head[3 if k < 3 else 1], 2)
    elif wid == "morning_star":
        for k in range(8):
            a = k * math.pi / 4 + 0.2
            w.line([(x + math.cos(a) * r, y + math.sin(a) * r), (x + math.cos(a) * (r + 2.6), y + math.sin(a) * (r + 2.6))],
                   STEEL[4 if k in (4, 5, 6) else 2])
    else:  # iron mace: a band and studs
        w.line([(x - r + 1, y + 1), (x + r - 1, y - 1)], head[0])
        for k in range(5):
            a = k * math.pi / 2.5 + 0.3
            w.px(x + math.cos(a) * (r - 1.5), y + math.sin(a) * (r - 1.5), IRON[4] if k < 2 else IRON[1])
    if A and (rarity >= 2 or dtype):
        w.px(x, y, ramp(A)[4])
        w.glowdot(x, y, 6, A, 0.8)


def staff(w, wid, M, H, A, rarity, dtype):
    L = w.reach() - 1
    wood = H or WOOD
    if wid == "thorn_staff":
        wood = [(40, 50, 26), (64, 82, 40), (92, 116, 56), (126, 150, 80), (170, 196, 120)]
    if wid in ("frost_staff", "frost_heart"):
        wood = [(50, 66, 90), (80, 100, 130), (120, 146, 176), (170, 196, 220), (220, 236, 250)]
    # gnarled shaft: a slight wave
    w.halves(-9, L - 7, 1.6, 1.9, wood, curve=0.4)
    w.grip(-2, 3, LEATHER, 1.5)
    col = A or MAGIC.get(dtype) or (190, 110, 255)
    x, y = w.P(L - 4)
    if wid == "oldric_spade":
        w.vpoly([(L - 9, -3.5), (L - 1, -3), (L, 0), (L - 1, 3), (L - 9, 3.5)], IRON)
        w.lline([(L - 9, -3.5), (L - 1, -3)], IRON[4])
        w.lline([(L - 1, 3), (L - 9, 3.5)], IRON[0])
        w.px(*w.P(L - 4, 1), (90, 70, 50))
        w.glowdot(*w.P(L - 4, 1), 4, (120, 255, 150), 0.7)
        return
    if wid == "thorn_staff":
        for t in range(-6, int(L) - 6, 3):
            sx, sy = w.P(t, -1.6 if t % 2 else 1.6)
            w.px(sx, sy, (180, 200, 120))
        w.disc(x, y, 3.0, ramp((110, 200, 70)))
        w.glowdot(x, y, 7, (140, 240, 90), 0.8)
        return
    # prongs holding the focus
    for s in (-3.2, 3.2):
        w.lline([(L - 8, s * 0.4), (L - 6, s), (L - 2.5, s * 0.8)], wood[3 if s < 0 else 1], 1)
    if wid in ("frost_staff", "frost_heart"):
        cr = ramp((150, 220, 255))
        w.lpoly([(L - 7, 0), (L - 4, -2.5), (L, 0), (L - 4, 2.5)], cr[3])
        w.lline([(L - 7, 0), (L - 4, -2.5), (L, 0)], cr[4])
        w.lline([(L - 4, 2.5), (L, 0)], cr[1])
        if wid == "frost_heart":
            w.disc(x, y, 1.5, ramp((255, 120, 150)))
        w.glowdot(x, y, 8, (150, 220, 255), 0.9)
    elif wid == "ilara_spark":
        w.lline([(L - 7, 0), (L - 4, -3), (L - 1, -2), (L - 1, 1)], wood[3], 1)  # curled head
        w.disc(*w.P(L - 3, -0.5), 1.8, ramp((255, 170, 60)))
        w.glowdot(*w.P(L - 3, -0.5), 8, (255, 150, 60), 1.0)
    else:
        w.disc(x, y, 3.6, ramp(col))
        if wid == "arcane_staff":
            w.d.ellipse((round(x - 5), round(y - 2), round(x + 5), round(y + 2)), outline=tuple(ramp(col)[3]) + (255,))
        if wid == "ember_staff":
            for k in range(3):
                w.px(x - 1 + k, y - 4 - k % 2, ramp((255, 160, 60))[3])
        w.glowdot(x, y, 8, col, 0.9)
    if rarity >= 2:
        for t in (2, 6):
            gx, gy = w.P(-t * 0 + L - 10 - t, 0)
            w.px(gx, gy, GOLD[3])


def wand(w, wid, M, H, A, rarity, dtype):
    L = min(w.reach(), 19)
    wood = H or WOOD
    w.halves(-4, L - 4, 1.4, 1.7, wood)
    w.grip(-4, 2, LEATHER, 1.3)
    w.lpoly([(L - 5, -1.8), (L - 4, -1.8), (L - 4, 1.8), (L - 5, 1.8)], GOLD[2])
    col = A or MAGIC.get(dtype) or (190, 110, 255)
    x, y = w.P(L - 2)
    w.disc(x, y, 2.8, ramp(col))
    w.glowdot(x, y, 7, col, 1.0)
    if wid == "storm_wand":
        w.line([(x + 2, y - 3), (x + 1, y - 1), (x + 3, y)], (255, 255, 200))
    elif wid == "fire_wand":
        w.px(x, y - 3, ramp(col)[3])
        w.px(x + 1, y - 4, ramp(col)[4])


def bow(w, wid, M, H, A, rarity, dtype):
    wood = H or WOOD
    if wid == "elven_bow":
        wood = [(70, 80, 50), (110, 124, 76), (160, 172, 110), (204, 214, 150), (236, 244, 200)]
    cx, cy = 16, 16
    h = 13 if wid != "longbow" else 15
    bulge = 6 if wid != "short_bow" else 5
    pts = []
    for k in range(25):
        t = -1 + 2 * k / 24
        y = cy + t * h
        x = cx - 2 + bulge * (1 - t * t) - (2 if wid == "elven_bow" and abs(t) > 0.8 else 0) * (abs(t) - 0.8) * 10
        pts.append((x, y))
    w.line(pts, wood[1], 3)
    w.line([(x - 1, y) for x, y in pts], wood[3])
    w.line([(x + 1, y) for x, y in pts], wood[0])
    w.line([pts[0], (cx - 6, cy), pts[-1]], (230, 226, 210))  # drawn string
    w.d.rectangle((cx + bulge - 4, cy - 2, cx + bulge - 1, cy + 2), fill=tuple(LEATHER[2]) + (255,))  # grip
    # the arrow, nocked
    w.line([(cx - 7, cy), (cx + 12, cy)], WOOD[3])
    w.poly([(cx + 15, cy), (cx + 11, cy - 2), (cx + 11, cy + 2)], STEEL[3])
    w.px(cx + 14, cy, STEEL[4])
    col = A or (220, 60, 60)
    w.poly([(cx - 7, cy), (cx - 10, cy - 2), (cx - 5, cy)], col)
    w.poly([(cx - 7, cy), (cx - 10, cy + 2), (cx - 5, cy)], ramp(col)[1])
    for y in (pts[0][1], pts[-1][1]):
        w.px(pts[0][0], y, GOLD[3] if rarity >= 1 else wood[4])  # nocks
    if rarity >= 2 and A:
        w.glowdot(cx + 13, cy, 4, A, 0.8)


def crossbow(w, wid, M, H, A, rarity, dtype):
    wood = H or WOOD
    cy = 17
    w.d.polygon([(3, cy + 1), (24, cy - 1), (24, cy + 2), (8, cy + 4), (4, cy + 7), (2, cy + 6)], fill=tuple(wood[2]) + (255,))  # stock
    w.line([(3, cy + 1), (24, cy - 1)], wood[4])
    w.line([(8, cy + 4), (24, cy + 2)], wood[0])
    w.d.rectangle((9, cy + 3, 11, cy + 5), fill=tuple(IRON[2]) + (255,))  # trigger
    prod = STEEL if wid == "heavy_crossbow" else wood
    span = 11 if wid == "heavy_crossbow" else 9
    pts = [(22 + 3 * (1 - (k / 10 - 1) ** 2), cy + (k - 10) / 10 * span) for k in range(21)]
    w.line(pts, prod[1], 3)
    w.line([(x - 1, y) for x, y in pts], prod[3])
    w.line([pts[0], (14, cy), pts[-1]], (226, 222, 206))  # string
    w.line([(14, cy - 1), (29, cy - 1)], STEEL[3])  # the bolt
    w.poly([(30, cy - 1), (27, cy - 3), (27, cy + 1)], STEEL[4])
    if wid == "repeater":
        w.d.rectangle((13, cy - 7, 20, cy - 2), fill=tuple(wood[2]) + (255,))  # magazine
        w.line([(13, cy - 7), (20, cy - 7)], wood[4])
        for x in (15, 18):
            w.line([(x, cy - 6), (x, cy - 3)], STEEL[2])
    for x, y in ((22, cy - 1), (6, cy + 3)):
        w.px(x, y, GOLD[3] if rarity >= 1 else IRON[4])


PAINTERS = [sword, axe, spear, dagger, bow, staff, mace, crossbow, wand]


# ------------------------------------------------------------- driver
def weapons():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "items", "equipment", "*.tres"))):
        s = open(f, encoding="utf-8").read()
        if "WeaponItemData" not in s:
            continue
        m = re.search(r'path="res://(assets/sprites/items/[^"]+\.png)"', s)
        wid = re.search(r'^id = &"([^"]+)"', s, re.M).group(1)
        wt = int(re.search(r"^weapon_type = (\d+)", s, re.M).group(1))
        rar = int(re.search(r"^rarity = (\d+)", s, re.M).group(1))
        dt = re.search(r"^damage_type = (\d+)", s, re.M)
        gp = re.search(r"^grip_pixel = Vector2\(([\d.]+), ([\d.]+)\)", s, re.M)
        ang = re.search(r"^held_angle = (-?[\d.]+)", s, re.M)
        out.append(dict(id=wid, icon=os.path.join(ROOT, m.group(1)), type=wt, rarity=rar, dtype=int(dt.group(1)) if dt else 0,
                        grip=(float(gp.group(1)) * 2, float(gp.group(2)) * 2) if gp else (6.0, 24.0),
                        angle=float(ang.group(1)) if ang else -45.0))
    return out


def draw(wpn, src_path):
    metal, handle, accent = palette(src_path, wpn["dtype"])
    M = metal_ramp(metal)
    H = ramp(handle) if handle else None
    w = W(wpn["grip"], wpn["angle"] if wpn["type"] not in (4, 7) else -45.0)
    PAINTERS[wpn["type"]](w, wpn["id"], M, H, accent, wpn["rarity"], wpn["dtype"])
    return w.finish()


def main():
    os.makedirs(SRC, exist_ok=True)
    n = 0
    for wpn in weapons():
        name = os.path.basename(wpn["icon"])
        keep = os.path.join(SRC, name)
        if not os.path.exists(keep):
            if Image.open(wpn["icon"]).size != (16, 16):
                print("skip (no 16px source):", name)
                continue
            shutil.copy(wpn["icon"], keep)
        draw(wpn, keep).save(wpn["icon"])
        n += 1
    print("weapon icons redrawn at 32x32:", n)


if __name__ == "__main__":
    main()
