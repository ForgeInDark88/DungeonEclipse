#!/usr/bin/env python3
"""Generates placeholder pixel-art for DungeonEclipse.

Run from the project root:  python3 tools/gen_placeholders.py
Every PNG written here can be replaced by real art with the same file name
(see README, section "Assets"). Requires Pillow.
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")

OUT = (24, 16, 12, 255)
LEATHER = (79, 48, 31, 255)
LEATHER_D = (52, 31, 20, 255)
LEATHER_L = (110, 70, 44, 255)
PARCH = (246, 216, 150, 255)
PARCH_D = (202, 177, 123, 255)
PARCH_DD = (170, 145, 98, 255)
GOLD = (244, 234, 17, 255)
GOLD_D = (190, 160, 20, 255)


def new(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def outline(img: Image.Image, color=OUT) -> Image.Image:
    """Adds a 1px dark outline around every opaque pixel."""
    w, h = img.size
    src = img.load()
    res = img.copy()
    dst = res.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                    dst[x, y] = color
                    break
    return res


def save(img: Image.Image, rel: str, do_outline: bool = True) -> None:
    path = os.path.join(A, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (outline(img) if do_outline else img).save(path)


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


# --------------------------------------------------------------------- items
def icon_sword(blade, hilt=(120, 80, 40, 255), guard=GOLD_D):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    for i in range(9):
        d.point((5 + i, 10 - i), fill=blade)
        d.point((6 + i, 10 - i), fill=shade(blade, 0.75))
    d.line((3, 9, 7, 13), fill=guard)
    d.line((2, 13, 4, 11), fill=hilt)
    d.point((1, 14), fill=guard)
    return im


def icon_dagger(blade):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    for i in range(6):
        d.point((7 + i, 8 - i), fill=blade)
        d.point((8 + i, 8 - i), fill=shade(blade, 0.7))
    d.line((5, 7, 8, 10), fill=GOLD_D)
    d.line((4, 11, 6, 9), fill=(90, 60, 30, 255))
    return im


def icon_axe(head):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.line((3, 14, 11, 4), fill=(120, 80, 40, 255), width=2)
    d.polygon([(9, 2), (14, 3), (14, 9), (11, 6)], fill=head)
    d.line((14, 3, 14, 9), fill=shade(head, 1.3))
    return im


def icon_staff(gem):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.line((3, 14, 11, 6), fill=(110, 75, 40, 255), width=2)
    d.ellipse((10, 1, 14, 5), fill=gem)
    d.point((11, 2), fill=(255, 255, 255, 255))
    return im


def icon_helmet(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.pieslice((2, 3, 13, 16), 180, 360, fill=c)
    d.rectangle((2, 9, 13, 11), fill=shade(c, 0.8))
    d.rectangle((7, 4, 8, 11), fill=shade(c, 1.25))
    return im


def icon_crown(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(2, 12), (2, 5), (5, 8), (8, 3), (11, 8), (14, 5), (14, 12)], fill=c)
    d.point((8, 9), fill=(160, 40, 220, 255))
    d.point((5, 10), fill=(220, 40, 60, 255))
    d.point((11, 10), fill=(220, 40, 60, 255))
    return im


def icon_armor(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(3, 3), (6, 2), (10, 2), (13, 3), (14, 7), (12, 7), (12, 14), (4, 14), (4, 7), (2, 7)], fill=c)
    d.line((8, 3, 8, 13), fill=shade(c, 0.75))
    d.line((5, 9, 11, 9), fill=shade(c, 1.2))
    return im


def icon_gloves(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((4, 6, 11, 13), fill=c)
    for x in (4, 6, 8, 10):
        d.rectangle((x, 2, x + 1, 6), fill=c)
    d.rectangle((11, 7, 13, 9), fill=c)
    d.rectangle((4, 12, 11, 13), fill=shade(c, 0.7))
    return im


def icon_boots(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((4, 2, 9, 11), fill=c)
    d.rectangle((4, 10, 13, 13), fill=c)
    d.rectangle((4, 13, 13, 13), fill=shade(c, 0.6))
    d.line((4, 4, 9, 4), fill=shade(c, 1.3))
    return im


def icon_ring(gem, band=GOLD_D):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((3, 5, 12, 14), outline=band, width=2)
    d.rectangle((6, 2, 9, 5), fill=gem)
    d.point((7, 3), fill=(255, 255, 255, 255))
    return im


def icon_amulet(gem):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.arc((2, 0, 13, 10), 20, 160, fill=(150, 130, 90, 255))
    d.line((3, 3, 7, 9), fill=(150, 130, 90, 255))
    d.line((12, 3, 8, 9), fill=(150, 130, 90, 255))
    d.ellipse((5, 8, 10, 13), fill=gem)
    d.point((6, 9), fill=(255, 255, 255, 255))
    return im


def icon_potion(liquid):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((6, 1, 9, 3), fill=(140, 90, 50, 255))
    d.rectangle((6, 4, 9, 5), fill=(200, 220, 230, 160))
    d.ellipse((3, 5, 12, 14), fill=(200, 220, 230, 160))
    d.ellipse((4, 8, 11, 14), fill=liquid)
    d.point((5, 7), fill=(255, 255, 255, 255))
    return im


def icon_crystal(c=(40, 200, 210, 255)):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(3, 10), (5, 5), (8, 7), (8, 13), (4, 13)], fill=shade(c, 0.8))
    d.polygon([(7, 13), (7, 4), (10, 1), (12, 5), (12, 13)], fill=c)
    d.polygon([(11, 13), (11, 8), (13, 7), (14, 12)], fill=shade(c, 0.65))
    d.line((9, 3, 9, 11), fill=shade(c, 1.4))
    return im


def icon_bomb():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((2, 4, 13, 15), fill=(40, 40, 48, 255))
    d.ellipse((4, 6, 7, 9), fill=(90, 90, 100, 255))
    d.line((10, 5, 12, 2), fill=(150, 110, 60, 255))
    d.point((13, 1), fill=(255, 200, 40, 255))
    return im


def icon_rope():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    c = (170, 120, 60, 255)
    d.ellipse((2, 3, 13, 14), outline=c, width=2)
    d.ellipse((5, 6, 10, 11), outline=shade(c, 0.8), width=1)
    d.line((11, 12, 14, 15), fill=c)
    return im


def icon_key():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((1, 1, 7, 7), outline=GOLD_D, width=2)
    d.line((6, 6, 13, 13), fill=GOLD_D, width=2)
    d.line((10, 12, 12, 10), fill=GOLD_D)
    d.line((12, 14, 14, 12), fill=GOLD_D)
    return im


def icon_pickaxe():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.line((3, 14, 10, 5), fill=(130, 85, 45, 255), width=2)
    d.arc((2, 1, 16, 14), 200, 330, fill=(170, 175, 185, 255), width=2)
    return im


def icon_coin():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((3, 3, 12, 12), fill=GOLD)
    d.ellipse((5, 5, 10, 10), outline=GOLD_D)
    return im


def icon_bone():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    c = (230, 225, 205, 255)
    d.line((4, 11, 11, 4), fill=c, width=2)
    for p in ((3, 10), (5, 12), (10, 3), (12, 5)):
        d.ellipse((p[0] - 1, p[1] - 1, p[0] + 1, p[1] + 1), fill=c)
    return im


def icon_ore():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(2, 12), (4, 5), (9, 3), (14, 7), (13, 13)], fill=(90, 85, 90, 255))
    for p in ((6, 7), (9, 10), (11, 6)):
        d.rectangle((p[0], p[1], p[0] + 1, p[1] + 1), fill=(200, 140, 90, 255))
    return im


def icon_spear(head, shaft=(130, 90, 50, 255), wide=False):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.line((1, 15, 11, 5), fill=shaft, width=1)
    d.line((2, 15, 12, 5), fill=shade(shaft, 0.8), width=1)
    if wide:
        d.polygon([(10, 3), (15, 0), (13, 6), (12, 8), (9, 6)], fill=head)
    else:
        d.polygon([(11, 3), (15, 0), (13, 5), (12, 6)], fill=head)
    return im


def icon_bow(wood, string=(230, 225, 205, 255)):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.arc((2, 1, 13, 14), 280, 80, fill=wood, width=2)
    d.line((8, 1, 8, 14), fill=string)
    d.point((8, 7), fill=GOLD_D)
    return im


def icon_club(c, spikes=False):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.line((2, 14, 8, 8), fill=(110, 75, 40, 255), width=2)
    d.ellipse((7, 2, 14, 9), fill=c)
    if spikes:
        for p in ((10, 1), (15, 5), (11, 10), (6, 5)):
            d.point(p, fill=(220, 220, 230, 255))
    return im


def icon_scroll():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((3, 3, 12, 12), fill=(230, 210, 160, 255))
    d.rectangle((2, 2, 13, 4), fill=(180, 150, 100, 255))
    d.rectangle((2, 11, 13, 13), fill=(180, 150, 100, 255))
    d.line((5, 6, 9, 8), fill=(150, 60, 50, 255))
    d.line((9, 8, 7, 10), fill=(150, 60, 50, 255))
    d.point((10, 6), fill=(150, 60, 50, 255))
    return im


def icon_whetstone():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(2, 10), (11, 4), (14, 7), (5, 13)], fill=(120, 125, 135, 255))
    d.line((3, 10, 11, 5), fill=(170, 175, 185, 255))
    d.point((12, 3), fill=(255, 255, 220, 255))
    return im


# -------------------------------------------------------------------- skills
def skill_bg(glow):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    for r in range(8, 0, -1):
        f = r / 8
        c = (int(glow[0] * (1 - f) + 20 * f), int(glow[1] * (1 - f) + 14 * f), int(glow[2] * (1 - f) + 10 * f), 255)
        d.ellipse((8 - r, 8 - r, 7 + r, 7 + r), fill=c)
    return im


def compose(bg, fg, dx=0, dy=0):
    res = bg.copy()
    res.alpha_composite(outline(fg), (dx, dy))
    return res


def skill_explosion(c1=(255, 90, 20, 255), c2=(255, 230, 90, 255)):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(16):
        r = 7 if i % 2 == 0 else 3
        a = i * math.pi / 8
        pts.append((8 + r * math.cos(a), 8 + r * math.sin(a)))
    d.polygon(pts, fill=c1)
    d.ellipse((6, 6, 10, 10), fill=c2)
    return im


def skill_shield(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(3, 2), (13, 2), (13, 8), (8, 14), (3, 8)], fill=c)
    d.rectangle((7, 4, 8, 10), fill=(240, 255, 240, 255))
    d.rectangle((5, 6, 10, 7), fill=(240, 255, 240, 255))
    return im


def skill_projectile(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.polygon([(2, 12), (9, 6), (11, 8)], fill=shade(c, 0.6))
    d.ellipse((7, 2, 14, 9), fill=c)
    d.ellipse((9, 4, 12, 7), fill=(255, 250, 200, 255))
    return im


def skill_blink(c):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.arc((2, 2, 14, 14), 0, 270, fill=c, width=2)
    d.arc((5, 5, 11, 11), 90, 360, fill=shade(c, 1.4), width=1)
    d.point((8, 8), fill=(255, 255, 255, 255))
    return im


def skill_knives():
    im = new(16, 16)
    for dy in (0, 4):
        im.alpha_composite(icon_dagger((210, 215, 225, 255)), (1, dy - 2))
    return im


def skill_smoke():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    for (x, y, r) in ((5, 9, 4), (10, 8, 4), (8, 5, 3), (8, 11, 3)):
        d.ellipse((x - r, y - r, x + r, y + r), fill=(140, 140, 150, 255))
    d.ellipse((6, 7, 9, 10), fill=(190, 190, 200, 255))
    return im


# --------------------------------------------------------------------- tiles
def tile_noise(base, seed, var=0.12):
    rnd = random.Random(seed)
    im = new(16, 16)
    px = im.load()
    for y in range(16):
        for x in range(16):
            px[x, y] = shade(base, 1 + rnd.uniform(-var, var))
    return im


def tile_bedrock():
    im = tile_noise((46, 42, 52, 255), 1)
    d = ImageDraw.Draw(im)
    d.line((0, 0, 15, 0), fill=(70, 66, 78, 255))
    d.line((3, 6, 7, 9), fill=(30, 27, 34, 255))
    d.line((10, 11, 13, 13), fill=(30, 27, 34, 255))
    return im


def tile_brick():
    im = tile_noise((92, 70, 58, 255), 2)
    d = ImageDraw.Draw(im)
    m = (50, 36, 30, 255)
    for y in (0, 5, 10, 15):
        d.line((0, y, 15, y), fill=m)
    for y0, xs in ((0, (4, 12)), (5, (0, 8)), (10, (4, 12))):
        for x in xs:
            d.line((x, y0, x, y0 + 5), fill=m)
    d.line((1, 1, 3, 1), fill=(125, 98, 80, 255))
    return im


def tile_platform():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 4), fill=(120, 82, 48, 255))
    d.line((0, 0, 15, 0), fill=(165, 120, 72, 255))
    d.line((0, 4, 15, 4), fill=(70, 46, 28, 255))
    d.point((3, 2), fill=(70, 46, 28, 255))
    d.point((12, 2), fill=(70, 46, 28, 255))
    d.line((2, 5, 2, 8), fill=(70, 46, 28, 255))
    d.line((13, 5, 13, 8), fill=(70, 46, 28, 255))
    return im


def tile_ladder():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    c = (150, 104, 60, 255)
    d.line((3, 0, 3, 15), fill=c, width=2)
    d.line((12, 0, 12, 15), fill=c, width=2)
    for y in (2, 7, 12):
        d.line((3, y, 12, y), fill=shade(c, 0.85), width=2)
    return im


def tile_backwall():
    im = tile_noise((34, 28, 32, 255), 5, 0.08)
    d = ImageDraw.Draw(im)
    m = (24, 19, 22, 255)
    for y in (7, 15):
        d.line((0, y, 15, y), fill=m)
    d.line((7, 0, 7, 7), fill=m)
    d.line((15, 8, 15, 15), fill=m)
    return im


# ------------------------------------------------------------------- actors
def char_sprite(body, head_skin, accent, hat=None):
    im = new(14, 22)
    d = ImageDraw.Draw(im)
    d.rectangle((4, 3, 9, 8), fill=head_skin)  # head
    d.point((8, 5), fill=(20, 20, 20, 255))
    d.rectangle((3, 9, 10, 16), fill=body)  # body
    d.rectangle((3, 13, 10, 13), fill=accent)  # belt
    d.rectangle((4, 17, 5, 21), fill=shade(body, 0.6))
    d.rectangle((8, 17, 9, 21), fill=shade(body, 0.6))
    if hat == "helm":
        d.rectangle((3, 1, 10, 4), fill=(150, 155, 165, 255))
    elif hat == "hood":
        d.polygon([(3, 5), (6, 0), (10, 2), (10, 5)], fill=accent)
    elif hat == "wizard":
        d.polygon([(2, 4), (11, 4), (8, 0), (6, -1)], fill=accent)
    return im


def slime():
    im = new(16, 12)
    d = ImageDraw.Draw(im)
    d.pieslice((0, 1, 15, 22), 180, 360, fill=(70, 190, 80, 255))
    d.rectangle((0, 10, 15, 11), fill=(50, 150, 60, 255))
    d.point((5, 6), fill=(10, 30, 10, 255))
    d.point((10, 6), fill=(10, 30, 10, 255))
    d.point((4, 3), fill=(180, 255, 190, 255))
    return im


def skeleton():
    im = new(14, 22)
    d = ImageDraw.Draw(im)
    b = (225, 220, 200, 255)
    d.rectangle((4, 1, 9, 6), fill=b)
    d.point((5, 3), fill=(30, 0, 0, 255))
    d.point((8, 3), fill=(30, 0, 0, 255))
    d.line((6, 7, 6, 15), fill=b, width=2)
    for y in (9, 11, 13):
        d.line((4, y, 9, y), fill=b)
    d.line((5, 15, 4, 21), fill=b)
    d.line((8, 15, 9, 21), fill=b)
    d.line((3, 9, 2, 14), fill=b)
    d.line((10, 9, 11, 14), fill=b)
    return im


def bat():
    im = new(16, 10)
    d = ImageDraw.Draw(im)
    c = (90, 60, 110, 255)
    d.polygon([(0, 2), (6, 4), (8, 8), (10, 4), (15, 2), (12, 7), (8, 9), (4, 7)], fill=c)
    d.ellipse((6, 3, 10, 7), fill=shade(c, 1.2))
    d.point((7, 4), fill=(255, 60, 60, 255))
    d.point((9, 4), fill=(255, 60, 60, 255))
    return im


def cultist():
    im = new(14, 22)
    d = ImageDraw.Draw(im)
    robe = (110, 25, 40, 255)
    d.polygon([(3, 8), (10, 8), (12, 21), (1, 21)], fill=robe)
    d.polygon([(3, 7), (6, 0), (10, 2), (11, 8)], fill=shade(robe, 0.8))
    d.rectangle((5, 4, 9, 7), fill=(20, 10, 15, 255))
    d.point((6, 5), fill=(255, 200, 40, 255))
    d.point((8, 5), fill=(255, 200, 40, 255))
    return im


def chest(body, trim, open_=False):
    im = new(16, 14)
    d = ImageDraw.Draw(im)
    if open_:
        d.rectangle((1, 0, 14, 4), fill=shade(body, 0.7))
        d.rectangle((2, 5, 13, 7), fill=(20, 12, 8, 255))
    else:
        d.rectangle((1, 2, 14, 7), fill=shade(body, 1.15))
    d.rectangle((1, 7, 14, 13), fill=body)
    d.line((1, 7, 14, 7), fill=trim)
    d.line((1, 13, 14, 13), fill=trim)
    d.rectangle((7, 6, 8, 9), fill=trim)
    return im


def door():
    im = new(20, 32)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 19, 31), fill=(60, 56, 66, 255))
    d.rectangle((3, 4, 16, 31), fill=(12, 8, 18, 255))
    d.pieslice((3, 0, 16, 10), 180, 360, fill=(12, 8, 18, 255))
    for y in range(8, 31, 3):
        d.line((4, y, 15, y), fill=(60, 20, 90, 255 - y * 5))
    d.point((9, 12), fill=(200, 120, 255, 255))
    return im


def projectile(c, w=8, h=4):
    im = new(w, h)
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, w - 1, h - 1), fill=c)
    d.ellipse((w // 2, 1, w - 2, h - 2), fill=(255, 255, 230, 255))
    return im


def light_tex(size=256):
    im = new(size, size)
    px = im.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c, y - c) / c
            a = max(0.0, 1 - r) ** 1.6
            px[x, y] = (255, 255, 255, int(a * 255))
    return im


# --------------------------------------------------------------- portraits
def portrait_face(skin, beard=None, ears=False, hair=(70, 45, 30, 255)):
    im = new(32, 32)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 24, 31, 31), fill=(70, 55, 45, 255))  # shoulders
    d.ellipse((8, 6, 23, 24), fill=skin)
    if ears:
        d.polygon([(8, 13), (3, 9), (9, 17)], fill=skin)
        d.polygon([(23, 13), (28, 9), (22, 17)], fill=skin)
    d.rectangle((11, 13, 13, 14), fill=(255, 255, 255, 255))
    d.rectangle((18, 13, 20, 14), fill=(255, 255, 255, 255))
    d.point((12, 14), fill=(30, 20, 20, 255))
    d.point((19, 14), fill=(30, 20, 20, 255))
    d.line((14, 18, 17, 18), fill=shade(skin, 0.7))
    d.arc((8, 4, 23, 16), 180, 360, fill=hair, width=3)
    if skin[1] > skin[0]:  # green skin: orc tusks
        d.rectangle((12, 19, 13, 21), fill=(240, 240, 220, 255))
        d.rectangle((18, 19, 19, 21), fill=(240, 240, 220, 255))
    if beard:
        d.polygon([(8, 16), (23, 16), (21, 27), (16, 30), (10, 27)], fill=beard)
        d.line((13, 20, 18, 20), fill=shade(skin, 0.6))
    return im


def portrait_overlay(kind, c):
    im = new(32, 32)
    d = ImageDraw.Draw(im)
    if kind == "warrior":
        d.pieslice((7, 1, 24, 20), 180, 360, fill=c)
        d.rectangle((7, 9, 24, 11), fill=shade(c, 0.8))
        d.rectangle((15, 2, 16, 15), fill=shade(c, 1.2))
        d.rectangle((0, 25, 31, 31), fill=shade(c, 0.9))
        d.ellipse((13, 3, 18, 7), fill=(255, 240, 160, 255))  # miner lamp
    elif kind == "rogue":
        d.polygon([(5, 22), (7, 6), (16, 1), (25, 6), (27, 22), (23, 22), (22, 9), (10, 9), (9, 22)], fill=c)
        d.rectangle((0, 25, 31, 31), fill=shade(c, 0.85))
        d.rectangle((9, 19, 22, 23), fill=shade(c, 0.6))
    elif kind == "mage":
        d.polygon([(4, 10), (28, 10), (19, 0), (14, -2)], fill=c)
        d.rectangle((6, 9, 25, 11), fill=shade(c, 0.7))
        d.point((17, 5), fill=GOLD)
        d.rectangle((0, 25, 31, 31), fill=shade(c, 0.9))
    return im


# ----------------------------------------------------------------------- UI
def book_panel():
    """Book cover + one page without the spine: base texture for the HUD."""
    book = Image.open(os.path.join(A, "ui", "book.png")).convert("RGBA")
    w, h = book.size
    half = book.crop((0, 0, 128, h))
    res = new(256, h)
    res.alpha_composite(half, (0, 0))
    res.alpha_composite(half.transpose(Image.FLIP_LEFT_RIGHT), (128, 0))
    return res


def slot_tex():
    im = new(24, 24)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 23, 23), fill=LEATHER_D)
    d.rectangle((1, 1, 22, 22), fill=LEATHER)
    d.rectangle((3, 3, 20, 20), fill=PARCH_DD)
    d.rectangle((4, 4, 20, 20), fill=PARCH_D)
    d.line((4, 4, 19, 4), fill=PARCH_DD)
    d.line((4, 4, 4, 19), fill=PARCH_DD)
    for (x, y) in ((1, 1), (21, 1), (1, 21), (21, 21)):
        d.rectangle((x, y, x + 1, y + 1), fill=GOLD)
    return im


def slot_dark_tex():
    """Empty-slot variant: slightly darker parchment."""
    im = slot_tex()
    d = ImageDraw.Draw(im)
    d.rectangle((4, 4, 20, 20), fill=PARCH_DD)
    return im


def slot_hover_tex():
    im = slot_tex()
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 23, 23), outline=GOLD)
    return im


def bar_frame():
    im = new(16, 8)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 7), fill=LEATHER_D)
    d.rectangle((1, 1, 14, 6), fill=LEATHER)
    d.rectangle((2, 2, 13, 5), fill=(30, 20, 14, 255))
    d.point((1, 1), fill=GOLD)
    d.point((14, 1), fill=GOLD)
    d.point((1, 6), fill=GOLD)
    d.point((14, 6), fill=GOLD)
    return im


def bar_fill(c):
    im = new(4, 4)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 3, 3), fill=c)
    d.line((0, 0, 3, 0), fill=shade(c, 1.35))
    d.line((0, 3, 3, 3), fill=shade(c, 0.7))
    return im


def dot(c):
    im = new(4, 4)
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, 3, 3), fill=c)
    return im


def tooltip_tex():
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 15), fill=LEATHER_D)
    d.rectangle((1, 1, 14, 14), fill=LEATHER)
    d.rectangle((3, 3, 12, 12), fill=PARCH)
    for (x, y) in ((1, 1), (13, 1), (1, 13), (13, 13)):
        d.rectangle((x, y, x + 1, y + 1), fill=GOLD)
    return im


def button_tex(fill):
    im = new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 15), fill=LEATHER_D)
    d.rectangle((1, 1, 14, 14), fill=LEATHER)
    d.rectangle((3, 3, 12, 12), fill=fill)
    for (x, y) in ((1, 1), (13, 1), (1, 13), (13, 13)):
        d.point((x, y), fill=GOLD)
    return im


def doll():
    """Silhouette drawn on the left page of the inventory book."""
    im = new(40, 64)
    d = ImageDraw.Draw(im)
    c = (190, 160, 110, 255)
    d.ellipse((13, 2, 26, 15), fill=c)
    d.polygon([(10, 17), (29, 17), (33, 38), (28, 38), (27, 30), (26, 40), (13, 40), (12, 30), (11, 38), (6, 38)], fill=c)
    d.rectangle((13, 40, 18, 62), fill=c)
    d.rectangle((21, 40, 26, 62), fill=c)
    return im


def main() -> None:
    items = {
        "rusty_sword": icon_sword((150, 120, 100, 255)),
        "iron_sword": icon_sword((200, 205, 215, 255)),
        "eclipse_blade": icon_sword((150, 80, 230, 255), guard=GOLD),
        "dagger": icon_dagger((200, 205, 215, 255)),
        "shadow_dagger": icon_dagger((120, 90, 200, 255)),
        "war_axe": icon_axe((180, 185, 195, 255)),
        "oak_staff": icon_staff((90, 160, 255, 255)),
        "arcane_staff": icon_staff((220, 80, 255, 255)),
        "leather_cap": icon_helmet((140, 95, 55, 255)),
        "iron_helm": icon_helmet((165, 170, 180, 255)),
        "crown_of_shadows": icon_crown((200, 170, 40, 255)),
        "leather_armor": icon_armor((140, 95, 55, 255)),
        "chainmail": icon_armor((160, 165, 175, 255)),
        "mage_robe": icon_armor((80, 60, 160, 255)),
        "leather_gloves": icon_gloves((140, 95, 55, 255)),
        "gauntlets": icon_gloves((165, 170, 180, 255)),
        "leather_boots": icon_boots((120, 80, 45, 255)),
        "swift_boots": icon_boots((70, 140, 200, 255)),
        "copper_ring": icon_ring((60, 200, 120, 255), band=(190, 110, 60, 255)),
        "ruby_ring": icon_ring((230, 40, 60, 255)),
        "eclipse_ring": icon_ring((150, 60, 240, 255)),
        "bone_amulet": icon_amulet((230, 225, 205, 255)),
        "moon_amulet": icon_amulet((150, 210, 255, 255)),
        "health_potion": icon_potion((200, 30, 40, 255)),
        "big_health_potion": icon_potion((255, 60, 90, 255)),
        "mana_crystal": icon_crystal(),
        "bomb": icon_bomb(),
        "rope": icon_rope(),
        "key": icon_key(),
        "gold_coin": icon_coin(),
        "bone": icon_bone(),
        "iron_ore": icon_ore(),
        # stage 12 weapons
        "knight_sword": icon_sword((220, 225, 240, 255), guard=(60, 90, 200, 255)),
        "hatchet": icon_axe((150, 150, 160, 255)),
        "executioner_axe": icon_axe((90, 20, 30, 255)),
        "wooden_spear": icon_spear((170, 170, 180, 255)),
        "glaive": icon_spear((200, 210, 230, 255), wide=True),
        "venom_fang": icon_dagger((90, 220, 80, 255)),
        "short_bow": icon_bow((140, 95, 50, 255)),
        "hunter_bow": icon_bow((90, 60, 35, 255)),
        "ember_staff": icon_staff((255, 120, 30, 255)),
        "club": icon_club((120, 85, 45, 255)),
        "morning_star": icon_club((150, 155, 165, 255), spikes=True),
        "whetstone": icon_whetstone(),
        # stage 15 potions
        "antidote": icon_potion((90, 210, 80, 255)),
        "regen_potion": icon_potion((240, 120, 170, 255)),
        "shield_elixir": icon_potion((90, 140, 255, 255)),
        "map_scroll": icon_scroll(),
    }
    for name, im in items.items():
        save(im, f"sprites/items/{name}.png")

    gold_bg = skill_bg((255, 160, 30))
    skills = {
        "haste": compose(gold_bg, icon_boots((150, 95, 50, 255))),
        "power_strike": compose(skill_bg((200, 200, 220)), icon_pickaxe()),
        "earthquake": compose(skill_bg((120, 40, 10)), skill_explosion(), 0, 0),
        "iron_skin": compose(skill_bg((40, 140, 50)), skill_shield((50, 170, 60, 255))),
        "dash": compose(skill_bg((90, 140, 220)), icon_boots((90, 90, 110, 255))),
        "throw_knives": compose(skill_bg((150, 150, 170)), skill_knives()),
        "smoke_bomb": compose(skill_bg((70, 70, 90)), skill_smoke()),
        "evasion": compose(skill_bg((40, 160, 120)), skill_shield((60, 180, 160, 255))),
        "fireball": compose(skill_bg((200, 70, 10)), skill_projectile((255, 110, 20, 255))),
        "frost_nova": compose(skill_bg((40, 100, 200)), skill_explosion((90, 170, 255, 255), (230, 250, 255, 255))),
        "arcane_shield": compose(skill_bg((60, 60, 200)), skill_shield((90, 110, 255, 255))),
        "blink": compose(skill_bg((120, 40, 180)), skill_blink((200, 120, 255, 255))),
        # stage 15.11: skill trees (passives on dark backgrounds)
        "toughness": compose(skill_bg((60, 50, 40)), icon_armor((170, 120, 70, 255))),
        "blade_master": compose(skill_bg((70, 60, 50)), icon_sword((220, 225, 240, 255))),
        "bloodletting": compose(skill_bg((90, 20, 25)), icon_axe((200, 40, 50, 255))),
        "war_cry": compose(skill_bg((230, 200, 60)), skill_explosion((255, 220, 80, 255), (255, 255, 220, 255))),
        "keen_eye": compose(skill_bg((50, 60, 50)), icon_bow((120, 80, 40, 255))),
        "venom_blades": compose(skill_bg((40, 80, 30)), icon_dagger((90, 220, 80, 255))),
        "knife_fan": compose(skill_bg((180, 60, 60)), skill_knives()),
        "shadow_step": compose(skill_bg((40, 35, 60)), icon_boots((60, 50, 90, 255))),
        "arcane_mind": compose(skill_bg((40, 40, 80)), icon_crystal((120, 140, 255, 255))),
        "chain_lightning": compose(skill_bg((150, 100, 255)), skill_projectile((230, 210, 255, 255))),
        "meteor": compose(skill_bg((160, 40, 10)), skill_explosion((255, 60, 10, 255), (255, 200, 60, 255))),
        "elemental_ward": compose(skill_bg((50, 70, 80)), skill_shield((240, 140, 60, 255))),
        "blessing": compose(skill_bg((80, 70, 40)), icon_armor((235, 215, 150, 255))),
        "holy_strike": compose(skill_bg((255, 230, 140)), icon_club((230, 230, 240, 255), spikes=True)),
        "light_aura": compose(skill_bg((70, 70, 40)), skill_shield((255, 240, 160, 255))),
        "righteous_wrath": compose(skill_bg((255, 240, 180)), skill_explosion((255, 240, 150, 255), (255, 255, 255, 255))),
    }
    for name, im in skills.items():
        save(im, f"sprites/skills/{name}.png", do_outline=False)

    # Tilesets are per biome now: see gen_biomes.py (sprites/tiles/tiles_<biome>.png).

    save(char_sprite((140, 40, 40, 255), (230, 190, 150, 255), (90, 60, 30, 255), "helm"), "sprites/player/warrior.png")
    save(char_sprite((50, 90, 50, 255), (230, 190, 150, 255), (40, 60, 40, 255), "hood"), "sprites/player/rogue.png")
    save(char_sprite((60, 50, 140, 255), (230, 190, 150, 255), (80, 60, 170, 255), "wizard"), "sprites/player/mage.png")

    save(slime(), "sprites/enemies/slime.png")
    save(skeleton(), "sprites/enemies/skeleton.png")
    save(bat(), "sprites/enemies/bat.png")
    save(cultist(), "sprites/enemies/cultist.png")

    save(chest((120, 80, 45, 255), (70, 50, 30, 255)), "sprites/props/chest_wood.png")
    save(chest((120, 80, 45, 255), (70, 50, 30, 255), True), "sprites/props/chest_wood_open.png")
    save(chest((95, 100, 110, 255), (60, 62, 70, 255)), "sprites/props/chest_iron.png")
    save(chest((95, 100, 110, 255), (60, 62, 70, 255), True), "sprites/props/chest_iron_open.png")
    save(chest((110, 40, 120, 255), GOLD), "sprites/props/chest_gold.png")
    save(chest((110, 40, 120, 255), GOLD, True), "sprites/props/chest_gold_open.png")
    save(door(), "sprites/props/exit_door.png")

    save(projectile((255, 120, 20, 255)), "sprites/fx/fireball.png")
    save(projectile((200, 205, 215, 255), 8, 3), "sprites/fx/knife.png")
    save(projectile((200, 60, 230, 255)), "sprites/fx/dark_bolt.png")
    arrow = new(10, 3)
    ImageDraw.Draw(arrow).line((0, 1, 8, 1), fill=(150, 110, 60, 255))
    ImageDraw.Draw(arrow).point((9, 1), fill=(210, 210, 220, 255))
    ImageDraw.Draw(arrow).point((0, 0), fill=(230, 230, 230, 255))
    ImageDraw.Draw(arrow).point((0, 2), fill=(230, 230, 230, 255))
    save(arrow, "sprites/fx/arrow.png", do_outline=False)
    save(projectile((120, 160, 255, 255), 7, 5), "sprites/fx/magic_bolt.png")
    save(light_tex(), "sprites/fx/light.png", do_outline=False)
    spark = new(4, 4)
    ImageDraw.Draw(spark).rectangle((0, 0, 3, 3), fill=(255, 255, 255, 255))
    save(spark, "sprites/fx/pixel.png", do_outline=False)

    skins = {"human": ((230, 185, 145, 255), None, False, (90, 55, 30, 255)),
             "dwarf": ((215, 160, 120, 255), (120, 70, 40, 255), False, (120, 70, 40, 255)),
             "elf": ((240, 215, 185, 255), None, True, (230, 220, 150, 255)),
             "orc": ((110, 160, 80, 255), None, False, (30, 30, 30, 255))}
    for name, (skin, beard, ears, hair) in skins.items():
        save(portrait_face(skin, beard, ears, hair), f"sprites/portraits/race_{name}.png")
    save(portrait_overlay("warrior", (110, 85, 50, 255)), "sprites/portraits/class_warrior.png")
    save(portrait_overlay("rogue", (50, 75, 50, 255)), "sprites/portraits/class_rogue.png")
    save(portrait_overlay("mage", (70, 50, 150, 255)), "sprites/portraits/class_mage.png")
    save(portrait_overlay("warrior", (225, 215, 170, 255)), "sprites/portraits/class_paladin.png")
    save(char_sprite((220, 220, 230, 255), (230, 190, 150, 255), (220, 180, 60, 255), "helm"), "sprites/player/paladin.png")
    shard = new(16, 16)
    ds = ImageDraw.Draw(shard)
    ds.polygon([(8, 1), (12, 7), (9, 15), (5, 9)], fill=(170, 80, 240, 255))
    ds.polygon([(8, 1), (9, 15), (5, 9)], fill=(120, 50, 190, 255))
    ds.line((8, 3, 9, 10), fill=(230, 200, 255, 255))
    save(shard, "sprites/items/eclipse_shard.png")

    save(book_panel(), "ui/book_panel.png", do_outline=False)
    save(slot_tex(), "ui/slot.png", do_outline=False)
    save(slot_dark_tex(), "ui/slot_empty.png", do_outline=False)
    save(slot_hover_tex(), "ui/slot_hover.png", do_outline=False)
    save(bar_frame(), "ui/bar_frame.png", do_outline=False)
    save(bar_fill((200, 40, 40, 255)), "ui/bar_hp.png", do_outline=False)
    save(bar_fill((50, 110, 230, 255)), "ui/bar_mana.png", do_outline=False)
    save(bar_fill((230, 190, 40, 255)), "ui/bar_xp.png", do_outline=False)
    save(dot((60, 140, 255, 255)), "ui/dot_full.png", do_outline=False)
    save(dot((90, 80, 70, 255)), "ui/dot_empty.png", do_outline=False)
    save(tooltip_tex(), "ui/tooltip.png", do_outline=False)
    save(button_tex(PARCH_D), "ui/button.png", do_outline=False)
    save(button_tex(PARCH), "ui/button_hover.png", do_outline=False)
    save(button_tex(PARCH_DD), "ui/button_pressed.png", do_outline=False)
    save(doll(), "ui/doll.png", do_outline=False)
    print("placeholders generated")
    import gen_sheets  # animated sprite sheets (see docs/ANIMATION_GUIDE.md)
    gen_sheets.main()
    import gen_biomes  # biome tilesets, parallax, decorations, extra layers
    gen_biomes.main()
    import gen_mechanics  # status icons, traps, merchant, bosses, monsters...
    gen_mechanics.main()


if __name__ == "__main__":
    main()
