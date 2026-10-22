#!/usr/bin/env python3
"""Detailed item icon shapes (16x16 pixel art).

Weapons are rasterised along the icon diagonal (handle bottom-left, tip top
right) with a lit edge, a fuller and a shaded edge; armour, jewellery and
potions get volume lit from the top left. Same signatures as the old
placeholder shapes: gen_placeholders.py and gen_items.py import these over
their own versions, so every icon (and the item .tres paths) stays the same.
This module must not import gen_placeholders (it is imported from it).
"""
from __future__ import annotations

import math

from PIL import Image, ImageDraw

OUT = (24, 16, 12, 255)
GOLD = (236, 196, 64, 255)
GOLD_D = (190, 160, 20, 255)
WOOD = (120, 80, 40, 255)
LEATHER = (96, 60, 36, 255)
WHITE = (255, 255, 255, 255)
LIGHT = (-0.55, -0.62, 0.56)

# Diagonal axis: origin at the bottom-left corner, u toward the top right,
# v across (positive = lower right = shadow side).
O = (2.0, 13.0)
DU = (1 / math.sqrt(2), -1 / math.sqrt(2))
DV = (1 / math.sqrt(2), 1 / math.sqrt(2))


def new():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))


def c4(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), c[3] if len(c) > 3 else a)


def sh(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3] if len(c) > 3 else 255)


def uv(x, y):
    px, py = x + 0.5 - O[0], y + 0.5 - O[1]
    return px * DU[0] + py * DU[1], px * DV[0] + py * DV[1]


def axis_fill(im, u0, u1, half, color_fn):
    """Fills pixels with u0 <= u <= u1 and |v - centre(u)| <= half(u)."""
    px = im.load()
    for y in range(16):
        for x in range(16):
            u, v = uv(x, y)
            if u < u0 or u > u1:
                continue
            h = half(u) if callable(half) else half
            if abs(v) <= h:
                c = color_fn(u, v, h)
                if c:
                    px[x, y] = c


def at(u, v=0.0):
    return (O[0] + u * DU[0] + v * DV[0] - 0.5, O[1] + u * DU[1] + v * DV[1] - 0.5)


def metal(base):
    def fn(u, v, h):
        if v < -h * 0.35:
            return sh(base, 1.38)
        if v > h * 0.45:
            return sh(base, 0.66)
        return sh(base, 1.0)
    return fn


def handle(im, u0, u1, wood=WOOD, wrap=None, half=0.75):
    def fn(u, v, h):
        c = wrap if wrap and int(u * 1.4) % 2 == 0 else wood
        return sh(c, 1.25 if v < -0.2 else (0.72 if v > 0.25 else 1.0))
    axis_fill(im, u0, u1, half, fn)


def ellipsoid(im, box, base, mask_fn=None):
    """Fills an ellipse lit from the top left (4 tones, dithered borders)."""
    x0, y0, x1, y1 = box
    cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, max(0.5, (x1 - x0) / 2), max(0.5, (y1 - y0) / 2)
    px = im.load()
    ln = math.sqrt(sum(v * v for v in LIGHT))
    w, h = im.size
    for y in range(max(0, int(y0)), min(h, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(w, int(x1) + 1)):
            nx, ny = (x + 0.5 - cx) / (rx + 0.5), (y + 0.5 - cy) / (ry + 0.5)
            r2 = nx * nx + ny * ny
            if r2 > 1.0 or (mask_fn and not mask_fn(x, y)):
                continue
            nz = math.sqrt(max(0.0, 1 - r2))
            dd = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
            f = 1.32 if dd > 0.72 else (1.08 if dd > 0.4 else (0.86 if dd > 0.05 else 0.66))
            if 0.38 < dd < 0.44 and (x + y) % 2:
                f = 0.86
            px[x, y] = sh(base, f)


def gem(d, x, y, c, big=False):
    if big:
        d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=c4(c))
        d.point((x - 1, y - 1), fill=sh(c, 1.6))
        d.point((x + 1, y + 1), fill=sh(c, 0.6))
    else:
        d.point((x, y), fill=c4(c))
    d.point((x - (1 if big else 0), y - (1 if big else 0)), fill=WHITE if big else sh(c, 1.5))


# ================================================================== weapons
def icon_sword(blade, hilt=(120, 80, 40, 255), guard=GOLD_D):
    im = new()
    tip = 16.2

    def bl(u, v, h):
        if u > tip - 1.4:
            return sh(blade, 1.25) if v <= 0 else sh(blade, 0.8)
        if v < -0.55:
            return sh(blade, 1.4)
        if v > 0.55:
            return sh(blade, 0.68)
        return sh(blade, 0.86) if 6.5 < u < tip - 3 else sh(blade, 1.05)  # fuller

    axis_fill(im, 5.4, tip, lambda u: 1.3 if u < tip - 2.2 else 1.3 * (tip - u) / 2.2 + 0.1, bl)
    handle(im, 1.2, 4.6, hilt, sh(hilt, 0.65), 0.7)
    axis_fill(im, 4.2, 5.4, 3.2, lambda u, v, h: sh(guard, 1.35) if v < -1 else (sh(guard, 0.7) if v > 1.2 else c4(guard)))
    d = ImageDraw.Draw(im)
    p = at(0.6)
    d.point(p, fill=c4(guard))
    g = at(4.8)
    d.point(g, fill=(220, 40, 60, 255))
    t = at(tip - 0.8, -0.3)
    d.point(t, fill=WHITE)
    return im


def icon_dagger(blade):
    im = new()
    tip = 12.4
    axis_fill(im, 5.4, tip, lambda u: 1.05 if u < tip - 2 else 1.05 * (tip - u) / 2 + 0.1,
              lambda u, v, h: sh(blade, 1.4) if v < -0.35 else (sh(blade, 0.68) if v > 0.4 else c4(blade)))
    handle(im, 2.6, 4.8, (90, 60, 30, 255), (60, 40, 22, 255), 0.65)
    axis_fill(im, 4.6, 5.5, 2.3, lambda u, v, h: sh(GOLD_D, 1.3) if v < 0 else sh(GOLD_D, 0.8))
    d = ImageDraw.Draw(im)
    d.point(at(2.1), fill=GOLD)
    d.point(at(tip - 0.7, -0.2), fill=WHITE)
    return im


def icon_saber(blade):
    im = new()
    tip = 16.0
    curve = lambda u: -0.035 * (u - 5.4) * (tip + 2 - u)  # bends up-left
    px = im.load()
    for y in range(16):
        for x in range(16):
            u, v = uv(x, y)
            if 5.4 <= u <= tip:
                vv = v - curve(u)
                h = 1.15 if u < tip - 2.5 else 1.15 * (tip - u) / 2.5 + 0.1
                if abs(vv) <= h:
                    px[x, y] = sh(blade, 1.4) if vv < -0.4 else (sh(blade, 0.68) if vv > 0.45 else c4(blade))
    handle(im, 1.4, 4.6, (100, 60, 30, 255), (70, 40, 20, 255), 0.7)
    d = ImageDraw.Draw(im)
    # knuckle bow
    for k in range(7):
        a = k / 6
        p = at(1.0 + a * 4.0, 1.8 + math.sin(a * math.pi) * 0.8)
        d.point(p, fill=GOLD_D)
    axis_fill(im, 4.6, 5.4, 2.0, lambda u, v, h: sh(GOLD_D, 1.3) if v < 0 else sh(GOLD_D, 0.85))
    d.point(at(tip - 0.8, curve(tip - 0.8) - 0.2), fill=WHITE)
    return im


def icon_axe(head):
    im = new()
    handle(im, 0.3, 14.5, WOOD, None, 0.8)
    px = im.load()
    for y in range(16):
        for x in range(16):
            u, v = uv(x, y)
            if 8.6 <= u <= 14.6:
                edge = 5.2 - 0.32 * (u - 11.6) ** 2  # crescent cutting edge
                if 0.6 <= v <= edge:
                    if v > edge - 1.0:
                        px[x, y] = sh(head, 1.45)
                    elif v < 1.6:
                        px[x, y] = sh(head, 0.7)
                    else:
                        px[x, y] = sh(head, 1.0 if u < 11.6 else 0.85)
                elif -1.9 <= v < -0.6 and 10.4 <= u <= 12.6:
                    px[x, y] = sh(head, 0.9)  # back spike
    d = ImageDraw.Draw(im)
    d.point(at(11.4, 0.9), fill=(200, 200, 210, 255))  # rivet
    d.point(at(1.0), fill=(70, 46, 24, 255))
    return im


def icon_hammer(head):
    im = new()
    handle(im, 0.3, 12.0, WOOD, (80, 50, 30, 255), 0.75)
    axis_fill(im, 10.4, 15.2, 3.4, lambda u, v, h: sh(head, 1.4) if (u > 14.4 or v < -2.6) else (sh(head, 0.66) if (v > 2.6 or u < 11.2) else c4(head)))
    d = ImageDraw.Draw(im)
    for vv in (-1.6, 1.6):
        d.point(at(12.8, vv), fill=sh(head, 1.7))
    d.point(at(12.8), fill=GOLD)
    return im


def icon_staff(gem_c):
    im = new()
    handle(im, 0.0, 12.0, (110, 75, 40, 255), None, 0.75)
    d = ImageDraw.Draw(im)
    for u in (3.0, 7.0):
        d.point(at(u, -0.4), fill=GOLD_D)
        d.point(at(u, 0.4), fill=sh(GOLD_D, 0.7))
    # claws holding the gem
    for vv in (-2.0, 2.0):
        d.line((*at(11.0, vv * 0.5), *at(13.6, vv)), fill=(150, 110, 60, 255))
    c = at(14.2)
    ellipsoid(im, (c[0] - 2, c[1] - 2, c[0] + 2, c[1] + 2), gem_c)
    d.point((c[0] - 1, c[1] - 1), fill=WHITE)
    return im


def icon_wand(gem_c, shaft=(120, 80, 45)):
    im = new()
    handle(im, 0.4, 11.0, c4(shaft), None, 0.55)
    d = ImageDraw.Draw(im)
    d.point(at(9.6), fill=GOLD_D)
    d.point(at(2.0), fill=GOLD_D)
    c = at(13.0)
    cx, cy = c
    d.polygon([(cx, cy - 3), (cx + 2.5, cy), (cx, cy + 3), (cx - 2.5, cy)], fill=c4(gem_c))
    d.polygon([(cx, cy - 3), (cx + 2.5, cy), (cx, cy)], fill=sh(gem_c, 1.35))
    d.polygon([(cx, cy + 3), (cx - 2.5, cy), (cx, cy)], fill=sh(gem_c, 0.7))
    d.point((cx - 1, cy - 1), fill=WHITE)
    return im


def icon_spear(head, shaft=(130, 90, 50, 255), wide=False):
    im = new()
    handle(im, -0.8, 12.0, shaft, None, 0.6)
    w = 2.2 if wide else 1.5
    tip = 16.6
    axis_fill(im, 10.6, tip, lambda u: w * math.sin(min(1.0, (tip - u) / (tip - 10.6)) * math.pi * 0.9) + 0.2,
              lambda u, v, h: sh(head, 1.4) if v < -0.3 else (sh(head, 0.66) if v > 0.4 else c4(head)))
    d = ImageDraw.Draw(im)
    d.point(at(10.6, -0.3), fill=(200, 60, 50, 255))  # tassel
    d.point(at(10.0, 0.9), fill=(200, 60, 50, 255))
    d.point(at(tip - 0.8), fill=WHITE)
    return im


def icon_trident(head):
    im = new()
    handle(im, -0.8, 11.0, (130, 90, 50, 255), None, 0.6)
    axis_fill(im, 10.4, 11.4, 2.6, lambda u, v, h: sh(head, 1.3) if v < 0 else sh(head, 0.8))
    for vv, length in ((-2.2, 14.2), (0.0, 16.2), (2.2, 14.2)):
        axis_fill(im, 11.0, length, lambda u, vv=vv: 0.55, lambda u, v, h, vv=vv: None)
        px = im.load()
        for y in range(16):
            for x in range(16):
                u, v = uv(x, y)
                if 11.0 <= u <= length and abs(v - vv) <= 0.55:
                    px[x, y] = sh(head, 1.35 if v < vv else 0.85)
    d = ImageDraw.Draw(im)
    d.point(at(16.0), fill=WHITE)
    return im


def icon_club(c, spikes=False):
    im = new()
    handle(im, 0.0, 9.0, (110, 75, 40, 255), (80, 52, 30, 255), 0.75)
    cc = at(11.6)
    ellipsoid(im, (cc[0] - 3.5, cc[1] - 3.5, cc[0] + 3.5, cc[1] + 3.5), c)
    d = ImageDraw.Draw(im)
    if spikes:
        for a in range(0, 360, 45):
            r = math.radians(a)
            x, y = cc[0] + math.cos(r) * 4.6, cc[1] + math.sin(r) * 4.6
            d.point((round(x), round(y)), fill=(226, 226, 236, 255))
    else:
        d.point((cc[0] + 1, cc[1] + 1), fill=sh(c, 0.6))  # knot
    return im


def icon_bow(wood, string=(230, 225, 205, 255)):
    im = new()
    d = ImageDraw.Draw(im)
    d.line((8, 1, 8, 14), fill=string)
    for y in range(1, 15):
        t = (y - 7.5) / 6.5
        x = 8 + 4.6 * math.cos(t * math.pi / 2) * 1.0
        f = 1.3 if y < 6 else (1.0 if y < 10 else 0.75)
        d.rectangle((round(x) - 1, y, round(x), y), fill=sh(wood, f))
        d.point((round(x) - 1, y), fill=sh(wood, f * 1.15))
    d.rectangle((11, 6, 12, 9), fill=LEATHER)  # grip
    d.point((11, 6), fill=sh(LEATHER, 1.4))
    for y in (1, 14):
        d.point((8, y), fill=sh(wood, 0.7))
    # nocked arrow
    d.line((3, 8, 11, 8), fill=(150, 110, 70, 255))
    d.point((2, 8), fill=(220, 220, 230, 255))
    d.point((1, 8), fill=(250, 250, 255, 255))
    d.point((10, 7), fill=(230, 70, 60, 255))
    d.point((10, 9), fill=(230, 70, 60, 255))
    return im


def icon_crossbow(wood, metal=(170, 170, 185)):
    im = new()
    d = ImageDraw.Draw(im)
    # stock
    d.rectangle((2, 7, 14, 9), fill=c4(wood))
    d.line((2, 7, 14, 7), fill=sh(wood, 1.3))
    d.line((2, 9, 14, 9), fill=sh(wood, 0.7))
    d.polygon([(11, 9), (14, 9), (14, 12), (12, 12)], fill=sh(wood, 0.8))
    # steel prod
    for y in range(2, 15):
        t = (y - 8) / 6
        x = 5 - 2.2 * math.cos(t * math.pi / 2)
        d.point((round(x), y), fill=sh(metal, 1.35 if y < 8 else 0.85))
        d.point((round(x) + 1, y), fill=sh(metal, 0.7))
    d.line((4, 2, 4, 14), fill=(230, 225, 205, 255))
    d.line((5, 8, 9, 8), fill=(150, 150, 160, 255))  # bolt
    d.point((4, 8), fill=WHITE)
    d.point((12, 10), fill=(200, 200, 210, 255))  # trigger
    return im


# ================================================================== armour
def icon_helmet(c):
    im = new()
    ellipsoid(im, (2, 1, 13, 15), c, lambda x, y: y <= 12)
    d = ImageDraw.Draw(im)
    d.rectangle((7, 1, 8, 9), fill=sh(c, 1.25))  # ridge
    d.point((7, 1), fill=WHITE)
    d.rectangle((2, 9, 13, 10), fill=sh(c, 0.78))  # brim band
    d.line((2, 9, 13, 9), fill=sh(c, 1.15))
    for x in (3, 6, 9, 12):
        d.point((x, 10), fill=sh(c, 1.6))  # rivets
    d.rectangle((2, 11, 4, 13), fill=sh(c, 0.85))  # cheek guards
    d.rectangle((11, 11, 13, 13), fill=sh(c, 0.7))
    d.point((2, 11), fill=sh(c, 1.2))
    d.line((7, 11, 7, 13), fill=sh(c, 0.95))  # nose guard
    d.line((8, 11, 8, 13), fill=sh(c, 0.7))
    return im


def icon_crown(c):
    im = new()
    d = ImageDraw.Draw(im)
    d.polygon([(2, 12), (2, 5), (5, 8), (8, 3), (11, 8), (14, 5), (14, 12)], fill=c4(c))
    d.line((2, 5, 5, 8), fill=sh(c, 1.35))
    d.line((5, 8, 8, 3), fill=sh(c, 1.35))
    d.rectangle((2, 10, 14, 12), fill=sh(c, 0.8))
    d.line((2, 10, 14, 10), fill=sh(c, 1.3))
    for x, y in ((2, 4), (8, 2), (14, 4)):
        d.point((x, y), fill=(255, 250, 210, 255))
    gem(d, 8, 7, (160, 40, 220), True)
    d.point((5, 11), fill=(220, 40, 60, 255))
    d.point((11, 11), fill=(220, 40, 60, 255))
    d.point((8, 11), fill=(60, 200, 255, 255))
    return im


def icon_armor(c):
    im = new()
    pts = [(3, 3), (6, 2), (10, 2), (13, 3), (14, 7), (12, 7), (12, 14), (4, 14), (4, 7), (2, 7)]
    m = new()
    ImageDraw.Draw(m).polygon(pts, fill=WHITE)
    mp = m.load()
    ellipsoid(im, (1, 1, 14, 16), c, lambda x, y: mp[x, y][3] > 0)
    d = ImageDraw.Draw(im)
    d.polygon([(6, 2), (8, 5), (10, 2)], fill=sh(c, 0.55))  # neckline
    d.line((8, 5, 8, 13), fill=sh(c, 0.72))
    for y in (8, 11):
        d.line((5, y, 11, y), fill=sh(c, 0.82))
    d.rectangle((4, 12, 12, 12), fill=(90, 60, 36, 255))  # belt
    d.point((8, 12), fill=GOLD)
    for x, y in ((3, 4), (13, 4)):
        d.point((x, y), fill=sh(c, 1.5))
    return im


def icon_plate(c):
    im = icon_armor(c)
    d = ImageDraw.Draw(im)
    for p in ((5, 4), (11, 4), (5, 10), (11, 10)):
        d.point(p, fill=(250, 240, 200, 255))
    d.line((4, 7, 12, 7), fill=sh(c, 0.6))
    d.line((4, 6, 12, 6), fill=sh(c, 1.3))
    return im


def icon_gloves(c):
    im = new()
    d = ImageDraw.Draw(im)
    ellipsoid(im, (4, 5, 11, 13), c)
    for k, x in enumerate((4, 6, 8, 10)):
        top = 2 if k in (1, 2) else 3
        d.rectangle((x, top, x + 1, 6), fill=sh(c, 1.1))
        d.point((x, top), fill=sh(c, 1.35))
        d.point((x + 1, 6), fill=sh(c, 0.75))
    d.rectangle((11, 7, 13, 9), fill=sh(c, 0.95))  # thumb
    d.point((11, 7), fill=sh(c, 1.3))
    d.rectangle((3, 12, 12, 14), fill=sh(c, 0.7))  # cuff
    d.line((3, 12, 12, 12), fill=sh(c, 1.05))
    d.point((5, 13), fill=GOLD_D)
    d.point((10, 13), fill=GOLD_D)
    return im


def icon_boots(c):
    im = new()
    d = ImageDraw.Draw(im)
    d.rectangle((4, 2, 9, 11), fill=c4(c))
    d.line((4, 2, 4, 11), fill=sh(c, 1.3))
    d.line((9, 3, 9, 10), fill=sh(c, 0.75))
    d.rectangle((4, 2, 9, 3), fill=sh(c, 0.8))  # cuff fold
    d.line((4, 2, 9, 2), fill=sh(c, 1.15))
    ellipsoid(im, (4, 9, 14, 14), c, lambda x, y: y <= 13 and x >= 4)
    d.rectangle((4, 13, 14, 14), fill=(50, 34, 26, 255))  # sole
    d.point((13, 13), fill=(70, 50, 38, 255))
    for y in (5, 7, 9):
        d.point((7, y), fill=(200, 190, 160, 255))  # laces
    d.point((10, 10), fill=sh(c, 1.5))
    return im


def icon_hood(c):
    im = new()
    m = new()
    ImageDraw.Draw(m).polygon([(8, 1), (14, 9), (13, 15), (3, 15), (2, 9)], fill=WHITE)
    mp = m.load()
    ellipsoid(im, (1, 0, 15, 17), c, lambda x, y: mp[x, y][3] > 0)
    d = ImageDraw.Draw(im)
    d.ellipse((5, 7, 11, 13), fill=(24, 16, 18, 255))
    d.arc((5, 7, 11, 13), 200, 340, fill=sh(c, 0.6))
    d.point((7, 10), fill=(200, 160, 120, 255))  # a hint of a face
    d.point((9, 10), fill=(200, 160, 120, 255))
    d.line((3, 14, 13, 14), fill=sh(c, 0.7))
    d.line((8, 2, 10, 5), fill=sh(c, 0.8))  # seam
    return im


def icon_robe(c, trim=(230, 200, 90)):
    im = new()
    m = new()
    ImageDraw.Draw(m).polygon([(5, 2), (11, 2), (13, 15), (3, 15)], fill=WHITE)
    mp = m.load()
    ellipsoid(im, (2, 0, 14, 18), c, lambda x, y: mp[x, y][3] > 0)
    d = ImageDraw.Draw(im)
    d.line((8, 3, 8, 15), fill=c4(trim))
    d.line((3, 15, 13, 15), fill=c4(trim))
    d.polygon([(6, 2), (8, 5), (10, 2)], fill=sh(c, 0.5))
    d.line((5, 8, 11, 8), fill=sh(trim, 0.8))  # sash
    d.point((8, 8), fill=WHITE)
    for x in (5, 11):
        d.line((x, 10, x - (1 if x < 8 else -1), 14), fill=sh(c, 0.7))  # folds
    return im


# ================================================================ jewellery
def icon_ring(gem_c, band=GOLD_D):
    im = new()
    d = ImageDraw.Draw(im)
    d.ellipse((3, 5, 12, 14), outline=c4(band), width=2)
    d.arc((3, 5, 12, 14), 150, 260, fill=sh(band, 1.4))
    d.arc((4, 6, 11, 13), 330, 80, fill=sh(band, 0.6))
    d.rectangle((5, 3, 10, 5), fill=sh(band, 0.9))  # setting
    d.point((5, 3), fill=sh(band, 1.4))
    ellipsoid(im, (6, 1, 9, 4), gem_c)
    d.point((6, 1), fill=WHITE)
    return im


def icon_amulet(gem_c):
    im = new()
    d = ImageDraw.Draw(im)
    chain = (170, 150, 100, 255)
    for k in range(9):
        a = math.radians(200 + k * 17.5)
        x, y = 7.5 + math.cos(a) * 6, 5 + math.sin(a) * 5
        d.point((round(x), round(y)), fill=sh(chain, 1.3 if k % 2 else 0.85))
    d.line((2, 5, 6, 9), fill=chain)
    d.line((13, 5, 9, 9), fill=sh(chain, 0.8))
    d.ellipse((4, 7, 11, 14), fill=GOLD_D)
    d.arc((4, 7, 11, 14), 160, 290, fill=sh(GOLD_D, 1.4))
    ellipsoid(im, (5, 8, 10, 13), gem_c)
    d.point((6, 9), fill=WHITE)
    return im


# ================================================================ potions
def icon_potion(liquid):
    im = new()
    d = ImageDraw.Draw(im)
    glass = (206, 228, 240, 150)
    # cork with a string, neck, round flask
    d.rectangle((6, 0, 9, 2), fill=(150, 100, 56, 255))
    d.line((6, 0, 9, 0), fill=(190, 140, 90, 255))
    d.point((9, 2), fill=(110, 70, 40, 255))
    d.rectangle((6, 3, 9, 5), fill=glass)
    d.line((5, 3, 10, 3), fill=(230, 240, 250, 200))  # lip
    d.ellipse((2, 5, 13, 15), fill=glass)
    ellipsoid(im, (3, 7, 12, 15), liquid, lambda x, y: y >= 9)
    d.line((4, 9, 11, 9), fill=sh(liquid, 1.45))  # surface
    d.point((6, 12), fill=sh(liquid, 1.6))  # bubbles
    d.point((9, 11), fill=sh(liquid, 1.5))
    d.point((4, 7), fill=WHITE)  # glass glint
    d.point((4, 8), fill=(255, 255, 255, 200))
    d.point((11, 13), fill=(255, 255, 255, 120))
    return im


def icon_bomb(body, spark=(255, 200, 60)):
    im = new()
    ellipsoid(im, (3, 5, 13, 15), body)
    d = ImageDraw.Draw(im)
    d.rectangle((7, 3, 10, 5), fill=(90, 90, 100, 255))
    d.line((7, 3, 10, 3), fill=(150, 150, 160, 255))
    d.line((9, 3, 11, 1), fill=(170, 140, 90, 255))
    d.point((12, 0), fill=c4(spark))
    d.point((13, 1), fill=(255, 250, 200, 255))
    d.point((11, 0), fill=(255, 120, 40, 255))
    d.point((5, 7), fill=WHITE)
    return im
