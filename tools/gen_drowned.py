#!/usr/bin/env python3
"""Drowned Vaults, its own look: nothing borrowed from other biomes.

* decor: kelp, glowing coral, a barnacled anchor, a sunken chest, a drowned
  statue, dripping moss, jellyfish lanterns, a barnacle-crusted wall, a pile
  of shells, a waterlogged lantern post;
* parallax: a flooded cathedral with light shafts from the surface (far),
  sunken columns standing in water (mid), hanging kelp and bubbles (near);
* tileset: the "algae" edge (slimy green tops, barnacles, drips under the
  bricks);
* data/biomes/drowned_vaults.tres with the new decor and bubbles instead of dust.
Run from tools/:  python3 gen_drowned.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_biomes as gb
import gen_deep_biomes as gdb
import gen_placeholders as gp
from gen_monsters import blank, lit, mask, rgba, sh, FULL
from gen_structures import finish, glow_dot

DECOR = os.path.join(gp.A, "sprites", "decor")
BG = os.path.join(gp.A, "sprites", "backgrounds")

STONE = (76, 98, 90)
ALGAE = (70, 150, 96)
ALGAE_LIT = (130, 210, 140)
KELP = (52, 118, 84)
RUST = (126, 82, 56)
BARNACLE = (196, 196, 176)
WATER = (60, 150, 160)
GLOW = (120, 240, 210)


def save(im, name):
    im.save(os.path.join(DECOR, name + ".png"))
    print("decor:", name)


# ----------------------------------------------------------------- decor
def kelp():
    """16x32 floor: three swaying blades of kelp with air bladders."""
    im = blank(16, 32)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)
    for k, (x0, top, phase) in enumerate(((5, 4, 0.0), (9, 1, 1.4), (12, 9, 2.6))):
        prev = None
        for y in range(31, top - 1, -1):
            t = (31 - y) / 28.0
            x = x0 + math.sin(t * 5.0 + phase) * (1 + t * 2.0)
            w = 2 if t < 0.75 else 1
            col = KELP if k != 1 else sh(KELP, 1.15)
            d.line((x, y, x + w - 1, y), fill=rgba(col))
            d.point((round(x), y), fill=rgba(sh(col, 1.3)))  # lit edge
            if prev and y % 6 == 0:
                d.ellipse((x + w - 1, y - 1, x + w + 1, y + 1), fill=rgba((150, 140, 60)))  # air bladder
            prev = (x, y)
    for _ in range(3):
        d.point((rnd.randint(2, 13), 31), fill=rgba(sh(STONE, 0.7)))
    return finish(im)


def coral():
    """16x16 floor: a branching coral glowing faintly, with a polyp fringe."""
    im = blank(16, 16)
    g = blank(16, 16)
    d = ImageDraw.Draw(im)
    base = (230, 110, 120)
    def branch(x, y, ang, ln, depth):
        if depth == 0 or ln < 1.5:
            d.point((round(x), round(y)), fill=rgba((255, 200, 190)))
            glow_dot(g, x, y, 1.6, (255, 170, 170), 0.5)
            return
        x2 = x + math.cos(ang) * ln
        y2 = y + math.sin(ang) * ln
        d.line((x, y, x2, y2), fill=rgba(sh(base, 0.8 + depth * 0.1)), width=2 if depth > 2 else 1)
        branch(x2, y2, ang - 0.5, ln * 0.7, depth - 1)
        branch(x2, y2, ang + 0.45, ln * 0.68, depth - 1)
    branch(8, 15, -math.pi / 2, 5.0, 4)
    d.line((5, 15, 11, 15), fill=rgba(sh(base, 0.6)))
    return finish(im, g)


def anchor():
    """32x24 floor: a rusted anchor half sunk, crusted with barnacles."""
    im = blank(32, 24)
    d = ImageDraw.Draw(im)
    iron = (92, 84, 80)
    # shank lying at a slant
    d.line((6, 20, 24, 4), fill=rgba(iron), width=3)
    d.line((6, 19, 24, 3), fill=rgba(sh(iron, 1.35)))
    # ring at the top
    d.ellipse((22, 0, 29, 7), outline=rgba(iron), width=2)
    d.point((23, 1), fill=rgba(sh(iron, 1.5)))
    # stock (crossbar) near the ring
    d.line((17, 5, 25, 13), fill=rgba(sh(iron, 0.9)), width=2)
    # arms and flukes at the bottom
    d.arc((0, 12, 14, 26), 200, 340, fill=rgba(iron), width=3)
    d.polygon([(0, 17), (3, 14), (4, 19)], fill=rgba(sh(iron, 1.1)))
    d.polygon([(13, 15), (11, 13), (10, 18)], fill=rgba(sh(iron, 1.1)))
    rnd = random.Random(5)
    for _ in range(14):  # rust and barnacles
        x, y = rnd.randint(4, 26), rnd.randint(3, 21)
        if im.getpixel((x, y))[3]:
            d.point((x, y), fill=rgba(RUST if rnd.random() < 0.6 else BARNACLE))
    d.line((0, 23, 31, 23), fill=rgba(sh(STONE, 0.75)))  # silt it sank into
    d.line((3, 22, 14, 22), fill=rgba(sh(STONE, 0.9)))
    return finish(im)


def sunken_chest():
    """16x16 floor: a waterlogged chest, lid ajar, algae on the planks."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    wood = (96, 70, 48)
    m = mask(16, 16, lambda dd: dd.rectangle((1, 7, 14, 15), fill=FULL))
    lit(im, m, wood, 4, 8, 8, 6, flat=0.4)
    d = ImageDraw.Draw(im)
    d.polygon([(1, 7), (3, 3), (15, 4), (14, 7)], fill=rgba(sh(wood, 1.1)))  # lid ajar
    for y in (10, 13):
        d.line((1, y, 14, y), fill=rgba(sh(wood, 0.65)))
    for x in (2, 13):
        d.line((x, 7, x, 15), fill=rgba((150, 120, 70)))  # iron bands
    d.rectangle((7, 8, 8, 10), fill=rgba((180, 160, 90)))  # lock
    d.line((3, 7, 13, 7), fill=rgba((255, 220, 120)))  # gold glinting in the gap
    for x in range(1, 15, 2):
        d.point((x, 15 - (x % 3)), fill=rgba(ALGAE))
    d.point((4, 4), fill=rgba(ALGAE_LIT))
    d.point((11, 5), fill=rgba(BARNACLE))
    g = blank(16, 16)
    glow_dot(g, 8, 7, 3.0, (255, 220, 120), 0.5)
    return finish(im, g)


def drowned_statue():
    """16x32 floor: a weeping hooded statue, green with algae, water pooled at its feet."""
    im = blank(16, 32)
    d = ImageDraw.Draw(im)
    stone = (118, 132, 124)
    m = mask(16, 32, lambda dd: dd.polygon([(5, 6), (11, 6), (13, 27), (3, 27)], fill=FULL))
    lit(im, m, stone, 6, 10, 5, 12, flat=0.2)
    hm = mask(16, 32, lambda dd: dd.ellipse((4, 1, 12, 10), fill=FULL))
    lit(im, hm, sh(stone, 0.95), 6, 3, 4, 4)
    d = ImageDraw.Draw(im)
    d.ellipse((6, 4, 10, 9), fill=rgba(sh(stone, 0.45)))  # face in the hood's shadow
    d.point((7, 6), fill=rgba(GLOW))
    d.point((9, 6), fill=rgba(GLOW))
    d.line((7, 7, 7, 9), fill=rgba(sh(WATER, 1.4)))  # tears of water
    d.line((8, 12, 6, 20), fill=rgba(sh(stone, 0.7)))  # robe folds
    d.line((10, 12, 11, 22), fill=rgba(sh(stone, 0.7)))
    rnd = random.Random(9)
    for _ in range(18):  # algae creeping up from the bottom
        x, y = rnd.randint(3, 13), rnd.randint(14, 27)
        if im.getpixel((x, y))[3] and rnd.random() < (y - 12) / 16:
            d.point((x, y), fill=rgba(ALGAE if rnd.random() < 0.7 else ALGAE_LIT))
    d.rectangle((2, 27, 14, 31), fill=rgba(sh(stone, 0.75)))  # plinth
    d.line((2, 27, 14, 27), fill=rgba(sh(stone, 1.15)))
    d.line((0, 31, 15, 31), fill=rgba(WATER, 200))  # pooled water
    g = blank(16, 32)
    glow_dot(g, 8, 6, 2.5, GLOW, 0.6)
    return finish(im, g)


def dripping_moss():
    """16x16 ceiling: slimy moss hanging in strands, drops at the tips."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(11)
    d.line((0, 0, 15, 0), fill=rgba(sh(ALGAE, 0.8)))
    for x in range(1, 15, 2):
        ln = rnd.randint(3, 12)
        for y in range(ln):
            col = ALGAE_LIT if y == 0 else (ALGAE if y < ln - 2 else sh(ALGAE, 0.75))
            d.point((x + (1 if y > ln * 0.6 and x % 4 == 1 else 0), y), fill=rgba(col))
        if rnd.random() < 0.6:
            d.point((x, ln + 1), fill=rgba(sh(WATER, 1.6)))
    return finish(im)


def jelly_lantern():
    """16x16 ceiling: a glowing jellyfish caught under the vault."""
    im = blank(16, 16)
    g = blank(16, 16)
    bell = (170, 120, 230)
    m = mask(16, 16, lambda dd: dd.pieslice((3, 1, 13, 11), 180, 360, fill=FULL))
    lit(im, m, bell, 6, 3, 5, 4, alpha=230)
    d = ImageDraw.Draw(im)
    d.line((3, 6, 12, 6), fill=rgba(sh(bell, 0.75)))
    for k, x in enumerate((4, 6, 8, 10, 12)):
        for y in range(7, 13 + (k % 2) * 2):
            d.point((x + (1 if (y + k) % 4 == 0 else 0), y), fill=rgba((210, 180, 255), 180))
    d.point((6, 3), fill=rgba((255, 255, 255)))
    glow_dot(g, 8, 5, 5.0, (190, 140, 255), 0.75)
    return finish(im, g)


def barnacle_wall():
    """16x16 wall: a patch of barnacles and mussels with a seep of water."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(13)
    d.line((8, 0, 8, 15), fill=rgba(sh(WATER, 1.2), 150))  # the seep
    d.line((9, 2, 9, 15), fill=rgba(sh(WATER, 0.9), 110))
    for _ in range(9):
        x, y = rnd.randint(2, 13), rnd.randint(3, 13)
        if rnd.random() < 0.6:
            d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=rgba(BARNACLE))
            d.point((x, y), fill=rgba(sh(BARNACLE, 0.5)))
        else:
            d.polygon([(x, y - 2), (x + 2, y + 1), (x - 1, y + 1)], fill=rgba((40, 46, 70)))  # mussel
            d.point((x, y - 1), fill=rgba((110, 120, 170)))
    return finish(im)


def shell_pile():
    """16x16 floor: shells, a starfish and pebbles washed into a corner."""
    im = blank(16, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((1, 12, 14, 16), fill=rgba(sh(STONE, 0.8)))
    for x, y, c in ((4, 12, (236, 214, 190)), (9, 13, (220, 180, 200)), (12, 12, (240, 230, 210))):
        d.pieslice((x - 2, y - 2, x + 2, y + 2), 180, 360, fill=rgba(c))
        d.line((x, y - 2, x, y), fill=rgba(sh(c, 0.7)))
    sx, sy = 7, 10  # starfish
    for k in range(5):
        a = -math.pi / 2 + k * math.tau / 5
        d.line((sx, sy, sx + math.cos(a) * 2.6, sy + math.sin(a) * 2.6), fill=rgba((240, 130, 80)))
    d.point((sx, sy), fill=rgba((255, 190, 140)))
    return finish(im)


def lantern_post():
    """16x32 floor: a drowned lamppost, its lantern still burning green."""
    im = blank(16, 32)
    g = blank(16, 32)
    d = ImageDraw.Draw(im)
    iron = (70, 76, 72)
    d.line((8, 10, 8, 31), fill=rgba(iron), width=2)
    d.line((8, 10, 8, 31), fill=rgba(sh(iron, 1.4)))
    d.line((5, 31, 11, 31), fill=rgba(iron))
    d.rectangle((5, 3, 11, 10), fill=rgba(sh(iron, 0.8)))
    d.rectangle((6, 4, 10, 9), fill=rgba((150, 255, 210)))
    d.point((7, 5), fill=rgba((240, 255, 245)))
    d.polygon([(4, 3), (8, 0), (12, 3)], fill=rgba(iron))
    for y in (14, 20, 26):
        d.point((7, y), fill=rgba(ALGAE))
        d.point((9, y + 2), fill=rgba(RUST))
    glow_dot(g, 8, 6, 6.0, (120, 255, 200), 0.7)
    return finish(im, g)


DECOR_MAP = {
    "kelp": kelp, "coral": coral, "anchor": anchor, "sunken_chest": sunken_chest,
    "drowned_statue": drowned_statue, "dripping_moss": dripping_moss, "jelly_lantern": jelly_lantern,
    "barnacle_wall": barnacle_wall, "shell_pile": shell_pile, "lantern_post": lantern_post,
}

# (name, placement 0 floor / 1 ceiling / 2 wall, weight, light, unshaded, sway)
DECOR_LIST = [("kelp", 0, 1.6, None, False, True), ("coral", 0, 1.2, (1.0, 0.6, 0.65), True, False),
              ("shell_pile", 0, 1.0, None, False, False), ("anchor", 0, 0.5, None, False, False),
              ("sunken_chest", 0, 0.5, (1.0, 0.85, 0.5), False, False), ("drowned_statue", 0, 0.5, (0.5, 1.0, 0.85), False, False),
              ("lantern_post", 0, 0.5, (0.5, 1.0, 0.8), True, False), ("dripping_moss", 1, 1.4, None, False, True),
              ("jelly_lantern", 1, 0.8, (0.75, 0.55, 1.0), True, True), ("barnacle_wall", 2, 1.1, None, False, False)]


# -------------------------------------------------------------- parallax
W, H = 320, 180


def _grad(top, bottom):
    im = Image.new("RGBA", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(W):
            px[x, y] = c
    return im


def drowned_far():
    """A flooded cathedral: gothic arches, light shafts from the surface far above."""
    im = _grad((10, 30, 34), (22, 54, 54))
    d = ImageDraw.Draw(im)
    col = (28, 60, 60, 255)
    for i in range(6):
        x = i * 56 + 10
        d.rectangle((x, 60, x + 8, H), fill=col)
        d.arc((x, 20, x + 56, 110), 180, 360, fill=col, width=6)
        d.polygon([(x + 28, 14), (x + 24, 22), (x + 32, 22)], fill=col)
    # light shafts (transparent wedges)
    shafts = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shafts)
    for x in (40, 150, 250):
        sd.polygon([(x, 0), (x + 14, 0), (x + 46, H), (x + 18, H)], fill=(150, 230, 210, 26))
        sd.polygon([(x + 4, 0), (x + 9, 0), (x + 30, H), (x + 22, H)], fill=(190, 250, 230, 22))
    im.alpha_composite(shafts)
    rnd = random.Random(21)
    for _ in range(60):  # motes / plankton
        im.putpixel((rnd.randint(0, W - 1), rnd.randint(0, H - 1)), (120, 200, 190, 255))
    d.line((0, 150, W, 150), fill=(60, 120, 120, 255))  # distant waterline
    d.rectangle((0, 151, W, H), fill=(20, 52, 56, 255))
    for x in range(0, W, 9):
        d.line((x, 154 + (x % 3), x + 4, 154 + (x % 3)), fill=(50, 110, 112, 255))
    return im


def drowned_mid():
    """Sunken columns standing in black water, algae up to the waterline."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = (40, 70, 66, 255)
    lit_c = (60, 98, 90, 255)
    dark = (28, 50, 48, 255)
    rnd = random.Random(23)
    for i in range(4):
        x = i * 80 + rnd.randint(10, 40)
        top = rnd.randint(30, 70)
        broken = i % 2 == 1
        d.rectangle((x - 9, top, x + 9, H), fill=col)
        d.line((x - 9, top, x - 9, H), fill=lit_c)
        d.line((x + 9, top, x + 9, H), fill=dark)
        for fx in (-4, 0, 4):
            d.line((x + fx, top + 4, x + fx, H), fill=dark)
        if broken:
            d.polygon([(x - 9, top), (x - 2, top - 8), (x + 4, top - 2), (x + 9, top - 6), (x + 9, top)], fill=col)
        else:
            d.rectangle((x - 13, top - 6, x + 13, top), fill=lit_c)
        for y in range(118, 140):  # algae band at the waterline
            for xx in range(x - 9, x + 10):
                if rnd.random() < 0.35:
                    d.point((xx, y), fill=(60, 120, 80, 255))
    # the water: dark band with a lit surface and reflections
    d.rectangle((0, 140, W, H), fill=(16, 44, 48, 210))
    d.line((0, 140, W, 140), fill=(110, 200, 190, 255))
    for x in range(0, W, 6):
        y = 143 + (x * 7) % 9
        d.line((x, y, x + 3, y), fill=(70, 150, 150, 200))
    return im


def drowned_near():
    """Hanging kelp from the vault and rising bubbles (semi-transparent)."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(25)
    for i in range(7):
        x0 = i * 48 + rnd.randint(0, 20)
        ln = rnd.randint(40, 90)
        for y in range(ln):
            x = x0 + math.sin(y * 0.12 + i) * 3
            d.line((x, y, x + 2, y), fill=(34, 80, 60, 170))
        d.ellipse((x0 - 2, ln - 2, x0 + 3, ln + 3), fill=(40, 96, 70, 170))
    for _ in range(26):
        x, y, r = rnd.randint(0, W - 1), rnd.randint(30, H - 1), rnd.choice((1, 1, 2, 3))
        d.ellipse((x - r, y - r, x + r, y + r), outline=(170, 240, 230, 120))
        d.point((x - r // 2, y - r // 2), fill=(230, 255, 250, 160))
    return im


# ------------------------------------------------------------ biome data
DROWNED = dict(gdb.DROWNED, top_kind="algae")


def main() -> None:
    os.makedirs(DECOR, exist_ok=True)
    for name, fn in DECOR_MAP.items():
        save(fn(), name)
    for name, fn in (("far", drowned_far), ("mid", drowned_mid), ("near", drowned_near)):
        fn().save(os.path.join(BG, "drowned_vaults_%s.png" % name))
        print("background:", name)
    gb.tileset("drowned_vaults", DROWNED)
    meta = dict(gdb.BIOME_META["drowned_vaults"][5], particle="bubbles")
    gdb.write_tres("drowned_vaults", "Затопленные своды", 7, DECOR_LIST, meta)
    print("drowned vaults regenerated")


if __name__ == "__main__":
    main()
