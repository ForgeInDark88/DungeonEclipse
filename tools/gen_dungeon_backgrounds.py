#!/usr/bin/env python3
"""Backgrounds of the dungeon biomes, in the style of the new surface:
depth by aerial perspective (the far layer sinks into the biome's haze),
volume lit from the top left, saturated colour, light sources that glow.

Per biome (BiomeData.parallax_far / _mid / _near keep their files):
  <biome>_far.png        the haze of the cave and its distant formations
  <biome>_mid.png        the biome's own architecture or nature, lit
  <biome>_near.png       framing details close to the eye, darker
  <biome>_<layer>_glow.png  white where the layer glows (candles, fungus,
                         lava, crystals, runes): the game makes those
                         pixels breathe softly (parallax_life shader)

Underground the parallax repeats in x AND y (the cave scrolls up and
down), so everything here tiles both ways: shapes crossing an edge are
folded onto the opposite side, the haze is periodic in y.
Run from the project root:  python3 tools/gen_dungeon_backgrounds.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

BACK = "assets/sprites/backgrounds"
W, H = 320, 180
M = 48


def clamp(v):
    return max(0, min(255, int(v)))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


def mul(c, k):
    return tuple(clamp(v * k) for v in c[:3])


def rgba(c, a=255):
    return (clamp(c[0]), clamp(c[1]), clamp(c[2]), clamp(a))


class Canvas:
    """A tile being drawn with a margin; shapes past an edge are folded onto
    the other side (tiles in x and y). `glowing` marks what is drawn into
    the glow mask too."""

    def __init__(self):
        self.im = Image.new("RGBA", (W + 2 * M, H + 2 * M), (0, 0, 0, 0))
        self.gm = Image.new("RGBA", (W + 2 * M, H + 2 * M), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.dg = ImageDraw.Draw(self.gm)
        self.glowing = False

    def _xy(self, xy):
        if isinstance(xy, (list, tuple)) and xy and isinstance(xy[0], (list, tuple)):
            return [(p[0] + M, p[1] + M) for p in xy]
        return [v + M for v in xy]

    def poly(self, pts, c, a=255):
        self.d.polygon(self._xy(pts), fill=rgba(c, a))
        if self.glowing:
            self.dg.polygon(self._xy(pts), fill=(255, 255, 255, 255))

    def rect(self, box, c, a=255):
        self.d.rectangle(self._xy(box), fill=rgba(c, a))
        if self.glowing:
            self.dg.rectangle(self._xy(box), fill=(255, 255, 255, 255))

    def ell(self, box, c, a=255):
        self.d.ellipse(self._xy(box), fill=rgba(c, a))
        if self.glowing:
            self.dg.ellipse(self._xy(box), fill=(255, 255, 255, 255))

    def line(self, pts, c, w=1, a=255):
        self.d.line(self._xy(pts), fill=rgba(c, a), width=w)
        if self.glowing:
            self.dg.line(self._xy(pts), fill=(255, 255, 255, 255), width=w)

    def dot(self, x, y, c, a=255):
        self.rect((x, y, x, y), c, a)

    def fold(self, src):
        out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                part = src.crop((M + dx * W, M + dy * H, M + dx * W + W, M + dy * H + H))
                out.alpha_composite(part)
        return out

    def result(self):
        return self.fold(self.im), self.fold(self.gm)


# ------------------------------------------------------------- shapes
def haze(top, bottom, glow=None, glow_at=(0.5, 0.5), rnd=None):
    """The far layer's base: a periodic vertical blend (tiles in y), a soft
    patch of light, a few drifting bands of mist."""
    im = Image.new("RGBA", (W, H))
    px = im.load()
    gx, gy = glow_at
    for y in range(H):
        t = 0.5 + 0.5 * math.cos(2 * math.pi * y / H)
        base = mix(bottom, top, t)
        for x in range(W):
            c = base
            if glow:
                dx = min(abs(x / W - gx), 1 - abs(x / W - gx)) * W
                dy = min(abs(y / H - gy), 1 - abs(y / H - gy)) * H
                g = max(0.0, 1.0 - math.hypot(dx, dy * 1.3) / 120.0) ** 2 * 0.5
                c = mix(c, glow, g)
            band = math.sin(2 * math.pi * (y / H * 2 + x / W) + 1.3) * 0.5 + 0.5
            if band > 0.8 and (x + y) % 2 == 0:
                c = mix(c, top, 0.12)
            px[x, y] = rgba(c)
    return im


def lit_column(cv, x, w, col, seams=True, y0=-M, y1=H + M):
    """A stone column, lit from the left, with block seams."""
    for k in range(w):
        f = 1.25 if k < w * 0.25 else (1.05 if k < w * 0.5 else (0.85 if k < w * 0.8 else 0.68))
        cv.rect((x + k, y0, x + k, y1), mul(col, f))
    if seams:
        for y in range(int(y0), int(y1), 9):
            cv.line([(x, y), (x + w - 1, y)], mul(col, 0.6))
            cv.line([(x, y + 1), (x + w - 1, y + 1)], mul(col, 1.12))


def arch(cv, x0, x1, y, thick, col):
    """A round arch between x0 and x1 with its crown at y."""
    cx = (x0 + x1) / 2
    r = (x1 - x0) / 2
    for k in range(thick):
        rr = r - k
        pts = [(cx + math.cos(a) * rr, y + r - math.sin(a) * rr) for a in [math.pi * i / 24 for i in range(25)]]
        cv.line(pts, mul(col, 1.15 - 0.4 * k / max(1, thick)), 1)


def stalactite(cv, x, y, ln, w, col, up=False):
    s = -1 if up else 1
    cv.poly([(x - w, y), (x + w, y), (x, y + s * ln)], col)
    cv.poly([(x, y), (x + w, y), (x, y + s * ln)], mul(col, 0.72))
    cv.line([(x - w + 1, y), (x - 1, y + s * ln * 0.7)], mul(col, 1.25))


def mushroom(cv, x, yb, h, r, stem, cap, spot, rnd):
    cv.rect((x - 1, yb - h, x + 1, yb), mul(stem, 1.0))
    cv.rect((x - 1, yb - h, x - 1, yb), mul(stem, 1.25))
    cv.poly([(x - r, yb - h + 2), (x - r * 0.7, yb - h - r * 0.55), (x, yb - h - r * 0.75),
             (x + r * 0.7, yb - h - r * 0.55), (x + r, yb - h + 2)], cap)
    cv.poly([(x, yb - h - r * 0.75), (x + r * 0.7, yb - h - r * 0.55), (x + r, yb - h + 2), (x + 1, yb - h + 2)], mul(cap, 0.75))
    cv.line([(x - r + 1, yb - h + 1), (x - r * 0.6, yb - h - r * 0.5)], mul(cap, 1.35))
    for k in range(-int(r) + 2, int(r) - 1, 2):  # gills
        cv.dot(x + k, yb - h + 2, mul(cap, 0.55))
    cv.glowing = True
    for _ in range(max(2, int(r / 2))):
        sx = x + rnd.uniform(-r * 0.7, r * 0.7)
        sy = yb - h - rnd.uniform(0, r * 0.5)
        cv.dot(sx, sy, spot)
    cv.glowing = False


def crystal(cv, x, yb, h, w, col, up=True):
    s = -1 if up else 1
    tip = (x + w * 0.2, yb + s * h)
    cv.glowing = True
    cv.poly([(x - w, yb), tip, (x + w, yb)], col)
    cv.glowing = False
    cv.poly([(x - w, yb), tip, (x - w * 0.1, yb)], mix(col, (255, 255, 255), 0.45))
    cv.poly([(x + w * 0.4, yb), tip, (x + w, yb)], mul(col, 0.6))
    cv.line([(x - w * 0.5, yb + s * 2), (tip[0] - 1, tip[1] - s * 2)], (255, 255, 255), 1, 200)


def root(cv, x0, y0, x1, y1, w, col, rnd, bend=20):
    pts = []
    for i in range(21):
        t = i / 20
        x = x0 + (x1 - x0) * t + math.sin(t * math.pi) * bend
        y = y0 + (y1 - y0) * t + math.sin(t * math.pi * 2) * bend * 0.3
        pts.append((x, y))
    for k in range(w, 0, -1):
        cv.line(pts, mul(col, 0.7 + 0.5 * (1 - k / w)), k)
    cv.line([(p[0] - w / 3, p[1] - w / 3) for p in pts], mul(col, 1.3))


def chain(cv, x, y0, y1, col):
    for y in range(int(y0), int(y1), 3):
        cv.rect((x - (y // 3) % 2, y, x + 1 - (y // 3) % 2, y + 1), mul(col, 1.1 if (y // 3) % 2 else 0.8))


def window(cv, x, y, w, h, frame, light):
    cv.rect((x - 1, y - 1, x + w, y + h), mul(frame, 0.7))
    cv.glowing = True
    cv.rect((x, y + 2, x + w - 1, y + h - 1), light)
    cv.poly([(x, y + 2), (x + w / 2, y - 1), (x + w - 1, y + 2)], light)
    cv.glowing = False
    cv.line([(x + w / 2, y), (x + w / 2, y + h - 1)], mul(frame, 0.6))


# ------------------------------------------------------------- biomes
def build(name, spec):
    rnd = random.Random(hash(name) & 0xffff)
    top, bottom, glow, rock, accent, kind = spec
    far = haze(top, bottom, glow, (rnd.random(), rnd.random()), rnd)
    # far formations: dim silhouettes in the haze (drawn on a canvas, folded)
    fc = Canvas()
    fog = mix(rock, top, 0.72)  # the far formations sink into the haze
    mc = Canvas()
    nc = Canvas()
    stone = rock
    dark = mul(rock, 0.55)
    if kind == "catacombs":
        for x in range(0, W, 64):
            lit_column(fc, x + rnd.randint(0, 10), 7, fog)
            arch(fc, x + 7, x + 64, 24, 2, fog)
        for x in range(10, W, 107):
            lit_column(mc, x, 12, stone)
            for y in (30, 120):  # skull niches with a candle
                mc.ell((x + 18, y, x + 30, y + 12), mul(stone, 0.35))
                mc.ell((x + 21, y + 4, x + 27, y + 10), (220, 214, 196))
                mc.dot(x + 22, y + 6, (30, 24, 24))
                mc.dot(x + 25, y + 6, (30, 24, 24))
                mc.glowing = True
                mc.rect((x + 32, y + 6, x + 33, y + 11), (250, 230, 170))
                mc.dot(x + 32, y + 4, (255, 200, 90))
                mc.glowing = False
            arch(mc, x + 12, x + 107, 6, 4, stone)
        for x in range(5, W, 53):
            chain(nc, x, -10, rnd.randint(20, 60), mul(stone, 0.8))
        for x in range(0, W, 23):
            stalactite(nc, x, 0, rnd.randint(6, 18), 3, dark)
    elif kind == "fungal":
        for _ in range(9):
            mushroom(fc, rnd.uniform(0, W), rnd.uniform(60, 180), rnd.uniform(30, 60), rnd.uniform(12, 22), fog, mix(fog, accent, 0.2), mix(fog, accent, 0.5), rnd)
        for _ in range(6):
            mushroom(mc, rnd.uniform(0, W), rnd.uniform(110, 185), rnd.uniform(40, 80), rnd.uniform(15, 26), (170, 190, 170), mix(rock, accent, 0.45), accent, rnd)
        for x in range(0, W, 9):  # hanging vines and spores
            ln = rnd.randint(8, 40)
            nc.line([(x, -4), (x + rnd.randint(-2, 2), ln)], mul(rock, 0.9))
            if rnd.random() < 0.4:
                nc.glowing = True
                nc.dot(x, ln + 1, accent)
                nc.glowing = False
    elif kind == "ruins":
        for x in range(0, W, 53):
            lit_column(fc, x, 8, fog)
            arch(fc, x + 8, x + 53, 40, 2, fog)
        for x in range(0, W, 107):
            lit_column(mc, x + 6, 14, stone)
            mc.rect((x + 2, 20, x + 23, 26), mul(stone, 1.15))  # capital
            mc.rect((x + 2, 26, x + 23, 27), mul(stone, 0.6))
            arch(mc, x + 20, x + 107, 30, 5, stone)
            if rnd.random() < 0.7:  # a broken statue on a plinth
                sx = x + 62
                mc.rect((sx - 5, 150, sx + 5, 160), mul(stone, 1.05))
                mc.poly([(sx - 3, 150), (sx - 2, 128), (sx + 2, 128), (sx + 3, 150)], mul(stone, 0.95))
                mc.ell((sx - 3, 120, sx + 3, 128), mul(stone, 1.1))
        for x in range(0, W, 17):
            nc.line([(x, -2), (x + 2, rnd.randint(5, 30))], mix(dark, (90, 120, 70), 0.4))
    elif kind == "lava":
        for _ in range(10):
            x = rnd.uniform(0, W)
            stalactite(fc, x, 180, rnd.uniform(40, 90), rnd.uniform(10, 20), fog, up=True)
        for _ in range(7):
            x = rnd.uniform(0, W)
            hh = rnd.uniform(50, 110)
            stalactite(mc, x, 180, hh, rnd.uniform(9, 15), stone, up=True)
            mc.glowing = True  # a glowing crack up the spire
            y = 180
            cx = x
            while y > 180 - hh * 0.8:
                ny = y - rnd.uniform(4, 9)
                ncx = cx + rnd.uniform(-2, 2)
                mc.line([(cx, y), (ncx, ny)], accent)
                cx, y = ncx, ny
            mc.glowing = False
        for x in range(0, W, 14):
            stalactite(nc, x, 0, rnd.randint(10, 34), rnd.randint(3, 6), dark)
            if rnd.random() < 0.3:
                nc.glowing = True
                nc.dot(x, rnd.randint(36, 60), accent)  # a falling ember
                nc.glowing = False
    elif kind == "mirrors":
        for x in range(0, W, 26):
            lit_column(fc, x, 10, fog, seams=False)
        for x in range(8, W, 54):
            lit_column(mc, x, 10, stone, seams=False)
            fx = x + 18
            mc.rect((fx - 1, 40, fx + 17, 120), (200, 170, 90))  # a gilt frame
            mc.glowing = True
            for y in range(42, 118):
                t = (y - 42) / 76
                mc.line([(fx + 1, y), (fx + 15, y)], mix((150, 140, 210), (230, 220, 255), 0.5 + 0.5 * math.sin(t * 6)))
            mc.glowing = False
            mc.line([(fx + 4, 50), (fx + 12, 90)], (255, 255, 255), 1, 180)
        for x in range(0, W, 21):  # hanging prisms
            y = rnd.randint(10, 50)
            nc.line([(x, -4), (x, y)], mul(stone, 0.8))
            nc.glowing = True
            nc.poly([(x - 2, y), (x, y - 3), (x + 2, y), (x, y + 5)], accent)
            nc.glowing = False
    elif kind == "crystal":
        for _ in range(14):
            crystal(fc, rnd.uniform(0, W), 180, rnd.uniform(30, 80), rnd.uniform(5, 10), mix(fog, accent, 0.3))
        for _ in range(9):
            x = rnd.uniform(0, W)
            for k in range(3):
                crystal(mc, x + k * 6 - 6, 180, rnd.uniform(20, 60), rnd.uniform(4, 8), mix(accent, (255, 255, 255), rnd.uniform(0, 0.3)))
        for _ in range(9):
            crystal(nc, rnd.uniform(0, W), 0, rnd.uniform(10, 30), rnd.uniform(3, 5), mul(accent, 0.8), up=False)
    elif kind == "ashen":
        for x in range(0, W, 46):  # burnt gothic halls
            hh = rnd.randint(70, 120)
            fc.rect((x, 180 - hh, x + 30, 180), fog)
            fc.poly([(x, 180 - hh), (x + 15, 180 - hh - 24), (x + 30, 180 - hh)], fog)
        for x in range(10, W, 107):
            lit_column(mc, x, 12, stone)
            arch(mc, x + 12, x + 107, 20, 4, stone)
            window(mc, x + 44, 60, 9, 24, stone, accent)
            # a torn banner
            bx = x + 74
            mc.rect((bx, 30, bx + 9, 70), (130, 40, 40))
            mc.rect((bx, 30, bx + 2, 70), (170, 60, 50))
            mc.poly([(bx, 70), (bx + 4, 64), (bx + 9, 72), (bx + 9, 70)], (0, 0, 0), 0)
        for _ in range(30):  # embers drifting close
            nc.glowing = True
            nc.dot(rnd.uniform(0, W), rnd.uniform(0, H), accent)
            nc.glowing = False
        for x in range(0, W, 29):
            stalactite(nc, x, 0, rnd.randint(4, 14), 2, dark)
    elif kind == "drowned":
        for x in range(0, W, 64):
            lit_column(fc, x, 8, fog)
            arch(fc, x + 8, x + 64, 30, 2, fog)
        for x in range(0, W, 107):
            lit_column(mc, x + 4, 12, stone)
            arch(mc, x + 16, x + 111, 24, 4, stone)
            for k in range(6):  # kelp swaying up from the floor
                kx = x + 36 + k * 9
                pts = [(kx + math.sin(t * 3 + k) * 3, 180 - t * rnd.uniform(40, 70)) for t in [i / 10 for i in range(11)]]
                mc.line(pts, mix((60, 120, 90), accent, 0.2), 2)
        for _ in range(40):  # plankton glowing in the dark water
            nc.glowing = True
            nc.dot(rnd.uniform(0, W), rnd.uniform(0, H), accent)
            nc.glowing = False
        for _ in range(14):  # bubbles
            bx, by = rnd.uniform(0, W), rnd.uniform(0, H)
            nc.ell((bx, by, bx + 3, by + 3), (180, 230, 230), 120)
            nc.dot(bx + 1, by + 1, (255, 255, 255), 200)
    elif kind == "roots":
        for _ in range(4):
            root(fc, rnd.uniform(-40, W), -20, rnd.uniform(0, W + 40), 200, rnd.randint(10, 16), fog, rnd, rnd.uniform(-40, 40))
        for _ in range(3):
            root(mc, rnd.uniform(-40, W), -20, rnd.uniform(0, W + 40), 200, rnd.randint(9, 13), stone, rnd, rnd.uniform(-50, 50))
        root(mc, -30, rnd.uniform(40, 140), W + 30, rnd.uniform(40, 140), 8, mul(stone, 0.9), rnd, rnd.uniform(-30, 30))
        for x in range(0, W, 8):  # tendrils and amber motes
            nc.line([(x, -2), (x + rnd.randint(-3, 3), rnd.randint(6, 40))], mul(rock, 0.7))
        for _ in range(26):
            nc.glowing = True
            nc.dot(rnd.uniform(0, W), rnd.uniform(0, H), accent)
            nc.glowing = False
    elif kind == "abyss":
        for _ in range(14):  # floating obsidian shards far away
            x, y = rnd.uniform(0, W), rnd.uniform(0, H)
            s = rnd.uniform(6, 14)
            fc.poly([(x, y - s), (x + s * 0.6, y), (x, y + s * 1.4), (x - s * 0.6, y)], fog)
        for _ in range(9):
            x, y = rnd.uniform(0, W), rnd.uniform(0, H)
            s = rnd.uniform(8, 18)
            mc.poly([(x, y - s), (x + s * 0.6, y), (x, y + s * 1.4), (x - s * 0.6, y)], stone)
            mc.poly([(x, y - s), (x + s * 0.6, y), (x, y + s * 1.4)], mul(stone, 0.6))
            mc.line([(x - s * 0.5, y), (x, y - s)], mul(stone, 1.6))
            mc.glowing = True
            mc.line([(x - s * 0.2, y - s * 0.3), (x + s * 0.1, y + s * 0.6)], accent)
            mc.glowing = False
        for k in range(3):  # violet veins of the void
            pts = [(x, 30 + k * 55 + math.sin(x / 30 + k) * 12) for x in range(-20, W + 21, 8)]
            nc.glowing = True
            nc.line(pts, mix(accent, (40, 20, 60), 0.4), 1)
            nc.glowing = False
    else:  # the heart of the Eclipse
        cx, cy = W * 0.62, H * 0.42
        for r in range(38, 0, -1):  # the dark sun and its corona, far away
            a = 255 if r < 26 else int(255 * (38 - r) / 12)
            col = (30, 20, 40) if r < 26 else mix(glow, (255, 240, 200), (38 - r) / 12)
            if r >= 26:
                fc.glowing = True
            fc.ell((cx - r, cy - r, cx + r, cy + r), col, a)
            fc.glowing = False
        for x in range(0, W, 60):
            lit_column(mc, x + 8, 12, stone)
            mc.rect((x + 4, 24, x + 24, 30), accent)  # gold capitals
            mc.rect((x + 4, 30, x + 24, 31), mul(accent, 0.6))
            mc.glowing = True
            mc.ell((x + 12, 60, x + 16, 64), accent)  # a rune
            mc.glowing = False
        for x in range(0, W, 31):
            nc.line([(x, -4), (x, rnd.randint(14, 50))], mul(accent, 0.6))
    for cv in (fc,):
        lay, _ = cv.result()
        far.alpha_composite(lay)
    _, far_glow = fc.result()
    mid, mid_glow = mc.result()
    near, near_glow = nc.result()
    # aerial perspective of the middle layer: a little toward the haze
    px = mid.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = rgba(mix((r, g, b), top, 0.18), a)
    os.makedirs(BACK, exist_ok=True)
    far.save(os.path.join(BACK, f"{name}_far.png"))
    mid.save(os.path.join(BACK, f"{name}_mid.png"))
    near.save(os.path.join(BACK, f"{name}_near.png"))
    for layer, g in (("far", far_glow), ("mid", mid_glow), ("near", near_glow)):
        path = os.path.join(BACK, f"{name}_{layer}_glow.png")
        if g.getbbox():
            g.save(path)
        elif os.path.exists(path):
            os.remove(path)


# haze top, haze bottom, light patch, rock, accent (glow), kind
BIOMES = {
    "catacombs":      ((56, 50, 70), (30, 26, 40), (120, 100, 80), (110, 104, 118), (250, 210, 120), "catacombs"),
    "fungal":         ((30, 74, 72), (14, 36, 40), (60, 160, 150), (60, 96, 90), (120, 250, 220), "fungal"),
    "ruins":          ((86, 78, 62), (44, 40, 34), (170, 150, 110), (150, 138, 116), (200, 180, 120), "ruins"),
    "lava":           ((120, 46, 26), (54, 18, 12), (255, 140, 60), (110, 60, 46), (255, 150, 50), "lava"),
    "mirror_halls":   ((70, 54, 110), (32, 24, 56), (180, 150, 240), (120, 104, 160), (220, 190, 255), "mirrors"),
    "crystal_depths": ((22, 46, 86), (8, 18, 40), (80, 160, 230), (50, 80, 120), (120, 220, 255), "crystal"),
    "ashen_halls":    ((80, 40, 34), (34, 16, 16), (220, 110, 60), (96, 72, 66), (255, 160, 80), "ashen"),
    "drowned_vaults": ((24, 70, 76), (10, 32, 40), (80, 180, 170), (70, 110, 106), (130, 255, 220), "drowned"),
    "world_roots":    ((60, 46, 30), (26, 20, 14), (160, 120, 60), (112, 82, 54), (255, 200, 110), "roots"),
    "obsidian_abyss": ((34, 22, 52), (10, 6, 18), (110, 60, 170), (60, 50, 80), (190, 110, 255), "abyss"),
    "eclipse_heart":  ((50, 30, 56), (20, 12, 24), (255, 200, 120), (96, 80, 100), (240, 200, 110), "eclipse"),
}


def main():
    for name, spec in BIOMES.items():
        build(name, spec)
    print("dungeon backgrounds: ok")


if __name__ == "__main__":
    main()
