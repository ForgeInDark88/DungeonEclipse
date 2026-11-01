#!/usr/bin/env python3
"""Art of the town ↔ expedition loop, in the style of tools/gen_town.py
(same pieces: shingled roofs, bricks, timber, lit windows, signs, glow):
the new buildings (alchemist, library, sanctum, warehouse, scout tower, hall
of fame, ruins, banners), the building icons for the UI, the people of the
town (street sprites 20×30 with two idle frames) and their portraits 48×48.

Run from the project root:  python3 tools/gen_town_loop_art.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp
from gen_monsters import blank, lit, mask, rgba, sh, FULL
from gen_structures import bricks, column, finish, glow_dot, planks
from gen_town import (ROOF_RED, ROOF_SLATE, STONE, chimney, door, foundation, hanging_sign, plaster_wall,
                      roof, save, timber_frame, window)

A = gp.A
OUT = (24, 16, 12, 255)


# =============================================================== buildings
def alchemist():
    w, h = 66, 72
    im, g = blank(w, h), blank(w, h)
    roof_h = 26
    bricks(im, 5, h - 26, w - 6, h - 6, (126, 120, 112), bw=5, bh=3, seed=41)
    plaster_wall(im, 5, roof_h - 2, w - 6, h - 26, (196, 204, 170), 41)
    timber_frame(im, 5, roof_h - 2, w - 6, h - 26, beams=False, color=(70, 60, 40))
    foundation(im, 4, w - 5, h - 6, h - 1, 41)
    chimney(im, w - 18, 4, roof_h, smoke=False)
    d = ImageDraw.Draw(im)
    for k, (dx, dy) in enumerate(((2, -3), (4, -6), (2, -9), (5, -12))):  # green alchemical smoke
        d.ellipse((w - 18 + dx - 1, 4 + dy - 1, w - 18 + dx + 2, 4 + dy + 1), fill=(120, 220, 140, 180 - k * 40))
    roof(im, 5, w - 6, 2, roof_h, (66, 104, 74))
    # the round laboratory window glowing green
    cx, cy = 22, roof_h + 10
    d = ImageDraw.Draw(im)
    d.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=(70, 50, 34, 255))
    for yy in range(cy - 6, cy + 7):
        for xx in range(cx - 6, cx + 7):
            if (xx - cx) ** 2 + (yy - cy) ** 2 <= 36:
                d.point((xx, yy), fill=sh((120, 230, 150), 1.05 - 0.3 * (yy - cy + 6) / 12))
    d.line((cx, cy - 6, cx, cy + 6), fill=(70, 50, 34, 255))
    d.line((cx - 6, cy, cx + 6, cy), fill=(70, 50, 34, 255))
    glow_dot(g, cx, cy, 10, (110, 255, 150), 0.6)
    window(im, g, 42, roof_h + 6, 8, 8, shutters=False)
    # shop window of the ground floor: shelves of potions
    d = ImageDraw.Draw(im)
    sx0, sy0 = 9, h - 22
    d.rectangle((sx0 - 1, sy0 - 1, sx0 + 22, sy0 + 12), fill=(70, 46, 30, 255))
    d.rectangle((sx0, sy0, sx0 + 21, sy0 + 11), fill=(48, 40, 52, 255))
    cols = [(220, 60, 60), (70, 120, 240), (90, 220, 120), (240, 200, 70), (200, 90, 230)]
    for row in range(2):
        d.line((sx0, sy0 + 5 + row * 6, sx0 + 21, sy0 + 5 + row * 6), fill=(110, 76, 44, 255))
        for k in range(5):
            c = cols[(k + row * 2) % 5]
            bx = sx0 + 2 + k * 4
            d.rectangle((bx, sy0 + 1 + row * 6, bx + 1, sy0 + 4 + row * 6), fill=rgba(c))
            d.point((bx, sy0 + 1 + row * 6), fill=(255, 255, 240, 255))
            glow_dot(g, bx + 1, sy0 + 3 + row * 6, 2.5, c, 0.35)
    door(im, 40, h - 6, 10, 16, (80, 96, 70))
    # a cauldron bubbling by the door

    def flask(dd, x, y):
        dd.polygon([(x - 1, y - 4), (x + 1, y - 4), (x + 1, y - 1), (x + 3, y + 3), (x - 3, y + 3), (x - 1, y - 1)], fill=(120, 230, 150, 255))
        dd.line((x - 1, y - 4, x + 1, y - 4), fill=(230, 230, 230, 255))
    hanging_sign(im, 52, roof_h + 18, flask)
    cm = mask(w, h, lambda dd: dd.ellipse((54, h - 13, 63, h - 5), fill=FULL))
    lit(im, cm, (54, 54, 62), 56, h - 11, 3, 3)
    d = ImageDraw.Draw(im)
    d.ellipse((55, h - 14, 62, h - 11), fill=(110, 230, 140, 255))
    for bx, by in ((56, h - 16), (60, h - 17), (58, h - 19)):
        d.point((bx, by), fill=(170, 255, 190, 220))
    glow_dot(g, 58, h - 12, 6, (110, 255, 150), 0.6)
    d.line((55, h - 5, 54, h - 3), fill=(40, 40, 46, 255))
    d.line((62, h - 5, 63, h - 3), fill=(40, 40, 46, 255))
    save(finish(im, g), "alchemist")


def library():
    w, h = 74, 74
    im, g = blank(w, h), blank(w, h)
    roof_h = 26
    sand = (196, 180, 146)
    bricks(im, 4, roof_h - 2, w - 5, h - 6, sand, bw=6, bh=3, seed=51, mortar=0.7)
    foundation(im, 3, w - 4, h - 6, h - 1, 51)
    roof(im, 4, w - 5, 0, roof_h, (58, 76, 130))
    d = ImageDraw.Draw(im)
    # round clock-window in the gable
    cx, cy = w // 2, 15
    d.ellipse((cx - 5, cy - 5, cx + 4, cy + 4), fill=(80, 60, 40, 255))
    d.ellipse((cx - 4, cy - 4, cx + 3, cy + 3), fill=(240, 230, 200, 255))
    d.line((cx - 0.5, cy - 0.5, cx - 0.5, cy - 3), fill=(40, 30, 30, 255))
    d.line((cx - 0.5, cy - 0.5, cx + 2, cy - 0.5), fill=(40, 30, 30, 255))
    # pilasters
    for x in (4, 24, 48, w - 8):
        column(im, x, roof_h - 1, x + 3, h - 7, sh(sand, 1.08)[:3])
    # tall arched windows full of light
    for wx in (11, 54):
        window(im, g, wx, roof_h + 8, 9, 18, shutters=False, arch=True)
    # the double door under an arch and an open-book sign over it
    door(im, w // 2 - 8, h - 6, 16, 20, (90, 60, 44), arch=True)
    d = ImageDraw.Draw(im)
    bx, by = w // 2, roof_h + 4
    d.polygon([(bx - 8, by), (bx, by + 2), (bx + 8, by), (bx + 8, by + 7), (bx, by + 9), (bx - 8, by + 7)], fill=(236, 226, 196, 255))
    d.line((bx, by + 2, bx, by + 9), fill=(120, 90, 60, 255))
    for k in range(3):
        d.line((bx - 6, by + 3 + k * 2, bx - 2, by + 3 + k * 2), fill=(120, 110, 100, 255))
        d.line((bx + 2, by + 3 + k * 2, bx + 6, by + 3 + k * 2), fill=(120, 110, 100, 255))
    d.line((bx - 8, by + 7, bx, by + 9), fill=(60, 80, 140, 255))
    d.line((bx, by + 9, bx + 8, by + 7), fill=(60, 80, 140, 255))
    # book stacks by the door
    for k, c in enumerate([(150, 50, 50), (60, 90, 150), (70, 120, 70)]):
        d.rectangle((14, h - 8 - k * 2, 21, h - 7 - k * 2), fill=rgba(c))
    save(finish(im, g), "library")


def sanctum():
    w, h = 66, 84
    im, g = blank(w, h), blank(w, h)
    roof_h = 34
    dark = (96, 86, 110)
    bricks(im, 6, roof_h - 2, w - 7, h - 6, dark, bw=5, bh=3, seed=61)
    foundation(im, 4, w - 5, h - 6, h - 1, 61)
    roof(im, 6, w - 7, 0, roof_h, (60, 44, 84), overhang=4)
    d = ImageDraw.Draw(im)
    # spire tip and floating eclipse crystal
    d.line((w // 2, 0, w // 2, 4), fill=(200, 170, 255, 255))
    # the eclipse disc over the door
    cx, cy = w // 2, roof_h + 10
    d.ellipse((cx - 9, cy - 9, cx + 8, cy + 8), fill=(255, 200, 110, 255))
    d.ellipse((cx - 8, cy - 8, cx + 7, cy + 7), fill=(40, 24, 56, 255))
    for a in range(0, 360, 30):
        r = math.radians(a)
        d.point((cx - 0.5 + math.cos(r) * 11, cy - 0.5 + math.sin(r) * 11), fill=(255, 210, 130, 255))
    glow_dot(g, cx, cy, 14, (190, 120, 255), 0.8)
    # pillars and a purple-lit doorway
    for x in (12, w - 16):
        column(im, x, roof_h, x + 4, h - 7, (140, 128, 150), fluted=True)
    d = ImageDraw.Draw(im)
    dx0 = cx - 7
    d.rectangle((dx0, h - 24, dx0 + 13, h - 7), fill=(30, 18, 44, 255))
    d.pieslice((dx0, h - 31, dx0 + 13, h - 17), 180, 360, fill=(30, 18, 44, 255))
    for yy in range(h - 24, h - 7):
        t = (yy - (h - 24)) / 17
        d.line((dx0 + 2, yy, dx0 + 11, yy), fill=sh((150, 90, 230), 0.6 + 0.6 * t, 200))
    glow_dot(g, cx, h - 14, 12, (170, 100, 255), 0.9)
    # crystals by the steps
    for bx, hh in ((8, 7), (w - 12, 9)):
        d.polygon([(bx, h - 6), (bx + 2, h - 6 - hh), (bx + 4, h - 6)], fill=(170, 130, 240, 255))
        d.line((bx + 2, h - 6 - hh, bx + 2, h - 7), fill=(230, 210, 255, 255))
        glow_dot(g, bx + 2, h - 9, 5, (170, 120, 255), 0.6)
    save(finish(im, g), "sanctum")


def warehouse():
    w, h = 78, 62
    im, g = blank(w, h), blank(w, h)
    roof_h = 22
    planks(im, 4, roof_h - 2, w - 5, h - 6, (132, 92, 56), vertical=False, step=3, seed=71)
    foundation(im, 3, w - 4, h - 6, h - 1, 71)
    roof(im, 4, w - 5, 2, roof_h, (110, 70, 46))
    d = ImageDraw.Draw(im)
    # hay loft door with the hoist beam
    lx = w // 2 - 6
    planks(im, lx, roof_h - 1, lx + 11, roof_h + 9, (100, 66, 40), vertical=True, step=3, seed=72)
    d = ImageDraw.Draw(im)
    d.line((w // 2, roof_h - 4, w // 2, roof_h - 1), fill=(80, 56, 36, 255), width=2)
    d.line((w // 2 + 1, roof_h - 3, w // 2 + 9, roof_h - 3), fill=(80, 56, 36, 255), width=2)
    d.line((w // 2 + 8, roof_h - 2, w // 2 + 8, roof_h + 12), fill=(200, 180, 130, 255))
    d.rectangle((w // 2 + 6, roof_h + 12, w // 2 + 10, roof_h + 15), fill=(120, 84, 50, 255))
    # big barn doors with X braces
    bx0, bx1, by0 = w // 2 - 14, w // 2 + 13, h - 28
    planks(im, bx0, by0, bx1, h - 7, (110, 72, 44), vertical=True, step=3, seed=73)
    d = ImageDraw.Draw(im)
    for x0, x1 in ((bx0, w // 2 - 1), (w // 2, bx1)):
        d.rectangle((x0, by0, x1, h - 7), outline=(70, 46, 28, 255))
        d.line((x0, by0, x1, h - 7), fill=(80, 54, 32, 255), width=2)
        d.line((x1, by0, x0, h - 7), fill=(80, 54, 32, 255), width=2)
    window(im, g, 9, roof_h + 6, 7, 7)
    window(im, g, w - 16, roof_h + 6, 7, 7)
    # crates and a barrel out front, a lantern
    d = ImageDraw.Draw(im)
    for cx0, cy0, s in ((6, h - 15, 9), (8, h - 23, 7), (w - 15, h - 15, 9)):
        planks(im, cx0, cy0, cx0 + s, cy0 + s, (156, 116, 70), vertical=True, step=3, seed=cx0)
        d = ImageDraw.Draw(im)
        d.rectangle((cx0, cy0, cx0 + s, cy0 + s), outline=(80, 54, 30, 255))
        d.line((cx0, cy0, cx0 + s, cy0 + s), fill=(110, 76, 44, 255))
    d.rectangle((w // 2 - 18, h - 34, w // 2 - 16, h - 31), fill=(255, 220, 120, 255))
    glow_dot(g, w // 2 - 17, h - 32, 6, (255, 190, 90), 0.7)
    save(finish(im, g), "warehouse")


def scout_tower():
    w, h = 34, 102
    im, g = blank(w, h), blank(w, h)
    # tapering stone shaft
    shaft = mask(w, h, lambda dd: dd.polygon([(5, h - 6), (9, 30), (w - 10, 30), (w - 6, h - 6)], fill=FULL))
    tmp = blank(w, h)
    bricks(tmp, 4, 28, w - 5, h - 6, (140, 134, 124), bw=4, bh=3, seed=81)
    im.paste(tmp, (0, 0), shaft)
    foundation(im, 3, w - 4, h - 6, h - 1, 81)
    d = ImageDraw.Draw(im)
    for wy in (44, 64):
        d.rectangle((w // 2 - 2, wy, w // 2 + 1, wy + 6), fill=(50, 40, 40, 255))
        d.rectangle((w // 2 - 1, wy + 1, w // 2, wy + 5), fill=(255, 210, 120, 255))
        glow_dot(g, w // 2, wy + 3, 4, (255, 190, 90), 0.5)
    door(im, w // 2 - 4, h - 6, 8, 13, (100, 66, 40))
    # wooden lookout with a railing and a small roof
    planks(im, 3, 26, w - 4, 30, (120, 82, 48), step=2, seed=82)
    d = ImageDraw.Draw(im)
    for x in range(4, w - 3, 4):
        d.line((x, 19, x, 26), fill=(110, 74, 44, 255))
    d.line((3, 19, w - 4, 19), fill=(140, 96, 58, 255))
    for x in (5, w - 7):
        d.line((x, 10, x, 26), fill=(90, 60, 36, 255), width=2)
    roof(im, 5, w - 7, 2, 11, (110, 60, 46), overhang=3)
    d = ImageDraw.Draw(im)
    # flag on the top and a brazier glow in the lookout
    d.line((w // 2, 0, w // 2, 3), fill=(80, 56, 36, 255))
    d.polygon([(w // 2 + 1, 0), (w // 2 + 7, 1), (w // 2 + 1, 3)], fill=(200, 50, 40, 255))
    glow_dot(g, w // 2, 22, 7, (255, 170, 80), 0.6)
    d.point((w // 2, 23), fill=(255, 210, 120, 255))
    save(finish(im, g), "scout_tower")


def hall():
    w, h = 86, 76
    im, g = blank(w, h), blank(w, h)
    marble = (214, 206, 190)
    # the pediment with gold trim and a shield trophy
    top = 8
    base = 26
    pm = mask(w, h, lambda dd: dd.polygon([(2, base), (w // 2, top), (w - 3, base)], fill=FULL))
    lit(im, pm, marble, w // 2, top + 6, 30, 10)
    d = ImageDraw.Draw(im)
    d.line((2, base, w // 2, top), fill=(220, 180, 70, 255), width=2)
    d.line((w // 2, top, w - 3, base), fill=(180, 140, 50, 255), width=2)
    d.line((2, base, w - 3, base), fill=(200, 160, 60, 255), width=2)
    sx, sy = w // 2, base - 7
    d.polygon([(sx - 4, sy - 4), (sx + 4, sy - 4), (sx + 4, sy + 1), (sx, sy + 5), (sx - 4, sy + 1)], fill=(170, 40, 40, 255))
    d.line((sx, sy - 4, sx, sy + 4), fill=(240, 200, 80, 255))
    d.line((sx - 4, sy - 1, sx + 4, sy - 1), fill=(240, 200, 80, 255))
    glow_dot(g, sx, sy, 6, (255, 210, 120), 0.4)
    # back wall, columns, red banners between them
    bricks(im, 6, base + 1, w - 7, h - 10, sh(marble, 0.86)[:3], bw=6, bh=3, seed=91, mortar=0.75)
    for x in (7, 25, 55, w - 13):
        column(im, x, base + 1, x + 5, h - 10, marble, fluted=True)
    d = ImageDraw.Draw(im)
    for bx in (16, w - 21):
        d.rectangle((bx, base + 5, bx + 5, base + 20), fill=(160, 36, 36, 255))
        d.polygon([(bx, base + 20), (bx + 2.5, base + 23), (bx + 5, base + 20)], fill=(160, 36, 36, 255))
        d.line((bx + 2, base + 8, bx + 3, base + 8), fill=(240, 200, 80, 255))
        d.rectangle((bx + 1, base + 10, bx + 4, base + 13), outline=(240, 200, 80, 255))
    # golden doorway
    dx0 = w // 2 - 9
    d.rectangle((dx0, base + 8, dx0 + 18, h - 10), fill=(60, 40, 24, 255))
    for yy in range(base + 9, h - 10):
        d.line((dx0 + 2, yy, dx0 + 16, yy), fill=sh((255, 200, 100), 0.55 + 0.35 * (yy - base) / (h - base)))
    glow_dot(g, w // 2, h - 20, 12, (255, 200, 110), 0.6)
    # steps
    for k in range(3):
        d.rectangle((3 + k * 2, h - 10 + k * 3, w - 4 - k * 2, h - 8 + k * 3), fill=sh(marble, 0.95 - 0.07 * k))
        d.line((3 + k * 2, h - 10 + k * 3, w - 4 - k * 2, h - 10 + k * 3), fill=sh(marble, 1.1))
    save(finish(im, g), "hall")


def ruins():
    w, h = 66, 30
    im, g = blank(w, h), blank(w, h)
    rnd = random.Random(5)
    stone = (132, 124, 114)
    # two broken wall stubs with jagged tops
    for x0, x1, top in ((4, 15, 4), (w - 19, w - 6, 9)):
        m = mask(w, h, lambda dd, x0=x0, x1=x1, top=top: dd.polygon(
            [(x0, h - 5), (x0, top + 3), (x0 + 3, top), (x0 + 6, top + 4), (x1 - 3, top + 1), (x1, top + 6), (x1, h - 5)], fill=FULL))
        tmp = blank(w, h)
        bricks(tmp, x0, top, x1, h - 5, stone, bw=4, bh=3, seed=x0)
        im.paste(tmp, (0, 0), m)
    d = ImageDraw.Draw(im)
    # rubble, a charred beam, weeds
    for _ in range(14):
        x, y = rnd.randint(14, w - 18), rnd.randint(h - 9, h - 5)
        s = rnd.randint(2, 4)
        d.rectangle((x, y, x + s, y + s - 1), fill=sh(stone, rnd.uniform(0.7, 1.1)))
        d.point((x, y), fill=sh(stone, 1.25))
    d.line((18, h - 12, 46, h - 7), fill=(56, 38, 28, 255), width=3)
    d.line((18, h - 13, 46, h - 8), fill=(80, 56, 38, 255))
    foundation(im, 2, w - 3, h - 5, h - 1, 9)
    for x in range(3, w - 3, 5):
        if rnd.random() < 0.6:
            d.line((x, h - 5, x + rnd.randint(-1, 1), h - 8), fill=(80, 140, 60, 255))
    save(finish(im, g), "ruins")


def banners():
    for name, c in (("banner_red", (180, 40, 40)), ("banner_blue", (60, 90, 170)), ("banner_gold", (220, 180, 50))):
        im = blank(9, 18)
        d = ImageDraw.Draw(im)
        d.line((0, 0, 0, 17), fill=(90, 60, 35, 255))
        d.point((0, 0), fill=(220, 190, 90, 255))
        d.polygon([(1, 1), (8, 1), (8, 11), (4.5, 8), (1, 11)], fill=rgba(c))
        d.line((1, 1, 8, 1), fill=sh(c, 1.3))
        d.line((8, 2, 8, 10), fill=sh(c, 0.7))
        d.point((4, 4), fill=(255, 240, 180, 255))
        save(finish(im), name)


# ================================================================== icons
def _icon(fn) -> Image.Image:
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    fn(ImageDraw.Draw(im))
    return gp.outline(im)


def icons():
    gold, dark = (240, 200, 80, 255), (60, 44, 30, 255)
    drawings = {
        "temple": lambda d: (d.rectangle((4, 6, 11, 14), fill=(170, 166, 170, 255)), d.polygon([(3, 6), (7.5, 1), (12, 6)], fill=(90, 96, 120, 255)),
                             d.ellipse((6, 8, 9, 11), fill=(150, 110, 230, 255)), d.rectangle((7, 12, 8, 14), fill=dark)),
        "shop": lambda d: (d.ellipse((3, 5, 12, 14), fill=(170, 120, 60, 255)), d.rectangle((6, 3, 9, 5), fill=(140, 96, 50, 255)),
                           d.text((5, 6), "$", fill=gold)),
        "alchemist": lambda d: (d.polygon([(6, 2), (9, 2), (9, 6), (13, 13), (2, 13), (6, 6)], fill=(200, 230, 220, 255)),
                                d.polygon([(4, 10), (11, 10), (13, 13), (2, 13)], fill=(100, 220, 130, 255)), d.point((7, 8), fill=(255, 255, 255, 255))),
        "tavern": lambda d: (d.rectangle((3, 4, 10, 14), fill=(220, 170, 60, 255)), d.rectangle((3, 2, 10, 4), fill=(250, 250, 240, 255)),
                             d.arc((9, 6, 14, 11), 270, 90, fill=(220, 170, 60, 255), width=2)),
        "quests": lambda d: (d.rectangle((2, 3, 13, 12), fill=(150, 104, 60, 255)), d.rectangle((4, 5, 7, 9), fill=(240, 228, 196, 255)),
                             d.rectangle((9, 5, 11, 10), fill=(240, 228, 196, 255)), d.line((3, 12, 3, 15), fill=dark), d.line((12, 12, 12, 15), fill=dark)),
        "library": lambda d: (d.polygon([(1, 4), (8, 6), (15, 4), (15, 13), (8, 15), (1, 13)], fill=(236, 226, 196, 255)),
                              d.line((8, 6, 8, 15), fill=(120, 90, 60, 255)), d.line((3, 8, 6, 9), fill=(120, 110, 100, 255)),
                              d.line((10, 9, 13, 8), fill=(120, 110, 100, 255)), d.line((1, 13, 8, 15), fill=(60, 80, 140, 255))),
        "smithy": lambda d: (d.polygon([(2, 5), (13, 5), (14, 7), (10, 8), (10, 11), (12, 13), (4, 13), (6, 11), (6, 8)], fill=(80, 82, 96, 255)),
                             d.line((2, 5, 13, 5), fill=(190, 196, 210, 255))),
        "warehouse": lambda d: (d.rectangle((2, 4, 13, 14), fill=(160, 116, 70, 255)), d.line((2, 4, 13, 14), fill=(100, 70, 40, 255)),
                                d.line((13, 4, 2, 14), fill=(100, 70, 40, 255)), d.rectangle((2, 4, 13, 14), outline=(100, 70, 40, 255))),
        "hall": lambda d: (d.pieslice((3, 1, 12, 10), 0, 180, fill=gold), d.rectangle((3, 3, 12, 5), fill=gold),
                           d.rectangle((7, 9, 8, 12), fill=gold), d.rectangle((4, 12, 11, 14), fill=(200, 160, 60, 255)),
                           d.point((5, 4), fill=(255, 250, 220, 255))),
        "sanctum": lambda d: (d.ellipse((2, 2, 13, 13), fill=(255, 200, 110, 255)), d.ellipse((3, 3, 12, 12), fill=(40, 24, 56, 255)),
                              d.point((5, 5), fill=(190, 140, 255, 255))),
        "scout_tower": lambda d: (d.polygon([(5, 15), (6, 5), (10, 5), (11, 15)], fill=(150, 144, 134, 255)), d.rectangle((4, 3, 12, 5), fill=(130, 88, 52, 255)),
                                  d.line((8, 0, 8, 3), fill=dark), d.polygon([(9, 0), (13, 1), (9, 2)], fill=(200, 50, 40, 255)),
                                  d.rectangle((7, 8, 8, 10), fill=(255, 210, 120, 255))),
        "gate": lambda d: (d.pieslice((2, 2, 13, 16), 180, 360, fill=(110, 100, 96, 255)), d.rectangle((2, 8, 13, 15), fill=(110, 100, 96, 255)),
                           d.pieslice((5, 5, 10, 14), 180, 360, fill=(80, 40, 140, 255)), d.rectangle((5, 9, 10, 15), fill=(80, 40, 140, 255))),
    }
    for name, fn in drawings.items():
        gp.save(_icon(fn), "ui/buildings/%s.png" % name, do_outline=False)


# ================================================================= people
# id: skin, hair, hair style, beard, headwear, body, apron/accent, item, bg
PEOPLE = {
    "elder": dict(skin=(232, 196, 160), hair=(214, 214, 220), style="bun", beard=None, hat=None,
                  body=(110, 80, 132), accent=(80, 60, 100), item="staff", bg=(70, 56, 86), shawl=(170, 150, 120)),
    "blacksmith": dict(skin=(214, 160, 120), hair=(60, 40, 30), style="bald", beard=(60, 40, 30), hat=None,
                       body=(150, 110, 80), accent=(80, 66, 56), item="hammer", bg=(90, 50, 34), bare_arms=True),
    "healer": dict(skin=(236, 200, 166), hair=(170, 96, 52), style="braid", beard=None, hat="hood",
                   body=(84, 130, 84), accent=(170, 140, 90), item="satchel", bg=(52, 80, 56)),
    "innkeeper": dict(skin=(236, 196, 160), hair=(232, 192, 96), style="braids", beard=None, hat=None,
                      body=(160, 60, 54), accent=(236, 228, 210), item="mug", bg=(96, 54, 40)),
    "alchemist": dict(skin=(226, 190, 156), hair=(150, 150, 156), style="wild", beard=(150, 150, 156), hat="goggles",
                      body=(70, 100, 150), accent=(120, 230, 150), item="flask", bg=(40, 60, 84)),
    "cartographer": dict(skin=(230, 192, 156), hair=(120, 72, 40), style="short", beard=None, hat="tricorn",
                         body=(126, 100, 64), accent=(230, 214, 170), item="scroll", bg=(70, 62, 44)),
    "mason": dict(skin=(214, 168, 130), hair=(96, 66, 40), style="short", beard=(110, 76, 46), hat="cap",
                  body=(126, 126, 120), accent=(190, 160, 110), item="chisel", bg=(76, 74, 70)),
    "townsfolk_a": dict(skin=(230, 194, 160), hair=(90, 60, 40), style="short", beard=None, hat=None,
                        body=(96, 118, 158), accent=(70, 86, 120), item=None, bg=(50, 60, 80)),
    "townsfolk_b": dict(skin=(200, 150, 112), hair=(40, 30, 25), style="bun", beard=None, hat=None,
                        body=(170, 140, 90), accent=(120, 96, 60), item=None, bg=(80, 70, 50)),
}


def _px(d, x, y, c):
    d.point((x, y), fill=rgba(c) if len(c) == 3 else c)


def person(p: dict, breath: int = 0) -> Image.Image:
    """A 20×30 townsperson facing right; breath lifts the upper body 1 px."""
    im = blank(20, 30)
    d = ImageDraw.Draw(im)
    b = breath
    skin, hair, body, acc = p["skin"], p["hair"], p["body"], p["accent"]
    # legs and shoes
    d.rectangle((7, 24, 8, 28), fill=sh(body, 0.55))
    d.rectangle((11, 24, 12, 28), fill=sh(body, 0.5))
    d.rectangle((6, 28, 9, 29), fill=(54, 38, 30, 255))
    d.rectangle((10, 28, 13, 29), fill=(54, 38, 30, 255))
    # torso (long dress / robe falls to the shoes)
    robe = p.get("style") in ("bun", "braid", "braids") or p.get("hat") in ("hood", "goggles")
    bottom = 28 if robe else 24
    tm = mask(20, 30, lambda dd: dd.polygon([(6, 13 - b), (13, 13 - b), (14, bottom), (5, bottom)], fill=FULL))
    lit(im, tm, body, 8, 15 - b, 4, 6)
    d = ImageDraw.Draw(im)
    d.line((6, 13 - b, 6, bottom), fill=sh(body, 1.2))
    d.line((13, 14 - b, 14, bottom), fill=sh(body, 0.7))
    if p.get("shawl"):
        d.polygon([(6, 13 - b), (13, 13 - b), (12, 17 - b), (7, 17 - b)], fill=rgba(p["shawl"]))
    if p["item"] in ("hammer", "chisel") or p.get("style") == "braids":  # an apron
        d.rectangle((8, 16 - b, 12, bottom - 1), fill=rgba(acc))
        d.line((8, 16 - b, 12, 16 - b), fill=sh(acc, 1.2))
    d.line((6, 20 - b, 13, 20 - b), fill=sh(body, 0.6))  # belt
    # arms
    arm = skin if p.get("bare_arms") else sh(body, 0.85)[:3]
    d.rectangle((5, 14 - b, 6, 20 - b), fill=rgba(arm))
    d.rectangle((13, 14 - b, 14, 19 - b), fill=rgba(arm))
    _px(d, 14, 20 - b, skin)
    _px(d, 5, 21 - b, skin)
    # head
    hm = mask(20, 30, lambda dd: dd.ellipse((6, 3 - b, 13, 12 - b), fill=FULL))
    lit(im, hm, skin, 10, 6 - b, 3, 3)
    d = ImageDraw.Draw(im)
    _px(d, 11, 7 - b, (30, 24, 30))  # eye (facing right)
    _px(d, 12, 9 - b, sh(skin, 0.8)[:3])  # nose shade
    _px(d, 11, 10 - b, (150, 80, 70))  # mouth
    st = p["style"]
    if st != "bald" or True:
        if st == "bald":
            d.line((6, 6 - b, 6, 9 - b), fill=rgba(hair))
        else:
            d.rectangle((6, 3 - b, 12, 5 - b), fill=rgba(hair))
            d.rectangle((6, 3 - b, 7, 9 - b), fill=rgba(hair))
            _px(d, 9, 3 - b, sh(hair, 1.3)[:3])
        if st == "bun":
            d.ellipse((4, 2 - b, 7, 5 - b), fill=rgba(hair))
        elif st == "braid":
            d.line((6, 9 - b, 5, 16 - b), fill=rgba(hair), width=2)
        elif st == "braids":
            for x in (6, 12):
                d.line((x, 8 - b, x, 15 - b), fill=rgba(hair), width=2)
        elif st == "wild":
            for x, y in ((5, 3), (8, 1), (11, 2), (13, 4)):
                _px(d, x, y - b, hair)
    if p.get("beard"):
        d.rectangle((9, 9 - b, 13, 12 - b), fill=rgba(p["beard"]))
        _px(d, 11, 10 - b, (150, 80, 70))
    hat = p.get("hat")
    if hat == "hood":
        d.polygon([(5, 9 - b), (6, 2 - b), (10, 1 - b), (13, 3 - b), (13, 5 - b), (8, 4 - b), (7, 12 - b)], fill=sh(body, 0.9))
    elif hat == "goggles":
        d.rectangle((6, 4 - b, 13, 5 - b), fill=(70, 50, 30, 255))
        d.rectangle((10, 3 - b, 12, 5 - b), fill=(120, 230, 150, 255))
    elif hat == "tricorn":
        d.polygon([(4, 4 - b), (9, 0 - b), (15, 4 - b), (13, 5 - b), (6, 5 - b)], fill=(70, 50, 36, 255))
        d.line((9, 0 - b, 7, -2 - b), fill=(220, 220, 240, 255))  # feather
    elif hat == "cap":
        d.rectangle((6, 2 - b, 12, 4 - b), fill=sh(body, 0.8))
        d.line((12, 4 - b, 14, 4 - b), fill=sh(body, 0.6))
    # what they hold (in the front hand)
    item = p["item"]
    if item == "staff":
        d.line((16, 6 - b, 16, 29), fill=(110, 76, 44, 255))
        _px(d, 16, 5 - b, (150, 110, 70))
    elif item == "hammer":
        d.line((15, 12 - b, 15, 20 - b), fill=(110, 76, 44, 255))
        d.rectangle((14, 10 - b, 17, 12 - b), fill=(120, 124, 136, 255))
    elif item == "satchel":
        d.rectangle((12, 18 - b, 16, 22 - b), fill=(150, 110, 60, 255))
        _px(d, 14, 17 - b, (90, 170, 80))
    elif item == "mug":
        d.rectangle((15, 17 - b, 17, 20 - b), fill=(220, 170, 60, 255))
        d.line((15, 16 - b, 17, 16 - b), fill=(250, 250, 240, 255))
    elif item == "flask":
        d.rectangle((15, 16 - b, 17, 20 - b), fill=(120, 230, 150, 255))
        _px(d, 16, 15 - b, (230, 230, 230))
    elif item == "scroll":
        d.rectangle((13, 15 - b, 17, 17 - b), fill=(236, 224, 190, 255))
        _px(d, 17, 15 - b, (200, 60, 50))
    elif item == "chisel":
        d.line((15, 15 - b, 17, 19 - b), fill=(150, 154, 166, 255))
        _px(d, 15, 15 - b, (110, 76, 44))
    return finish(im)


def portrait(p: dict) -> Image.Image:
    """48×48 head-and-shoulders portrait with a soft lit background."""
    im = Image.new("RGBA", (48, 48), rgba(p["bg"]))
    d = ImageDraw.Draw(im)
    for y in range(48):  # background: light behind the head
        for x in range(48):
            r = math.hypot(x - 24, y - 18) / 34
            d.point((x, y), fill=sh(p["bg"], 1.45 - 0.6 * r))
    skin, hair, body, acc = p["skin"], p["hair"], p["body"], p["accent"]
    # shoulders
    sm = mask(48, 48, lambda dd: dd.ellipse((4, 34, 44, 66), fill=FULL))
    lit(im, sm, body, 18, 38, 10, 6)
    d = ImageDraw.Draw(im)
    if p.get("shawl"):
        d.polygon([(8, 40), (40, 40), (34, 48), (14, 48)], fill=rgba(p["shawl"]))
    if p["item"] in ("hammer", "chisel") or p["style"] == "braids":
        d.rectangle((17, 40, 31, 48), fill=rgba(acc))
    d.rectangle((21, 30, 27, 37), fill=sh(skin, 0.85))  # neck
    # face
    d = ImageDraw.Draw(im)
    d.ellipse((13, 8, 35, 34), fill=rgba(skin))
    d.chord((13, 8, 35, 34), 300, 60, fill=sh(skin, 0.86))  # the far cheek in shade
    d.ellipse((16, 10, 26, 18), fill=sh(skin, 1.06))  # lit forehead
    for cx in (18, 29):  # cheeks
        d.ellipse((cx - 2, 24, cx + 2, 26), fill=sh((230, 140, 120), 1.0, 120))
    d.arc((13, 8, 35, 34), 20, 160, fill=sh(skin, 0.7))
    st = p["style"]
    if st != "bald":
        d.pieslice((12, 5, 36, 25), 180, 360, fill=rgba(hair))
        d.rectangle((12, 14, 15, 24), fill=rgba(hair))
        d.rectangle((33, 14, 36, 24), fill=rgba(hair))
        d.line((16, 8, 28, 7), fill=sh(hair, 1.3))
    else:
        d.arc((14, 8, 34, 22), 200, 340, fill=sh(skin, 1.15))
    if st == "bun":
        d.ellipse((19, 1, 29, 9), fill=rgba(hair))
    elif st == "braid":
        d.line((14, 22, 11, 40), fill=rgba(hair), width=4)
    elif st == "braids":
        for x in (13, 35):
            d.line((x, 20, x, 38), fill=rgba(hair), width=4)
            d.point((x, 38), fill=(200, 60, 60, 255))
    elif st == "wild":
        for x, y in ((11, 9), (16, 4), (24, 2), (31, 4), (36, 9)):
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(hair))
    # eyes, brows, nose, mouth
    for ex in (19, 28):
        d.rectangle((ex, 19, ex + 2, 21), fill=(250, 250, 250, 255))
        d.rectangle((ex + 1, 19, ex + 2, 21), fill=(40, 30, 40, 255))
        d.line((ex - 1, 17, ex + 3, 17), fill=sh(hair if st != "bald" else (60, 40, 30), 0.8))
    d.line((24, 21, 24, 25), fill=sh(skin, 0.8))
    d.point((25, 25), fill=sh(skin, 0.75))
    d.line((21, 28, 27, 28), fill=(150, 80, 70, 255))
    d.point((19, 25), fill=sh(skin, 0.92))
    if p.get("beard"):
        d.pieslice((15, 18, 33, 38), 0, 180, fill=rgba(p["beard"]))
        d.line((21, 29, 27, 29), fill=(120, 60, 50, 255))
    if st in ("bun",):  # wrinkles of age
        d.line((17, 24, 18, 25), fill=sh(skin, 0.85))
        d.line((31, 24, 30, 25), fill=sh(skin, 0.85))
    hat = p.get("hat")
    if hat == "hood":
        d.pieslice((9, 2, 39, 34), 180, 360, fill=sh(body, 0.9))
        d.rectangle((9, 17, 13, 40), fill=sh(body, 0.85))
        d.rectangle((35, 17, 39, 40), fill=sh(body, 0.75))
    elif hat == "goggles":
        d.rectangle((13, 10, 35, 13), fill=(80, 56, 34, 255))
        for gx in (17, 27):
            d.ellipse((gx, 8, gx + 6, 14), fill=(60, 44, 30, 255))
            d.ellipse((gx + 1, 9, gx + 5, 13), fill=(130, 240, 160, 255))
            d.point((gx + 2, 10), fill=(240, 255, 240, 255))
    elif hat == "tricorn":
        d.polygon([(6, 12), (24, 1), (42, 12), (36, 14), (12, 14)], fill=(70, 50, 36, 255))
        d.line((6, 12, 24, 1), fill=(110, 80, 56, 255))
        d.line((30, 4, 38, -2), fill=(230, 230, 250, 255), width=2)
    elif hat == "cap":
        d.chord((12, 3, 36, 21), 180, 360, fill=sh(body, 0.8))
        d.rectangle((30, 11, 40, 13), fill=sh(body, 0.6))
    # a hint of their trade at the shoulder
    item = p["item"]
    if item == "staff":
        d.line((42, 10, 42, 48), fill=(110, 76, 44, 255), width=2)
    elif item == "hammer":
        d.line((41, 22, 41, 46), fill=(110, 76, 44, 255), width=2)
        d.rectangle((37, 18, 45, 23), fill=(120, 124, 136, 255))
    elif item == "flask":
        d.rectangle((38, 36, 43, 44), fill=(120, 230, 150, 255))
        d.rectangle((39, 33, 42, 36), fill=(220, 220, 220, 255))
    elif item == "mug":
        d.rectangle((37, 36, 44, 45), fill=(220, 170, 60, 255))
        d.rectangle((37, 34, 44, 36), fill=(250, 250, 240, 255))
    elif item == "scroll":
        d.rectangle((35, 38, 46, 42), fill=(236, 224, 190, 255))
    elif item == "satchel":
        d.line((10, 36, 38, 48), fill=(130, 90, 50, 255), width=2)
    d.rectangle((0, 0, 47, 47), outline=OUT)
    return im


def people():
    for pid, p in PEOPLE.items():
        a = person(p, 0)
        b = person(p, 1)
        sheet = Image.new("RGBA", (40, 30), (0, 0, 0, 0))
        sheet.paste(a, (0, 0))
        sheet.paste(b, (20, 0))
        gp.save(a, "sprites/npc/%s.png" % pid, do_outline=False)
        gp.save(sheet, "sprites/npc/%s_idle.png" % pid, do_outline=False)
        gp.save(portrait(p), "sprites/portraits/npc_%s.png" % pid, do_outline=False)


def main():
    alchemist()
    library()
    sanctum()
    warehouse()
    scout_tower()
    hall()
    ruins()
    banners()
    icons()
    people()
    print("town loop art generated")


if __name__ == "__main__":
    main()


# ============================================================ road events
# The scenery of a road event in its room (EventData.prop): the hero walks
# up to it and the choice opens. assets/sprites/road_events/<prop>.png
def _ev(w, h):
    return blank(w, h), blank(w, h)


def _sit_person(im, x, by, body, skin=(230, 194, 160), hair=(90, 60, 40), bandage=False):
    d = ImageDraw.Draw(im)
    d.rectangle((x, by - 6, x + 9, by - 1), fill=sh(body, 0.6))  # legs
    tm = mask(im.width, im.height, lambda dd: dd.polygon([(x, by - 6), (x + 2, by - 15), (x + 7, by - 15), (x + 8, by - 6)], fill=FULL))
    lit(im, tm, body, x + 3, by - 12, 3, 4)
    d = ImageDraw.Draw(im)
    d.ellipse((x + 1, by - 22, x + 8, by - 15), fill=rgba(skin))
    d.rectangle((x + 1, by - 22, x + 8, by - 20), fill=rgba(hair))
    d.point((x + 6, by - 19), fill=(30, 24, 30, 255))
    if bandage:
        d.rectangle((x + 4, by - 6, x + 8, by - 4), fill=(236, 230, 220, 255))
        d.point((x + 6, by - 5), fill=(190, 40, 40, 255))


def event_props():
    out = "sprites/road_events/"

    def store(im, g, name):
        gp.save(finish(im, g), out + name + ".png", do_outline=False)

    # wounded scout against a rock, a map on his knees
    im, g = _ev(36, 28)
    d = ImageDraw.Draw(im)
    rm = mask(36, 28, lambda dd: dd.ellipse((14, 6, 35, 28), fill=FULL))
    lit(im, rm, (110, 104, 96), 22, 12, 8, 6)
    _sit_person(im, 6, 27, (90, 110, 70), bandage=True)
    d = ImageDraw.Draw(im)
    d.rectangle((8, 16, 15, 20), fill=(236, 224, 190, 255))
    d.line((9, 18, 13, 17), fill=(160, 60, 50, 255))
    store(im, g, "scout")
    # forgotten shrine: a niche with a bowl and candles
    im, g = _ev(32, 36)
    bricks(im, 2, 4, 29, 35, (132, 126, 118), bw=4, bh=3, seed=3)
    d = ImageDraw.Draw(im)
    d.pieslice((6, 4, 25, 26), 180, 360, fill=(40, 34, 44, 255))
    d.rectangle((6, 15, 25, 28), fill=(40, 34, 44, 255))
    d.ellipse((12, 8, 19, 15), fill=(230, 190, 90, 255))
    d.ellipse((13, 9, 18, 14), fill=(250, 230, 150, 255))
    d.rectangle((10, 24, 21, 27), fill=(150, 120, 70, 255))
    for cx in (8, 23):
        d.rectangle((cx, 22, cx + 1, 27), fill=(236, 226, 200, 255))
        d.point((cx, 21), fill=(255, 210, 110, 255))
        glow_dot(g, cx, 20, 4, (255, 190, 90), 0.6)
    store(im, g, "shrine")
    # broken caravan: an overturned cart with scattered crates
    im, g = _ev(48, 28)
    planks(im, 8, 8, 36, 20, (120, 82, 48), vertical=False, step=3, seed=5)
    d = ImageDraw.Draw(im)
    d.polygon([(8, 8), (36, 8), (40, 4), (12, 4)], fill=(100, 68, 40, 255))
    d.ellipse((30, 16, 41, 27), outline=(70, 46, 30, 255), width=2)
    d.line((35, 16, 35, 27), fill=(70, 46, 30, 255))
    d.line((30, 21, 41, 21), fill=(70, 46, 30, 255))
    for cx, cy in ((2, 20), (37, 20), (14, 21)):
        planks(im, cx, cy, cx + 6, cy + 6, (156, 116, 70), vertical=True, step=2, seed=cx)
    d = ImageDraw.Draw(im)
    d.rectangle((20, 22, 24, 27), fill=(150, 40, 40, 255))
    store(im, g, "caravan")
    # dice player behind a barrel
    im, g = _ev(32, 28)
    _sit_person(im, 4, 27, (120, 96, 70), hair=(60, 50, 40))
    bm = mask(32, 28, lambda dd: dd.rounded_rectangle((15, 12, 28, 27), 3, fill=FULL))
    lit(im, bm, (130, 84, 46), 19, 16, 5, 6)
    d = ImageDraw.Draw(im)
    d.line((15, 17, 28, 17), fill=(60, 60, 70, 255))
    d.line((15, 23, 28, 23), fill=(60, 60, 70, 255))
    for dx in (18, 23):
        d.rectangle((dx, 9, dx + 3, 12), fill=(240, 236, 226, 255))
        d.point((dx + 1, 10), fill=(30, 30, 30, 255))
    store(im, g, "gambler")
    # collapsed tunnel: rubble with iron veins
    im, g = _ev(44, 32)
    rnd = random.Random(7)
    d = ImageDraw.Draw(im)
    for _ in range(26):
        x, y, s = rnd.randint(0, 36), rnd.randint(8, 26), rnd.randint(4, 8)
        sm = mask(44, 32, lambda dd, x=x, y=y, s=s: dd.ellipse((x, y, x + s, y + s - 1), fill=FULL))
        lit(im, sm, sh((126, 118, 108), rnd.uniform(0.8, 1.1))[:3], x + 1, y + 1, 2, 2)
    d = ImageDraw.Draw(im)
    for _ in range(6):
        x, y = rnd.randint(6, 36), rnd.randint(12, 26)
        d.point((x, y), fill=(220, 190, 140, 255))
        glow_dot(g, x, y, 2, (255, 210, 140), 0.3)
    store(im, g, "rubble")
    # prisoner cart: a cage on wheels
    im, g = _ev(46, 36)
    planks(im, 4, 26, 40, 29, (110, 74, 44), step=2, seed=9)
    d = ImageDraw.Draw(im)
    d.rectangle((6, 8, 38, 26), outline=(70, 70, 80, 255), width=2)
    for x in range(10, 38, 4):
        d.line((x, 8, x, 26), fill=(110, 110, 120, 255))
    _sit_person(im, 17, 26, (96, 118, 158))
    d = ImageDraw.Draw(im)
    for x in range(10, 38, 4):
        d.line((x, 8, x, 26), fill=(110, 110, 120, 255))
    for wx in (8, 32):
        d.ellipse((wx, 26, wx + 9, 35), outline=(70, 46, 30, 255), width=2)
    store(im, g, "cart")
    # ossuary: a stone bowl of embers among skulls
    im, g = _ev(40, 26)
    d = ImageDraw.Draw(im)
    for sx, sy in ((2, 18), (8, 20), (30, 19), (34, 21), (5, 13), (32, 14)):
        d.ellipse((sx, sy, sx + 5, sy + 5), fill=(226, 218, 196, 255))
        d.point((sx + 1, sy + 2), fill=(40, 30, 30, 255))
        d.point((sx + 3, sy + 2), fill=(40, 30, 30, 255))
    bricks(im, 15, 16, 24, 25, (120, 114, 108), bw=3, bh=2, seed=4)
    d = ImageDraw.Draw(im)
    d.chord((11, 8, 28, 20), 0, 180, fill=(110, 104, 98, 255))
    for k in range(5):
        d.point((14 + k * 3, 12), fill=(255, 120 + k * 20, 40, 255))
    glow_dot(g, 20, 12, 7, (255, 130, 40), 0.7)
    store(im, g, "ossuary")
    # glowing mushrooms
    im, g = _ev(40, 26)
    d = ImageDraw.Draw(im)
    for mx, mh, ms in ((4, 10, 7), (13, 16, 10), (25, 12, 8), (33, 8, 6), (19, 6, 5)):
        d.rectangle((mx + ms // 2 - 1, 26 - mh, mx + ms // 2, 25), fill=(220, 220, 236, 255))
        d.pieslice((mx, 26 - mh - ms // 2, mx + ms, 26 - mh + ms // 2), 180, 360, fill=(90, 170, 255, 255))
        d.point((mx + 2, 26 - mh - 2), fill=(220, 240, 255, 255))
        glow_dot(g, mx + ms / 2, 26 - mh, ms * 0.9, (90, 180, 255), 0.7)
    store(im, g, "mushrooms")
    # the gravedigger's ghost with his spade over an open grave
    im, g = _ev(34, 36)
    d = ImageDraw.Draw(im)
    d.rectangle((2, 30, 31, 35), fill=(70, 52, 40, 255))
    d.rectangle((6, 31, 27, 35), fill=(30, 22, 20, 255))
    gm = mask(34, 36, lambda dd: dd.polygon([(10, 30), (12, 12), (20, 8), (24, 14), (24, 30), (20, 26), (16, 31), (13, 27)], fill=FULL))
    lit(im, gm, (170, 200, 220), 17, 14, 5, 8)
    d = ImageDraw.Draw(im)
    d.point((19, 12), fill=(30, 50, 60, 255))
    d.point((21, 12), fill=(30, 50, 60, 255))
    d.line((25, 6, 28, 30), fill=(120, 140, 150, 255))
    d.rectangle((26, 28, 30, 32), fill=(140, 160, 170, 255))
    glow_dot(g, 17, 18, 12, (150, 220, 255), 0.5)
    store(im, g, "ghost")
    # fallen statue of the king with ruby eyes
    im, g = _ev(48, 26)
    sm = mask(48, 26, lambda dd: dd.rounded_rectangle((6, 10, 42, 22), 4, fill=FULL))
    lit(im, sm, (176, 172, 164), 18, 13, 12, 4)
    d = ImageDraw.Draw(im)
    d.ellipse((34, 6, 46, 18), fill=(170, 166, 158, 255))
    d.polygon([(35, 7), (37, 1), (39, 5), (41, 0), (43, 5), (45, 2), (45, 8)], fill=(210, 180, 80, 255))
    for ex in (38, 42):
        d.point((ex, 11), fill=(220, 30, 50, 255))
        glow_dot(g, ex, 11, 2, (255, 40, 60), 0.6)
    bricks(im, 2, 22, 46, 25, (120, 114, 108), bw=5, bh=2, seed=2)
    store(im, g, "statue")
    # a smith's chest over a crack of lava
    im, g = _ev(44, 26)
    d = ImageDraw.Draw(im)
    for x in range(0, 44):
        d.point((x, 24 + (x % 3 == 0)), fill=(255, 120, 30, 255))
    glow_dot(g, 22, 24, 18, (255, 120, 30), 0.6)
    planks(im, 14, 10, 29, 21, (120, 80, 46), vertical=True, step=3, seed=11)
    d = ImageDraw.Draw(im)
    d.rectangle((14, 10, 29, 21), outline=(60, 60, 70, 255))
    d.line((14, 14, 29, 14), fill=(60, 60, 70, 255))
    d.rectangle((20, 13, 23, 16), fill=(230, 190, 80, 255))
    store(im, g, "lava_chest")
    # the jester's mirror
    im, g = _ev(28, 44)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((2, 2, 25, 41), 6, fill=(210, 170, 70, 255))
    d.rounded_rectangle((5, 5, 22, 38), 4, fill=(120, 140, 180, 255))
    for yy in range(5, 39):
        d.line((6, yy, 21, yy), fill=sh((130, 150, 200), 1.15 - 0.4 * (yy - 5) / 34))
    d.line((8, 10, 12, 6), fill=(230, 240, 255, 255))
    d.ellipse((10, 14, 17, 21), fill=(80, 60, 110, 180))  # the reflection's face
    d.point((12, 17), fill=(255, 255, 255, 255))
    glow_dot(g, 14, 20, 10, (170, 190, 255), 0.4)
    store(im, g, "mirror")
    # bell half-sunk in black water
    im, g = _ev(40, 32)
    d = ImageDraw.Draw(im)
    bm = mask(40, 32, lambda dd: dd.polygon([(10, 26), (13, 8), (20, 4), (27, 8), (30, 26)], fill=FULL))
    lit(im, bm, (150, 120, 70), 17, 10, 6, 8)
    d = ImageDraw.Draw(im)
    d.line((10, 26, 30, 26), fill=(110, 86, 50, 255), width=2)
    for y in range(22, 32):
        d.line((0, y, 39, y), fill=sh((24, 34, 56), 1.0 - (y - 22) * 0.03, 210))
    d.line((4, 23, 12, 23), fill=(110, 150, 200, 255))
    d.line((26, 24, 34, 24), fill=(110, 150, 200, 255))
    store(im, g, "bell")
    # crystal vein in a rock
    im, g = _ev(40, 32)
    rm = mask(40, 32, lambda dd: dd.ellipse((2, 6, 38, 34), fill=FULL))
    lit(im, rm, (100, 96, 104), 14, 12, 10, 8)
    d = ImageDraw.Draw(im)
    for cx, ch in ((12, 12), (19, 16), (27, 10)):
        d.polygon([(cx - 3, 26), (cx, 26 - ch), (cx + 3, 26)], fill=(170, 220, 255, 255))
        d.line((cx, 26 - ch, cx, 25), fill=(240, 250, 255, 255))
        glow_dot(g, cx, 26 - ch / 2, 6, (150, 210, 255), 0.6)
    store(im, g, "crystal")
    # ash pilgrims singing around a fire
    im, g = _ev(48, 28)
    for x, c in ((2, (110, 108, 104)), (36, (100, 98, 96)), (12, (120, 118, 112))):
        _sit_person(im, x, 27, c, skin=(170, 166, 160), hair=(90, 88, 86))
    d = ImageDraw.Draw(im)
    d.polygon([(22, 26), (25, 16), (28, 26)], fill=(255, 150, 50, 255))
    d.polygon([(24, 26), (25, 20), (26, 26)], fill=(255, 230, 120, 255))
    glow_dot(g, 25, 22, 10, (255, 150, 60), 0.8)
    store(im, g, "pilgrims")
    # the black sun's whisper: a dark orb with a burning rim
    im, g = _ev(32, 40)
    d = ImageDraw.Draw(im)
    d.ellipse((5, 4, 26, 25), fill=(255, 200, 110, 255))
    d.ellipse((6, 5, 25, 24), fill=(20, 10, 30, 255))
    for k in range(6):
        d.point((15 + k % 2, 28 + k * 2), fill=(255, 200, 120, 200 - k * 30))
    glow_dot(g, 15.5, 14.5, 18, (200, 120, 255), 0.9)
    store(im, g, "black_sun")
    # last survivors huddled under a blanket
    im, g = _ev(40, 28)
    _sit_person(im, 4, 27, (130, 100, 70), hair=(200, 200, 200))
    _sit_person(im, 14, 27, (150, 60, 60))
    _sit_person(im, 25, 27, (80, 100, 140), hair=(170, 110, 60))
    d = ImageDraw.Draw(im)
    d.polygon([(2, 27), (6, 12), (36, 12), (39, 27)], fill=(110, 90, 70, 150))
    store(im, g, "survivors")


if __name__ == "__main__":
    event_props()
