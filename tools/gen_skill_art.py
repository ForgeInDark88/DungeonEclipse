#!/usr/bin/env python3
"""Skill icon subjects v5: small illustrations instead of glyphs.

Every subject is painted at 32x32 the way Dota's icons are: a real object
or moment (a sword mid-swing with a fullered blade and a wrapped grip, a
flask with bubbling liquid, a hooded figure dissolving into smoke) with
materials (steel, gold, leather, wood, glass, bone), volume light from the
top left and the skill's colour as the magic in it. gen_skill_icons32.draw
puts it on a painted backdrop, adds the rim light, shadow, bloom and frame.

Same subject names and params as v4 (see the ICONS tables of
gen_skills_v2 / gen_necromancer).
"""
from __future__ import annotations

import math

from PIL import Image, ImageDraw

from gen_monsters import lit, mask, FULL

S = 32
INK = (14, 9, 20, 255)


def C(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


def F(c, f, a=255):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), a)


def MIX(c1, c2, t, a=255):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (a,)


# materials: dark, mid, base, lite, hi
STEEL = [(54, 60, 78), (96, 106, 128), (150, 160, 182), (206, 214, 230), (250, 252, 255)]
GOLDM = [(96, 58, 20), (160, 106, 34), (214, 160, 52), (250, 210, 96), (255, 246, 196)]
WOODM = [(56, 34, 20), (92, 58, 32), (132, 86, 48), (170, 118, 70), (204, 156, 100)]
LEATHER = [(44, 26, 22), (74, 44, 34), (104, 64, 46), (138, 90, 64), (170, 120, 90)]
BONEM = [(110, 96, 78), (160, 146, 120), (206, 196, 170), (236, 230, 210), (255, 252, 240)]
IRON = [(34, 32, 40), (58, 56, 66), (84, 82, 94), (120, 118, 132), (170, 168, 184)]
CLOTH = [(26, 18, 34), (44, 32, 56), (66, 50, 82), (92, 74, 112), (124, 104, 146)]
GLASS = [(40, 60, 70), (90, 120, 130), (160, 200, 210), (210, 240, 245), (255, 255, 255)]


class Art:
    def __init__(self, accent):
        self.im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        a = tuple(accent[:3])
        self.acc = a
        # the skill's colour as a material: deep .. white-hot
        self.A = [F(a, 0.32)[:3], F(a, 0.58)[:3], F(a, 0.9)[:3], MIX(a, (255, 255, 255), 0.35)[:3],
                  MIX(a, (255, 255, 255), 0.75)[:3]]

    # -- pixels
    def p(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < S and 0 <= y < S:
            self.im.putpixel((x, y), C(c) if len(c) == 3 else c)

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=C(c) if len(c) == 3 else c, width=w)

    def poly(self, pts, c):
        self.d.polygon(pts, fill=C(c) if len(c) == 3 else c)

    def ell(self, box, c):
        self.d.ellipse(box, fill=C(c) if len(c) == 3 else c)

    def vol(self, draw_fn, mat, cx, cy, rx, ry, flat=0.0, alpha=255):
        """Fill a shape with ellipsoid light (4 tones of the material)."""
        m = mask(S, S, draw_fn)
        lit(self.im, m, mat[2], cx, cy, rx, ry, alpha, flat=flat)
        self.d = ImageDraw.Draw(self.im)

    def vpoly(self, pts, mat, flat=0.25):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        self.vol(lambda dd: dd.polygon(pts, fill=FULL), mat, cx - (max(xs) - min(xs)) * 0.2,
                 cy - (max(ys) - min(ys)) * 0.2, max(1, (max(xs) - min(xs)) / 2 + 1), max(1, (max(ys) - min(ys)) / 2 + 1), flat)

    def vell(self, box, mat, flat=0.0):
        x0, y0, x1, y1 = box
        self.vol(lambda dd: dd.ellipse(box, fill=FULL), mat, x0 + (x1 - x0) * 0.35, y0 + (y1 - y0) * 0.33,
                 (x1 - x0) / 2 + 0.5, (y1 - y0) / 2 + 0.5, flat)

    # -- light
    def glowdot(self, cx, cy, r, col=None, strength=1.0):
        col = col or self.acc
        gp = self.glow.load()
        for y in range(max(0, int(cy - r)), min(S, int(cy + r + 1))):
            for x in range(max(0, int(cx - r)), min(S, int(cx + r + 1))):
                dd = math.hypot(x - cx, y - cy)
                if dd <= r:
                    a = int(120 * strength * (1 - dd / r) ** 1.3)
                    if a > gp[x, y][3]:
                        gp[x, y] = (col[0], col[1], col[2], a)

    def spark(self, x, y, big=False):
        self.p(x, y, self.A[4])
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            self.p(x + dx, y + dy, self.A[3])
        if big:
            for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
                self.p(x + dx, y + dy, self.A[2])
        self.glowdot(x, y, 3 if not big else 5, strength=0.8)

    def energy(self, pts, w=2):
        """A stroke of the skill's power: dark rim, coloured body, white-hot core."""
        self.line(pts, self.A[1], w + 2)
        self.line(pts, self.A[2], w)
        self.line(pts, self.A[4], max(1, w - 1))
        for x, y in pts[:: max(1, len(pts) // 4)]:
            self.glowdot(x, y, 4, strength=0.6)

    def arc(self, cx, cy, r, a0, a1, w=2, squash=1.0):
        pts = []
        for k in range(24):
            a = math.radians(a0 + (a1 - a0) * k / 23)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * squash))
        self.energy(pts, w)

    def speed(self, x0, y0, dx, dy, n=3, ln=6):
        for k in range(n):
            ox, oy = -dy * (k - n // 2) * 3, dx * (k - n // 2) * 3
            self.line([(x0 + ox, y0 + oy), (x0 + ox - dx * ln, y0 + oy - dy * ln)], F(self.A[2], 1.0, 150))


# ------------------------------------------------------------- weapons
def _blade(g, x0, y0, x1, y1, w, mat=STEEL, fuller=True):
    """A straight blade from (x0,y0) (base) to (x1,y1) (tip): lit half,
    shaded half, a fuller, an edge glint."""
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy, ux
    tip_back = 4
    bx, by = x1 - ux * tip_back, y1 - uy * tip_back
    left = [(x0 + nx * w, y0 + ny * w), (bx + nx * w, by + ny * w), (x1, y1)]
    right = [(x0 - nx * w, y0 - ny * w), (bx - nx * w, by - ny * w), (x1, y1)]
    g.poly([(x0, y0)] + left + [(x1, y1)], mat[3])  # lit half (towards the top left)
    g.poly([(x0, y0)] + right + [(x1, y1)], mat[1])  # shaded half
    g.line([(x0, y0), (x1, y1)], mat[2])
    if fuller:
        g.line([(x0 + ux * 2, y0 + uy * 2), (bx - ux * 2, by - uy * 2)], mat[0])
    g.line([left[0], left[1], (x1, y1)], mat[4])  # bright edge
    g.line([right[0], right[1]], F(mat[0], 0.8))
    return ux, uy, nx, ny


def _grip(g, x0, y0, x1, y1, mat=LEATHER, pommel=None):
    n = int(math.hypot(x1 - x0, y1 - y0))
    for k in range(n + 1):
        t = k / max(1, n)
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        c = mat[3] if k % 2 == 0 else mat[1]
        g.p(x, y, c)
        g.p(x + 1, y, F(c, 0.8))
    if pommel:
        g.vell((x1 - 2, y1 - 1, x1 + 2, y1 + 3), pommel)


def s_blade(g, p):
    ln = 22 if p.get("len") == "short" else 25
    edge = p.get("edge")
    x0, y0 = 9, 22
    x1, y1 = x0 + ln * 0.72, y0 - ln * 0.72
    mat = GOLDM if edge == "gold" else STEEL
    _blade(g, x0, y0, x1, y1, 2, mat)
    if p.get("guard") != "none":
        g.line([(5, 18), (13, 26)], GOLDM[1], 3)
        g.line([(5, 18), (13, 26)], GOLDM[3], 1)
        g.vell((7, 20, 11, 24), g.A)  # the gem in the guard
        g.p(8, 21, g.A[4])
    _grip(g, 8, 24, 4, 28, LEATHER, GOLDM)
    if edge == "blood":
        for x, y, n in ((15, 16, 3), (19, 12, 2), (23, 8, 2)):
            g.line([(x, y), (x + 1, y + n)], (150, 20, 30))
            g.p(x + 1, y + n + 1, (200, 40, 50))
        g.p(17, 25, (170, 24, 34))
        g.p(20, 27, (200, 40, 50))
    elif edge == "flame":
        for k, (x, y) in enumerate(((13, 17), (17, 13), (21, 9), (24, 6))):
            hgt = 4 + k % 2 * 2
            g.poly([(x - 2, y + 1), (x, y - hgt), (x + 2, y + 1)], g.A[2])
            g.poly([(x - 1, y), (x, y - hgt + 2), (x + 1, y)], g.A[4])
            g.glowdot(x, y - 2, 4, strength=0.7)
    elif edge == "poison":
        for x, y in ((14, 17), (19, 12)):
            g.line([(x, y), (x, y + 3)], g.A[2])
            g.vell((x - 1, y + 3, x + 1, y + 5), g.A)
        g.glowdot(17, 15, 8, strength=0.4)
    elif edge == "gold":
        for t in (0.35, 0.55, 0.75):
            g.spark(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        g.glowdot((x0 + x1) / 2, (y0 + y1) / 2, 10, strength=0.5)
    g.spark(x1 - 2, y1 + 2, big=True)  # the glint on the tip


def s_dagger(g, p):
    def one(x0, y0, x1, y1, gx):
        _blade(g, x0, y0, x1, y1, 2, STEEL, fuller=False)
        g.line([(x0 - 3, y0 - 3 * gx), (x0 + 3, y0 + 3 * gx)], GOLDM[2], 2)
        _grip(g, x0 - 1, y0 + 1, x0 - 4, y0 + 4, CLOTH, GOLDM)
    if p.get("twin"):
        one(9, 20, 24, 5, 1)
        one(23, 20, 8, 5, -1)
        g.spark(16, 11, big=True)
    else:
        one(10, 21, 26, 5, 1)
        g.spark(23, 8, big=True)
        g.speed(26, 5, 0.7, -0.7, 3, 5)
    g.glowdot(16, 13, 10, strength=0.35)


def s_axe(g, p):
    _grip(g, 6, 27, 18, 9, WOODM)
    g.line([(6, 27), (18, 9)], WOODM[2], 2)
    g.line([(6, 26), (17, 9)], WOODM[3])
    # the head: a bearded crescent
    head = [(15, 6), (21, 3), (27, 6), (29, 13), (25, 19), (21, 15), (17, 13)]
    g.vpoly(head, STEEL)
    g.line([(21, 3), (27, 6), (29, 13), (25, 19)], STEEL[4])  # honed edge
    g.line([(17, 13), (21, 15), (25, 19)], STEEL[0])
    g.vell((16, 7, 21, 13), IRON)  # the eye of the axe
    for x, y in ((18, 8), (19, 11)):
        g.p(x, y, GOLDM[3])
    if p.get("spike"):
        g.poly([(14, 9), (8, 6), (13, 12)], STEEL[1])
        g.line([(14, 9), (8, 6)], STEEL[3])
        for x, y in ((26, 20), (24, 22), (27, 23)):
            g.p(x, y, (190, 30, 40))
    g.arc(16, 16, 13, -80, 40, 1)  # the swing
    g.spark(28, 9, big=True)


def s_hammer(g, p):
    big = p.get("w", 8) >= 10
    _grip(g, 7, 28, 16, 13, WOODM)
    g.line([(7, 28), (16, 13)], WOODM[2], 2)
    hx0, hy0, hx1, hy1 = (9, 3, 27, 14) if big else (11, 4, 25, 13)
    g.vpoly([(hx0, hy0 + 2), (hx0 + 2, hy0), (hx1 - 2, hy0), (hx1, hy0 + 2), (hx1, hy1 - 2), (hx1 - 2, hy1),
             (hx0 + 2, hy1), (hx0, hy1 - 2)], IRON)
    g.line([(hx0 + 2, hy0), (hx1 - 2, hy0)], IRON[4])
    for bx in (hx0 + 3, hx1 - 4):  # iron bands
        g.line([(bx, hy0), (bx, hy1)], IRON[0], 2)
        g.line([(bx, hy0), (bx, hy1)], GOLDM[2])
    cx, cy = (hx0 + hx1) / 2, (hy0 + hy1) / 2
    if p.get("glow"):
        g.line([(cx - 2, cy - 2), (cx + 2, cy + 2)], g.A[4])  # a rune burning in the face
        g.line([(cx + 2, cy - 2), (cx - 2, cy + 2)], g.A[4])
        g.p(cx, cy, (255, 255, 255))
        g.glowdot(cx, cy, 8, strength=0.9)
    if big:  # it hits the ground: cracks and debris
        for pts in (((2, 30), (5, 27), (4, 24)), ((9, 30), (12, 28), (16, 30))):
            g.line(list(pts), g.A[3])
        for x, y in ((3, 21), (19, 26), (24, 22)):
            g.vell((x - 1, y - 1, x + 1, y + 1), IRON)
        g.glowdot(8, 29, 7, strength=0.7)


def s_slash(g, p):
    def crescent(cx, cy, r, a0, a1, flip=1):
        outer, inner = [], []
        for k in range(26):
            t = k / 25
            a = math.radians(a0 + (a1 - a0) * t)
            w = math.sin(t * math.pi) * 4.5
            outer.append((cx + math.cos(a) * r, cy + math.sin(a) * r * flip))
            inner.append((cx + math.cos(a) * (r - w), cy + math.sin(a) * (r - w) * flip))
        g.poly(outer + inner[::-1], C(g.A[2]))
        g.line(outer, g.A[4])
        g.line(inner[3:-3], g.A[1])
        for x, y in outer[::5]:
            g.glowdot(x, y, 4, strength=0.6)
    crescent(8, 26, 20, -92, 5)
    if p.get("double"):
        crescent(25, 26, 20, -88, -185)
    for x, y in ((24, 12), (27, 16), (21, 8), (29, 20)):
        g.p(x, y, (200, 30, 44))
    g.spark(16, 7, big=True)

def s_fan(g, p):
    n = max(1, p.get("count", 5))
    for k in range(n):
        a = math.radians(-90 + (k - (n - 1) / 2) * (110 / max(1, n - 1) if n > 1 else 0))
        x0, y0 = 16 + math.cos(a) * 4, 26 + math.sin(a) * 4
        x1, y1 = 16 + math.cos(a) * 21, 26 + math.sin(a) * 21
        _blade(g, x0, y0, x1, y1, 1, STEEL, fuller=False)
        g.line([(x0, y0), (16 + math.cos(a) * 1, 26 + math.sin(a) * 1)], LEATHER[2], 2)
        g.glowdot(x1, y1, 3, strength=0.5)
    g.vell((13, 23, 19, 29), g.A)
    g.spark(16, 26, big=True)


def s_blades(g, p):
    s_fan(g, {"count": p.get("count", 5)})


def s_whirl(g, p):
    arms = p.get("arms", 3)
    for k in range(3):
        g.arc(16, 16, 6 + k * 4, k * 70, k * 70 + 230, 1, 0.9)
    for k in range(arms):
        a = math.radians(k * 360 / arms - 30)
        x, y = 16 + math.cos(a) * 13, 16 + math.sin(a) * 12
        tx, ty = x + math.cos(a + 1.6) * 6, y + math.sin(a + 1.6) * 6
        _blade(g, x, y, tx, ty, 1, STEEL, fuller=False)
    g.vell((13, 13, 19, 19), g.A)
    g.spark(16, 16, big=True)


def s_impact(g, p):
    rays = p.get("rays", 8)
    g.vol(lambda dd: dd.ellipse((4, 20, 28, 30), fill=FULL), [F(g.A[0], 0.8)[:3]] * 5, 16, 24, 12, 5)  # a dent in the ground
    for k in range(rays):
        a = math.radians(k * 360 / rays - 90 + 10)
        r0, r1 = 5, 14 if k % 2 == 0 else 10
        g.energy([(16 + math.cos(a) * r0, 17 + math.sin(a) * r0), (16 + math.cos(a) * r1, 17 + math.sin(a) * r1)], 1)
    g.arc(16, 22, 12, 180, 360, 1, 0.35)  # shockwave ring in perspective
    g.arc(16, 22, 12, 0, 180, 1, 0.35)
    for x, y in ((5, 12), (26, 9), (24, 26), (7, 26)):
        g.vell((x - 1, y - 1, x + 1, y + 1), IRON)  # debris
    g.vell((12, 13, 20, 21), g.A)
    g.ell((14, 15, 18, 19), C(g.A[4]))
    g.glowdot(16, 17, 11, strength=1.0)


def s_nova(g, p):
    for k, r in enumerate((14, 10, 6)):
        g.arc(16, 21, r, 0, 360, 2 if k == 0 else 1, 0.4)
    g.poly([(13, 21), (14, 3), (18, 3), (19, 21)], F(g.A[2], 1.0, 140))  # pillar of light
    g.poly([(15, 21), (15.5, 4), (16.5, 4), (17, 21)], C(g.A[4], 220))
    g.glowdot(16, 12, 12, strength=0.9)
    for x, y in ((6, 13), (26, 11), (9, 7), (23, 5), (4, 22), (28, 24)):
        g.spark(x, y)


def s_bolt(g, p):
    main = [(19, 2), (12, 13), (17, 14), (9, 29)]
    g.line(main, g.A[1], 5)
    g.line(main, g.A[2], 3)
    g.line(main, g.A[4], 1)
    if p.get("fork"):
        for br in (((12, 13), (5, 17), (3, 23)), ((17, 14), (24, 19), (27, 26)), ((15, 8), (22, 7))):
            g.line(list(br), g.A[2], 2)
            g.line(list(br), g.A[4], 1)
    g.vol(lambda dd: dd.ellipse((10, -3, 30, 6), fill=FULL), CLOTH, 16, 0, 10, 4)  # the storm cloud
    g.glowdot(13, 15, 13, strength=0.9)
    g.spark(9, 29, big=True)


def s_arrow(g, p):
    n = max(1, p.get("count", 1))
    for k in range(n):
        a = math.radians(-45 + (k - (n - 1) / 2) * (14 if n <= 3 else 9))
        ox, oy = (k - (n - 1) / 2) * 2.5, -(k - (n - 1) / 2) * 1.0
        x0, y0 = 7 + ox - math.cos(a) * 1, 25 + oy
        ln = 22 if n == 1 else 19
        x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
        ux, uy = math.cos(a), math.sin(a)
        g.line([(x0, y0), (x1, y1)], WOODM[3])
        hx, hy = x1 + ux * 3, y1 + uy * 3
        g.poly([(hx, hy), (x1 - uy * 2, y1 + ux * 2), (x1 + uy * 2, y1 - ux * 2)], STEEL[3])  # head
        g.line([(hx, hy), (x1 - uy * 2, y1 + ux * 2)], STEEL[4])
        g.poly([(x0, y0), (x0 - ux * 3 - uy * 2, y0 - uy * 3 + ux * 2), (x0 + ux * 2, y0 + uy * 2)], C(g.A[2]))  # fletching
        g.poly([(x0, y0), (x0 - ux * 3 + uy * 2, y0 - uy * 3 - ux * 2), (x0 + ux * 2, y0 + uy * 2)], C(g.A[1]))
        g.line([(x0 - ux * 3, y0 - uy * 3), (x0 - ux * 8, y0 - uy * 8)], F(g.A[2], 1.0, 140))  # trail
        g.glowdot(hx, hy, 4, strength=0.7)
        if k == n - 1:
            g.spark(hx, hy, big=True)
def s_shield(g, p):
    rim = [(5, 4), (27, 4), (27, 15), (16, 29), (5, 15)]
    g.vpoly(rim, IRON)
    field = [(7, 6), (25, 6), (25, 15), (16, 26), (7, 15)]
    g.vpoly(field, g.A)
    g.line([(7, 6), (25, 6)], F(g.A[3], 1.0))
    if p.get("herald") == "wings":
        for side in (-1, 1):
            for k in range(3):
                g.line([(16, 13), (16 + side * (4 + k * 2), 9 + k * 2)], GOLDM[3 - k % 2], 1)
        g.vell((14, 11, 18, 15), GOLDM)
    else:  # a domed boss with a cross
        g.line([(16, 7), (16, 24)], GOLDM[2], 2)
        g.line([(8, 12), (24, 12)], GOLDM[2], 2)
        g.vell((12, 8, 20, 16), STEEL)
        g.p(14, 10, STEEL[4])
    for x, y in ((6, 5), (26, 5), (6, 14), (26, 14), (16, 27)):
        g.p(x, y, GOLDM[3])  # rivets
    g.line([(5, 4), (27, 4)], IRON[4])
    g.line([(20, 18), (22, 16)], F(g.A[0], 0.8))  # a scratch
    g.glowdot(16, 13, 13, strength=0.45)


def s_wall(g, p):
    cren = p.get("cren", 1)
    y_top = 9 if cren else 6
    g.vpoly([(3, y_top), (29, y_top), (29, 29), (3, 29)], [F(c, 1.0)[:3] for c in IRON], 0.4)
    if cren:
        for x in (3, 11, 19, 27):
            g.vpoly([(x, 3), (x + 4, 3), (x + 4, y_top), (x, y_top)], IRON)
    for row, y in enumerate(range(y_top, 29, 5)):
        g.line([(3, y), (29, y)], IRON[0])
        for x in range(3 + (row % 2) * 4, 29, 8):
            g.line([(x, y), (x, y + 5)], IRON[0])
            g.line([(x + 1, y + 1), (x + 6, y + 1)], IRON[3])  # lit top of each block
    # a glowing ward sigil on the stones
    g.ell((10, 13, 22, 25), C(g.A[1], 160))
    g.d.ellipse((10, 13, 22, 25), outline=C(g.A[3]))
    g.line([(16, 14), (16, 24)], g.A[4])
    g.line([(11, 19), (21, 19)], g.A[4])
    g.glowdot(16, 19, 10, strength=0.8)


def s_heart(g, p):
    g.vol(lambda dd: (dd.ellipse((4, 5, 16, 17), fill=FULL), dd.ellipse((16, 5, 28, 17), fill=FULL),
                      dd.polygon([(5, 13), (27, 13), (16, 28)], fill=FULL)), g.A, 11, 10, 12, 12)
    g.poly([(15, 5), (17, 5), (16, 8)], (0, 0, 0, 0))  # the dimple between the lobes
    g.ell((8, 8, 12, 11), C(g.A[4]))  # gloss
    g.p(9, 8, (255, 255, 255))
    g.line([(21, 8), (23, 12), (21, 16)], g.A[0])  # veins
    g.line([(16, 11), (15, 17), (17, 22)], g.A[0])
    if p.get("pulse"):  # the beat, as a line across it
        g.energy([(2, 18), (8, 18), (10, 14), (13, 23), (16, 11), (19, 21), (21, 18), (29, 18)], 1)
    g.glowdot(16, 15, 13, strength=0.7)

def s_cross(g, p):
    if p.get("halo"):
        g.arc(16, 9, 9, 0, 360, 1, 0.35)
    g.vpoly([(14, 3), (18, 3), (18, 10), (26, 10), (26, 14), (18, 14), (18, 29), (14, 29), (14, 14), (6, 14),
             (6, 10), (14, 10)], GOLDM)
    g.line([(14, 3), (18, 3)], GOLDM[4])
    g.line([(6, 10), (14, 10)], GOLDM[4])
    g.vell((13, 9, 19, 15), g.A)  # the gem in the crossing
    g.p(15, 10, (255, 255, 255))
    for k in range(8):
        a = math.radians(k * 45 + 22)
        g.line([(16 + math.cos(a) * 9, 12 + math.sin(a) * 9), (16 + math.cos(a) * 14, 12 + math.sin(a) * 14)],
               C(g.A[3], 150))
    g.glowdot(16, 12, 14, strength=0.9)


def s_boot(g, p):
    g.vpoly([(9, 4), (19, 4), (19, 20), (26, 22), (27, 27), (8, 27), (8, 20)], LEATHER)
    g.vpoly([(9, 4), (19, 4), (19, 14), (9, 14)], STEEL)  # greave
    g.line([(9, 4), (19, 4)], STEEL[4])
    for y in (7, 11):
        g.line([(9, y), (19, y)], STEEL[0])
    g.line([(8, 27), (27, 27)], LEATHER[0], 2)  # sole
    for x in (11, 15):
        g.p(x, 18, GOLDM[3])  # buckle
    g.line([(10, 18), (17, 18)], LEATHER[0])
    if p.get("wings"):
        for k in range(3):
            g.line([(19, 7 + k * 2), (25 + k, 3 + k * 3)], C(g.A[3 - k % 2]), 2)
        g.glowdot(23, 7, 7, strength=0.7)
    g.speed(6, 22, 1, 0, 3, 4)
    g.spark(26, 26)


def s_wing(g, p):
    for k in range(6):  # primaries, longest first
        a = math.radians(200 + k * 18)
        ln = 21 - k * 2
        x1, y1 = 22 + math.cos(a) * ln, 20 + math.sin(a) * ln
        g.line([(22, 20), (x1, y1)], g.A[1], 4)
        g.line([(22, 20), (x1, y1)], g.A[2], 2)
        g.line([(22, 19), (x1, y1 - 1)], g.A[4])
    g.vpoly([(22, 20), (12, 8), (26, 6), (28, 18)], g.A, 0.3)  # coverts
    for k in range(4):
        g.line([(14 + k * 3, 9 + k), (20 + k * 2, 13 + k)], g.A[3])
    g.glowdot(20, 14, 13, strength=0.7)
    for x, y in ((6, 26), (10, 28), (4, 22)):
        g.p(x, y, g.A[4])  # a falling feather's glints


def s_cloak(g, p):
    g.vpoly([(16, 3), (24, 10), (25, 20), (22, 28), (10, 28), (7, 20), (8, 10)], CLOTH)
    g.vol(lambda dd: dd.ellipse((10, 6, 22, 18), fill=FULL), [F(c, 0.6)[:3] for c in CLOTH], 14, 9, 6, 6)  # hood
    g.ell((12, 9, 20, 17), C((6, 3, 10)))  # the dark under the hood
    g.p(14, 13, g.A[4])
    g.p(18, 13, g.A[4])
    g.glowdot(16, 13, 4, strength=0.8)
    for x in (12, 16, 20):
        g.line([(x, 18), (x - 1, 27)], CLOTH[0])  # folds
    # the lower half dissolves into smoke
    for k, (x, y, r) in enumerate(((8, 26, 3), (14, 28, 3), (21, 27, 3), (26, 23, 2), (4, 21, 2))):
        g.ell((x - r, y - r, x + r, y + r), C(g.A[1], 170 - k * 20))
        g.p(x - 1, y - 1, g.A[3])
    g.glowdot(16, 25, 10, strength=0.5)


# ------------------------------------------------------------- magic
def s_flame(g, p):
    big = p.get("big")
    g.poly([(4, 28), (12, 22), (9, 26)], C(g.A[1], 160))  # the trail
    g.poly([(2, 30), (11, 24), (7, 29)], C(g.A[0], 140))
    layers = ((g.A[1], 0), (g.A[2], 2), (g.A[3], 4), (g.A[4], 6))
    for col, inset in layers:
        r = (11 if big else 9) - inset
        g.vol(lambda dd, r=r: (dd.ellipse((18 - r, 15 - r, 18 + r, 15 + r), fill=FULL),
                               dd.polygon([(18 - r, 15), (8 + inset, 26 - inset // 2), (18, 15 + r)], fill=FULL)),
              [col] * 5, 16, 13, r, r)
        for k in range(4):
            a = math.radians(-120 + k * 30)
            g.poly([(18 + math.cos(a - 0.3) * r, 15 + math.sin(a - 0.3) * r),
                    (18 + math.cos(a) * (r + 4), 15 + math.sin(a) * (r + 4)),
                    (18 + math.cos(a + 0.3) * r, 15 + math.sin(a + 0.3) * r)], C(col))
    g.ell((17, 12, 21, 16), C((255, 255, 240)))
    g.glowdot(18, 14, 15, strength=1.0)
    for x, y in ((28, 4), (6, 8), (27, 25)):
        g.spark(x, y)


def s_snowflake(g, p):
    arms = p.get("arms", 6)
    for k in range(arms):
        a = math.radians(k * 360 / arms - 90)
        x1, y1 = 16 + math.cos(a) * 13, 16 + math.sin(a) * 13
        g.line([(16, 16), (x1, y1)], g.A[1], 3)
        g.line([(16, 16), (x1, y1)], g.A[4])
        for t, ln in ((0.45, 4), (0.75, 3)):
            bx, by = 16 + math.cos(a) * 13 * t, 16 + math.sin(a) * 13 * t
            for s_ in (-0.7, 0.7):
                g.line([(bx, by), (bx + math.cos(a + s_) * ln, by + math.sin(a + s_) * ln)], g.A[3])
        g.p(x1, y1, (255, 255, 255))
    g.vpoly([(16, 11), (21, 16), (16, 21), (11, 16)], g.A)
    g.p(15, 14, (255, 255, 255))
    g.glowdot(16, 16, 14, strength=0.8)


def s_orb(g, p):
    g.vell((6, 6, 26, 26), g.A)
    g.arc(16, 16, 6, 0, 270, 1)  # a swirl inside
    g.ell((10, 9, 14, 12), C((255, 255, 255, 220)))  # the window highlight
    g.p(20, 22, g.A[4])
    g.d.arc((6, 6, 26, 26), 30, 120, fill=C(g.A[4]))  # rim light, lower right
    if p.get("ring"):
        g.arc(16, 16, 15, 160, 380, 1, 0.3)
    if p.get("stars"):
        for x, y in ((4, 6), (27, 5), (28, 26)):
            g.spark(x, y)
    g.glowdot(16, 16, 15, strength=0.9)


def s_eye(g, p):
    g.vol(lambda dd: dd.ellipse((3, 8, 29, 24), fill=FULL), BONEM, 13, 12, 13, 8)  # the white
    g.vell((10, 9, 22, 23), g.A)  # iris
    for k in range(10):
        a = math.radians(k * 36)
        g.line([(16 + math.cos(a) * 2, 16 + math.sin(a) * 2), (16 + math.cos(a) * 5, 16 + math.sin(a) * 5)], g.A[3])
    g.poly([(15, 10), (17, 10), (17.5, 16), (17, 22), (15, 22), (14.5, 16)], C((8, 4, 12)))  # slit pupil
    g.p(13, 12, (255, 255, 255))
    g.d.arc((3, 6, 29, 26), 200, 340, fill=C(CLOTH[0]), width=2)  # lids
    g.d.arc((3, 6, 29, 26), 20, 160, fill=C(CLOTH[1]), width=2)
    if p.get("lashes"):
        for k in range(5):
            x = 7 + k * 4.5
            g.line([(x, 8 - (k % 2)), (x - 1, 4 - (k % 2))], CLOTH[0])
    g.glowdot(16, 16, 12, strength=0.7)


def s_poison(g, p):
    g.vell((7, 11, 25, 29), GLASS, 0.1)  # the flask
    g.vol(lambda dd: dd.chord((8, 12, 24, 28), 10, 170, fill=FULL), g.A, 13, 21, 9, 6)  # liquid
    g.line([(9, 20), (23, 20)], g.A[4])  # surface
    for x, y in ((13, 24), (18, 22), (15, 26)):
        g.p(x, y, g.A[4])  # bubbles
    g.vpoly([(13, 4), (19, 4), (19, 12), (13, 12)], GLASS)  # neck
    g.vpoly([(12, 1), (20, 1), (19, 5), (13, 5)], WOODM)  # cork
    g.ell((10, 14, 13, 17), C((255, 255, 255, 200)))
    g.vell((13, 15, 19, 21), BONEM)  # skull label
    g.p(15, 17, (20, 10, 20))
    g.p(17, 17, (20, 10, 20))
    for k in range(p.get("drops", 1)):
        x = 24 + k * 3
        g.vell((x - 1, 24 + k * 2, x + 1, 27 + k * 2), g.A)
    g.glowdot(16, 22, 11, strength=0.7)
    for x, y in ((6, 8), (26, 9)):
        g.p(x, y, g.A[3])  # fumes


def s_bomb(g, p):
    g.vell((5, 9, 25, 29), IRON)
    g.ell((9, 13, 13, 16), C(IRON[4]))
    g.line([(5, 19), (25, 19)], IRON[0], 2)  # band
    g.line([(5, 18), (25, 18)], GOLDM[2])
    g.vpoly([(13, 6), (18, 6), (18, 10), (13, 10)], IRON)  # neck
    g.line([(16, 6), (19, 3), (23, 3)], WOODM[2], 1)  # fuse
    g.spark(24, 2, big=True)
    if p.get("smoke"):
        for k, (x, y, r) in enumerate(((26, 9, 3), (28, 14, 2), (5, 6, 2), (3, 26, 3), (27, 26, 3))):
            g.ell((x - r, y - r, x + r, y + r), C(MIX(IRON[3], g.acc, 0.4), 170))
            g.p(x - 1, y - 1, MIX(IRON[4], g.acc, 0.3))
    g.glowdot(16, 19, 13, strength=0.5)


def s_sun(g, p):
    for k in range(12):
        a = math.radians(k * 30 + 15)
        r1 = 15 if k % 2 == 0 else 11
        g.poly([(16 + math.cos(a - 0.2) * 7, 16 + math.sin(a - 0.2) * 7), (16 + math.cos(a) * r1, 16 + math.sin(a) * r1),
                (16 + math.cos(a + 0.2) * 7, 16 + math.sin(a + 0.2) * 7)], C(g.A[3] if k % 2 == 0 else g.A[2]))
    g.vell((8, 8, 24, 24), g.A)
    g.ell((10, 10, 22, 22), C(g.A[4]))
    g.ell((12, 12, 18, 18), C((255, 255, 250)))
    if p.get("wave"):
        g.arc(16, 16, 14, 0, 360, 1)
    g.glowdot(16, 16, 16, strength=1.0)


def s_star(g, p):
    for k in range(4):
        a = math.radians(k * 90 - 90)
        g.poly([(16 + math.cos(a - 1.2) * 3, 15 + math.sin(a - 1.2) * 3), (16 + math.cos(a) * 14, 15 + math.sin(a) * 14),
                (16 + math.cos(a + 1.2) * 3, 15 + math.sin(a + 1.2) * 3)], C(g.A[3]))
        g.line([(16, 15), (16 + math.cos(a) * 13, 15 + math.sin(a) * 13)], g.A[4])
    for k in range(4):
        a = math.radians(k * 90 - 45)
        g.line([(16, 15), (16 + math.cos(a) * 7, 15 + math.sin(a) * 7)], g.A[2])
    g.ell((13, 12, 19, 18), C((255, 255, 255)))
    g.glowdot(16, 15, 14, strength=1.0)
    if p.get("twinkle"):
        for x, y in ((5, 6), (26, 25), (25, 6), (6, 26)):
            g.spark(x, y)


def s_hourglass(g, p):
    for y in (3, 27):
        g.vpoly([(6, y), (26, y), (26, y + 3), (6, y + 3)], WOODM)
        g.line([(6, y), (26, y)], GOLDM[3])
    for x in (7, 24):
        g.line([(x, 6), (x, 27)], WOODM[1], 2)
    g.poly([(9, 6), (23, 6), (17, 16), (23, 27), (9, 27), (15, 16)], C(GLASS[2], 120))
    g.poly([(11, 9), (21, 9), (16, 15)], C(g.A[2]))  # the sand still above
    g.poly([(10, 26), (22, 26), (16, 20)], C(g.A[2]))
    g.line([(16, 15), (16, 22)], g.A[4])  # the falling grains
    g.line([(10, 8), (13, 13)], C((255, 255, 255, 200)))
    if p.get("hold"):
        for x, y in ((4, 10), (28, 12), (4, 22), (28, 22)):
            g.spark(x, y)
        g.glowdot(16, 16, 14, strength=0.7)
    g.glowdot(16, 22, 7, strength=0.6)


def s_meteor(g, p):
    for k, w in enumerate((9, 6, 3)):  # the burning tail, widening behind
        col = g.A[1 + k]
        g.poly([(13, 13), (30 - k * 2, -2 + k), (31, 2 + k * 2), (19, 20)], C(col, 170 + k * 30)) if k == 0 else \
            g.poly([(13 + k, 14), (29 - k, 0 + k), (30 - k, 3 + k), (17, 19 - k)], C(col))
    g.vell((4, 14, 18, 28), [(30, 20, 20), (58, 40, 36), (88, 64, 56), (120, 92, 80), (150, 120, 104)], 0.1)
    for pts in (((8, 17), (10, 20), (9, 23)), ((13, 19), (15, 22)), ((7, 24), (11, 25))):
        g.line(list(pts), g.A[3])  # magma cracks
    g.d.arc((4, 14, 18, 28), 280, 60, fill=C(g.A[4]), width=2)  # the burning front
    g.glowdot(12, 20, 14, strength=0.9)
    for x, y in ((24, 12), (20, 4), (28, 18), (4, 10)):
        g.spark(x, y)

def s_thorns(g, p):
    for k, (x, h, w) in enumerate(((6, 14, 3), (12, 22, 4), (19, 26, 4), (26, 16, 3), (16, 12, 2))):
        pts = [(x - w, 29), (x, 29 - h), (x + w, 29)]
        g.vpoly(pts, g.A)
        g.line([(x - w, 29), (x, 29 - h)], g.A[4])
        g.p(x, 29 - h, (255, 255, 255))
    g.line([(1, 29), (31, 29)], F(g.A[0], 0.7), 2)
    g.glowdot(16, 20, 13, strength=0.6)
    for x, y in ((9, 6), (25, 8)):
        g.spark(x, y)


def s_chains(g, p):
    brk = p.get("break")
    for k in range(6):
        cx, cy = 5 + k * 4.4, 26 - k * 4.4
        if brk and k == 3:
            for x, y in ((cx - 3, cy - 1), (cx + 3, cy + 1)):
                g.spark(x, y, big=True)
            continue
        if k % 2:
            g.d.ellipse((cx - 3, cy - 2, cx + 3, cy + 2), outline=C(IRON[3]), width=2)
            g.d.arc((cx - 3, cy - 2, cx + 3, cy + 2), 180, 270, fill=C(IRON[4]))
        else:
            g.d.ellipse((cx - 2, cy - 3, cx + 2, cy + 3), outline=C(IRON[2]), width=2)
            g.p(cx - 1, cy - 2, IRON[4])
    g.vpoly([(22, 2), (30, 2), (30, 10), (22, 10)], g.A)  # a glowing seal on the chain
    g.line([(26, 3), (26, 9)], g.A[4])
    g.glowdot(26, 6, 8, strength=0.8)


def s_fist(g, p):
    g.vpoly([(7, 12), (23, 10), (26, 18), (22, 26), (9, 26), (6, 20)], STEEL)  # gauntlet
    for k in range(4):  # knuckle plates
        x = 8 + k * 4
        g.vpoly([(x, 9), (x + 4, 9), (x + 4, 14), (x, 14)], STEEL)
        g.line([(x, 9), (x + 4, 9)], STEEL[4])
    g.vpoly([(3, 15), (9, 13), (10, 20), (5, 21)], STEEL)  # thumb
    g.vpoly([(10, 25), (21, 25), (21, 31), (10, 31)], LEATHER)  # cuff
    g.line([(10, 27), (21, 27)], GOLDM[2])
    if p.get("burst"):
        for k in range(7):
            a = math.radians(-160 + k * 23)
            g.energy([(16 + math.cos(a) * 11, 11 + math.sin(a) * 8), (16 + math.cos(a) * 15, 11 + math.sin(a) * 11)], 1)
    g.glowdot(16, 11, 11, strength=0.7)


def s_figure(g, p):
    if p.get("aura"):
        for k in range(5):
            x = 6 + k * 5
            g.poly([(x - 2, 29), (x, 6 + (k % 2) * 5), (x + 2, 29)], C(g.A[2], 110))
        g.glowdot(16, 18, 15, strength=0.8)
    g.vpoly([(9, 13), (23, 13), (25, 29), (7, 29)], CLOTH)  # cape
    g.vpoly([(11, 12), (21, 12), (20, 24), (12, 24)], STEEL)  # breastplate
    g.line([(16, 13), (16, 23)], STEEL[0])
    g.vpoly([(8, 11), (13, 10), (13, 15), (8, 15)], STEEL)  # pauldrons
    g.vpoly([(19, 10), (24, 11), (24, 15), (19, 15)], STEEL)
    g.vell((12, 3, 20, 12), STEEL)  # helm
    g.line([(13, 8), (19, 8)], (10, 6, 14), 1)  # visor slit
    g.p(14, 8, g.A[4])
    g.p(18, 8, g.A[4])
    g.line([(16, 1), (16, 4)], g.A[2], 2)  # plume
    g.vpoly([(12, 24), (15, 24), (15, 30), (12, 30)], IRON)  # legs
    g.vpoly([(17, 24), (20, 24), (20, 30), (17, 30)], IRON)
    _blade(g, 25, 20, 29, 4, 1, STEEL, fuller=False)  # sword raised
    g.line([(23, 21), (27, 19)], GOLDM[2])
    g.spark(29, 5)


def s_skull(g, p):
    var = p.get("id")
    if var == "executioner":  # a hood over it
        g.vpoly([(5, 4), (16, 1), (27, 4), (29, 22), (3, 22)], CLOTH)
    g.vol(lambda dd: (dd.ellipse((7, 4, 25, 22), fill=FULL), dd.rectangle((10, 17, 22, 27), fill=FULL)), BONEM, 13, 9, 10, 10)
    for ex in (10, 18):  # sockets with a light in them
        g.ell((ex, 12, ex + 5, 17), C((16, 8, 20)))
        g.p(ex + 2, 14, g.A[4])
        g.p(ex + 3, 14, g.A[3])
        g.glowdot(ex + 2.5, 14.5, 4, strength=0.9)
    g.poly([(15, 18), (17, 18), (16, 21)], C((30, 20, 26)))  # nose
    g.line([(11, 23), (21, 23)], BONEM[0])
    for x in range(11, 22, 2):
        g.line([(x, 22), (x, 26)], BONEM[1])  # teeth
    g.line([(19, 6), (21, 10), (20, 13)], BONEM[0])  # a crack
    if var == "assassin":  # a mask over the jaw and crossed daggers behind
        g.vpoly([(9, 19), (23, 19), (22, 27), (10, 27)], CLOTH)
        g.line([(3, 29), (9, 23)], STEEL[3], 2)
        g.line([(29, 29), (23, 23)], STEEL[3], 2)
    elif var == "child_of_dark":  # horns and a dark crown
        for side in (-1, 1):
            g.vpoly([(16 + side * 7, 8), (16 + side * 13, 2), (16 + side * 10, 9)], BONEM)
        g.glowdot(16, 12, 15, strength=0.7)
    elif var == "executioner":
        g.vpoly([(5, 4), (11, 2), (9, 14), (5, 20)], [F(c, 0.8)[:3] for c in CLOTH])
        g.vpoly([(27, 4), (21, 2), (23, 14), (27, 20)], [F(c, 0.8)[:3] for c in CLOTH])
    else:
        g.vell((3, 25, 9, 29), BONEM)  # bones crossed below
        g.vell((23, 25, 29, 29), BONEM)


def _skull_any(g, p):
    s_skull(g, p)


def s_blood(g, p):
    g.vol(lambda dd: (dd.ellipse((8, 11, 24, 28), fill=FULL), dd.polygon([(9, 17), (16, 2), (23, 17)], fill=FULL)),
          [(80, 6, 16), (130, 14, 28), (186, 26, 40), (226, 70, 80), (255, 170, 170)], 13, 15, 8, 10)
    g.ell((11, 15, 14, 19), C((255, 200, 200)))
    g.p(12, 16, (255, 255, 255))
    g.d.arc((8, 11, 24, 28), 0, 90, fill=C(g.A[3]))  # reflected light
    if p.get("splashes"):
        for x, y, r in ((5, 24, 2), (27, 22, 2), (25, 28, 1), (4, 29, 1)):
            g.ell((x - r, y - r, x + r, y + r), C((170, 20, 34)))
            g.p(x - r + 1, y - r + 1, (240, 120, 120))
    g.glowdot(16, 18, 12, strength=0.5)


def s_frenzy(g, p):
    g.vol(lambda dd: dd.ellipse((6, 4, 26, 28), fill=FULL), [(60, 30, 26), (100, 52, 40), (150, 84, 62),
                                                              (190, 120, 90), (220, 160, 130)], 12, 10, 10, 12)
    for side in (-1, 1):  # furrowed brows and eyes burning
        g.line([(16 + side * 2, 12), (16 + side * 8, 9)], (40, 20, 18), 2)
        g.ell((16 + side * 5 - 2, 13, 16 + side * 5 + 2, 16), C(g.A[4]))
        g.glowdot(16 + side * 5, 14.5, 4, strength=1.0)
    g.vpoly([(10, 19), (22, 19), (20, 27), (12, 27)], [(40, 6, 10)] * 5)  # the roaring mouth
    for x in (11, 14, 18, 21):
        g.poly([(x, 19), (x + 1, 22), (x + 2, 19)], C(BONEM[3]))
        g.poly([(x, 27), (x + 1, 24), (x + 2, 27)], C(BONEM[2]))
    for x, y in ((8, 8), (24, 9), (7, 18)):
        g.line([(x, y), (x + 1, y + 3)], (150, 30, 30))  # veins
    for k in range(5):
        a = math.radians(-150 + k * 30)
        g.energy([(16 + math.cos(a) * 13, 16 + math.sin(a) * 13), (16 + math.cos(a) * 16, 16 + math.sin(a) * 16)], 1)


def s_hat(g, p):
    g.vpoly([(16, 1), (24, 22), (8, 22)], CLOTH)
    g.poly([(16, 1), (22, 4), (19, 8)], C(CLOTH[2]))  # the bent tip
    g.vol(lambda dd: dd.ellipse((2, 19, 30, 28), fill=FULL), CLOTH, 12, 21, 14, 4)  # brim
    g.line([(9, 19), (23, 19)], GOLDM[2], 2)  # band
    g.vell((14, 17, 18, 21), g.A)
    for x, y in ((14, 9), (18, 13), (12, 14)):
        g.spark(x, y)
    g.glowdot(16, 12, 12, strength=0.6)


def s_execution(g, p):
    s_axe(g, {"spike": 1})
    g.vpoly([(2, 26), (14, 26), (14, 31), (2, 31)], WOODM)  # the block
    g.line([(2, 26), (14, 26)], (150, 30, 40))


def s_poison_cloud(g, p):
    s_nova(g, p)


SUBJECTS = {k[2:]: v for k, v in list(globals().items()) if k.startswith("s_")}


def outline(im):
    """Dark outline outside the subject; on the shadow side it takes a dark
    tint of what it borders (hand-made pixel art style)."""
    src = im.load()
    out = im.copy()
    o = out.load()
    for y in range(S):
        for x in range(S):
            if src[x, y][3] >= 60:
                continue
            best = None
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < S and 0 <= ny < S and src[nx, ny][3] >= 60:
                    best = (dx, dy, src[nx, ny])
                    if dx < 0 or dy < 0:
                        break
            if best:
                dx, dy, c = best
                if dx < 0 or dy < 0:  # the shape is up/left: a shadow-side edge
                    o[x, y] = (max(14, c[0] // 4), max(9, c[1] // 4), max(20, c[2] // 4), 255)
                else:
                    o[x, y] = INK
    return out
