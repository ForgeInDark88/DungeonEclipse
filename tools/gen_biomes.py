#!/usr/bin/env python3
"""Biome placeholders: tilesets with edge/variant tiles, 3 parallax layers,
decorations, plus extra hero equipment layers and UI details.

Tileset atlas (16x16 cells, 4 columns x 7 rows) — see docs/ANIMATION_GUIDE.md:
  row 0: bedrock variants 0-3
  row 1: brick interior: plain, plain 2, cracked, ORE (glows)
  row 2: brick with exposed TOP (moss / dust / magma crust) variants 0-3
  row 3: brick with exposed BOTTOM (ceiling, drips) variants 0-3
  row 4: platform left, middle, right, ladder
  row 5: back wall variants 0-3
  row 6: glow overlay for ORE (drawn unshaded on top), rest empty
  row 7: floor fringe (grass, pebbles, tiny crystals) in the cell above a floor
  row 8: ceiling fringe (roots, vines, cobwebs, icicles) under a ceiling
  row 9: back wall details (crack, stain, protruding stone, biome sign)
  row 10: crumbling back wall rims inside the gaps (wall above, below, left, right)
"""
from __future__ import annotations

import math
import os
import random
import re
import zlib

from PIL import Image, ImageDraw

import gen_mushrooms as gm
import gen_placeholders as gp
import gen_sheets as gs

A = gp.A

# Background colors (back wall, parallax) are only a little darker than the
# foreground stone: the dungeon is lit evenly, depth comes from the shading.
BIOMES = {
    "catacombs": dict(stone=(92, 70, 58), bedrock=(46, 42, 52), mortar=(50, 36, 30), back=(64, 54, 58),
                      top=(150, 140, 120), top_kind="dust", ore=(200, 140, 90), ore_glow=(255, 170, 90),
                      wood=(120, 82, 48), sky=(44, 36, 50), far=(62, 52, 68), mid=(80, 68, 82), near=(98, 84, 92),
                      accent=(150, 140, 120)),
    "fungal": dict(stone=(52, 74, 78), bedrock=(30, 40, 46), mortar=(24, 36, 40), back=(38, 58, 60),
                   top=(60, 200, 170), top_kind="moss", ore=(80, 230, 240), ore_glow=(120, 255, 255),
                   wood=(90, 70, 60), sky=(18, 38, 40), far=(32, 62, 64), mid=(42, 84, 86), near=(54, 104, 104),
                   accent=(60, 170, 140)),
    "ruins": dict(stone=(150, 132, 100), bedrock=(80, 72, 60), mortar=(100, 86, 64), back=(100, 88, 74),
                  top=(80, 150, 60), top_kind="grass", ore=(230, 200, 80), ore_glow=(255, 230, 120),
                  wood=(130, 95, 60), sky=(56, 50, 42), far=(80, 70, 58), mid=(100, 88, 72), near=(120, 106, 86),
                  accent=(90, 140, 70)),
    "lava": dict(stone=(70, 40, 38), bedrock=(30, 18, 18), mortar=(40, 20, 18), back=(70, 36, 30),
                 top=(255, 120, 30), top_kind="magma", ore=(255, 80, 40), ore_glow=(255, 140, 60),
                 wood=(70, 50, 40), sky=(60, 18, 12), far=(90, 32, 22), mid=(110, 44, 28), near=(130, 58, 34),
                 accent=(200, 80, 40)),
    # Mirror Halls (the Illusionist's domain): violet marble, crystal growths.
    "mirror_halls": dict(stone=(104, 86, 138), bedrock=(44, 34, 64), mortar=(60, 46, 84), back=(78, 64, 108),
                         top=(200, 190, 240), top_kind="crystal", ore=(220, 170, 255), ore_glow=(240, 200, 255),
                         wood=(110, 80, 70), sky=(30, 22, 48), far=(52, 42, 80), mid=(74, 60, 106), near=(96, 80, 130),
                         accent=(190, 170, 240)),
}


def c4(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


def noise_tile(base, seed, var=0.12):
    return gp.tile_noise(c4(base), seed, var)


def _px_shade(px, x, y, f):
    r, g, b, a = px[x, y]
    px[x, y] = (max(0, min(255, int(r * f))), max(0, min(255, int(g * f))), max(0, min(255, int(b * f))), a)


# Joints of the brick rows (x of vertical mortar) per row y0 and variant offset.
def _joints(seed):
    off = seed % 2 * 4
    return {0: sorted({(4 + off) % 16, 12}), 5: sorted({(0 + off) % 16, 8}), 10: sorted({4, (12 - off) % 16})}


def brick(b, seed, cracked=False, ore=False):
    """Brick with bevelled blocks: every block has its own tone, a lit top-left
    edge, a shadowed bottom-right edge, pits and biome specks."""
    rnd = random.Random(seed * 31 + 7)
    base = c4(b["stone"])
    im = gp.new(16, 16)
    px = im.load()
    mortar = gp.shade(c4(b["mortar"]), 0.9)
    joints = _joints(seed)
    for y0, xs in joints.items():
        bounds = sorted(set(xs))
        # blocks between joints (wrapping over the tile edge)
        cuts = bounds + [bounds[0] + 16]
        for k in range(len(bounds)):
            a, z = cuts[k], cuts[k + 1]
            tone_f = 1.0 + rnd.uniform(-0.09, 0.09)
            for xx in range(a + 1, z):
                x = xx % 16
                for y in range(y0 + 1, y0 + 5):
                    f = tone_f * (1.0 + rnd.uniform(-0.05, 0.05))
                    if y == y0 + 1:
                        f *= 1.16
                    elif y == y0 + 4:
                        f *= 0.8
                    if xx == a + 1:
                        f *= 1.07
                    elif xx == z - 1:
                        f *= 0.86
                    px[x, y] = gp.shade(base, f)
            for y in range(y0, y0 + 6):
                if y < 16:
                    px[a % 16, y] = mortar
    for y in (0, 5, 10, 15):
        for x in range(16):
            px[x, y] = mortar
    # pits and chips
    for _ in range(3):
        x, y = rnd.randint(1, 14), rnd.choice((2, 3, 7, 8, 12, 13))
        if px[x, y] != mortar:
            _px_shade(px, x, y, 0.72)
            if x + 1 < 16 and px[x + 1, y] != mortar:
                _px_shade(px, x + 1, y, 1.12)
    accent = b.get("accent")
    if accent and rnd.random() < 0.7:
        for _ in range(rnd.randint(1, 3)):
            x, y = rnd.randint(0, 15), rnd.choice((1, 4, 6, 9, 11, 14))
            px[x, y] = c4(accent, 200)
    d = ImageDraw.Draw(im)
    if cracked:
        cm = gp.shade(base, 0.45)
        d.line((5, 6, 8, 9), fill=cm)
        d.line((8, 9, 7, 13), fill=cm)
        d.line((8, 9, 11, 10), fill=cm)
        d.point((9, 9), fill=gp.shade(base, 1.25))
    if ore:
        orr = random.Random(seed)
        for _ in range(5):
            x, y = orr.randint(2, 12), orr.randint(2, 12)
            d.rectangle((x, y, x + 1, y + 1), fill=c4(b["ore"]))
            d.point((x + 1, y + 1), fill=gp.shade(c4(b["ore"]), 0.65))
    return im


def top_edge(b, seed):
    im = brick(b, seed + 11)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    t = c4(b["top"])
    kind = b["top_kind"]
    for x in range(16):
        h = rnd.randint(1, 3) if kind != "dust" else rnd.randint(0, 2)
        for y in range(h):
            d.point((x, y), fill=gp.shade(t, 1.08 - y * 0.16))
        if kind in ("moss", "grass") and rnd.random() < 0.35:
            # moss creeping down the brick face
            for y in range(h, h + rnd.randint(1, 3)):
                d.point((x, y), fill=gp.shade(t, 0.7))
        if kind == "grass" and rnd.random() < 0.3:
            d.point((x, 0), fill=gp.shade(t, 1.3))
    if kind == "grass":
        for x in (rnd.randint(1, 6), rnd.randint(9, 14)):
            d.point((x, 1), fill=(240, 220, 90, 255) if seed % 2 else (230, 120, 150, 255))
    elif kind == "moss":
        for _ in range(3):
            x = rnd.randint(0, 15)
            d.point((x, rnd.randint(0, 2)), fill=(200, 255, 230, 255))
    elif kind == "magma":
        for x in range(0, 16, 5):
            x0 = x + rnd.randint(0, 3)
            d.line((x0, 2, x0 + rnd.randint(-1, 1), 6), fill=c4((255, 200, 80)))
            d.point((x0, 3), fill=(255, 255, 200, 255))
    elif kind == "crystal":
        for x0 in (rnd.randint(1, 5), rnd.randint(7, 10), rnd.randint(12, 14)):
            hgt = rnd.randint(2, 4)
            col = c4(b["ore"]) if rnd.random() < 0.5 else c4((170, 230, 255))
            d.polygon([(x0 - 1, hgt + 1), (x0, 0), (x0 + 1, hgt + 1)], fill=col)
            d.point((x0, 1), fill=(255, 255, 255, 255))
    else:  # dust: pebbles
        for _ in range(2):
            x = rnd.randint(1, 14)
            d.point((x, 0), fill=gp.shade(t, 0.75))
            d.point((x + 1, 0), fill=gp.shade(t, 1.15))
    return im


def bottom_edge(b, seed):
    im = brick(b, seed + 21)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    stone = c4(b["stone"])
    kind = b["top_kind"]
    for x in range(1, 15, 3):
        if rnd.random() < 0.6:
            h = rnd.randint(1, 3)
            d.line((x, 15 - h, x, 15), fill=gp.shade(stone, 0.6))
    d.line((0, 15, 15, 15), fill=gp.shade(stone, 0.5))
    if kind in ("moss", "grass"):
        for _ in range(2):
            x = rnd.randint(1, 14)
            ln = rnd.randint(2, 4)
            d.line((x, 15 - ln, x, 15), fill=gp.shade(c4(b["top"]), 0.65))
            d.point((x, 15), fill=gp.shade(c4(b["top"]), 0.9))
    elif kind == "magma":
        x = rnd.randint(2, 13)
        d.line((x, 12, x, 15), fill=(255, 150, 50, 255))
        d.point((x, 15), fill=(255, 230, 140, 255))
    elif kind == "crystal":
        x = rnd.randint(2, 13)
        d.polygon([(x - 1, 12), (x + 1, 12), (x, 15)], fill=c4(b["ore"]))
    return im


def bedrock(b, seed):
    """Dark layered rock: strata lines, bevelled chunks."""
    rnd = random.Random(seed * 13 + 5)
    base = c4(b["bedrock"])
    im = noise_tile(b["bedrock"], seed + 40, 0.1)
    px = im.load()
    d = ImageDraw.Draw(im)
    for y in (4 + seed % 3, 10 + seed % 2):
        for x in range(16):
            yy = y + (1 if (x + seed) % 7 == 0 else 0)
            px[x, yy % 16] = gp.shade(base, 0.62)
            if yy - 1 >= 0:
                _px_shade(px, x, yy - 1, 1.18)
    for _ in range(2):
        x, y = rnd.randint(1, 11), rnd.randint(1, 11)
        w, h = rnd.randint(3, 4), rnd.randint(2, 3)
        d.rectangle((x, y, x + w, y + h), fill=gp.shade(base, 1.12))
        d.line((x, y + h, x + w, y + h), fill=gp.shade(base, 0.7))
        d.line((x + w, y, x + w, y + h), fill=gp.shade(base, 0.75))
    d.line((0, 0, 15, 0), fill=gp.shade(base, 1.45))
    return im


def platform(b, part):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    w = c4(b["wood"])
    d.rectangle((0, 0, 15, 4), fill=w)
    d.line((0, 0, 15, 0), fill=gp.shade(w, 1.35))
    d.line((0, 4, 15, 4), fill=gp.shade(w, 0.55))
    # grain and plank seams
    d.line((1, 2, 6, 2), fill=gp.shade(w, 0.85))
    d.line((9, 1, 14, 1), fill=gp.shade(w, 0.9))
    d.line((4, 3, 11, 3), fill=gp.shade(w, 0.82))
    seam = 7 if part == 1 else 15 if part == 0 else 0
    d.line((seam, 0, seam, 4), fill=gp.shade(w, 0.6))
    for nx in (2, 13):
        d.point((nx, 1), fill=(170, 170, 180, 255))
    if part == 0:
        d.line((0, 0, 0, 4), fill=gp.shade(w, 0.6))
        d.line((2, 5, 2, 9), fill=gp.shade(w, 0.6))
        d.line((2, 9, 6, 5), fill=gp.shade(w, 0.6))
    elif part == 2:
        d.line((15, 0, 15, 4), fill=gp.shade(w, 0.6))
        d.line((13, 5, 13, 9), fill=gp.shade(w, 0.6))
        d.line((13, 9, 9, 5), fill=gp.shade(w, 0.6))
    return im


def backwall(b, seed):
    """Back wall: large bevelled stone blocks; variants with a crack, a niche
    and a biome carving (skull, spores, rune, ember vein, mirror shard)."""
    base = c4(b["back"])
    im = noise_tile(b["back"], seed + 70, 0.06)
    px = im.load()
    d = ImageDraw.Draw(im)
    m = gp.shade(base, 0.68)
    off = 0 if seed % 2 else 4
    for y0 in (0, 8):
        for x in range(16):
            px[x, y0] = m
            if y0 + 1 < 16:
                _px_shade(px, x, y0 + 1, 1.1)
            _px_shade(px, x, y0 + 7, 0.88)
        jx = (off + (4 if y0 else 0) + 3) % 16
        d.line((jx, y0, jx, y0 + 7), fill=m)
        if jx + 1 < 16:
            for y in range(y0 + 1, y0 + 8):
                _px_shade(px, jx + 1, y, 1.08)
    kind = b["top_kind"]
    if seed == 2:
        cm = gp.shade(base, 0.5)
        d.line((10, 2, 12, 5), fill=cm)
        d.line((12, 5, 11, 7), fill=cm)
    elif seed == 3:
        d.rectangle((4, 9, 11, 14), fill=gp.shade(base, 0.45))  # niche
        d.line((4, 9, 11, 9), fill=gp.shade(base, 0.3))
        d.line((4, 14, 11, 14), fill=gp.shade(base, 1.15))
        if kind == "dust":
            d.ellipse((6, 10, 9, 13), fill=(200, 195, 175, 255))  # skull in the niche
            d.point((7, 11), fill=(30, 25, 25, 255))
            d.point((8, 11), fill=(30, 25, 25, 255))
        elif kind == "moss":
            for x in (6, 8, 10):
                d.point((x, 12), fill=(120, 255, 220, 255))
        elif kind == "grass":
            d.rectangle((6, 11, 9, 14), fill=(170, 120, 70, 255))  # little pot
        elif kind == "magma":
            d.point((7, 12), fill=(255, 150, 50, 255))
            d.point((8, 13), fill=(255, 200, 90, 255))
        elif kind == "crystal":
            d.polygon([(6, 14), (8, 10), (10, 14)], fill=c4(b["ore"]))
    return im


def ore_glow(b):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)  # same pattern as brick(..., ore=True) seed 3
    for _ in range(5):
        x, y = rnd.randint(2, 12), rnd.randint(2, 12)
        d.rectangle((x, y, x + 1, y + 1), fill=c4(b["ore_glow"], 230))
        d.point((x, y), fill=(255, 255, 255, 255))
    return im


# ------------------------------------------------- detail rows (no collision)
# row 7: floor fringe (drawn in the empty cell above a floor brick, bottom part)
# row 8: ceiling fringe (in the empty cell below a ceiling brick, top part)
# row 9: wall details (over the back wall: cracks, moss, runes, stains)
def floor_fringe(b, v):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(100 + v)
    kind = b["top_kind"]
    t = c4(b["top"])
    if kind == "grass":
        for _ in range(6 + v):
            x = rnd.randint(0, 15)
            h = rnd.randint(2, 5)
            lean = rnd.choice((-1, 0, 1))
            d.line((x, 15, x + lean, 15 - h), fill=gp.shade(t, rnd.uniform(0.8, 1.25)))
        if v % 2 == 0:
            x = rnd.randint(3, 12)
            d.line((x, 15, x, 10), fill=gp.shade(t, 0.8))
            col = ((240, 220, 90), (230, 120, 150), (170, 150, 240))[v % 3]
            d.point((x, 9), fill=c4(col))
            d.point((x - 1, 10), fill=c4(col))
            d.point((x + 1, 10), fill=c4(col))
    elif kind == "moss":
        for _ in range(5):
            x = rnd.randint(0, 15)
            d.line((x, 15, x, 15 - rnd.randint(1, 3)), fill=gp.shade(t, 0.75))
        for _ in range(1 + v % 2):
            x = rnd.randint(2, 13)
            h = rnd.randint(2, 4)
            d.line((x, 15, x, 15 - h), fill=(215, 225, 205, 255))
            d.ellipse((x - 2, 13 - h, x + 2, 16 - h), fill=c4((90, 240, 210) if v % 2 else (200, 120, 240)))
            d.point((x - 1, 14 - h), fill=(240, 255, 255, 255))
    elif kind == "magma":
        for _ in range(4):
            x = rnd.randint(0, 14)
            d.ellipse((x, 13, x + 2, 15), fill=gp.shade(c4(b["stone"]), 0.6))
        for _ in range(2 + v % 2):
            x = rnd.randint(1, 14)
            d.point((x, 14), fill=(255, 150, 50, 255))
            d.point((x, 13 - rnd.randint(0, 3)), fill=(255, 200, 90, 200))
    elif kind == "crystal":
        for _ in range(2 + v % 2):
            x = rnd.randint(2, 13)
            h = rnd.randint(3, 6)
            col = c4(b["ore"]) if rnd.random() < 0.5 else c4((170, 230, 255))
            d.polygon([(x - 1, 15), (x, 15 - h), (x + 1, 15)], fill=col)
            d.point((x, 16 - h), fill=(255, 255, 255, 255))
    else:  # dust: pebbles, a bone bit, dust
        for _ in range(3 + v):
            x = rnd.randint(0, 14)
            d.point((x, 15), fill=gp.shade(c4(b["stone"]), 1.25))
            d.point((x + 1, 15), fill=gp.shade(c4(b["stone"]), 0.8))
        if v % 2 == 1:
            x = rnd.randint(2, 10)
            d.line((x, 15, x + 3, 14), fill=(220, 215, 195, 255))
            d.point((x + 3, 13), fill=(220, 215, 195, 255))
    return im


def ceil_fringe(b, v):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(200 + v)
    kind = b["top_kind"]
    t = c4(b["top"])
    stone = c4(b["stone"])
    if kind in ("grass", "moss"):
        for _ in range(2 + v % 2):
            x = rnd.randint(1, 14)
            ln = rnd.randint(4, 11)
            for y in range(ln):
                d.point((x + (y // 3) % 2, y), fill=gp.shade(t, 0.65 if kind == "grass" else 0.75))
            if kind == "moss":
                d.point((x, ln), fill=(160, 255, 230, 255))
            elif rnd.random() < 0.6:
                d.point((x + 1, ln // 2), fill=gp.shade(t, 1.2))  # leaf
    elif kind == "magma":
        for _ in range(2):
            x = rnd.randint(2, 13)
            ln = rnd.randint(3, 7)
            d.polygon([(x - 2, 0), (x + 2, 0), (x, ln)], fill=gp.shade(stone, 0.55))
            d.point((x, ln), fill=(255, 140, 40, 255))
    elif kind == "crystal":
        for _ in range(2 + v % 2):
            x = rnd.randint(2, 13)
            ln = rnd.randint(3, 7)
            d.polygon([(x - 1, 0), (x + 1, 0), (x, ln)], fill=c4((200, 180, 250)))
            d.point((x, 1), fill=(255, 255, 255, 255))
    else:  # dust: cobweb corner or a small stalactite
        if v % 2 == 0:
            web = (220, 220, 230, 140)
            x0 = 0 if v < 2 else 15
            sx = 1 if x0 == 0 else -1
            for k in range(0, 9, 3):
                d.line((x0, k, x0 + sx * (8 - k), 0), fill=web)
            d.line((x0, 0, x0 + sx * 6, 6), fill=web)
        else:
            x = rnd.randint(3, 12)
            d.polygon([(x - 2, 0), (x + 2, 0), (x, rnd.randint(4, 7))], fill=gp.shade(stone, 0.7))
            d.point((x - 1, 1), fill=gp.shade(stone, 1.1))
    return im


def wall_detail(b, v):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    rnd = random.Random(300 + v)
    back = c4(b["back"])
    kind = b["top_kind"]
    if v == 0:  # crack
        x, y = rnd.randint(3, 8), rnd.randint(2, 5)
        pts = [(x, y)]
        for _ in range(4):
            x += rnd.choice((-1, 0, 1))
            y += 2
            pts.append((x, y))
        d.line(pts, fill=gp.shade(back, 0.45))
        d.line((pts[2][0], pts[2][1], pts[2][0] + 3, pts[2][1] + 1), fill=gp.shade(back, 0.5))
    elif v == 1:  # stain / moss / soot patch
        col = {"moss": (60, 150, 120), "grass": (80, 130, 60), "magma": (30, 20, 20), "crystal": (150, 120, 220)}.get(
            kind, (80, 70, 60))
        for _ in range(14):
            x, y = rnd.randint(3, 12), rnd.randint(4, 12)
            d.point((x, y), fill=c4(col, 170))
    elif v == 2:  # protruding stone
        d.rectangle((4, 6, 11, 10), fill=gp.shade(back, 1.15))
        d.line((4, 6, 11, 6), fill=gp.shade(back, 1.35))
        d.line((4, 10, 11, 10), fill=gp.shade(back, 0.6))
        d.line((11, 6, 11, 10), fill=gp.shade(back, 0.7))
    else:  # biome sign: rune / scratch marks / ember vein / spores
        if kind == "crystal":
            col = (220, 180, 255, 255)
            d.line((8, 3, 8, 12), fill=col)
            d.line((5, 6, 11, 6), fill=col)
            d.line((5, 10, 8, 12, 11, 10), fill=col)
        elif kind == "magma":
            d.line((2, 12, 6, 9, 10, 11, 14, 7), fill=(200, 80, 30, 255))
            d.point((6, 9), fill=(255, 190, 80, 255))
        elif kind == "moss":
            for x, y in ((5, 5), (9, 8), (6, 11), (11, 4)):
                d.point((x, y), fill=(140, 255, 220, 255))
        else:
            for k in range(4):
                d.line((5 + k * 2, 5, 5 + k * 2, 10), fill=gp.shade(back, 0.55))  # tally marks
            d.line((4, 9, 12, 6), fill=gp.shade(back, 0.55))
    return im


def _is_mortar(c, mortar):
    return abs(c[0] - mortar[0]) + abs(c[1] - mortar[1]) + abs(c[2] - mortar[2]) < 10


def enrich_stone(im, b, seed, back=False):
    """Material detail over a brick / back wall tile: mineral speckle
    clusters, grime under the joints, depth in the mortar and a biome
    feature (bone chips, lichen, erosion, ember veins, marble gloss)."""
    rnd = random.Random(seed * 97 + (5 if back else 1))
    px = im.load()
    mortar = gp.shade(c4(b["mortar"]), 0.9) if not back else gp.shade(c4(b["back"]), 0.68)
    kind = b["top_kind"]
    stone = [(x, y) for y in range(16) for x in range(16) if px[x, y][3] and not _is_mortar(px[x, y], mortar)]
    if not stone:
        return im
    if back:
        # each big block is lit from above and falls into shadow at its foot
        for (x, y) in stone:
            r = y % 8
            _px_shade(px, x, y, 1.08 - 0.035 * r)
    # mortar depth: dark seam with a lit lip under it
    for y in range(16):
        for x in range(16):
            if px[x, y][3] and _is_mortar(px[x, y], mortar):
                _px_shade(px, x, y, 0.82)
                if y + 1 < 16 and not _is_mortar(px[x, y + 1], mortar) and (x + y) % 3:
                    _px_shade(px, x, y + 1, 1.06)
    # mineral speckle clusters (light + dark pairs)
    for _ in range(4 if not back else 2):
        x, y = rnd.choice(stone)
        f = rnd.choice((1.14, 0.84))
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            if 0 <= x + dx < 16 and 0 <= y + dy < 16 and (x + dx, y + dy) in stone and rnd.random() < 0.8:
                _px_shade(px, x + dx, y + dy, f)
    # grime: darker pixels just above each horizontal joint
    for y in range(1, 16):
        for x in range(16):
            if _is_mortar(px[x, y], mortar) and not _is_mortar(px[x, y - 1], mortar) and (x * 5 + seed) % 4 == 0:
                _px_shade(px, x, y - 1, 0.9)
    accent = c4(b.get("accent", b["top"]))
    if kind == "dust" and not back and seed % 2 == 0:
        x, y = rnd.choice([p for p in stone if 2 < p[0] < 13 and p[1] not in (0, 5, 10, 15)])
        px[x, y] = (214, 206, 182, 255)  # bone chip in the brick
        if x + 1 < 16 and (x + 1, y) in stone:
            px[x + 1, y] = (178, 170, 150, 255)
    elif kind == "moss":
        for _ in range(3 if not back else 2):
            x, y = rnd.choice(stone)
            px[x, y] = gp.shade(accent, 0.75 if back else 0.9)
            if (x + 1, y) in stone and rnd.random() < 0.6:
                px[x + 1, y] = gp.shade(accent, 0.6)
    elif kind == "grass":
        # eroded corner chips
        for _ in range(2):
            x, y = rnd.choice(stone)
            if (x, y - 1) not in stone or (x - 1, y) not in stone:
                px[x, y] = gp.shade(c4(b["stone"] if not back else b["back"]), 0.62)
        if not back and seed % 2:
            x, y = rnd.randint(3, 11), rnd.choice((2, 7, 12))
            for k in range(3):
                if (x + k, y) in stone:
                    _px_shade(px, x + k, y, 0.7)  # carved groove
    elif kind == "magma":
        if seed % 2 == 1 or back:
            x, y = rnd.randint(3, 12), rnd.choice((1, 6, 11))
            for k in range(3):
                xx, yy = x + (k if not back else 0), y + k
                if (xx, yy) in stone:
                    px[xx, yy] = (200, 70, 30, 255) if not back else (130, 50, 30, 255)
            if (x, y) in stone and not back:
                px[x, y] = (255, 160, 60, 255)
        for _ in range(2):
            x, y = rnd.choice(stone)
            _px_shade(px, x, y, 0.7)  # soot
    elif kind == "crystal":
        # diagonal gloss on the polished stone and fine veins
        off = rnd.randint(0, 15)
        for (x, y) in stone:
            if (x + y + off) % 13 == 0:
                _px_shade(px, x, y, 1.16 if not back else 1.08)
        x, y = rnd.choice(stone)
        for k in range(4):
            if (x + k, y + k // 2) in stone:
                _px_shade(px, x + k, y + k // 2, 0.82)
    return im


def back_edge(b, direction):
    """Crumbling rim of the back wall drawn inside a gap cell, so the gaps
    (where the parallax cave shows through) get broken, jagged edges instead
    of straight tile borders. direction: where the wall is (0 above, 1 below,
    2 left, 3 right)."""
    wall = enrich_stone(backwall(b, direction % 2), b, direction, back=True)
    src = wall.load()
    im = gp.new(16, 16)
    px = im.load()
    rnd = random.Random(direction * 7 + len(b["top_kind"]))
    depth = [rnd.choice((1, 2, 2, 3, 4)) for _ in range(16)]
    for k in range(1, 15):  # smooth a little so the rim reads as rock, not noise
        depth[k] = max(1, (depth[k - 1] + depth[k] * 2 + depth[k + 1]) // 4 + rnd.choice((0, 0, 1)))
    shadow = gp.shade(c4(b["back"]), 0.4)
    for k in range(16):
        dk = depth[k]
        for t in range(dk + 1):
            if direction == 0:
                x, y = k, t
            elif direction == 1:
                x, y = k, 15 - t
            elif direction == 2:
                x, y = t, k
            else:
                x, y = 15 - t, k
            if t == dk:
                px[x, y] = shadow  # dark broken edge facing the gap
            else:
                c = src[x, y]
                f = 1.15 if (t == dk - 1 and direction in (1, 3)) else 1.0
                px[x, y] = gp.shade(c, f)
    # a few loose pebbles / fragments
    for _ in range(2):
        k = rnd.randint(2, 13)
        t = depth[k] + rnd.randint(2, 4)
        x, y = {0: (k, t), 1: (k, 15 - t), 2: (t, k), 3: (15 - t, k)}[direction]
        if 0 <= x < 16 and 0 <= y < 16:
            px[x, y] = gp.shade(c4(b["back"]), 0.85)
    return im


def tileset(name, b):
    atlas = gp.new(16 * 4, 16 * 11)
    rows = [
        [bedrock(b, i) for i in range(4)],
        [enrich_stone(brick(b, 0), b, 0), enrich_stone(brick(b, 1), b, 1), enrich_stone(brick(b, 2, cracked=True), b, 2),
         brick(b, 3, ore=True)],
        [enrich_stone(top_edge(b, i), b, i + 4) for i in range(4)],
        [enrich_stone(bottom_edge(b, i), b, i + 8) for i in range(4)],
        [platform(b, 0), platform(b, 1), platform(b, 2), gp.tile_ladder()],
        [enrich_stone(backwall(b, i), b, i, back=True) for i in range(4)],
        [ore_glow(b)],
        [floor_fringe(b, i) for i in range(4)],
        [ceil_fringe(b, i) for i in range(4)],
        [wall_detail(b, i) for i in range(4)],
        [back_edge(b, i) for i in range(4)],
    ]
    for y, row in enumerate(rows):
        for x, t in enumerate(row):
            atlas.alpha_composite(t, (x * 16, y * 16))
    atlas.save(os.path.join(A, f"sprites/tiles/tiles_{name}.png"))


# ------------------------------------------------------------------ parallax
def _gradient(w, h, top, bottom):
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(w):
            px[x, y] = c
    return im


def parallax(name, b):
    """Three layers: far (gradient, distant shapes, motes), mid (big biome
    structures with lit edges), near (hanging things, semi-transparent)."""
    w, h = 320, 180
    rnd = random.Random(zlib.crc32(name.encode()) & 0xFFFF)
    sky = b["sky"]
    far_c = c4(b["far"])
    far = _gradient(w, h, gp.shade(c4(sky), 0.75)[:3], gp.shade(c4(b["far"]), 0.9)[:3])
    d = ImageDraw.Draw(far)
    # distant row (lighter, smaller) then the closer row of silhouettes
    for layer, (col, top_rng, width) in enumerate(((gp.shade(far_c, 0.85), (70, 110), 26), (far_c, (40, 90), 40))):
        for i in range(8 if layer == 0 else 6):
            x = i * (w // (8 if layer == 0 else 6)) + rnd.randint(-10, 10)
            top = rnd.randint(*top_rng)
            if name == "ruins":
                d.rectangle((x - width // 4, top, x + width // 4, h), fill=col)
                d.rectangle((x - width // 3, top - 4, x + width // 3, top), fill=col)
            elif name == "fungal":
                d.rectangle((x - 2, top + 10, x + 2, h), fill=col)
                d.pieslice((x - width // 2, top - 6, x + width // 2, top + 22), 180, 360, fill=col)
            elif name == "mirror_halls":
                d.rectangle((x - width // 3, top, x + width // 3, h), fill=col)
                d.rectangle((x - width // 3 + 3, top + 3, x + width // 3 - 3, h), fill=gp.shade(col, 1.3))
                d.line((x - width // 3 + 4, top + 20, x + width // 3 - 6, top + 6), fill=gp.shade(col, 1.7))
            else:
                d.polygon([(x - width, h), (x, top), (x + width, h)], fill=col)
                d.line((x, top, x - width // 2, top + 40), fill=gp.shade(col, 1.15))
    if name == "lava":
        d.polygon([(110, h), (170, 70), (190, 74), (250, h)], fill=gp.shade(far_c, 0.8))
        d.line((178, 72, 172, 120), fill=(255, 120, 40, 255), width=2)
        d.ellipse((168, 62, 196, 78), fill=(255, 110, 40, 120))
    if name == "catacombs":
        for i in range(5):
            x = 20 + i * 64
            d.arc((x, 100, x + 50, 160), 180, 360, fill=gp.shade(far_c, 1.25), width=3)
    for i in range(45):
        x, y = rnd.randint(0, w - 1), rnd.randint(0, h * 2 // 3)
        d.point((x, y), fill=gp.shade(far_c, 1.7 + rnd.random() * 0.5))
    far.save(os.path.join(A, f"sprites/backgrounds/{name}_far.png"))

    mid = gp.new(w, h)
    d = ImageDraw.Draw(mid)
    col = c4(b["mid"])
    lit = gp.shade(col, 1.25)
    dark = gp.shade(col, 0.75)
    for i in range(4):
        x = i * 80 + rnd.randint(10, 50)
        if name == "fungal":
            d.rectangle((x - 3, 70, x + 3, h), fill=col)
            d.line((x - 3, 70, x - 3, h), fill=lit)
            d.pieslice((x - 26, 40, x + 26, 100), 180, 360, fill=gp.shade(col, 1.2))
            d.arc((x - 26, 40, x + 26, 100), 200, 300, fill=gp.shade(col, 1.5))
            d.line((x - 24, 70, x + 24, 70), fill=dark)
            for k in range(5):
                d.point((x - 20 + k * 10, 62 - (k % 2) * 4), fill=c4((90, 255, 220)))
        elif name == "ruins":
            d.rectangle((x - 8, 50, x + 8, h), fill=col)
            d.line((x - 8, 50, x - 8, h), fill=lit)
            d.line((x + 8, 50, x + 8, h), fill=dark)
            for fx in (-4, 0, 4):
                d.line((x + fx, 54, x + fx, h), fill=dark)
            d.rectangle((x - 12, 44, x + 12, 50), fill=lit)
            d.arc((x + 8, 40, x + 72, 110), 180, 360, fill=col, width=6)
            for vy in range(50, 120, 7):
                d.point((x - 9 + (vy // 7) % 3, vy), fill=(80, 150, 60, 255))
        elif name == "lava":
            d.polygon([(x - 18, h), (x - 6, 60), (x + 6, 80), (x + 20, h)], fill=col)
            d.line((x - 6, 60, x - 14, h), fill=lit)
            d.line((x - 30, h - 6, x + 40, h - 10), fill=c4((255, 110, 30)), width=2)
            d.line((x - 2, 90, x + 4, 130), fill=c4((255, 140, 50)))
        elif name == "mirror_halls":
            # framed mirror on a pedestal, crystal shard pillars
            d.rectangle((x - 12, 40, x + 12, 96), fill=c4((150, 120, 60)))
            d.rectangle((x - 9, 43, x + 9, 93), fill=gp.shade(col, 1.45))
            d.line((x - 7, 80, x + 6, 50), fill=(235, 230, 255, 200), width=2)
            d.line((x - 7, 88, x + 7, 66), fill=(235, 230, 255, 120))
            d.rectangle((x - 6, 96, x + 6, h), fill=col)
            d.line((x - 6, 96, x - 6, h), fill=lit)
            sx = x + 40
            d.polygon([(sx - 6, h), (sx, 100 + rnd.randint(0, 20)), (sx + 6, h)], fill=c4((160, 120, 220), 200))
        else:
            d.rectangle((x - 7, 30, x + 7, h), fill=col)
            d.line((x - 7, 30, x - 7, h), fill=lit)
            d.line((x + 7, 30, x + 7, h), fill=dark)
            for y in range(40, h, 18):
                d.line((x - 7, y, x + 7, y), fill=dark)
                d.line((x - 7, y + 1, x + 7, y + 1), fill=lit)
            d.ellipse((x - 4, 60, x + 4, 66), fill=c4((25, 20, 28)))
            d.point((x - 1, 62), fill=(255, 200, 120, 255))
    mid.save(os.path.join(A, f"sprites/backgrounds/{name}_mid.png"))

    near = gp.new(w, h)
    d = ImageDraw.Draw(near)
    col = c4(b["near"], 200)
    for i in range(12):
        x = rnd.randint(0, w - 1)
        ln = rnd.randint(20, 70)
        if name in ("fungal", "ruins"):
            for y in range(0, ln, 3):
                d.point((x + int(2 * math.sin(y * 0.3)), y), fill=col)
                d.point((x + int(2 * math.sin(y * 0.3)) + 1, y + 1), fill=col)
                if y % 9 == 0:
                    d.point((x + int(2 * math.sin(y * 0.3)) + 2, y + 1), fill=gp.shade(col, 1.3))
        elif name == "lava":
            d.polygon([(x - 6, 0), (x + 6, 0), (x, ln)], fill=col)
            d.line((x - 3, 0, x, ln - 4), fill=gp.shade(col, 1.25))
        elif name == "mirror_halls":
            for y in range(0, ln, 4):
                d.ellipse((x - 1, y, x + 1, y + 3), outline=col)
            d.polygon([(x - 3, ln), (x, ln - 5), (x + 3, ln), (x, ln + 8)], fill=c4((200, 170, 255), 210))
            d.point((x, ln), fill=(255, 255, 255, 230))
        else:
            for y in range(0, ln, 4):
                d.ellipse((x - 1, y, x + 1, y + 3), outline=col)
    near.save(os.path.join(A, f"sprites/backgrounds/{name}_near.png"))


# --------------------------------------------------------------- decorations
def decor_all():
    D = {}

    def img(w, h):
        im = gp.new(w, h)
        return im, ImageDraw.Draw(im)

    im, d = img(16, 16)  # bones
    bone = (225, 220, 200, 255)
    d.line((2, 14, 9, 12), fill=bone, width=2)
    d.line((8, 15, 13, 11), fill=bone)
    d.ellipse((10, 9, 14, 13), fill=bone)
    D["bones"] = im
    im, d = img(16, 16)  # skull pile
    for x, y in ((3, 10), (8, 10), (5, 6), (10, 7)):
        d.ellipse((x, y, x + 5, y + 5), fill=bone)
        d.point((x + 1, y + 2), fill=(30, 20, 20, 255))
        d.point((x + 3, y + 2), fill=(30, 20, 20, 255))
    D["skulls"] = im
    im, d = img(16, 16)  # cobweb (ceiling)
    web = (220, 220, 230, 160)
    for a in range(0, 91, 22):
        r = math.radians(a)
        d.line((0, 0, 15 * math.cos(r), 15 * math.sin(r)), fill=web)
    for rr in (5, 10, 14):
        d.arc((-rr, -rr, rr, rr), 0, 90, fill=web)
    D["cobweb"] = im
    im, d = img(16, 16)  # candles
    for x, h in ((4, 6), (8, 9), (11, 5)):
        d.rectangle((x, 16 - h, x + 2, 15), fill=(230, 220, 190, 255))
        d.point((x + 1, 15 - h), fill=(255, 200, 60, 255))
        d.point((x + 1, 14 - h), fill=(255, 240, 150, 255))
    D["candles"] = im
    D["mushrooms"] = gm.mushrooms()
    D["big_mushroom"] = gm.big_mushroom()
    im, d = img(16, 16)  # glowing crystals
    d.polygon([(3, 15), (5, 6), (8, 15)], fill=(110, 240, 255, 255))
    d.polygon([(7, 15), (10, 3), (13, 15)], fill=(80, 210, 240, 255))
    d.line((10, 5, 10, 14), fill=(220, 255, 255, 255))
    D["crystals"] = im
    im, d = img(16, 16)  # hanging vines (ceiling)
    for x in (3, 8, 12):
        ln = 9 + x % 5
        for y in range(ln):
            d.point((x + (y // 3) % 2, y), fill=(60, 140, 50, 255))
        d.point((x, ln), fill=(120, 200, 80, 255))
    D["vines"] = im
    im, d = img(16, 32)  # statue
    stone = (150, 145, 135, 255)
    d.rectangle((2, 26, 13, 31), fill=gp.shade(stone, 0.8))
    d.rectangle((5, 10, 10, 26), fill=stone)
    d.ellipse((5, 3, 10, 9), fill=stone)
    d.line((5, 12, 2, 20), fill=stone, width=2)
    d.line((10, 12, 12, 6), fill=stone, width=2)
    D["statue"] = im
    im, d = img(16, 16)  # broken column
    d.rectangle((4, 6, 11, 15), fill=(170, 160, 140, 255))
    d.polygon([(4, 6), (7, 3), (9, 5), (11, 4), (11, 6)], fill=(170, 160, 140, 255))
    for x in (6, 9):
        d.line((x, 6, x, 15), fill=(130, 120, 105, 255))
    D["column"] = im
    im, d = img(16, 16)  # barrel
    d.rectangle((3, 3, 12, 15), fill=(120, 80, 45, 255))
    for y in (5, 13):
        d.line((3, y, 12, y), fill=(80, 80, 90, 255))
    d.line((7, 3, 7, 15), fill=(90, 60, 35, 255))
    D["barrel"] = im
    im, d = img(16, 16)  # stalactite (ceiling)
    d.polygon([(2, 0), (9, 0), (5, 14)], fill=(70, 50, 48, 255))
    d.polygon([(9, 0), (14, 0), (12, 8)], fill=(60, 42, 40, 255))
    D["stalactite"] = im
    im, d = img(16, 16)  # ember rocks (glow)
    d.ellipse((2, 9, 9, 15), fill=(50, 30, 28, 255))
    d.ellipse((7, 7, 14, 15), fill=(60, 34, 30, 255))
    for p in ((4, 11), (10, 10), (11, 13)):
        d.point(p, fill=(255, 140, 40, 255))
    D["ember_rocks"] = im
    im, d = img(16, 16)  # fire crystal (glow)
    d.polygon([(4, 15), (6, 5), (9, 15)], fill=(255, 100, 40, 255))
    d.polygon([(8, 15), (11, 7), (13, 15)], fill=(255, 160, 60, 255))
    D["fire_crystal"] = im
    im, d = img(16, 16)  # chains (ceiling)
    for x in (4, 11):
        for y in range(0, 14, 3):
            d.ellipse((x - 1, y, x + 1, y + 3), outline=(110, 110, 120, 255))
    D["chains"] = im
    # ---- extra detail (every biome) and the Mirror Halls
    im, d = img(16, 16)  # urn
    d.ellipse((4, 5, 11, 15), fill=(150, 110, 80, 255))
    d.rectangle((6, 2, 9, 5), fill=(130, 95, 70, 255))
    d.line((5, 9, 10, 9), fill=(200, 170, 90, 255))
    d.point((5, 7), fill=(200, 160, 120, 255))
    D["urn"] = im
    im, d = img(16, 16)  # tombstone
    d.rectangle((3, 5, 12, 15), fill=(120, 118, 125, 255))
    d.pieslice((3, 1, 12, 10), 180, 360, fill=(120, 118, 125, 255))
    d.line((7, 6, 7, 11), fill=(70, 68, 75, 255))
    d.line((5, 8, 9, 8), fill=(70, 68, 75, 255))
    d.line((3, 14, 12, 14), fill=(80, 140, 70, 255))
    D["tombstone"] = im
    D["puffball"] = gm.puffball()
    im, d = img(16, 16)  # fern
    for k, (x, h) in enumerate(((5, 10), (8, 13), (11, 9))):
        d.line((x, 15, x + (k - 1) * 2, 15 - h), fill=(60, 150, 90, 255))
        for y in range(15 - h + 2, 15, 2):
            d.point((x + (k - 1) + 1, y), fill=(90, 190, 110, 255))
            d.point((x + (k - 1) - 1, y + 1), fill=(90, 190, 110, 255))
    D["fern"] = im
    im, d = img(16, 16)  # vase
    d.polygon([(5, 15), (3, 9), (5, 5), (10, 5), (12, 9), (10, 15)], fill=(190, 120, 70, 255))
    d.line((4, 9, 11, 9), fill=(90, 50, 30, 255))
    d.rectangle((6, 2, 9, 5), fill=(170, 105, 60, 255))
    d.point((5, 7), fill=(230, 170, 120, 255))
    D["vase"] = im
    im, d = img(16, 32)  # banner (ceiling)
    d.line((1, 1, 14, 1), fill=(120, 90, 50, 255), width=2)
    d.polygon([(3, 2), (12, 2), (12, 26), (7, 22), (3, 26)], fill=(150, 40, 40, 255))
    d.line((3, 5, 12, 5), fill=(220, 180, 70, 255))
    d.ellipse((5, 9, 10, 14), outline=(220, 180, 70, 255))
    D["banner"] = im
    im, d = img(16, 16)  # rubble
    for x, y, r in ((3, 12, 3), (9, 11, 4), (13, 13, 2)):
        d.ellipse((x - r, y - r + 2, x + r, 15), fill=(140, 125, 100, 255))
        d.point((x - 1, y - r + 3), fill=(180, 165, 140, 255))
    D["rubble"] = im
    im, d = img(16, 16)  # obsidian spikes
    d.polygon([(2, 15), (4, 5), (7, 15)], fill=(40, 30, 45, 255))
    d.polygon([(6, 15), (9, 2), (12, 15)], fill=(55, 40, 60, 255))
    d.line((9, 3, 10, 14), fill=(140, 110, 170, 255))
    d.point((4, 7), fill=(255, 120, 60, 255))
    D["obsidian"] = im
    im, d = img(16, 32)  # standing mirror (glows faintly)
    gold = (210, 170, 70, 255)
    d.rectangle((2, 2, 13, 26), fill=gold)
    d.rectangle((4, 4, 11, 24), fill=(170, 160, 210, 255))
    d.line((5, 20, 10, 8), fill=(240, 235, 255, 255))
    d.line((5, 23, 10, 14), fill=(210, 200, 240, 255))
    d.rectangle((6, 27, 9, 31), fill=gold)
    d.line((3, 31, 12, 31), fill=gold)
    d.point((7, 1), fill=(255, 230, 140, 255))
    D["mirror"] = im
    im, d = img(16, 16)  # rune crystal (glow)
    d.polygon([(8, 1), (13, 8), (8, 15), (3, 8)], fill=(170, 120, 240, 255))
    d.polygon([(8, 1), (13, 8), (8, 8)], fill=(210, 170, 255, 255))
    d.line((6, 8, 10, 8), fill=(255, 255, 255, 255))
    d.line((8, 5, 8, 11), fill=(255, 255, 255, 255))
    D["rune_crystal"] = im
    im, d = img(16, 16)  # candelabra (glow)
    d.line((8, 6, 8, 15), fill=(200, 170, 70, 255))
    d.line((4, 15, 12, 15), fill=(200, 170, 70, 255))
    d.arc((3, 3, 13, 11), 0, 180, fill=(200, 170, 70, 255))
    for x in (3, 8, 13):
        d.rectangle((x - 1 if x != 13 else x - 1, 3, x if x != 13 else x, 6), fill=(240, 235, 220, 255))
        d.point((x, 1), fill=(200, 140, 255, 255))
        d.point((x, 2), fill=(255, 230, 255, 255))
    D["candelabra"] = im
    im, d = img(16, 32)  # violet banner (ceiling)
    d.line((1, 1, 14, 1), fill=(200, 170, 70, 255), width=2)
    d.polygon([(3, 2), (12, 2), (12, 26), (7, 22), (3, 26)], fill=(90, 50, 140, 255))
    d.rectangle((5, 8, 10, 14), fill=(240, 236, 230, 255))
    d.rectangle((5, 8, 7, 14), fill=(30, 25, 40, 255))
    d.line((3, 4, 12, 4), fill=(200, 170, 70, 255))
    D["violet_banner"] = im
    im, d = img(16, 16)  # hanging cards (ceiling)
    for x, ln, red in ((4, 6, True), (11, 9, False)):
        d.line((x, 0, x, ln), fill=(200, 190, 230, 200))
        d.rectangle((x - 2, ln, x + 2, ln + 6), fill=(245, 240, 230, 255), outline=(60, 40, 70, 255))
        d.point((x, ln + 3), fill=(200, 30, 50, 255) if red else (30, 30, 40, 255))
    D["cards"] = im
    # ---- wall props (placement WALL: hang on the back wall at eye level)
    im, d = img(16, 16)  # shelf with skulls
    d.rectangle((1, 11, 14, 12), fill=(110, 75, 45, 255))
    d.line((1, 11, 14, 11), fill=(150, 105, 65, 255))
    d.line((3, 13, 3, 15), fill=(90, 60, 35, 255))
    d.line((12, 13, 12, 15), fill=(90, 60, 35, 255))
    for x in (3, 9):
        d.ellipse((x, 5, x + 4, 10), fill=bone)
        d.point((x + 1, 7), fill=(30, 20, 20, 255))
        d.point((x + 3, 7), fill=(30, 20, 20, 255))
    D["wall_skull_shelf"] = im
    im, d = img(16, 16)  # shackles on chains
    for x in (4, 11):
        for y in range(0, 8, 2):
            d.point((x, y), fill=(130, 130, 140, 255))
        d.ellipse((x - 2, 8, x + 2, 12), outline=(150, 150, 160, 255))
    d.rectangle((2, 0, 13, 1), fill=(90, 90, 100, 255))
    D["wall_shackles"] = im
    D["wall_fungi"] = gm.wall_fungi()
    im, d = img(16, 16)  # roots through the wall
    for x0 in (3, 9, 13):
        x = x0
        for y in range(16):
            x += random.Random(x0 * 7 + y).choice((-1, 0, 0, 1))
            d.point((x, y), fill=(100, 75, 50, 255))
    D["wall_roots"] = im
    im, d = img(32, 16)  # faded fresco
    d.rectangle((0, 0, 31, 15), fill=(160, 140, 105, 255))
    d.rectangle((1, 1, 30, 14), fill=(190, 170, 130, 255))
    d.ellipse((5, 3, 11, 9), fill=(170, 80, 60, 255))
    d.line((8, 9, 8, 14), fill=(120, 90, 160, 255), width=2)
    d.polygon([(16, 13), (21, 4), (26, 13)], fill=(90, 130, 90, 255))
    d.point((21, 3), fill=(230, 190, 70, 255))
    for x in (2, 13, 29):
        d.line((x, 2, x + 2, 6), fill=(140, 120, 90, 255))  # cracks / missing paint
    D["wall_fresco"] = im
    im, d = img(16, 16)  # ivy patch
    for _ in range(26):
        rr = random.Random(_ * 13)
        x, y = rr.randint(1, 14), rr.randint(0, 15)
        d.point((x, y), fill=(70, 140, 55, 255) if _ % 3 else (110, 180, 80, 255))
    D["wall_ivy"] = im
    im, d = img(16, 16)  # glowing lava crack (glow)
    d.line((2, 2, 6, 6, 5, 10, 9, 14), fill=(255, 120, 40, 255), width=2)
    d.line((6, 6, 12, 5), fill=(255, 150, 60, 255))
    d.point((6, 7), fill=(255, 240, 160, 255))
    D["wall_lava_crack"] = im
    im, d = img(16, 16)  # small round mirror (glow)
    d.ellipse((2, 2, 13, 13), fill=(210, 170, 70, 255))
    d.ellipse((4, 4, 11, 11), fill=(180, 170, 220, 255))
    d.line((5, 9, 9, 5), fill=(245, 240, 255, 255))
    D["wall_mirror"] = im
    im, d = img(16, 16)  # theatre masks
    d.ellipse((1, 3, 8, 12), fill=(240, 236, 230, 255))
    d.ellipse((8, 4, 15, 13), fill=(40, 30, 50, 255))
    d.point((3, 6), fill=(30, 25, 35, 255))
    d.point((6, 6), fill=(30, 25, 35, 255))
    d.arc((3, 7, 7, 11), 20, 160, fill=(30, 25, 35, 255))
    d.point((10, 7), fill=(230, 220, 240, 255))
    d.point((13, 7), fill=(230, 220, 240, 255))
    d.arc((10, 10, 14, 13), 200, 340, fill=(230, 220, 240, 255))
    D["wall_masks"] = im
    # ---- wide floor set pieces (two cells)
    im, d = img(32, 16)  # sarcophagus
    stone = (125, 120, 130, 255)
    d.rectangle((1, 6, 30, 15), fill=stone)
    d.rectangle((0, 3, 31, 7), fill=gp.shade(stone, 1.15))
    d.line((0, 3, 31, 3), fill=gp.shade(stone, 1.35))
    d.line((1, 15, 30, 15), fill=gp.shade(stone, 0.6))
    d.ellipse((12, 4, 19, 7), fill=gp.shade(stone, 0.85))  # carved face
    d.line((4, 10, 27, 10), fill=gp.shade(stone, 0.75))
    d.line((24, 3, 27, 7), fill=gp.shade(stone, 0.5))  # crack in the lid
    D["sarcophagus"] = im
    D["mushroom_cluster"] = gm.mushroom_cluster()
    im, d = img(32, 32)  # broken arch
    stone = (165, 152, 125, 255)
    d.rectangle((2, 10, 7, 31), fill=stone)
    d.rectangle((25, 18, 30, 31), fill=stone)
    d.arc((2, 0, 30, 28), 180, 270, fill=stone, width=5)
    d.line((2, 10, 2, 31), fill=gp.shade(stone, 1.25))
    d.line((7, 10, 7, 31), fill=gp.shade(stone, 0.7))
    for y in (16, 23):
        d.line((2, y, 7, y), fill=gp.shade(stone, 0.75))
        d.line((25, y + 3, 30, y + 3), fill=gp.shade(stone, 0.75))
    for x, y in ((14, 29), (18, 30), (21, 28)):
        d.rectangle((x, y, x + 2, 31), fill=gp.shade(stone, 0.9))  # fallen stones
    d.line((3, 12, 5, 30), fill=(80, 140, 60, 255))  # ivy
    D["broken_arch"] = im
    im, d = img(32, 16)  # charred bone pile
    for k in range(9):
        x = 2 + (k * 7) % 26
        d.line((x, 15 - (k % 3), x + 6, 13 - (k % 2)), fill=(70, 60, 55, 255), width=2)
    d.ellipse((12, 6, 19, 13), fill=(80, 70, 65, 255))
    d.point((14, 9), fill=(255, 120, 40, 255))
    d.point((17, 9), fill=(255, 120, 40, 255))
    for x in (5, 22, 27):
        d.point((x, 14), fill=(255, 150, 50, 255))
    D["charred_bones"] = im
    im, d = img(32, 32)  # grand mirror (glow)
    gold = (215, 175, 70, 255)
    d.rectangle((4, 1, 27, 27), fill=gold)
    d.pieslice((4, -6, 27, 10), 180, 360, fill=gold)
    d.rectangle((7, 4, 24, 25), fill=(150, 140, 200, 255))
    d.line((9, 21, 21, 7), fill=(240, 235, 255, 255), width=2)
    d.line((10, 24, 22, 13), fill=(210, 200, 245, 255))
    d.ellipse((14, -3, 17, 0), fill=(255, 80, 120, 255))
    d.rectangle((12, 28, 19, 31), fill=gold)
    d.line((6, 31, 25, 31), fill=gp.shade(gold, 0.7))
    D["grand_mirror"] = im
    for name, im in D.items():
        gp.save(im, f"sprites/decor/{name}.png", do_outline=name not in ("cobweb", "wall_roots", "wall_ivy"))


# ------------------------------------------------- hero gloves/boots layers
def gen_hero_extra_layers():
    poses = gs.hero_poses()
    lay = gs.Layout("hero_layout", gs.HERO_FW, gs.HERO_FH, (gs.CX, gs.GROUND + 1))
    for name, (fps, loop, frames) in poses.items():
        lay.add(name, len(frames), fps, loop)

    def boots_fn(color):
        def fn(name, i, _n):
            pz = poses[name][2][i]
            im = gp.new(gs.HERO_FW, gs.HERO_FH)
            d = ImageDraw.Draw(im)
            s = gs.skel(pz, gs.RACES["human"])
            for side in ("l", "r"):
                fx, fy = s[side + "foot"]
                c = c4(color) if side == "r" else gp.shade(c4(color), 0.8)
                d.rectangle((fx - 1, fy - 2, fx + 2, fy), fill=c)
                d.point((fx + 2, fy - 2), fill=gp.shade(c4(color), 1.3))
            return gs.apply_rot(im, pz)
        return fn

    def gloves_fn(color):
        def fn(name, i, _n):
            pz = poses[name][2][i]
            im = gp.new(gs.HERO_FW, gs.HERO_FH)
            d = ImageDraw.Draw(im)
            s = gs.skel(pz, gs.RACES["human"])
            hx, hy = s["rhand"]
            d.rectangle((hx - 1, hy - 1, hx + 1, hy + 1), fill=c4(color))
            d.point((hx + 1, hy - 1), fill=gp.shade(c4(color), 1.3))
            return gs.apply_rot(im, pz)
        return fn

    for key, col in (("leather_boots", (110, 72, 40)), ("swift_boots", (70, 140, 200))):
        gs.render_sheet(lay, boots_fn(col), f"sprites/player/equip_{key}.png", do_outline=False)
    for key, col in (("leather_gloves", (140, 95, 55)), ("gauntlets", (170, 175, 185))):
        gs.render_sheet(lay, gloves_fn(col), f"sprites/player/equip_{key}.png", do_outline=False)


def misc_ui():
    # Blob shadow under creatures.
    sh = gp.new(16, 6)
    d = ImageDraw.Draw(sh)
    d.ellipse((0, 0, 15, 5), fill=(0, 0, 0, 110))
    d.ellipse((3, 1, 12, 4), fill=(0, 0, 0, 150))
    sh.save(os.path.join(A, "sprites/fx/shadow.png"))
    # Slot frame with metal rivets (like the HUD reference).
    for name, base in (("slot", gp.slot_tex()), ("slot_empty", gp.slot_dark_tex()), ("slot_hover", gp.slot_hover_tex())):
        d = ImageDraw.Draw(base)
        for (x, y) in ((2, 2), (21, 2), (2, 21), (21, 21)):
            d.point((x, y), fill=(200, 200, 210, 255))
            d.point((x - 1, y), fill=(120, 120, 130, 255))
        base.save(os.path.join(A, f"ui/{name}.png"))
    # Rivet for the HUD panel border, and a small plaque frame.
    rv = gp.new(5, 5)
    d = ImageDraw.Draw(rv)
    d.ellipse((0, 0, 4, 4), fill=(110, 110, 120, 255))
    d.point((1, 1), fill=(230, 230, 240, 255))
    d.point((3, 3), fill=(60, 60, 70, 255))
    rv.save(os.path.join(A, "ui/rivet.png"))


# ----------------------------------------------------------- biome .tres
DATA = os.path.join(os.path.dirname(__file__), "..", "data", "biomes")
# biome -> extra decorations: (name, placement 0 floor / 1 ceiling / 2 wall, weight, light rgb or None, unshaded, sway)
EXTRA_DECOR = {
    "catacombs": [("urn", 0, 1.2, None, False, False), ("tombstone", 0, 1.0, None, False, False),
                  ("wall_skull_shelf", 2, 1.2, None, False, False), ("wall_shackles", 2, 1.0, None, False, False),
                  ("sarcophagus", 0, 0.8, None, False, False)],
    "fungal": [("puffball", 0, 1.5, (0.8, 0.5, 1.0), True, False), ("fern", 0, 1.5, None, False, False),
               ("wall_fungi", 2, 1.5, (1.0, 0.7, 0.4), True, False), ("wall_roots", 2, 1.2, None, False, False),
               ("mushroom_cluster", 0, 0.8, (0.5, 1.0, 0.9), True, False)],
    "ruins": [("vase", 0, 1.2, None, False, False), ("banner", 1, 1.0, None, False, True),
              ("rubble", 0, 1.5, None, False, False), ("wall_fresco", 2, 1.0, None, False, False),
              ("wall_ivy", 2, 1.5, None, False, False), ("broken_arch", 0, 0.7, None, False, False)],
    "lava": [("obsidian", 0, 1.5, None, False, False), ("wall_lava_crack", 2, 1.5, (1.0, 0.5, 0.2), True, False),
             ("charred_bones", 0, 1.0, None, False, False), ("wall_shackles", 2, 0.6, None, False, False)],
}
MIRROR_DECOR = [("mirror", 0, 1.5, (0.75, 0.65, 1.0), True, False), ("rune_crystal", 0, 1.5, (0.7, 0.5, 1.0), True, False),
                ("candelabra", 0, 1.0, (0.85, 0.6, 1.0), True, False), ("violet_banner", 1, 1.2, None, False, True),
                ("cards", 1, 1.2, None, False, True), ("chains", 1, 0.8, None, False, True),
                ("crystals", 0, 1.0, (0.8, 0.6, 1.0), True, False),
                ("wall_mirror", 2, 1.5, (0.75, 0.65, 1.0), True, False), ("wall_masks", 2, 1.2, None, False, False),
                ("grand_mirror", 0, 0.7, (0.75, 0.6, 1.0), True, False)]


def _decor_sub(sid, tex_id, placement, weight, light, unshaded, sway):
    lc = "Color(%s, %s, %s, 1)" % light if light else "Color(0, 0, 0, 0)"
    return "\n".join(['[sub_resource type="Resource" id="%s"]' % sid, 'script = ExtResource("decor_script")',
                      'texture = ExtResource("%s")' % tex_id, "placement = %d" % placement, "weight = %s" % weight,
                      "light_color = " + lc, "light_scale = 0.25", "unshaded = %s" % ("true" if unshaded else "false"),
                      "sway = %s" % ("true" if sway else "false")])


def add_decor(biome, items):
    """Adds decorations to an existing biome .tres (idempotent)."""
    path = os.path.join(DATA, biome + ".tres")
    s = open(path, encoding="utf-8").read()
    head, res = s.split("[resource]", 1)
    script_id = re.search(r'\[ext_resource type="Script" path="res://scripts/data/decor_data.gd" id="([^"]+)"\]', head).group(1)
    for name, placement, weight, light, unshaded, sway in items:
        if "decor/%s.png" % name in head:
            continue
        ext = '[ext_resource type="Texture2D" path="res://assets/sprites/decor/%s.png" id="dx_%s"]' % (name, name)
        head = head.replace("\n\n[sub_resource", "\n" + ext + "\n\n[sub_resource", 1)
        sub = _decor_sub("Decor_" + name, "dx_" + name, placement, weight, light, unshaded, sway).replace(
            'ExtResource("decor_script")', 'ExtResource("%s")' % script_id)
        head = head.rstrip("\n") + "\n\n" + sub + "\n\n"
        res = re.sub(r"(decorations = Array\[ExtResource\(\"[^\"]+\"\)\]\(\[)(.*?)(\]\))",
                     lambda m: m.group(1) + m.group(2) + ', SubResource("Decor_%s")' % name + m.group(3), res, count=1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(head + "[resource]" + res)


def mirror_biome_tres():
    ext = ['[ext_resource type="Script" path="res://scripts/data/decor_data.gd" id="decor_script"]',
           '[ext_resource type="Script" path="res://scripts/data/biome_data.gd" id="biome_script"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/tiles/tiles_mirror_halls.png" id="tiles"]']
    for layer in ("far", "mid", "near"):
        ext.append('[ext_resource type="Texture2D" path="res://assets/sprites/backgrounds/mirror_halls_%s.png" id="bg_%s"]' % (layer, layer))
    subs = []
    for name, placement, weight, light, unshaded, sway in MIRROR_DECOR:
        ext.append('[ext_resource type="Texture2D" path="res://assets/sprites/decor/%s.png" id="dx_%s"]' % (name, name))
        subs.append(_decor_sub("Decor_" + name, "dx_" + name, placement, weight, light, unshaded, sway))
    res = """[resource]
script = ExtResource("biome_script")
music = &"mirror_halls"
step_sound = &"step_stone"
id = &"mirror_halls"
display_name = "Зеркальные чертоги"
order = 4
tileset_texture = ExtResource("tiles")
parallax_far = ExtResource("bg_far")
parallax_mid = ExtResource("bg_mid")
parallax_near = ExtResource("bg_near")
ambient = Color(0.98, 0.95, 1, 1)
back_wall_modulate = Color(0.84, 0.8, 0.9, 1)
torch_color = Color(0.8, 0.55, 1, 1)
ambient_particles = Color(0.85, 0.75, 1, 1)
particle_style = &"sparkles"
fog_color = Color(0.55, 0.45, 0.75, 1)
fog_amount = 0.09
grade_tint = Color(0.98, 0.95, 1.03, 1)
saturation = 1.0
contrast = 1.05
decorations = Array[ExtResource("decor_script")]([%s])
decor_per_room = 5.0
ore_chance = 0.04
ore_item = &"moon_crystal"
""" % ", ".join('SubResource("Decor_%s")' % n[0] for n in MIRROR_DECOR)
    text = '[gd_resource type="Resource" script_class="BiomeData" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1)
    text += "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n" + res
    with open(os.path.join(DATA, "mirror_halls.tres"), "w", encoding="utf-8") as f:
        f.write(text)


def main():
    os.makedirs(os.path.join(A, "sprites/backgrounds"), exist_ok=True)
    for name, b in BIOMES.items():
        tileset(name, b)
        parallax(name, b)
    decor_all()
    for biome, items in EXTRA_DECOR.items():
        add_decor(biome, items)
    mirror_biome_tres()
    gen_hero_extra_layers()
    misc_ui()
    print("biomes generated")


if __name__ == "__main__":
    main()
