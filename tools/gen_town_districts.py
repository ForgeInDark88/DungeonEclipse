#!/usr/bin/env python3
"""Art of the bigger town (stage 18), in the style of tools/gen_town.py
(same pieces: lit stone and wood, bricks, planks, glow): the fountain of
the square, the memorial to the fallen, scaffolding of a district being
built, a tower of the town wall, the closed gate of a district not open
yet, the shooting target and the sparring ring of the training ground,
the carriage stop between districts, a stone stair of a terrace.

Writes assets/sprites/town/<name>.png.
Run from the project root:  python3 tools/gen_town_districts.py
"""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import gen_placeholders as gp  # noqa: E402
from gen_monsters import blank, lit, mask, rgba, sh, FULL  # noqa: E402
from gen_structures import bricks, column, finish, glow_dot, planks  # noqa: E402
from gen_town import ROOF_RED, ROOF_SLATE, STONE, roof, save  # noqa: E402


def fountain():
    w, h = 56, 40
    im, g = blank(w, h), blank(w, h)
    # the basin: a lit stone rim and water inside
    bm = mask(w, h, lambda d: d.ellipse((2, h - 16, w - 3, h - 1), fill=FULL))
    lit(im, bm, STONE, w // 2 - 8, h - 12, w // 2, 8, flat=0.2)
    d = ImageDraw.Draw(im)
    d.ellipse((7, h - 14, w - 8, h - 5), fill=(70, 120, 170, 255))
    d.arc((9, h - 13, w - 10, h - 6), 200, 330, fill=(170, 210, 240, 255))
    bricks(im, 2, h - 6, w - 3, h - 1, STONE, bw=5, bh=2, seed=12)
    # the column and the bowl on top
    column(im, w // 2 - 2, 10, w // 2 + 2, h - 10, sh(STONE, 1.05)[:3])
    tm = mask(w, h, lambda d: d.ellipse((w // 2 - 10, 6, w // 2 + 10, 14), fill=FULL))
    lit(im, tm, STONE, w // 2 - 3, 8, 10, 4)
    d = ImageDraw.Draw(im)
    # water falling in arcs, glowing a little
    for side in (-1, 1):
        for k in range(10):
            t = k / 9
            x = w // 2 + side * (8 + t * 12)
            y = 10 + t * t * (h - 22)
            d.point((int(x), int(y)), fill=(190, 225, 250, 220))
            glow_dot(g, x, y, 1.5, (120, 170, 220), 0.25)
    d.point((w // 2, 4), fill=(220, 240, 255, 255))
    save(finish(gp.outline(im), g), "fountain")


def memorial():
    w, h = 30, 56
    im = blank(w, h)
    bricks(im, 2, h - 10, w - 3, h - 1, STONE, bw=4, bh=2, seed=3)
    om = mask(w, h, lambda d: d.polygon([(9, h - 10), (11, 8), (15, 2), (19, 8), (21, h - 10)], fill=FULL))
    lit(im, om, (150, 146, 140), 12, 20, 6, 24, flat=0.25)
    d = ImageDraw.Draw(im)
    for y in range(18, h - 14, 4):  # carved names
        d.line((12, y, 18, y), fill=sh((150, 146, 140), 0.65))
    d.ellipse((12, 10, 18, 16), fill=(196, 160, 70, 255))  # a bronze wreath
    d.ellipse((13, 11, 17, 15), fill=(150, 146, 140, 255))
    for x in (4, w - 6):  # candles at the foot
        d.rectangle((x, h - 15, x + 1, h - 11), fill=(236, 226, 200, 255))
        d.point((x, h - 16), fill=(255, 200, 90, 255))
    save(gp.outline(im), "memorial")


def scaffold():
    w, h = 64, 56
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    for x in (4, 22, 40, 58):
        column(im, x, 4, x + 2, h - 1, (126, 88, 52))
    for y in (16, 34):
        planks(im, 2, y, w - 3, y + 2, (150, 110, 66), step=3, seed=y)
    d = ImageDraw.Draw(im)
    for x0 in (4, 22, 40):
        d.line((x0 + 2, h - 2, x0 + 18, 18), fill=(110, 76, 44, 255))  # braces
    bricks(im, 8, h - 14, w - 9, h - 1, STONE, bw=5, bh=3, seed=7)  # a wall rising
    d = ImageDraw.Draw(im)
    d.rectangle((26, 8, 34, 15), fill=(200, 196, 180, 255))  # a sack of lime
    d.line((10, 4, 30, 4), fill=(200, 180, 130, 255))  # a rope of the hoist
    save(gp.outline(im), "scaffold")


def wall_tower():
    w, h = 40, 96
    im, g = blank(w, h), blank(w, h)
    bricks(im, 4, 18, w - 5, h - 1, STONE, bw=6, bh=3, seed=21)
    d = ImageDraw.Draw(im)
    for x in range(2, w - 6, 7):  # battlements
        bricks(im, x, 10, x + 4, 18, STONE, bw=4, bh=3, seed=x)
    roof(im, 6, w - 7, 0, 11, ROOF_SLATE, overhang=2)
    d = ImageDraw.Draw(im)
    for y in (30, 54):
        d.rectangle((w // 2 - 2, y, w // 2 + 1, y + 8), fill=(20, 18, 24, 255))  # arrow slits
    d.rectangle((w // 2 - 3, 72, w // 2 + 2, 80), fill=(255, 206, 110, 255))  # a lit window
    glow_dot(g, w // 2, 76, 6, (255, 190, 90), 0.5)
    planks(im, w // 2 - 6, h - 18, w // 2 + 5, h - 1, (110, 72, 44), vertical=True, step=3, seed=2)
    save(finish(gp.outline(im), g), "wall_tower")


def district_gate():
    """A closed palisade across a district not open yet (with a notice)."""
    w, h = 40, 48
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    for x in range(1, w - 1, 5):
        planks(im, x, 6, x + 3, h - 1, (130, 94, 58), vertical=True, step=2, seed=x)
        d.polygon([(x, 6), (x + 1.5, 1), (x + 3, 6)], fill=(130, 94, 58, 255))
    d.line((0, 16, w - 1, 16), fill=(96, 66, 40, 255), width=2)
    d.line((0, 36, w - 1, 36), fill=(96, 66, 40, 255), width=2)
    d.rectangle((12, 20, 27, 30), fill=(226, 210, 170, 255))  # the notice
    for y in (23, 26):
        d.line((14, y, 25, y), fill=(120, 100, 80, 255))
    save(gp.outline(im), "district_gate")


def target():
    w, h = 22, 34
    im = blank(w, h)
    for x in (5, w - 7):
        column(im, x, 14, x + 1, h - 1, (110, 76, 44))
    tm = mask(w, h, lambda d: d.ellipse((1, 0, w - 2, 19), fill=FULL))
    lit(im, tm, (220, 200, 160), 7, 6, 10, 10, flat=0.3)
    d = ImageDraw.Draw(im)
    for r, c in ((7, (190, 50, 40)), (5, (236, 226, 200)), (3, (190, 50, 40)), (1, (240, 200, 60))):
        d.ellipse((w // 2 - 1 - r, 9 - r, w // 2 - 1 + r, 9 + r), fill=c + (255,))
    d.line((w // 2 + 2, 6, w // 2 + 7, 3), fill=(150, 110, 70, 255))  # a stuck arrow
    save(gp.outline(im), "target")


def ring_post():
    """A post of the sparring ring: a pole, a rope, a small banner."""
    w, h = 14, 44
    im = blank(w, h)
    column(im, 5, 6, 7, h - 1, (110, 76, 44))
    d = ImageDraw.Draw(im)
    d.polygon([(8, 6), (13, 9), (8, 13)], fill=(180, 50, 40, 255))
    d.line((0, 22, w - 1, 22), fill=(200, 180, 130, 255))
    save(gp.outline(im), "ring_post")


def carriage_stop():
    w, h = 26, 40
    im = blank(w, h)
    column(im, 11, 8, 13, h - 1, (96, 66, 40))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 6, w - 3, 18), fill=(150, 110, 66, 255))
    d.line((2, 6, w - 3, 6), fill=(190, 150, 96, 255))
    # a little carriage on the sign
    d.rectangle((7, 9, 17, 13), fill=(90, 60, 36, 255))
    d.ellipse((7, 13, 10, 16), fill=(40, 30, 24, 255))
    d.ellipse((14, 13, 17, 16), fill=(40, 30, 24, 255))
    d.line((17, 11, 21, 11), fill=(90, 60, 36, 255))
    d.ellipse((4, 0, 21, 6), fill=(180, 140, 60, 255))  # a bell / lamp cap
    save(gp.outline(im), "carriage_stop")


def banner_pole():
    """Growth: a tall pole with the town's banner (more of them as the town prospers)."""
    w, h = 16, 52
    im = blank(w, h)
    column(im, 2, 2, 3, h - 1, (110, 112, 124))
    bm = mask(w, h, lambda d: d.polygon([(4, 4), (15, 6), (15, 22), (10, 19), (4, 22)], fill=FULL))
    lit(im, bm, (60, 90, 160), 7, 8, 6, 9, flat=0.4)
    d = ImageDraw.Draw(im)
    d.ellipse((7, 9, 12, 14), fill=(230, 200, 80, 255))
    save(gp.outline(im), "banner_pole")


def main():
    fountain()
    memorial()
    scaffold()
    wall_tower()
    district_gate()
    target()
    ring_post()
    carriage_stop()
    banner_pole()
    print("town districts art: ok")


if __name__ == "__main__":
    main()
