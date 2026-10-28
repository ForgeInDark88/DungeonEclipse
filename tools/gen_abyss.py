#!/usr/bin/env python3
"""The last descent, floors 25-35: three biomes of their own.

* «Корни мира» (world_roots, floors 25-27): petrified roots of the world tree
  break through the stone, amber sap glows in their knots, fireflies;
* «Обсидиановая бездна» (obsidian_abyss, 28-30): black volcanic glass over
  nothing, violet veins of the void instead of lava, floating shards;
* «Сердце Затмения» (eclipse_heart, 31-35): the drowned Sun Temple inside the
  eclipse - black gold, the burning corona in the sky. The Eclipse fights here.

Each gets a tileset, three parallax layers, its decor (nothing borrowed),
music, a monster (sheets on existing layouts) and its .tres. Run from tools/:
python3 gen_abyss.py
"""
from __future__ import annotations

import colorsys
import math
import os
import random

from PIL import Image, ImageDraw

import gen_biomes as gb
import gen_deep_biomes as gdb
import gen_placeholders as gp
import gen_sheets as gs
from gen_monsters import blank, lit, mask, rgba, sh, FULL, dissolve, _limb
from gen_structures import finish, glow_dot

DECOR = os.path.join(gp.A, "sprites", "decor")
BG = os.path.join(gp.A, "sprites", "backgrounds")
TILES = os.path.join(gp.A, "sprites", "tiles")
W, H = 320, 180

# ----------------------------------------------------------------- palettes
ROOTS = dict(stone=(96, 78, 60), bedrock=(36, 28, 22), mortar=(54, 42, 32), back=(64, 52, 40),
             top=(118, 156, 72), top_kind="grass", ore=(240, 176, 70), ore_glow=(255, 210, 110),
             wood=(112, 80, 52), sky=(20, 18, 14), far=(40, 34, 26), mid=(58, 48, 36), near=(80, 64, 46),
             accent=(240, 180, 70))
OBSIDIAN = dict(stone=(48, 42, 62), bedrock=(14, 10, 20), mortar=(24, 18, 34), back=(32, 26, 44),
                top=(196, 96, 255), top_kind="magma", ore=(190, 100, 255), ore_glow=(230, 170, 255),
                wood=(62, 52, 74), sky=(8, 4, 14), far=(22, 14, 32), mid=(32, 22, 46), near=(46, 32, 62),
                accent=(190, 90, 255))
ECLIPSE = dict(stone=(74, 62, 78), bedrock=(20, 14, 24), mortar=(34, 26, 40), back=(48, 38, 54),
               top=(236, 188, 92), top_kind="crystal", ore=(255, 200, 90), ore_glow=(255, 232, 150),
               wood=(92, 72, 60), sky=(10, 6, 14), far=(30, 20, 34), mid=(46, 32, 50), near=(64, 46, 66),
               accent=(255, 190, 80))

AMBER = (240, 170, 60)
AMBER_HOT = (255, 226, 150)
BARK = (104, 78, 54)
BARK_DARK = (62, 44, 32)
LEAF = (108, 150, 70)
GLASS = (40, 34, 56)
GLASS_LIT = (108, 96, 140)
VOID = (186, 92, 255)
VOID_HOT = (236, 190, 255)
GOLD = (232, 182, 72)
GOLD_LIT = (255, 230, 150)
BLACK = (16, 10, 22)


def save(im, name):
    im.save(os.path.join(DECOR, name + ".png"))
    print("decor:", name)


def _root(d, pts, w, col, alpha=255):
    """A gnarled root along pts: dark body, lit upper edge."""
    d.line(pts, fill=rgba(col, alpha), width=w)
    d.line([(x, y - (w // 2)) for x, y in pts], fill=rgba(sh(col, 1.35), alpha))


# ======================================================== world roots decor
def root_arch():
    """32x32 floor: a petrified root bursting out of the floor and diving back,
    an amber knot glowing in its bend, a tuft of moss."""
    im, g = blank(32, 32), blank(32, 32)
    d = ImageDraw.Draw(im)
    pts = [(3, 31), (5, 22), (9, 14), (15, 10), (21, 11), (26, 17), (28, 25), (29, 31)]
    d.line(pts, fill=rgba(BARK_DARK), width=6)
    d.line(pts, fill=rgba(BARK), width=4)
    d.line([(x, y - 2) for x, y in pts], fill=rgba(sh(BARK, 1.35)))
    for x, y in pts[1:-1:2]:  # bark rings
        d.line((x - 2, y - 1, x + 1, y + 2), fill=rgba(BARK_DARK))
    _root(d, [(9, 14), (7, 9), (8, 5)], 2, BARK)  # a broken off shoot
    _root(d, [(24, 13), (27, 9), (31, 8)], 2, BARK)
    d.ellipse((13, 8, 18, 13), fill=rgba(AMBER))
    d.point((14, 9), fill=rgba(AMBER_HOT))
    d.point((16, 11), fill=rgba((90, 50, 20)))  # a fly in the amber
    glow_dot(g, 15.5, 10.5, 6, (255, 180, 80), 0.7)
    for x in range(5, 12):
        d.point((x, 21 - (x - 5) // 2), fill=rgba(LEAF))
    for x in (2, 4, 27, 30):
        d.point((x, 31), fill=rgba(sh(BARK_DARK, 0.8)))
    return finish(im, g)


def hanging_roots():
    """16x32 ceiling: root tendrils hanging from the vault, amber drops on the tips."""
    im, g = blank(16, 32), blank(16, 32)
    d = ImageDraw.Draw(im)
    for k, (x0, ln, ph) in enumerate(((3, 26, 0.0), (7, 18, 1.2), (10, 30, 2.1), (13, 14, 0.7))):
        prev = None
        for y in range(ln):
            x = x0 + math.sin(y * 0.25 + ph) * 1.2
            if prev:
                d.line((prev[0], prev[1], x, y), fill=rgba(BARK if k % 2 else sh(BARK, 0.85)), width=2 if y < ln // 2 else 1)
            prev = (x, y)
        d.point((round(prev[0]), ln), fill=rgba(AMBER))
        d.point((round(prev[0]), ln + 1), fill=rgba(AMBER_HOT))
        glow_dot(g, prev[0], ln + 1, 2.5, (255, 190, 90), 0.5)
    d.line((0, 0, 15, 0), fill=rgba(BARK_DARK), width=2)
    return finish(im, g)


def amber_node():
    """16x16 floor: a lump of glowing sap on a root stub, something sleeps inside."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    _root(d, [(1, 15), (5, 13), (11, 14), (15, 15)], 3, BARK)
    m = mask(16, 16, lambda dd: dd.polygon([(4, 13), (5, 6), (8, 2), (11, 5), (12, 13)], fill=FULL))
    lit(im, m, AMBER, 6, 5, 4, 6, alpha=235)
    d = ImageDraw.Draw(im)
    d.line((6, 4, 6, 10), fill=rgba(AMBER_HOT))
    d.ellipse((7, 7, 10, 10), fill=rgba((110, 60, 30)))  # a curled beetle
    d.point((9, 8), fill=rgba((180, 120, 60)))
    glow_dot(g, 8, 8, 7, (255, 170, 70), 0.75)
    return finish(im, g)


def root_wall():
    """16x16 wall: roots forcing their way through cracked masonry."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((0, 8, 4, 6, 9, 9, 15, 7), fill=rgba((30, 22, 18)), width=2)  # the crack
    _root(d, [(0, 3), (4, 5), (8, 4), (12, 7), (15, 6)], 2, BARK)
    _root(d, [(2, 15), (5, 11), (9, 12), (11, 9)], 2, sh(BARK, 0.9))
    for x, y in ((6, 4), (12, 6), (5, 12)):
        d.point((x, y - 1), fill=rgba(LEAF))
    d.point((11, 8), fill=rgba(AMBER))
    return finish(im)


def firefly_bloom():
    """16x16 floor: pale bell flowers that fireflies sleep in."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for x0, top, ph in ((4, 5, 0), (8, 3, 1), (12, 6, 2)):
        d.line((x0, 15, x0 + (ph - 1) * 0.5, top + 2), fill=rgba(sh(LEAF, 0.8)))
        d.polygon([(x0 - 2, top + 2), (x0, top - 1), (x0 + 2, top + 2)], fill=rgba((230, 220, 160)))
        d.point((x0, top + 2), fill=rgba((255, 250, 200)))
        glow_dot(g, x0, top + 1, 3, (220, 255, 140), 0.55)
    d.line((2, 15, 14, 15), fill=rgba(LEAF))
    for x, y in ((2, 2), (14, 1), (10, 9)):
        d.point((x, y), fill=rgba((220, 255, 120)))
        glow_dot(g, x, y, 1.5, (220, 255, 120), 0.6)
    return finish(im, g)


def petrified_stump():
    """16x16 floor: a stone-hard stump with growth rings and a mushroom."""
    im = blank(16, 16)
    m = mask(16, 16, lambda dd: dd.rectangle((3, 6, 12, 15), fill=FULL))
    lit(im, m, sh(BARK, 0.9), 5, 8, 5, 6, flat=0.2)
    d = ImageDraw.Draw(im)
    d.ellipse((3, 4, 12, 8), fill=rgba((150, 120, 84)))
    d.ellipse((5, 5, 10, 7), outline=rgba((112, 86, 60)))
    d.point((7, 6), fill=rgba((90, 66, 46)))
    for x in (5, 8, 11):
        d.line((x, 9, x, 14), fill=rgba(BARK_DARK))
    d.polygon([(1, 15), (3, 12), (4, 15)], fill=rgba(BARK))  # flared roots
    d.polygon([(11, 15), (13, 12), (15, 15)], fill=rgba(BARK))
    d.ellipse((11, 9, 14, 11), fill=rgba((200, 120, 80)))  # shelf mushroom
    d.point((12, 9), fill=rgba((240, 190, 150)))
    return finish(im)


def seed_pod():
    """16x16 ceiling: a glowing seed of the world tree on a stalk, veined."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((8, 0, 8, 4), fill=rgba(BARK), width=2)
    m = mask(16, 16, lambda dd: dd.ellipse((4, 4, 12, 14), fill=FULL))
    lit(im, m, (196, 150, 70), 6, 6, 4, 5)
    d = ImageDraw.Draw(im)
    for x in (6, 8, 10):
        d.line((8, 5, x, 13), fill=rgba(AMBER_HOT))
    d.point((8, 14), fill=rgba(AMBER_HOT))
    glow_dot(g, 8, 9, 6, (255, 200, 100), 0.7)
    return finish(im, g)


ROOTS_DECOR = [("root_arch", 0, 1.0, None, False, False), ("hanging_roots", 1, 1.4, (1.0, 0.75, 0.4), True, True),
               ("amber_node", 0, 1.2, (1.0, 0.72, 0.35), True, False), ("root_wall", 2, 1.4, None, False, False),
               ("firefly_bloom", 0, 1.3, (0.85, 1.0, 0.55), True, False), ("petrified_stump", 0, 1.0, None, False, False),
               ("seed_pod", 1, 0.8, (1.0, 0.8, 0.45), True, False)]


# ===================================================== obsidian abyss decor
def obsidian_spire():
    """16x32 floor: a black glass spike, faceted, a violet vein pulsing inside."""
    im, g = blank(16, 32), blank(16, 32)
    d = ImageDraw.Draw(im)
    d.polygon([(3, 31), (7, 2), (12, 31)], fill=rgba(GLASS))
    d.polygon([(7, 2), (12, 31), (9, 31)], fill=rgba(sh(GLASS, 0.7)))  # shadow facet
    d.line((7, 2, 4, 31), fill=rgba(GLASS_LIT))  # lit edge
    d.line((6, 10, 5, 20), fill=rgba((200, 190, 230)))  # glint
    d.line((8, 8, 9, 16, 7, 23, 9, 30), fill=rgba(VOID))
    d.point((9, 16), fill=rgba(VOID_HOT))
    d.polygon([(11, 31), (13, 22), (15, 31)], fill=rgba(GLASS))  # a small one beside
    d.line((13, 22, 12, 31), fill=rgba(GLASS_LIT))
    glow_dot(g, 8, 18, 5, (200, 110, 255), 0.6)
    return finish(im, g)


def void_rift():
    """16x16 wall: the wall split open, and behind it - nothing, violet."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    pts = [(8, 0), (6, 4), (9, 7), (6, 11), (8, 15)]
    d.line(pts, fill=rgba((20, 10, 30)), width=4)
    d.line(pts, fill=rgba(VOID), width=2)
    d.line(pts, fill=rgba(VOID_HOT))
    for x, y in ((3, 5), (12, 9), (4, 12), (11, 3)):
        d.point((x, y), fill=rgba(VOID))  # motes drawn out of the rift
    glow_dot(g, 7.5, 7.5, 7, (190, 100, 255), 0.75)
    return finish(im, g)


def floating_shards():
    """16x16 floor: obsidian shards hanging in the air over a glowing scar."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((2, 15, 13, 15), fill=rgba(VOID))
    d.line((5, 15, 10, 15), fill=rgba(VOID_HOT))
    for cx, cy, s in ((4, 9, 2), (8, 4, 3), (12, 10, 2)):
        d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy + s + 1), (cx - s, cy)], fill=rgba(GLASS))
        d.line((cx, cy - s, cx - s, cy), fill=rgba(GLASS_LIT))
        d.point((cx, cy + s + 1), fill=rgba(VOID))
    glow_dot(g, 8, 14, 6, (190, 100, 255), 0.6)
    return finish(im, g)


def glass_skull():
    """16x16 floor: a skull half grown over with volcanic glass."""
    im = blank(16, 16)
    m = mask(16, 16, lambda dd: dd.ellipse((3, 5, 12, 14), fill=FULL))
    lit(im, m, (200, 192, 170), 6, 7, 5, 5)
    d = ImageDraw.Draw(im)
    d.rectangle((5, 12, 10, 15), fill=rgba((180, 170, 150)))
    for x in (6, 8, 10):
        d.point((x, 14), fill=rgba((60, 50, 50)))
    d.ellipse((4, 8, 6, 10), fill=rgba((30, 20, 30)))
    d.ellipse((8, 8, 10, 10), fill=rgba((30, 20, 30)))
    d.point((9, 9), fill=rgba(VOID))  # something still looks out
    d.polygon([(9, 4), (14, 6), (15, 15), (10, 15), (11, 10)], fill=rgba(GLASS))  # glass crust
    d.line((9, 4, 11, 10), fill=rgba(GLASS_LIT))
    return finish(im)


def void_brazier():
    """16x16 floor: an iron brazier burning with cold violet fire."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    iron = (70, 64, 80)
    d.line((5, 15, 7, 10), fill=rgba(iron))
    d.line((10, 15, 8, 10), fill=rgba(iron))
    d.polygon([(3, 7), (12, 7), (10, 10), (5, 10)], fill=rgba(iron))
    d.line((3, 7, 12, 7), fill=rgba(sh(iron, 1.5)))
    for x, hgt in ((5, 4), (7, 6), (9, 5), (11, 3)):
        d.line((x, 7, x, 7 - hgt), fill=rgba(VOID))
        d.point((x, 7 - hgt), fill=rgba(VOID_HOT))
    d.line((7, 6, 8, 3), fill=rgba(VOID_HOT))
    glow_dot(g, 7.5, 4, 6, (200, 110, 255), 0.8)
    return finish(im, g)


def abyss_chain():
    """16x32 ceiling: a chain into the dark with a weight of black glass."""
    im, g = blank(16, 32), blank(16, 32)
    d = ImageDraw.Draw(im)
    iron = (96, 90, 108)
    for y in range(0, 22, 3):
        if (y // 3) % 2:
            d.rectangle((7, y, 8, y + 3), outline=rgba(iron))
        else:
            d.ellipse((6, y, 9, y + 3), outline=rgba(sh(iron, 1.2)))
    d.polygon([(8, 22), (12, 26), (8, 31), (4, 26)], fill=rgba(GLASS))
    d.line((8, 22, 4, 26), fill=rgba(GLASS_LIT))
    d.point((8, 26), fill=rgba(VOID_HOT))
    glow_dot(g, 8, 26, 3, (190, 100, 255), 0.6)
    return finish(im, g)


def glass_stalactite():
    """16x16 ceiling: black glass dripping from the vault, a violet bead at the tip."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for x0, ln in ((3, 8), (7, 13), (11, 6), (13, 9)):
        d.polygon([(x0 - 2, 0), (x0 + 2, 0), (x0, ln)], fill=rgba(GLASS))
        d.line((x0 - 2, 0, x0, ln), fill=rgba(GLASS_LIT))
    d.point((7, 14), fill=rgba(VOID))
    d.point((7, 15), fill=rgba(VOID_HOT))
    glow_dot(g, 7, 14, 2.5, (190, 100, 255), 0.6)
    return finish(im, g)


OBSIDIAN_DECOR = [("obsidian_spire", 0, 1.3, (0.75, 0.4, 1.0), True, False), ("void_rift", 2, 1.2, (0.75, 0.4, 1.0), True, False),
                  ("floating_shards", 0, 1.0, (0.75, 0.4, 1.0), True, False), ("glass_skull", 0, 1.0, None, False, False),
                  ("void_brazier", 0, 0.9, (0.8, 0.45, 1.0), True, False), ("abyss_chain", 1, 1.0, None, False, True),
                  ("glass_stalactite", 1, 1.3, None, False, False)]


# ======================================================= eclipse heart decor
def _black_sun(d, g, cx, cy, r, rays=12):
    for i in range(rays):
        a = i * math.tau / rays
        ln = r + (3 if i % 2 == 0 else 1)
        d.line((cx + math.cos(a) * r, cy + math.sin(a) * r, cx + math.cos(a) * ln, cy + math.sin(a) * ln), fill=rgba(GOLD))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgba(GOLD_LIT))
    d.ellipse((cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1), fill=rgba(BLACK))
    if g is not None:
        glow_dot(g, cx, cy, r + 4, (255, 190, 80), 0.6)


def sun_altar():
    """32x16 floor: the Sun Temple's broken altar, the eclipse disc above it."""
    im, g = blank(32, 16), blank(32, 16)
    d = ImageDraw.Draw(im)
    stone = (98, 86, 100)
    m = mask(32, 16, lambda dd: dd.rectangle((4, 9, 27, 15), fill=FULL))
    lit(im, m, stone, 10, 10, 12, 4, flat=0.3)
    d = ImageDraw.Draw(im)
    d.rectangle((2, 8, 29, 9), fill=rgba(sh(stone, 1.3)))
    d.line((4, 12, 27, 12), fill=rgba(GOLD))  # gilded band
    d.polygon([(20, 9), (23, 15), (25, 9)], fill=rgba((30, 22, 34)))  # the break
    _black_sun(d, g, 15, 4, 3)
    for x in (6, 25):
        d.point((x, 7), fill=rgba(GOLD_LIT))  # candles' flames
        d.line((x, 8, x, 8), fill=rgba((230, 220, 200)))
        glow_dot(g, x, 7, 2, (255, 200, 100), 0.6)
    return finish(im, g)


def eclipse_banner():
    """16x32 wall: a black banner with the gold eclipse, frayed and singed."""
    im = blank(16, 32)
    d = ImageDraw.Draw(im)
    d.line((1, 1, 14, 1), fill=rgba((120, 96, 60)), width=2)
    cloth = (34, 24, 42)
    d.polygon([(3, 2), (12, 2), (12, 27), (10, 25), (8, 29), (6, 25), (3, 28)], fill=rgba(cloth))
    d.line((3, 2, 3, 28), fill=rgba(sh(cloth, 1.5)))
    d.line((4, 4, 11, 4), fill=rgba(GOLD))
    _black_sun(d, None, 7.5, 13, 3, rays=8)
    d.line((4, 22, 11, 22), fill=rgba(GOLD))
    for x, y in ((5, 26), (10, 26), (8, 28)):
        d.point((x, y), fill=rgba((90, 60, 40)))  # scorched hem
    return finish(im)


def golden_statue():
    """16x32 floor: a faceless gilded worshipper, hands raised to the black sun."""
    im = blank(16, 32)
    m = mask(16, 32, lambda dd: dd.polygon([(4, 30), (5, 14), (7, 10), (9, 10), (11, 14), (12, 30)], fill=FULL))
    lit(im, m, (190, 150, 70), 6, 14, 4, 10)
    d = ImageDraw.Draw(im)
    hm = mask(16, 32, lambda dd: dd.ellipse((6, 5, 10, 10), fill=FULL))
    lit(im, hm, (200, 160, 80), 7, 6, 2, 2)
    d = ImageDraw.Draw(im)
    d.line((6, 13, 3, 6), fill=rgba((180, 140, 64)), width=2)  # raised arms
    d.line((10, 13, 13, 6), fill=rgba((150, 116, 52)), width=2)
    d.point((8, 7), fill=rgba((90, 70, 30)))  # no face, only a crack
    for y in (18, 22, 26):
        d.line((6, y, 10, y + 1), fill=rgba((140, 104, 44)))  # robe folds
    d.rectangle((3, 30, 12, 31), fill=rgba((84, 72, 90)))
    d.line((9, 16, 11, 22), fill=rgba((40, 26, 30)))  # a black crack through the gilding
    return finish(im)


def corona_brazier():
    """16x16 floor: a golden bowl on a stem, a ring of fire around a dark core."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((8, 10, 8, 14), fill=rgba(GOLD), width=2)
    d.line((5, 15, 11, 15), fill=rgba(sh(GOLD, 0.7)))
    d.chord((3, 6, 13, 12), 0, 180, fill=rgba(GOLD))
    d.line((3, 9, 13, 9), fill=rgba(GOLD_LIT))
    for x in (4, 6, 10, 12):
        d.line((x, 8, x, 4 + (x % 3)), fill=rgba((255, 170, 60)))
        d.point((x, 4 + (x % 3)), fill=rgba(GOLD_LIT))
    d.ellipse((7, 5, 9, 7), fill=rgba(BLACK))
    glow_dot(g, 8, 6, 6, (255, 180, 70), 0.8)
    return finish(im, g)


def sun_relief():
    """16x16 wall: a carved relief of the sun, gouged out by the Eclipse's servants."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    stone = (98, 86, 100)
    d.ellipse((2, 2, 13, 13), fill=rgba(sh(stone, 0.85)))
    d.ellipse((2, 2, 13, 13), outline=rgba(sh(stone, 1.3)))
    for i in range(8):
        a = i * math.tau / 8
        d.line((7.5 + math.cos(a) * 3, 7.5 + math.sin(a) * 3, 7.5 + math.cos(a) * 5.5, 7.5 + math.sin(a) * 5.5),
               fill=rgba(GOLD if i % 2 else sh(GOLD, 0.7)))
    d.ellipse((5, 5, 10, 10), fill=rgba((26, 18, 30)))  # the face hacked out
    d.line((3, 12, 6, 9), fill=rgba((30, 20, 30)))  # chisel scars
    d.line((11, 4, 9, 6), fill=rgba((30, 20, 30)))
    return finish(im)


def black_sun_lamp():
    """16x16 ceiling: a hanging lamp, a black orb in a golden cage shining around its edge."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((8, 0, 8, 4), fill=rgba(sh(GOLD, 0.7)))
    _black_sun(d, g, 8, 9, 3)
    d.arc((3, 4, 13, 14), 200, 340, fill=rgba(GOLD))
    d.arc((3, 4, 13, 14), 20, 160, fill=rgba(sh(GOLD, 0.7)))
    return finish(im, g)


def offering_pile():
    """16x16 floor: coins, a cracked chalice and burnt petals left for the sun."""
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for x, y in ((3, 14), (5, 13), (7, 14), (9, 13), (11, 14), (6, 12), (8, 12), (10, 12), (7, 11)):
        d.ellipse((x - 1, y - 1, x + 1, y), fill=rgba(GOLD))
        d.point((x - 1, y - 1), fill=rgba(GOLD_LIT))
    d.polygon([(11, 5), (15, 5), (14, 8), (12, 8)], fill=rgba(sh(GOLD, 0.9)))  # chalice
    d.line((13, 8, 13, 11), fill=rgba(sh(GOLD, 0.8)))
    d.line((11, 12, 15, 12), fill=rgba(sh(GOLD, 0.8)))
    d.line((11, 5, 15, 5), fill=rgba(GOLD_LIT))
    for x, y in ((2, 10), (4, 9), (13, 14)):
        d.point((x, y), fill=rgba((120, 40, 40)))  # burnt petals
    glow_dot(g, 7, 13, 4, (255, 200, 90), 0.35)
    return finish(im, g)


ECLIPSE_DECOR = [("sun_altar", 0, 0.8, (1.0, 0.75, 0.35), True, False), ("eclipse_banner", 2, 1.2, None, False, True),
                 ("golden_statue", 0, 0.9, None, False, False), ("corona_brazier", 0, 1.1, (1.0, 0.7, 0.3), True, False),
                 ("sun_relief", 2, 1.2, None, False, False), ("black_sun_lamp", 1, 1.0, (1.0, 0.75, 0.4), True, False),
                 ("offering_pile", 0, 1.0, None, False, False)]


# -------------------------------------------------------------- parallax
def _grad(top, bottom):
    im = Image.new("RGBA", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(W):
            px[x, y] = c
    return im


def roots_far():
    """The world tree's trunk far away, roots the size of towers, amber lights."""
    im = _grad((16, 14, 10), (40, 32, 22))
    d = ImageDraw.Draw(im)
    rnd = random.Random(51)
    trunk = (34, 28, 20, 255)
    d.polygon([(120, 0), (200, 0), (214, H), (106, H)], fill=trunk)
    for k in range(9):  # bark furrows
        x = 126 + k * 9
        d.line((x, 0, x + (k - 4) * 2, H), fill=(28, 22, 16, 255))
    for side in (-1, 1):  # great roots spreading down to both sides
        for k in range(3):
            x0 = 160 + side * (30 + k * 16)
            pts = [(x0, 60 + k * 30)]
            for s in range(6):
                px_, py_ = pts[-1]
                pts.append((px_ + side * rnd.randint(18, 30), py_ + rnd.randint(6, 18)))
            d.line(pts, fill=(38, 30, 22, 255), width=12 - k * 3)
    for _ in range(40):  # amber lights / fireflies in the dark
        x, y = rnd.randint(0, W - 1), rnd.randint(0, H - 1)
        im.putpixel((x, y), (200, 150, 70, 255) if rnd.random() < 0.6 else (160, 200, 90, 255))
    return im


def roots_mid():
    """Roots crossing the cave, stone hanging in them like fruit."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(53)
    col, lit_c = (54, 42, 30, 255), (78, 62, 42, 255)
    for k in range(4):
        y0 = rnd.randint(10, 60)
        pts = [(-10, y0)]
        x = -10
        while x < W + 20:
            x += rnd.randint(30, 50)
            pts.append((x, pts[-1][1] + rnd.randint(-16, 22)))
        d.line(pts, fill=col, width=10 - k * 2)
        d.line([(px_, py_ - (5 - k)) for px_, py_ in pts], fill=lit_c, width=2)
        for px_, py_ in pts[1:-1:2]:  # dangling tendrils
            ln = rnd.randint(20, 60)
            d.line((px_, py_, px_ + rnd.randint(-4, 4), py_ + ln), fill=col, width=2)
            d.point((px_, py_ + ln + 1), fill=(220, 160, 70, 255))
    for i in range(3):  # boulders caught in the roots
        x, y = 50 + i * 110 + rnd.randint(-10, 10), rnd.randint(60, 110)
        d.ellipse((x - 12, y - 10, x + 12, y + 10), fill=(60, 50, 40, 255))
        d.arc((x - 12, y - 10, x + 12, y + 10), 180, 290, fill=(86, 72, 56, 255), width=2)
    d.rectangle((0, 150, W, H), fill=(42, 34, 26, 255))
    for x in range(0, W, 4):
        d.line((x, 150, x + rnd.randint(-1, 1), 146 - rnd.randint(0, 5)), fill=(70, 96, 50, 255))
    return im


def roots_near():
    """Root curtains and floating seeds (semi-transparent)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(55)
    for i in range(8):
        x0, ln = i * 42 + rnd.randint(0, 18), rnd.randint(30, 80)
        for y in range(ln):
            x = x0 + math.sin(y * 0.1 + i) * 2
            d.line((x, y, x + 2, y), fill=(60, 44, 30, 170))
        d.point((x0 + 1, ln), fill=(240, 180, 80, 200))
    for _ in range(18):
        x, y = rnd.randint(0, W - 1), rnd.randint(20, H - 1)
        d.point((x, y), fill=(255, 220, 140, 180))
        d.line((x - 2, y - 1, x + 2, y - 1), fill=(230, 220, 190, 80))  # seed fluff
    return im


def obsidian_far():
    """Black glass cliffs over the void, a violet aurora, falling stars upward."""
    im = _grad((6, 2, 12), (24, 12, 36))
    d = ImageDraw.Draw(im)
    rnd = random.Random(61)
    aur = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(aur)
    for k in range(3):
        pts = [(x, 30 + k * 14 + math.sin(x * 0.03 + k) * 10) for x in range(0, W + 8, 8)]
        ad.line(pts, fill=(170, 80, 255, 40), width=8)
        ad.line(pts, fill=(220, 160, 255, 50), width=2)
    im.alpha_composite(aur)
    for _ in range(70):
        im.putpixel((rnd.randint(0, W - 1), rnd.randint(0, 120)), (190, 150, 230, 255))
    cl = (16, 10, 24, 255)
    for i in range(7):  # jagged glass cliffs
        x = i * 50 + rnd.randint(-10, 10)
        top = rnd.randint(80, 130)
        d.polygon([(x - 34, H), (x - 6, top), (x + 4, top + 8), (x + 30, H)], fill=cl)
        d.line((x - 6, top, x - 20, H), fill=(60, 46, 84, 255))
    return im


def obsidian_mid():
    """Floating islands of black glass trailing violet dust."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(63)
    col, lit_c = (30, 22, 42, 255), (74, 60, 104, 255)
    for i in range(4):
        x, y, w = i * 82 + rnd.randint(20, 50), rnd.randint(40, 110), rnd.randint(16, 30)
        d.polygon([(x - w, y), (x + w, y), (x + w // 3, y + w * 1.4), (x - w // 4, y + w)], fill=col)
        d.line((x - w, y, x + w, y), fill=lit_c, width=2)
        d.line((x - w, y, x - w // 4, y + w), fill=lit_c)
        d.line((x + 2, y + 3, x - 1, y + w), fill=(190, 100, 255, 255))  # vein
        for k in range(6):  # dust falling off into the void
            d.point((x + rnd.randint(-w // 2, w // 2), y + w + 4 + k * 5), fill=(170, 90, 240, 200 - k * 25))
        if i % 2 == 0:
            d.polygon([(x - 6, y), (x - 3, y - 14), (x, y)], fill=col)  # spire on top
    return im


def obsidian_near():
    """Drifting shards and void motes (semi-transparent)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(65)
    for _ in range(16):
        x, y, s = rnd.randint(0, W - 1), rnd.randint(0, H - 1), rnd.choice((2, 3, 4))
        d.polygon([(x, y - s), (x + s, y), (x, y + s + 2), (x - s + 1, y)], fill=(26, 18, 36, 190))
        d.line((x, y - s, x - s + 1, y), fill=(110, 90, 150, 190))
    for _ in range(30):
        d.point((rnd.randint(0, W - 1), rnd.randint(0, H - 1)), fill=(210, 150, 255, 150))
    return im


def eclipse_far():
    """The eclipse fills the sky: a black disc in a burning corona over the
    temple's ruined domes."""
    im = _grad((8, 4, 12), (40, 22, 40))
    d = ImageDraw.Draw(im)
    rnd = random.Random(71)
    cx, cy, r = 160, 64, 34
    cor = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cor)
    for i in range(10, 0, -1):
        cd.ellipse((cx - r - i * 4, cy - r - i * 4, cx + r + i * 4, cy + r + i * 4), fill=(255, 170, 70, 14))
    for i in range(36):
        a = i * math.tau / 36 + 0.05
        ln = r + 10 + (12 if i % 3 == 0 else 4)
        cd.line((cx + math.cos(a) * (r + 2), cy + math.sin(a) * (r + 2), cx + math.cos(a) * ln, cy + math.sin(a) * ln),
                fill=(255, 200, 110, 120), width=2 if i % 3 == 0 else 1)
    im.alpha_composite(cor)
    d.ellipse((cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2), fill=(255, 230, 160, 255))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(6, 2, 10, 255))
    for _ in range(50):
        im.putpixel((rnd.randint(0, W - 1), rnd.randint(0, 140)), (200, 160, 120, 255))
    dome = (24, 14, 26, 255)
    for x, w, top in ((40, 46, 110), (130, 30, 128), (250, 52, 104)):
        d.rectangle((x - w // 2, top, x + w // 2, H), fill=dome)
        d.pieslice((x - w // 2, top - w // 2, x + w // 2, top + w // 2), 180, 360, fill=dome)
        d.line((x, top - w // 2, x, top - w // 2 - 8), fill=dome, width=2)
        d.rectangle((x - 3, top + 10, x + 3, top + 22), fill=(255, 190, 90, 255))  # lit window
    return im


def eclipse_mid():
    """Broken gilded colonnade, chains of the Eclipse's banners."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(73)
    col, lit_c, dark = (44, 30, 48, 255), (70, 52, 70, 255), (30, 20, 32, 255)
    for i in range(4):
        x = i * 80 + rnd.randint(14, 40)
        top = rnd.randint(30, 70)
        d.rectangle((x - 9, top, x + 9, H), fill=col)
        d.line((x - 9, top, x - 9, H), fill=lit_c)
        d.line((x + 9, top, x + 9, H), fill=dark)
        for fx in (-4, 0, 4):
            d.line((x + fx, top + 6, x + fx, H), fill=dark)
        d.rectangle((x - 13, top - 6, x + 13, top), fill=(150, 110, 50, 255))  # gilded capital
        d.line((x - 13, top - 6, x + 13, top - 6), fill=(230, 180, 80, 255))
        if i % 2:
            d.polygon([(x - 13, top - 6), (x - 2, top - 16), (x + 6, top - 8), (x + 13, top - 6)], fill=col)
        # banner between columns
        bx = x + 40
        d.polygon([(bx - 8, 20), (bx + 8, 20), (bx + 8, 70), (bx, 62), (bx - 8, 70)], fill=(26, 16, 30, 255))
        d.ellipse((bx - 4, 34, bx + 4, 42), outline=(230, 180, 80, 255))
    d.rectangle((0, 156, W, H), fill=(34, 24, 36, 255))
    d.line((0, 156, W, 156), fill=(120, 90, 60, 255))
    return im


def eclipse_near():
    """Ash and golden embers drifting toward the black sun (semi-transparent)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(75)
    for _ in range(40):
        x, y = rnd.randint(0, W - 1), rnd.randint(0, H - 1)
        if rnd.random() < 0.5:
            d.point((x, y), fill=(255, 200, 110, 190))
        else:
            d.line((x, y, x + 1, y - 1), fill=(90, 80, 90, 150))
    for i in range(5):  # chains hanging from above
        x = i * 70 + rnd.randint(0, 30)
        for y in range(0, rnd.randint(30, 70), 3):
            d.point((x, y), fill=(60, 50, 64, 180))
            d.point((x + (y // 3) % 2, y + 1), fill=(90, 76, 90, 180))
    return im


# --------------------------------------------------------------- tilesets
def _recolor(path, fn):
    """Recolors the tileset's accent pixels (the stock magma / crystal kinds)."""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = fn(r, g, b, a)
    im.save(path)


def _void_veins(r, g, b, a):
    """Magma orange -> void violet (only warm, saturated pixels)."""
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if ss > 0.45 and vv > 0.55 and (hh < 0.16 or hh > 0.95):
        nr, ng, nb = colorsys.hsv_to_rgb(0.78, ss * 0.85, vv)
        return int(nr * 255), int(ng * 255), int(nb * 255), a
    return r, g, b, a


def _gold_crystals(r, g, b, a):
    """Stock pale-blue crystal tips -> pale gold."""
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if ss > 0.2 and vv > 0.6 and 0.45 < hh < 0.62:
        nr, ng, nb = colorsys.hsv_to_rgb(0.12, ss, vv)
        return int(nr * 255), int(ng * 255), int(nb * 255), a
    return r, g, b, a


# --------------------------------------------------------------- monsters
def root_strangler():
    """World roots: a walking knot of roots shaped like a hunched man, an
    amber heart, a whip of a root for an arm (cultist frame layout)."""
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})

    def body(lash=(18, 16), lean=0, step=0, flash=False, dis=0, alpha=255, glow=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        L = lean
        for k, x in enumerate((9 + step, 14 - step)):  # root legs splitting into feet
            col = sh(BARK, 0.7 if k == 0 else 0.95)[:3]
            _limb(d, (x + L, 18), (x + L - 1, 24), col, alpha)
            d.line((x + L - 1, 24, x + L - 3, 27), fill=rgba(col, alpha))
            d.line((x + L - 1, 24, x + L + 1, 27), fill=rgba(col, alpha))
        tm = mask(fw, fh, lambda dd: dd.polygon([(7 + L, 20), (6 + L, 12), (9 + L, 6), (15 + L, 6), (17 + L, 12), (16 + L, 20)],
                                                fill=FULL))
        lit(im, tm, BARK, 9 + L, 9, 5, 7, alpha)
        d = ImageDraw.Draw(im)
        for (x0, y0, x1, y1) in ((8, 8, 10, 19), (12, 7, 12, 19), (15, 8, 14, 19)):  # twisted strands
            d.line((x0 + L, y0, x1 + L, y1), fill=rgba(BARK_DARK, alpha))
        heart = AMBER_HOT if flash or glow else AMBER
        d.ellipse((10 + L, 12, 13 + L, 15), fill=rgba(heart, alpha))
        d.point((11 + L, 13), fill=(255, 255, 230, alpha))
        # head: a knot with two amber eyes and a crown of shoots
        hm = mask(fw, fh, lambda dd: dd.ellipse((9 + L, 1, 16 + L, 8), fill=FULL))
        lit(im, hm, sh(BARK, 1.05)[:3], 11 + L, 3, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        e = (255, 255, 255, alpha) if flash else rgba(AMBER_HOT, alpha)
        d.point((12 + L, 4), fill=e)
        d.point((14 + L, 4), fill=e)
        for sx in (10, 13, 15):
            d.line((sx + L, 1, sx + L + (sx - 13) // 2, -1), fill=rgba(LEAF, alpha))
        _limb(d, (8 + L, 9), (5 + L, 16), sh(BARK, 0.7)[:3], alpha)  # back arm
        hx, hy = lash  # the whip arm, a thinning root
        mx, my = (15 + L + hx) / 2, (9 + hy) / 2 - 2
        d.line((15 + L, 9, mx, my), fill=rgba(BARK, alpha), width=2)
        d.line((mx, my, hx + L, hy), fill=rgba(sh(BARK, 1.2), alpha))
        d.point((hx + L, hy), fill=rgba(AMBER, alpha))
        if dis:
            dissolve(im, dis, color=(120, 90, 60, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(lash=(18, 16 + [0, 1, 0, -1][i]), glow=i == 1)
        if name == "walk":
            return body(lash=(18, 15 + i % 2), step=[-1, 0, 1, 1, 0, -1][i])
        if name == "windup":
            return body(lash=(14 - i, 3 + i // 2), lean=-1, glow=1)
        if name == "attack":
            return body(lash=[(22, 6), (23, 14), (21, 20)][i], lean=1, flash=i == 0)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    return lay, fn


def void_ray():
    """Obsidian abyss: a manta of black glass gliding over the void, its wings
    edged with violet light, a stinger tail (glass_layout: flyer 20x16)."""
    fw, fh = 20, 16
    lay = gs.monster_layout("glass_layout", fw, fh, (10, 12), "fly", {"idle": 4, "fly": 4, "windup": 2, "attack": 3, "death": 5})

    def body(wing, dy=0, rot=0, alpha=255, flash=False, tail=0, eye=True):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + dy
        for side in (-1, 1):
            tip = (10 + side * 9, cy - wing)
            pts = [(10, cy - 2), tip, (10 + side * 7, cy + 2), (10, cy + 2)]
            d.polygon(pts, fill=rgba(GLASS if side < 0 else sh(GLASS, 1.2)[:3], alpha))
            d.line((10, cy - 2, tip[0], tip[1]), fill=rgba(VOID_HOT if flash else VOID, alpha))  # glowing edge
            d.line((tip[0], tip[1], 10 + side * 7, cy + 2), fill=rgba(sh(VOID, 0.6), alpha))
        m = mask(fw, fh, lambda dd: dd.ellipse((7, cy - 3, 13, cy + 3), fill=FULL))
        lit(im, m, GLASS_LIT, 9, cy - 2, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        tx = 10 + tail
        d.line((10, cy + 3, tx, cy + 7), fill=rgba(GLASS_LIT, alpha))  # tail
        d.point((tx, cy + 7), fill=rgba(VOID_HOT, alpha))
        if eye:
            d.point((9, cy - 1), fill=(255, 255, 255, alpha) if flash else rgba(VOID_HOT, alpha))
            d.point((11, cy - 1), fill=(255, 255, 255, alpha) if flash else rgba(VOID_HOT, alpha))
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST, center=(10, 8))
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body([3, 1, -2, 1][i], dy=[0, 0, 1, 1][i] if name == "idle" else 0, tail=[0, 1, 0, -1][i])
        if name == "windup":
            return body(4 + i, dy=-1 - i, flash=i == 1, tail=-2)
        if name == "attack":
            return body(-2, dy=1, rot=[-25, -40, -30][i], flash=i == 0, tail=2)
        if name == "hurt":
            return body(2, flash=True, eye=False)
        im = body(-2, dy=i, rot=i * 50, alpha=255 - i * 40, eye=False)
        dissolve(im, 2 + i * 2, color=(150, 90, 220))
        return im

    return lay, fn


def light_eater():
    """Eclipse heart: a tall shroud with a black sun for a face, eating the
    light around it; it throws clots of darkness (cultist frame layout)."""
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    shroud = (40, 30, 48)

    def body(hand=(17, 15), orb=1, lean=0, sway=0, flash=False, dis=0, alpha=255, corona=0):
        im = blank(fw, fh)
        L = lean
        m = mask(fw, fh, lambda dd: dd.polygon([(6 + L + sway, 27), (8 + L, 10), (12 + L, 7), (16 + L, 10),
                                                (18 + L - sway, 27), (15 + L, 25), (12 + L, 27), (9 + L, 25)], fill=FULL))
        lit(im, m, shroud, 9 + L, 11, 5, 9, alpha, flat=0.15)
        d = ImageDraw.Draw(im)
        for x in (9, 12, 15):
            d.line((x + L, 13, x + L + (x - 12) // 3, 25), fill=rgba(sh(shroud, 0.6), alpha))
        d.line((8 + L, 16, 16 + L, 16), fill=rgba(GOLD, alpha))  # a gold sash, the temple's
        # the face: a black sun in a ring of gold rays that pulse
        cx, cy, r = 12 + L, 6, 3
        for k in range(10):
            a = k * math.tau / 10
            ln = r + 1 + (1 + corona if k % 2 == 0 else 0)
            d.line((cx + math.cos(a) * r, cy + math.sin(a) * r, cx + math.cos(a) * ln, cy + math.sin(a) * ln),
                   fill=rgba(GOLD_LIT if flash else GOLD, alpha))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgba(GOLD_LIT, alpha))
        d.ellipse((cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1), fill=rgba(BLACK, alpha))
        d.point((cx, cy), fill=(255, 255, 255, alpha) if flash else rgba((150, 90, 220), alpha))
        hx, hy = hand
        _limb(d, (15 + L, 11), (hx + L, hy), sh(shroud, 1.2)[:3], alpha)  # thin grey hand
        d.point((hx + L + 1, hy), fill=rgba((170, 160, 170), alpha))
        if orb:
            ox, oy = hx + L + 1, hy - 2
            d.ellipse((ox - orb, oy - orb, ox + orb, oy + orb), fill=rgba(BLACK, alpha))
            d.arc((ox - orb - 1, oy - orb - 1, ox + orb + 1, oy + orb + 1), 180, 300, fill=rgba(VOID, alpha))
        if dis:
            dissolve(im, dis, color=(230, 180, 90, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i], corona=i % 2)
        if name == "walk":
            return body(sway=[1, 0, -1, -1, 0, 1][i], hand=(17, 15 + i % 2), corona=i % 2)
        if name == "windup":
            return body(hand=(15, 11 - i), orb=1 + i // 2, lean=-1, corona=1)
        if name == "attack":
            return body(hand=[(18, 9), (20, 12), (19, 15)][i], orb=[2, 0, 0][i], flash=i == 0, lean=1, corona=2)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30, orb=0)

    return lay, fn


MONSTERS = {"root_strangler": root_strangler, "void_ray": void_ray, "light_eater": light_eater}

ENEMY_TRES = {
    # id: name, desc, sheet layout, behavior, collision, hp, dmg, armor, speed, chase, aggro, range, cd, xp, gold,
    #     weight, biomes, resistances, immunities, on-hit (status, duration, power, chance), projectile, jumps, sound
    "root_strangler": ("Корнедушец", "Узел корней мирового древа, обретший форму. Хлещет корнем и опутывает — ноги вязнут.",
                       "cultist_layout", 0, (12, 18), 120, 17, 4, 26.0, 50.0, 160.0, 22.0, 1.5, 34, (4, 10), 1.2,
                       ["world_roots"], {"res_fire": -0.6, "res_poison": 0.5}, [], ("slow", 2.0, 0.4, 0.5), None, False,
                       "enemy_attack"),
    "void_ray": ("Бездновый скат", "Стеклянный скат, что плывёт над пустотой. Пикирует молча — слышно только звон крыльев.",
                 "glass_layout", 1, (14, 10), 64, 18, 0, 34.0, 100.0, 210.0, 12.0, 1.1, 32, (3, 8), 1.1,
                 ["obsidian_abyss"], {"res_ice": 0.4, "res_fire": -0.4}, [], ("bleed", 3.0, 3.0, 0.35), None, False, ""),
    "light_eater": ("Пожиратель света", "Служитель Затмения с чёрным солнцем вместо лица. Гасит свет вокруг и бросает сгустки тьмы.",
                    "cultist_layout", 2, (12, 18), 90, 19, 1, 28.0, 46.0, 210.0, 170.0, 1.8, 40, (5, 12), 1.0,
                    ["eclipse_heart"], {"res_magic": 0.6, "res_fire": -0.6}, ["curse"], ("curse", 3.0, 1.0, 0.35),
                    "res://assets/sprites/fx/dark_bolt.png", False, "enemy_shoot"),
}


def enemy_tres(eid, spec):
    (name, desc, layout, beh, coll, hp, dmg, armor, spd, chase, aggro, rng, cd, xp, gold, weight, biomes, res, imm,
     onhit, proj, jumps, sound) = spec
    ext = ['[ext_resource type="Resource" path="res://data/loot_tables/enemy_common.tres" id="1_lt"]',
           '[ext_resource type="Script" path="res://scripts/combat/hit_effect.gd" id="2_he"]',
           '[ext_resource type="Script" path="res://scripts/combat/status_hit_effect.gd" id="3_st"]',
           '[ext_resource type="Script" path="res://scripts/data/enemy_data.gd" id="4_ed"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/enemies/%s_sheet.png" id="5_sh"]' % eid,
           '[ext_resource type="Resource" path="res://data/animations/%s.tres" id="6_la"]' % layout,
           '[ext_resource type="Texture2D" path="res://assets/sprites/enemies/%s.png" id="7_ic"]' % eid]
    if proj:
        ext.append('[ext_resource type="Texture2D" path="%s" id="8_pr"]' % proj)
    st, dur, pw, ch = onhit
    sub = "\n".join(['[sub_resource type="Resource" id="Resource_hit"]', 'script = ExtResource("3_st")',
                     "status = &\"%s\"" % st, "duration = %s" % dur, "power = %s" % pw, "chance = %s" % ch])
    lines = ["[resource]", 'script = ExtResource("4_ed")', 'id = &"%s"' % eid, 'display_name = "%s"' % name,
             'description = "%s"' % desc, 'texture = ExtResource("7_ic")', 'sheet = ExtResource("5_sh")',
             'sheet_layout = ExtResource("6_la")', "behavior = %d" % beh, "collision_size = Vector2(%d, %d)" % coll,
             "max_hp = %d" % hp, "damage = %d" % dmg, "armor = %d" % armor, "speed = %s" % spd, "chase_speed = %s" % chase,
             "aggro_range = %s" % aggro, "attack_range = %s" % rng, "attack_cooldown = %s" % cd,
             "jumps = %s" % ("true" if jumps else "false")]
    if proj:
        lines.append('projectile_texture = ExtResource("8_pr")')
    lines += ["projectile_speed = 150.0", "xp_reward = %d" % xp, 'loot_table = ExtResource("1_lt")', "loot_chance = 0.4",
              "gold_min = %d" % gold[0], "gold_max = %d" % gold[1], "min_floor = 25", "spawn_weight = %s" % weight,
              "biomes = Array[StringName]([%s])" % ", ".join('&"%s"' % b for b in biomes), "tint = Color(1, 1, 1, 1)",
              'gender = "m"', "phases_through_walls = false", "ceiling_ambush = false", "aoe_radius = 0.0",
              "max_summons = 3", "resistances = {\n%s\n}" % ",\n".join('"%s": %s' % kv for kv in res.items()),
              "status_immunities = Array[StringName]([%s])" % ", ".join('&"%s"' % s for s in imm),
              'on_hit_effects = Array[ExtResource("2_he")]([SubResource("Resource_hit")])',
              'sound_hurt = &"enemy_hurt"', 'sound_death = &"enemy_death"', 'sound_attack = &"%s"' % sound]
    head = '[gd_resource type="Resource" script_class="EnemyData" load_steps=%d format=3]' % (len(ext) + 2)
    return head + "\n\n" + "\n".join(ext) + "\n\n" + sub + "\n\n" + "\n".join(lines) + "\n"


# Existing monsters that also live down here (added to their biome lists).
ALSO = {
    "world_roots": ["spider", "sporeling", "ghost", "bog_spitter"],
    "obsidian_abyss": ["ember_hound", "crystal_crawler", "ash_husk", "glass_stalker"],
    "eclipse_heart": ["cultist", "summoner", "ghost", "runite_sentinel", "glass_stalker"],
}


def add_biome_to_enemy(eid, biome):
    path = os.path.join(gb.DATA, "..", "enemies", eid + ".tres")
    s = open(path, encoding="utf-8").read()
    if '&"%s"' % biome in s:
        return
    import re
    s = re.sub(r"biomes = Array\[StringName\]\(\[(.*?)\]\)",
               lambda m: "biomes = Array[StringName]([%s])" % ((m.group(1) + ", " if m.group(1) else "") + '&"%s"' % biome), s, count=1)
    open(path, "w", encoding="utf-8", newline="\n").write(s)


# ------------------------------------------------------------- biome data
BIOMES = {
    "world_roots": ("Корни мира", 8, ROOTS, ROOTS_DECOR, (roots_far, roots_mid, roots_near), None,
                    dict(music="world_roots", particle="pollen", ore="iron_ore",
                         ambient="Color(0.95, 0.9, 0.82, 1)", back_mod="Color(0.82, 0.76, 0.68, 1)",
                         torch="Color(1.0, 0.75, 0.4, 1)", particles="Color(1.0, 0.85, 0.5, 1)",
                         fog="Color(0.4, 0.32, 0.22, 1)", fog_amount="0.1", tint="Color(1.02, 0.98, 0.92, 1)",
                         contrast="1.03", per_room="4.5", ore_chance="0.06")),
    "obsidian_abyss": ("Обсидиановая бездна", 9, OBSIDIAN, OBSIDIAN_DECOR, (obsidian_far, obsidian_mid, obsidian_near),
                       _void_veins,
                       dict(music="obsidian_abyss", particle="embers", ore="moon_crystal",
                            ambient="Color(0.86, 0.8, 0.96, 1)", back_mod="Color(0.7, 0.64, 0.82, 1)",
                            torch="Color(0.8, 0.5, 1.0, 1)", particles="Color(0.8, 0.55, 1.0, 1)",
                            fog="Color(0.3, 0.18, 0.42, 1)", fog_amount="0.12", tint="Color(0.98, 0.95, 1.04, 1)",
                            contrast="1.06", per_room="4.5", ore_chance="0.05")),
    "eclipse_heart": ("Сердце Затмения", 10, ECLIPSE, ECLIPSE_DECOR, (eclipse_far, eclipse_mid, eclipse_near),
                      _gold_crystals,
                      dict(music="eclipse_heart", particle="sparkles", ore="moon_crystal",
                           ambient="Color(0.92, 0.86, 0.9, 1)", back_mod="Color(0.76, 0.68, 0.76, 1)",
                           torch="Color(1.0, 0.72, 0.36, 1)", particles="Color(1.0, 0.8, 0.45, 1)",
                           fog="Color(0.34, 0.22, 0.3, 1)", fog_amount="0.12", tint="Color(1.03, 0.97, 0.95, 1)",
                           contrast="1.07", per_room="4.5", ore_chance="0.05")),
}

# Music (gen_audio.compose specs).
TRACKS = {
    # World roots: an old forest under the earth - warm dorian, wooden plucks,
    # hand drums like a slow pulse in the trunk, a flute high in the branches.
    "world_roots": dict(key="D", scale="dorian", bpm=78, prog=[0, 6, 3, 4], pad="pad", bright=0.6, bass="roots",
                        arp="pluck", arp_rate=2, drums="hand", drums_from=1, lead="flute", lead_octave=1,
                        density=0.4, sevenths=True, bars=32, seed=51),
    # Obsidian abyss: falling forever - harmonic minor, glass bells over a
    # pulsing low ostinato, no drums at first, then taiko like distant rockfalls.
    "obsidian_abyss": dict(key="F", scale="harmonic", bpm=70, prog=[0, 5, 1, 4], pad="choir", bright=0.45,
                           bass="ostinato", grit=0.3, bass_drive=1.2, arp="bell", arp_rate=2, drums="taiko",
                           drums_from=2, lead="box", lead_octave=1, density=0.3, bars=32, seed=53),
    # Eclipse heart: the dead temple - phrygian choir, tolling, brass stabs of
    # the coming fight; the Dies irae is near.
    "eclipse_heart": dict(key="C", scale="phrygian", bpm=66, prog=[0, 1, 6, 0, 0, 1, 3, 4], pad="choir", bright=0.5,
                          bass="roots", toll=True, drums="heartbeat", stabs=True, lead="lead", lead_octave=1,
                          density=0.3, bars=32, seed=55),
}


def main() -> None:
    os.makedirs(DECOR, exist_ok=True)
    for bid, (title, order, pal, decor, layers, recolor, meta) in BIOMES.items():
        for name, *_ in decor:
            save(globals()[name](), name)
        for layer, fn in zip(("far", "mid", "near"), layers):
            fn().save(os.path.join(BG, "%s_%s.png" % (bid, layer)))
        gb.tileset(bid, pal)
        if recolor:
            _recolor(os.path.join(TILES, "tiles_%s.png" % bid), recolor)
        gdb.write_tres(bid, title, order, decor, meta)
        print("biome:", bid)
    for eid, builder in MONSTERS.items():
        lay, fn = builder()
        gs.render_sheet(lay, fn, "sprites/enemies/%s_sheet.png" % eid, do_outline=True)
        sheet = Image.open(os.path.join(gp.A, "sprites/enemies/%s_sheet.png" % eid))
        sheet.crop((0, 0, lay.fw, lay.fh)).save(os.path.join(gp.A, "sprites/enemies/%s.png" % eid))
        with open(os.path.join(gb.DATA, "..", "enemies", eid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(enemy_tres(eid, ENEMY_TRES[eid]))
        print("monster:", eid)
    for biome, ids in ALSO.items():
        for eid in ids:
            add_biome_to_enemy(eid, biome)
    if os.environ.get("NO_MUSIC") != "1":
        import gen_audio as ga
        for name, spec in TRACKS.items():
            ga.write_ogg("music_" + name, ga.compose(spec))


if __name__ == "__main__":
    main()
