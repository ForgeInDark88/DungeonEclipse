#!/usr/bin/env python3
"""Finished art for what used to be flat placeholders (stages 14-19).

Same file names and sizes as before (code offsets and hitboxes stay valid),
drawn with the dungeon toolkit: volume lit from the top left in four tones
with dithered borders (gen_monsters.lit / relight), stone blocks with mortar
(gen_structures.bricks), wood planks with grain, iron rivets, layered flames
and soft quantised glow, a dark outline.

  portals   assets/sprites/portals/*       cave mouths, stairs, the road sign,
                                           the guardian's gate, lift, well,
                                           crypt, ruin stairs, sinkhole
  surface   assets/sprites/surface/*       tent, campfire, cart, gravestone,
                                           well, reeds, bush, ruins, tower,
                                           ore vein, herb, berry bush, dig
                                           mark, barrel, crate
  items     assets/sprites/items/*         pickaxe, shovel, wild berries,
                                           blueprint and revive scrolls
  world     assets/sprites/world/cage.png  the rescue cage
  ui        assets/ui/map/*, assets/ui/res/*  map medallions, hints, the hero
                                           marker, resource icons

Run:  python3 tools/gen_quality_art.py   (then godot --headless --editor --quit)
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp
from gen_monsters import FULL, LEVELS, LIGHT, blank, lit, mask, rgba, sh
from gen_structures import bricks, planks, rivet, glow_dot, flame, finish, STONE, STONE_WARM, IRON, WOOD, GOLD

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUT = gp.OUT
CUTS = (0.7, 0.38, 0.02)

EARTH = (104, 76, 52)
GRASS = (86, 140, 62)
MOSS = (82, 122, 58)
CANVAS = (176, 150, 110)
ROPE = (184, 156, 104)
DARK = (14, 10, 14)
LEATHER = (96, 60, 36)


def save(im, rel, outline=True, glow=None):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    finish(im, glow, outline).save(path)


def h(x, y, s=0):
    """Hashed noise in [0, 1)."""
    return ((x * 73856093) ^ (y * 19349663) ^ (s * 83492791)) % 1000 / 1000.0


def relight(im, m, cx, cy, rx, ry, strength=1.0):
    """Shades what is already drawn under mask m like a lit ellipsoid."""
    px, mp = im.load(), m.load()
    w, hh = im.size
    for y in range(hh):
        for x in range(w):
            if mp[x, y][3] == 0 or px[x, y][3] == 0:
                continue
            nx, ny = (x - cx) / max(rx, 0.5), (y - cy) / max(ry, 0.5)
            nz = math.sqrt(max(0.0, 1 - min(1.0, nx * nx + ny * ny)))
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            dd = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
            i = 0
            while i < len(CUTS) and dd <= CUTS[i]:
                i += 1
            if i > 0 and dd > CUTS[i - 1] - 0.06 and (x + y) % 2 == 0:
                i -= 1
            f = 1.0 + (LEVELS[i] - 1.0) * strength
            r, g, b, a = px[x, y]
            px[x, y] = (min(255, int(r * f)), min(255, int(g * f)), min(255, int(b * f)), a)


def clip(im, m):
    """Keeps im only where mask m is set."""
    px, mp = im.load(), m.load()
    for y in range(im.height):
        for x in range(im.width):
            if mp[x, y][3] == 0:
                px[x, y] = (0, 0, 0, 0)


def textured(w, hh, m, fill_fn):
    """A layer filled by fill_fn(im) and cut to mask m."""
    t = blank(w, hh)
    fill_fn(t)
    clip(t, m)
    return t


def stone_rough(im, x0, y0, x1, y1, base, seed=1):
    """Natural rock: Voronoi-like lumps with dark seams."""
    rnd = random.Random(seed)
    pts = [(rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(0.9, 1.1)) for _ in range(max(3, (x1 - x0) * (y1 - y0) // 26))]
    px = im.load()
    for y in range(max(0, y0), min(im.height, y1 + 1)):
        for x in range(max(0, x0), min(im.width, x1 + 1)):
            best, second, tone, bx, by = 1e9, 1e9, 1.0, 0, 0
            for (qx, qy, t) in pts:
                d = (x - qx) ** 2 + ((y - qy) * 1.4) ** 2
                if d < best:
                    second = best
                    best, tone, bx, by = d, t, qx, qy
                elif d < second:
                    second = d
            f = tone
            if math.sqrt(second) - math.sqrt(best) < 0.9:
                f *= 0.62
            elif y < by - 1.2 or x < bx - 1.6:
                f *= 1.12
            elif y > by + 1.2:
                f *= 0.88
            if h(x, y, seed) < 0.06:
                f *= 0.86
            px[x, y] = sh(base, f)


def grass_tufts(d, x0, x1, y, seed=1, col=GRASS, tall=3):
    rnd = random.Random(seed)
    for x in range(x0, x1 + 1):
        if rnd.random() < 0.55:
            ht = rnd.randint(1, tall)
            d.line((x, y, x + rnd.choice((-1, 0, 0, 1)), y - ht), fill=sh(col, rnd.choice((0.8, 1.0, 1.2))))


def moss_on(im, m, col=MOSS, seed=3, density=0.5, top_only=True):
    """Moss where the mask has open sky above."""
    px, mp = im.load(), m.load()
    for y in range(1, im.height):
        for x in range(im.width):
            if mp[x, y][3] and (not top_only or mp[x, y - 1][3] == 0 or (y > 1 and mp[x, y - 2][3] == 0 and h(x, y, seed) < 0.5)):
                if h(x, y, seed) < density:
                    px[x, y] = sh(col, 1.25 if h(x, y, seed + 1) < 0.4 else 0.95)


def leaf_cluster(im, blobs, base, seed=1, berries=None):
    """Leafy clumps: each blob lit, small leaf notches, highlights."""
    w, hh = im.size
    rnd = random.Random(seed)
    for (cx, cy, rx, ry) in blobs:
        m = mask(w, hh, lambda d, cx=cx, cy=cy, rx=rx, ry=ry: d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(255, 255, 255, 255)))
        lit(im, m, base, cx - rx * 0.2, cy - ry * 0.25, rx * 1.2, ry * 1.2)
    px = im.load()
    for y in range(hh):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            v = h(x, y, seed)
            if v < 0.08:
                px[x, y] = sh(px[x, y], 0.72)
            elif v < 0.14 and y > 0 and px[x, y - 1][3] == 0:
                px[x, y] = (0, 0, 0, 0)  # ragged leafy rim
            elif v > 0.94:
                px[x, y] = sh(px[x, y], 1.3)
    if berries:
        d = ImageDraw.Draw(im)
        for _ in range(berries[1]):
            for _try in range(20):
                x, y = rnd.randint(1, w - 2), rnd.randint(1, hh - 3)
                if px[x, y][3] and px[x + 1, y + 1][3]:
                    break
            d.point((x, y), fill=rgba(berries[0]))
            d.point((x + 1, y), fill=sh(berries[0], 0.75))
            d.point((x, y + 1), fill=sh(berries[0], 0.6))
            d.point((x + 1, y + 1), fill=sh(berries[0], 0.5))
            d.point((x, y), fill=sh(berries[0], 1.6))


def dark_hole(im, m, cy0, cy1, base=(40, 30, 34)):
    """A mouth that falls into darkness toward its middle / bottom."""
    px, mp = im.load(), m.load()
    for y in range(im.height):
        for x in range(im.width):
            if mp[x, y][3]:
                t = (y - cy0) / max(1, cy1 - cy0)
                f = 0.75 - 0.6 * max(0.0, min(1.0, t))
                if (x + y) % 2 and 0.2 < t < 0.5:
                    f -= 0.08
                px[x, y] = sh(base, max(0.12, f))


# =================================================================== portals
def cave(mossy):
    w, hh = 44, 36
    outer = mask(w, hh, lambda d: (d.ellipse((0, 1, 43, 60), fill=FULL), d.rectangle((0, 30, 43, 35), fill=FULL)))
    im = textured(w, hh, outer, lambda t: stone_rough(t, 0, 0, w - 1, hh - 1, (118, 108, 98) if not mossy else (100, 104, 92), seed=11 if mossy else 7))
    relight(im, outer, 18, 10, 26, 26, 0.9)
    mouth = mask(w, hh, lambda d: (d.ellipse((10, 9, 33, 52), fill=FULL), d.rectangle((10, 30, 33, 35), fill=FULL)))
    dark_hole(im, mouth, 10, 26)
    d = ImageDraw.Draw(im)
    # rim stones around the mouth, lit on top
    for k in range(9):
        a = math.pi + k * math.pi / 8
        x, y = 21.5 + math.cos(a) * 13, 30 + math.sin(a) * 22
        d.ellipse((x - 2, y - 1, x + 2, y + 2), fill=sh((140, 128, 114), 1.0 if k < 5 else 0.82))
        d.point((x - 1, y - 1), fill=sh((140, 128, 114), 1.35))
        d.point((x + 1, y + 2), fill=sh((140, 128, 114), 0.6))
    # stalactite teeth
    for x, ln in ((15, 4), (19, 2), (24, 5), (28, 3)):
        top = 11 if x in (19, 24) else 13
        d.polygon([(x - 1, top), (x + 1, top), (x, top + ln)], fill=sh((110, 100, 92), 0.8))
        d.point((x - 1, top), fill=sh((110, 100, 92), 1.2))
    # rubble and a faint glint in the deep
    for x, y in ((6, 33), (37, 34), (12, 34), (32, 33)):
        d.ellipse((x - 2, y - 1, x + 2, y + 1), fill=sh((120, 110, 100), 0.9))
        d.point((x - 1, y - 1), fill=sh((120, 110, 100), 1.3))
    d.point((21, 27), fill=(120, 150, 170, 255))
    d.point((24, 29), fill=(90, 110, 130, 255))
    grass_tufts(d, 0, 9, 35, 3)
    grass_tufts(d, 34, 43, 35, 4)
    if mossy:
        moss_on(im, outer, MOSS, 5, 0.75)
        for x, ln in ((9, 6), (13, 9), (30, 7), (34, 5), (20, 3)):
            for k in range(ln):
                if 0 <= 10 + k < hh:
                    d.point((x + (k // 3) % 2, 9 + k), fill=sh(MOSS, 1.1 if k % 2 else 0.85))
            d.point((x, 9 + ln), fill=(220, 210, 120, 255))
    else:
        moss_on(im, outer, (110, 140, 70), 9, 0.25)
    save(im, "sprites/portals/%s.png" % ("cave_mossy" if mossy else "cave"))


def arch_frame(im, d, w, hh, base, seed=1):
    """A stone doorway (bricks) with an arch, returns the opening mask."""
    frame = mask(w, hh, lambda dd: (dd.ellipse((0, 0, w - 1, 22), fill=FULL), dd.rectangle((0, 10, w - 1, hh - 1), fill=FULL)))
    layer = textured(w, hh, frame, lambda t: bricks(t, 0, 0, w - 1, hh - 1, base, 5, 3, seed))
    relight(layer, frame, w * 0.35, hh * 0.3, w * 0.8, hh * 0.9, 0.6)
    im.alpha_composite(layer)
    opening = mask(w, hh, lambda dd: (dd.ellipse((5, 5, w - 6, 24), fill=FULL), dd.rectangle((5, 14, w - 6, hh - 2), fill=FULL)))
    # voussoirs: the arch ring
    for k in range(7):
        a = math.pi + k * math.pi / 6
        x, y = (w - 1) / 2 + math.cos(a) * (w / 2 - 3.5), 14.5 + math.sin(a) * 9
        d.point((x, y), fill=sh(base, 0.55))
    return opening


def stairs(up):
    w, hh = 28, 36
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (112, 108, 122)
    op = arch_frame(im, d, w, hh, base, 21 if up else 23)
    if up:
        # stairs rising into warm light
        lay = blank(w, hh)
        ld = ImageDraw.Draw(lay)
        ld.rectangle((0, 0, w, hh), fill=(250, 214, 140, 255))
        for k in range(6):
            y = 30 - k * 4
            x0 = 6 + k
            ld.rectangle((x0, y, w - 6, y + 4), fill=sh((170, 150, 120), 1.0 - k * 0.04))
            ld.line((x0, y, w - 6, y), fill=sh((230, 210, 170), 1.0))
            ld.line((x0, y + 4, w - 6, y + 4), fill=sh((120, 100, 80), 0.9))
        clip(lay, op)
        im.alpha_composite(lay)
        glow = blank(w, hh)
        glow_dot(glow, 14, 10, 9, (255, 230, 160), 0.7)
        clip(glow, op)
        im.alpha_composite(glow)
    else:
        dark_hole(im, op, 6, 34, (60, 48, 50))
        px = im.load()
        for k in range(5):
            y = 22 + k * 3
            for x in range(6 + k, w - 6 - k):
                if op.getpixel((x, y))[3]:
                    px[x, y] = sh((150, 136, 120), 0.95 - k * 0.15)
                    if y + 1 < hh:
                        px[x, y + 1] = sh((90, 80, 72), 0.7 - k * 0.1)
    # keystone with a glyph
    d.rectangle((11, 1, 16, 6), fill=sh(base, 1.15))
    d.line((11, 1, 16, 1), fill=sh(base, 1.45))
    d.line((16, 1, 16, 6), fill=sh(base, 0.7))
    tri = [(12, 5), (15, 5), (13.5, 2)] if up else [(12, 2), (15, 2), (13.5, 5)]
    d.polygon(tri, fill=(255, 210, 90, 255))
    # threshold
    d.rectangle((2, hh - 3, w - 3, hh - 1), fill=sh(base, 0.95))
    d.line((2, hh - 3, w - 3, hh - 3), fill=sh(base, 1.35))
    d.point((4, 12), fill=(120, 150, 80, 255))
    d.point((23, 20), fill=(120, 150, 80, 255))
    g = blank(w, hh)
    glow_dot(g, 13.5, 3.5, 3, (255, 200, 90), 0.8)
    save(im, "sprites/portals/stairs_%s.png" % ("up" if up else "down"), glow=g)


def map_exit():
    w, hh = 22, 32
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    # the post: round wood lit from the left
    post = mask(w, hh, lambda dd: dd.rectangle((9, 3, 12, hh - 1), fill=FULL))
    lit(im, post, (110, 76, 44), 9.5, 14, 2.4, 40)
    for y in range(6, hh, 4):
        d.point((10 + (y // 4) % 2, y), fill=sh((110, 76, 44), 0.65))
    d.ellipse((9, 1, 12, 4), fill=sh((110, 76, 44), 1.1))
    # two arrow boards with planks, nails and burnt letters
    def board(y, right):
        if right:
            pts = [(1, y), (16, y), (20, y + 3), (16, y + 6), (1, y + 6)]
        else:
            pts = [(21, y), (5, y), (1, y + 3), (5, y + 6), (21, y + 6)]
        m = mask(w, hh, lambda dd: dd.polygon(pts, fill=FULL))
        t = textured(w, hh, m, lambda tt: planks(tt, 0, y, w - 1, y + 6, (162, 116, 70), False, 3, y))
        im.alpha_composite(t)
        d.line((pts[0][0], y, pts[1][0], y), fill=sh((162, 116, 70), 1.35))
        xs = range(4, 15, 3) if right else range(7, 18, 3)
        for x in xs:
            d.point((x, y + 3), fill=sh((70, 44, 26), 1.0))
            d.point((x + 1, y + 2 + (x % 2)), fill=sh((70, 44, 26), 1.0))
        rivet(d, 10, y + 1, IRON)
        rivet(d, 10, y + 4, IRON)
    board(6, True)
    board(14, False)
    # a little lantern hanging from the post
    d.line((13, 22, 15, 22), fill=sh(IRON, 1.0))
    d.line((15, 22, 15, 23), fill=sh(IRON, 1.0))
    d.rectangle((14, 24, 16, 27), fill=(255, 200, 90, 255))
    d.point((14, 24), fill=(255, 250, 220, 255))
    d.line((14, 23, 16, 23), fill=sh(IRON, 0.8))
    d.line((14, 28, 16, 28), fill=sh(IRON, 0.8))
    # stones and grass at the foot
    for x in (7, 14):
        d.ellipse((x - 2, hh - 3, x + 2, hh - 1), fill=sh(STONE, 1.0))
        d.point((x - 1, hh - 3), fill=sh(STONE, 1.4))
    grass_tufts(d, 2, 20, hh - 1, 8)
    g = blank(w, hh)
    glow_dot(g, 15, 25.5, 5, (255, 200, 100), 0.7)
    save(im, "sprites/portals/map_exit.png", glow=g)


def arena_exit():
    w, hh = 30, 40
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (70, 64, 88)
    op = arch_frame(im, d, w, hh, base, 31)
    # a violet swirl inside
    px = im.load()
    for y in range(hh):
        for x in range(w):
            if op.getpixel((x, y))[3]:
                dx, dy = x - 14.5, y - 22
                r = math.hypot(dx, dy * 0.7)
                a = math.atan2(dy, dx) + r * 0.35
                v = 0.5 + 0.5 * math.sin(a * 3)
                f = 0.35 + 0.65 * v * max(0.0, 1 - r / 14)
                c = (120 + int(120 * f), 60 + int(90 * f), 200 + int(55 * f))
                px[x, y] = (min(255, c[0]), min(255, c[1]), min(255, c[2]), 255)
    d.point((14, 22), fill=(255, 250, 255, 255))
    d.point((15, 21), fill=(240, 220, 255, 255))
    # runes up both jambs
    for y in range(14, hh - 4, 4):
        for x in (2, w - 3):
            d.point((x, y), fill=(200, 150, 255, 255))
            d.point((x, y + 1), fill=(150, 100, 220, 255))
    # horns on top
    for sx in (-1, 1):
        x = 14.5 + sx * 9
        d.polygon([(x - 2, 6), (x + 2, 6), (x + sx * 5, -1)], fill=(220, 210, 190, 255))
        d.line((x - 2 * sx, 6, x + sx * 5, -1), fill=(250, 245, 230, 255))
    d.rectangle((11, 0, 18, 5), fill=sh(base, 1.2))
    d.ellipse((12, 1, 17, 5), fill=(30, 20, 40, 255))
    d.point((13, 3), fill=(220, 120, 255, 255))
    d.point((16, 3), fill=(220, 120, 255, 255))
    g = blank(w, hh)
    glow_dot(g, 14.5, 23, 11, (190, 120, 255), 0.55)
    save(im, "sprites/portals/arena_exit.png", glow=g)


def lift():
    w, hh = 30, 40
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    beam = (124, 84, 48)
    for x0 in (1, w - 5):
        m = mask(w, hh, lambda dd, x0=x0: dd.rectangle((x0, 4, x0 + 3, hh - 1), fill=FULL))
        im.alpha_composite(textured(w, hh, m, lambda t: planks(t, x0, 0, x0 + 3, hh - 1, beam, True, 4, x0)))
        d.line((x0, 4, x0, hh - 1), fill=sh(beam, 1.3))
        d.line((x0 + 3, 4, x0 + 3, hh - 1), fill=sh(beam, 0.6))
    # crossbeam and braces
    m = mask(w, hh, lambda dd: dd.rectangle((0, 1, w - 1, 5), fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: planks(t, 0, 1, w - 1, 5, beam, False, 5, 4)))
    d.line((0, 1, w - 1, 1), fill=sh(beam, 1.4))
    d.line((5, 6, 9, 10), fill=sh(beam, 0.9))
    d.line((w - 6, 6, w - 10, 10), fill=sh(beam, 0.9))
    for x in (2, w - 3, 8, w - 9):
        rivet(d, x, 3)
    # pulley wheel
    d.ellipse((11, 3, 18, 10), fill=sh(IRON, 1.0))
    d.arc((11, 3, 18, 10), 160, 300, fill=sh(IRON, 1.6))
    d.ellipse((13, 5, 16, 8), fill=sh(IRON, 0.6))
    d.point((14, 6), fill=sh(IRON, 1.8))
    # ropes
    for x in (11, 18):
        for y in range(8, 22):
            d.point((x, y), fill=sh(ROPE, 1.15 if y % 2 else 0.8))
    # the cage platform
    d.rectangle((6, 21, 23, 22), fill=sh(IRON, 1.2))
    d.line((6, 21, 23, 21), fill=sh(IRON, 1.6))
    for x in range(7, 23, 3):
        d.line((x, 23, x, 33), fill=sh(IRON, 0.95))
        d.point((x, 24), fill=sh(IRON, 1.5))
    pm = mask(w, hh, lambda dd: dd.rectangle((5, 34, 24, 37), fill=FULL))
    im.alpha_composite(textured(w, hh, pm, lambda t: planks(t, 5, 34, 24, 37, (150, 104, 60), True, 3, 9)))
    d.line((5, 34, 24, 34), fill=sh((150, 104, 60), 1.35))
    d.line((5, 37, 24, 37), fill=sh((150, 104, 60), 0.6))
    # counterweight and crank
    d.rectangle((25, 22, 27, 26), fill=sh(STONE, 0.9))
    d.point((25, 22), fill=sh(STONE, 1.4))
    d.line((3, 16, 0, 18), fill=sh(IRON, 1.1))
    d.ellipse((-1, 17, 1, 19), fill=sh(WOOD, 1.1))
    save(im, "sprites/portals/lift.png")


def well(rel, w, hh):
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    top = hh // 2 + 1
    # roof
    rpts = [(0, 7), (w // 2, 0), (w - 1, 7), (w - 3, 8), (2, 8)]
    rm = mask(w, hh, lambda dd: dd.polygon(rpts, fill=FULL))
    roof = blank(w, hh)
    rd = ImageDraw.Draw(roof)
    for y in range(0, 9):
        for x in range(w):
            c = (150, 64, 46)
            f = 1.15 if (y % 3 == 0) else (0.85 if (x + y // 3 * 2) % 4 == 0 else 1.0)
            if x > w // 2:
                f *= 0.82
            rd.point((x, y), fill=sh(c, f))
    clip(roof, rm)
    im.alpha_composite(roof)
    d.line((0, 7, w // 2, 0), fill=sh((150, 64, 46), 1.4))
    # posts
    for x0 in (3, w - 5):
        pm = mask(w, hh, lambda dd, x0=x0: dd.rectangle((x0, 8, x0 + 1, top), fill=FULL))
        lit(im, pm, (110, 76, 44), x0, 14, 1.2, 30)
    # winch with rope and bucket
    d.line((4, 11, w - 5, 11), fill=sh(WOOD, 1.1))
    d.line((4, 12, w - 5, 12), fill=sh(WOOD, 0.7))
    d.line((w - 4, 11, w - 2, 13), fill=sh(IRON, 1.2))
    for y in range(12, top - 1):
        d.point((w // 2, y), fill=sh(ROPE, 1.1 if y % 2 else 0.8))
    by = top - 5
    d.rectangle((w // 2 - 2, by, w // 2 + 2, by + 3), fill=sh(WOOD, 1.0))
    d.line((w // 2 - 2, by, w // 2 + 2, by), fill=sh(IRON, 1.3))
    d.point((w // 2 - 2, by + 1), fill=sh(WOOD, 1.35))
    # stone ring
    rm2 = mask(w, hh, lambda dd: dd.rectangle((1, top, w - 2, hh - 1), fill=FULL))
    ring = textured(w, hh, rm2, lambda t: bricks(t, 1, top, w - 2, hh - 1, (130, 124, 116), 5, 3, w))
    relight(ring, rm2, w * 0.3, top, w * 0.7, hh - top + 4, 0.7)
    im.alpha_composite(ring)
    d.rectangle((0, top - 1, w - 1, top + 1), fill=sh((140, 134, 124), 1.15))
    d.line((0, top - 1, w - 1, top - 1), fill=sh((140, 134, 124), 1.45))
    d.ellipse((3, top - 2, w - 4, top + 1), fill=(24, 30, 44, 255))
    d.point((w // 2 - 3, top - 1), fill=(110, 150, 200, 255))
    moss_on(im, rm2, MOSS, w, 0.3, False)
    grass_tufts(d, 0, w - 1, hh - 1, w, GRASS, 2)
    save(im, rel)


def crypt():
    w, hh = 34, 32
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (128, 126, 134)
    body = mask(w, hh, lambda dd: dd.rectangle((3, 11, w - 4, hh - 3), fill=FULL))
    im.alpha_composite(textured(w, hh, body, lambda t: bricks(t, 3, 11, w - 4, hh - 3, base, 6, 3, 41)))
    relight(im, body, 10, 14, 24, 24, 0.6)
    # pediment
    ped = [(1, 12), (w // 2, 3), (w - 2, 12)]
    pm = mask(w, hh, lambda dd: dd.polygon(ped, fill=FULL))
    lit(im, pm, base, w * 0.3, 6, 16, 10, flat=0.4)
    d.line((1, 12, w // 2, 3), fill=sh(base, 1.45))
    d.rectangle((1, 11, w - 2, 12), fill=sh(base, 0.8))
    d.line((1, 11, w - 2, 11), fill=sh(base, 1.3))
    d.ellipse((w // 2 - 2, 6, w // 2 + 2, 10), fill=sh(base, 0.6))
    d.point((w // 2, 8), fill=(150, 220, 200, 255))
    # cross on the top
    d.line((w // 2, 0, w // 2, 4), fill=sh(base, 1.3))
    d.line((w // 2 - 2, 1, w // 2 + 2, 1), fill=sh(base, 1.3))
    # pillars
    for x0 in (4, w - 8):
        cm = mask(w, hh, lambda dd, x0=x0: dd.rectangle((x0, 13, x0 + 3, hh - 4), fill=FULL))
        lit(im, cm, (150, 148, 156), x0 + 0.5, 20, 2.6, 40)
    moss_on(im, body, MOSS, 44, 0.3)
    # the door: dark wood, iron studs, a ring
    dm = mask(w, hh, lambda dd: (dd.ellipse((11, 13, 22, 22), fill=FULL), dd.rectangle((11, 18, 22, hh - 4), fill=FULL)))
    im.alpha_composite(textured(w, hh, dm, lambda t: planks(t, 11, 13, 22, hh - 4, (70, 48, 36), True, 3, 5)))
    for y in (19, 25):
        d.line((11, y, 22, y), fill=sh(IRON, 1.0))
        for x in (12, 16, 20):
            rivet(d, x, y - 1)
    d.ellipse((17, 21, 19, 23), outline=(200, 170, 80, 255))
    # steps
    d.rectangle((1, hh - 3, w - 2, hh - 1), fill=sh(base, 0.95))
    d.line((1, hh - 3, w - 2, hh - 3), fill=sh(base, 1.35))
    d.line((8, hh - 2, w - 9, hh - 2), fill=sh(base, 0.7))
    for x, ln in ((5, 5), (26, 7)):
        for k in range(ln):
            d.point((x + k % 2, 12 + k), fill=sh(MOSS, 1.0 if k % 2 else 0.8))
    grass_tufts(d, 0, w - 1, hh - 1, 41)
    save(im, "sprites/portals/crypt.png")


def ruin_stairs():
    w, hh = 36, 28
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (150, 142, 128)
    # the pit with stairs going down
    pm = mask(w, hh, lambda dd: dd.rectangle((7, 12, w - 8, hh - 1), fill=FULL))
    dark_hole(im, pm, 12, 27, (70, 60, 56))
    px = im.load()
    for k in range(5):
        y = 13 + k * 3
        for x in range(8 + k, w - 8 - k):
            px[x, y] = sh(base, 1.05 - k * 0.17)
            px[x, y + 1] = sh(base, 0.72 - k * 0.12)
    # broken columns on both sides
    for x0, top in ((1, 2), (w - 7, 7)):
        cm = mask(w, hh, lambda dd, x0=x0, top=top: dd.polygon([(x0, hh - 1), (x0, top + 2), (x0 + 2, top), (x0 + 4, top + 3), (x0 + 6, top + 1), (x0 + 6, hh - 1)], fill=FULL))
        lit(im, cm, base, x0 + 1, top + 6, 4.5, 26)
        for y in range(top + 4, hh - 1, 5):
            d.line((x0, y, x0 + 6, y), fill=sh(base, 0.7))
        d.line((x0 + 2, top + 1, x0 + 1, top + 6), fill=sh(base, 0.6))
    # a fallen lintel
    lm = mask(w, hh, lambda dd: dd.polygon([(5, 10), (w - 6, 13), (w - 6, 16), (5, 13)], fill=FULL))
    im.alpha_composite(textured(w, hh, lm, lambda t: bricks(t, 0, 9, w - 1, 17, base, 7, 2, 77)))
    d.line((5, 10, w - 6, 13), fill=sh(base, 1.4))
    # rubble and ivy
    for x, y in ((9, hh - 2), (w - 10, hh - 1), (14, 11), (24, 13)):
        d.ellipse((x - 1, y - 1, x + 1, y), fill=sh(base, 0.9))
        d.point((x - 1, y - 1), fill=sh(base, 1.3))
    for x0, ln in ((2, 12), (w - 6, 9)):
        for k in range(ln):
            d.point((x0 + (k // 2) % 3, 5 + k + (2 if x0 > 10 else 0)), fill=sh(MOSS, 1.15 if k % 3 else 0.8))
    grass_tufts(d, 0, w - 1, hh - 1, 7)
    save(im, "sprites/portals/ruin_stairs.png")


def sinkhole():
    w, hh = 40, 14
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    rim = mask(w, hh, lambda dd: dd.ellipse((0, 1, w - 1, hh + 10), fill=FULL))
    im.alpha_composite(textured(w, hh, rim, lambda t: stone_rough(t, 0, 0, w - 1, hh - 1, EARTH, 13)))
    hole = mask(w, hh, lambda dd: dd.ellipse((5, 4, w - 6, hh + 8), fill=FULL))
    dark_hole(im, hole, 4, 12, (60, 44, 36))
    # roots hanging into the dark
    for x, ln in ((10, 5), (17, 7), (25, 4), (30, 6)):
        for k in range(ln):
            d.point((x + (k // 2) % 2, 5 + k), fill=sh((130, 96, 62), 0.9 - k * 0.08))
    # the grass edge breaking off, crumbs falling
    for x in range(1, w - 1):
        y = 2 + int(abs(x - w / 2) / (w / 2) * 3)
        d.point((x, y - 1), fill=sh(GRASS, 1.2 if x % 3 else 0.9))
        d.point((x, y), fill=sh(GRASS, 0.8))
    grass_tufts(d, 0, w - 1, 2, 17, GRASS, 2)
    for x, y in ((19, 9), (22, 11), (14, 10)):
        d.point((x, y), fill=sh(EARTH, 1.2))
    save(im, "sprites/portals/sinkhole.png")


# =================================================================== surface
def tent():
    w, hh = 40, 28
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    pts = [(1, 27), (20, 2), (38, 27)]
    m = mask(w, hh, lambda dd: dd.polygon(pts, fill=FULL))
    t = blank(w, hh)
    td = ImageDraw.Draw(t)
    for y in range(hh):
        for x in range(w):
            f = 1.12 if x < 20 else 0.8
            if (x - 20) % 6 == 0:
                f *= 0.82  # seams
            if h(x, y, 5) < 0.05:
                f *= 0.9
            td.point((x, y), fill=sh((150, 76, 54), f))
    clip(t, m)
    im.alpha_composite(t)
    d.line((1, 27, 20, 2), fill=sh((150, 76, 54), 1.45))
    # patches
    d.rectangle((8, 19, 11, 22), fill=sh(CANVAS, 0.95))
    d.point((8, 19), fill=sh(CANVAS, 1.3))
    d.line((26, 14, 28, 16), fill=sh((150, 76, 54), 0.55))
    # the open flap
    d.polygon([(16, 27), (20, 9), (24, 27)], fill=rgba(DARK))
    d.polygon([(20, 9), (24, 27), (27, 27)], fill=sh((150, 76, 54), 1.05))
    d.line((20, 9, 27, 27), fill=sh((150, 76, 54), 1.35))
    d.point((19, 24), fill=(200, 150, 80, 255))  # something glinting inside
    # pole tip, ropes and pegs
    d.line((20, 0, 20, 2), fill=sh(WOOD, 1.2))
    d.point((20, 0), fill=(220, 60, 50, 255))
    for (x0, y0), (x1, y1) in (((6, 20), (0, 27)), ((34, 20), (39, 27))):
        d.line((x0, y0, x1, y1), fill=sh(ROPE, 1.0))
        d.line((x1, y1 - 2, x1, y1), fill=sh(WOOD, 0.9))
    d.line((1, 27, 38, 27), fill=sh((90, 50, 36), 0.9))
    save(im, "sprites/surface/tent.png")


def campfire():
    w, hh = 18, 12
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    # logs crossed, bark and cut ends
    for (x0, y0, x1, y1) in ((2, 11, 15, 7), (2, 7, 15, 11)):
        d.line((x0, y0, x1, y1), fill=sh((96, 62, 36), 1.0), width=2)
        d.line((x0, y0 - 1, x1, y1 - 1), fill=sh((96, 62, 36), 1.3))
        d.point((x1, y1), fill=(190, 150, 100, 255))
        d.point((x0, y0), fill=(190, 150, 100, 255))
    # embers
    for x in (6, 9, 12):
        d.point((x, 10), fill=(255, 120, 40, 255))
    flame(d, 9, 9, 8, 0, 2)
    flame(d, 6, 9, 4, -1, 1)
    flame(d, 12, 9, 5, 1, 1)
    # stone ring
    for x, y in ((0, 10), (3, 11), (14, 11), (17, 10), (8, 11)):
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=sh(STONE, 1.0))
        d.point((x - 1, y - 1), fill=sh(STONE, 1.45))
    g = blank(w, hh)
    glow_dot(g, 9, 5, 7, (255, 170, 70), 0.6)
    save(im, "sprites/surface/campfire.png", glow=g)


def wheel(d, cx, cy, r):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=sh(WOOD, 0.9), width=2)
    d.arc((cx - r, cy - r, cx + r, cy + r), 170, 280, fill=sh(WOOD, 1.4))
    for k in range(4):
        a = k * math.pi / 4 + 0.3
        d.line((cx - math.cos(a) * (r - 1), cy - math.sin(a) * (r - 1), cx + math.cos(a) * (r - 1), cy + math.sin(a) * (r - 1)), fill=sh(WOOD, 0.95))
    d.ellipse((cx - 1, cy - 1, cx + 1, cy + 1), fill=sh(IRON, 1.2))


def cart():
    w, hh = 44, 26
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    # the bed of planks, broken at one corner
    bm = mask(w, hh, lambda dd: dd.polygon([(2, 8), (41, 8), (41, 18), (6, 18), (2, 15)], fill=FULL))
    im.alpha_composite(textured(w, hh, bm, lambda t: planks(t, 2, 8, 41, 18, (150, 106, 62), False, 3, 2)))
    d.line((2, 8, 41, 8), fill=sh((150, 106, 62), 1.4))
    d.line((2, 18, 41, 18), fill=sh((150, 106, 62), 0.55))
    for x in (3, 14, 28, 40):
        d.line((x, 8, x, 18), fill=sh(WOOD, 0.75))
        rivet(d, x, 10)
    # sacks and a crate in the bed
    sm = mask(w, hh, lambda dd: dd.ellipse((8, 1, 19, 10), fill=FULL))
    lit(im, sm, CANVAS, 12, 4, 6, 5)
    d.line((13, 2, 14, 4), fill=sh(CANVAS, 0.7))
    sm2 = mask(w, hh, lambda dd: dd.ellipse((17, 3, 26, 10), fill=FULL))
    lit(im, sm2, sh(CANVAS, 0.9), 20, 5, 5, 4)
    d.rectangle((29, 2, 37, 8), fill=sh(WOOD, 1.1))
    d.line((29, 2, 37, 2), fill=sh(WOOD, 1.4))
    d.line((29, 5, 37, 5), fill=sh(WOOD, 0.7))
    d.line((29, 2, 37, 8), fill=sh(WOOD, 0.8))
    # shaft and wheels
    d.line((41, 16, 43, 20), fill=sh(WOOD, 1.0), width=2)
    wheel(d, 10, 19, 6)
    # the second wheel lies broken on the ground
    d.arc((28, 15, 40, 27), 200, 360, fill=sh(WOOD, 0.9), width=2)
    d.line((30, 24, 38, 22), fill=sh(WOOD, 0.8))
    d.line((34, 23, 34, 19), fill=sh(WOOD, 0.8))
    grass_tufts(d, 0, w - 1, hh - 1, 23)
    save(im, "sprites/surface/cart.png")


def gravestone():
    w, hh = 12, 16
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    m = mask(w, hh, lambda dd: dd.rounded_rectangle((1, 1, 10, 14), radius=4, fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: stone_rough(t, 0, 0, w - 1, hh - 1, (130, 130, 140), 61)))
    relight(im, m, 4, 4, 7, 9, 0.9)
    d.line((5, 4, 5, 10), fill=sh((130, 130, 140), 0.5))
    d.line((3, 6, 7, 6), fill=sh((130, 130, 140), 0.5))
    d.line((6, 4, 6, 10), fill=sh((130, 130, 140), 1.25))
    d.line((8, 2, 9, 5), fill=sh((130, 130, 140), 0.6))  # crack
    moss_on(im, m, MOSS, 62, 0.5)
    d.rectangle((0, 14, 11, 15), fill=sh(EARTH, 0.9))
    grass_tufts(d, 0, 11, 15, 63, GRASS, 2)
    save(im, "sprites/surface/gravestone.png")


def reeds():
    w, hh = 16, 20
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    rnd = random.Random(19)
    for x in range(1, 15, 2):
        top = rnd.randint(3, 9)
        bend = rnd.choice((-1, 0, 1))
        d.line((x, hh - 1, x + bend, top), fill=sh((104, 134, 62), 0.85 + 0.25 * (x % 3 == 0)))
        if x % 4 == 1:
            d.rectangle((x + bend, top - 1, x + bend + 1, top + 3), fill=sh((128, 82, 48), 1.0))
            d.point((x + bend, top - 1), fill=sh((128, 82, 48), 1.4))
            d.point((x + bend + 1, top + 3), fill=sh((128, 82, 48), 0.65))
            d.point((x + bend, top - 2), fill=sh((104, 134, 62), 1.1))
        else:
            d.line((x, hh - 6, x + 2 * (1 if x % 3 else -1), hh - 9), fill=sh((120, 150, 70), 1.1))  # a blade leaf
    for x in range(0, 16, 3):
        d.point((x, hh - 1), fill=(70, 110, 140, 255))
    save(im, "sprites/surface/reeds.png")


def bush(rel, w, hh, berries=None, seed=1):
    im = blank(w, hh)
    blobs = [(5, hh - 5, 5, 4.5), (12, hh - 7 + (1 if berries else 0), 6, 6), (w - 6, hh - 5, 5.5, 4.5), (9, hh - 4, 5, 3.5), (w - 10, hh - 3, 5, 3)]
    leaf_cluster(im, blobs, (74, 128, 62) if not berries else (66, 116, 60), seed, berries)
    save(im, rel)


def ruin_wall():
    w, hh = 40, 34
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (150, 144, 132)
    pts = [(0, 33), (0, 8), (4, 6), (7, 9), (10, 4), (13, 7), (16, 12), (20, 10), (23, 4), (26, 2), (30, 6), (34, 7), (39, 10), (39, 33)]
    m = mask(w, hh, lambda dd: dd.polygon(pts, fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: bricks(t, 0, 0, w - 1, hh - 1, base, 6, 3, 71, rough=0.08)))
    relight(im, m, 14, 10, 30, 30, 0.55)
    # broken top edge lit, a missing block, a window slit
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if a[1] < 30 and b[1] < 30 and a[0] != b[0]:
            d.line((a[0], a[1], b[0], b[1]), fill=sh(base, 1.35))
    d.rectangle((26, 14, 29, 21), fill=rgba(DARK))
    d.line((26, 14, 29, 14), fill=sh(base, 0.5))
    d.rectangle((6, 22, 11, 25), fill=sh(base, 0.4))
    moss_on(im, m, MOSS, 72, 0.7)
    for x0, ln in ((3, 10), (18, 14), (35, 8)):
        for k in range(ln):
            d.point((x0 + (k // 3) % 2, 9 + k), fill=sh(MOSS, 1.15 if k % 2 else 0.8))
    # rubble at the foot
    for x in (2, 9, 31, 37):
        d.ellipse((x - 2, hh - 3, x + 2, hh - 1), fill=sh(base, 0.95))
        d.point((x - 1, hh - 3), fill=sh(base, 1.35))
    grass_tufts(d, 0, w - 1, hh - 1, 73)
    save(im, "sprites/surface/ruin_wall.png")


def ruin_column():
    w, hh = 14, 46
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (162, 156, 144)
    shaft = mask(w, hh, lambda dd: dd.polygon([(3, hh - 4), (3, 9), (10, 7), (10, hh - 4)], fill=FULL))
    lit(im, shaft, base, 4, 20, 4.2, 80, flat=0.1)
    for x in (5, 8):
        d.line((x, 9, x, hh - 5), fill=sh(base, 0.82))
    for y in (18, 31):
        d.line((3, y, 10, y), fill=sh(base, 0.65))
        d.line((3, y + 1, 10, y + 1), fill=sh(base, 1.2))
    d.line((9, 12, 7, 16), fill=sh(base, 0.5))
    # broken capital
    cm = mask(w, hh, lambda dd: dd.polygon([(0, 7), (0, 3), (4, 2), (6, 4), (9, 1), (13, 3), (13, 7)], fill=FULL))
    lit(im, cm, base, 4, 3, 8, 5, flat=0.3)
    d.line((0, 7, 13, 7), fill=sh(base, 0.6))
    # plinth
    pm = mask(w, hh, lambda dd: dd.rectangle((1, hh - 4, 12, hh - 1), fill=FULL))
    lit(im, pm, base, 4, hh - 4, 8, 4, flat=0.3)
    d.line((1, hh - 4, 12, hh - 4), fill=sh(base, 1.35))
    moss_on(im, cm, MOSS, 81, 0.6)
    for k in range(16):
        d.point((9 + (k // 4) % 2, 20 + k), fill=sh(MOSS, 1.1 if k % 2 else 0.8))
    save(im, "sprites/surface/ruin_column.png")


def tower_ruin():
    w, hh = 36, 96
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    base = (146, 140, 128)
    pts = [(2, 95), (3, 14), (6, 10), (9, 12), (12, 6), (15, 9), (18, 14), (22, 8), (26, 2), (29, 5), (33, 10), (33, 95)]
    m = mask(w, hh, lambda dd: dd.polygon(pts, fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: bricks(t, 0, 0, w - 1, hh - 1, base, 7, 4, 91, rough=0.07)))
    relight(im, m, 10, 40, 22, 90, 0.7)
    for i in range(len(pts) - 2):
        a, b = pts[i + 1], pts[i + 2]
        if a[1] < 20 and b[1] < 20:
            d.line((a[0], a[1], b[0], b[1]), fill=sh(base, 1.35))
    # arrow slit window and an arched doorway
    for (x0, y0) in ((15, 30), (19, 56)):
        d.rectangle((x0, y0, x0 + 2, y0 + 9), fill=rgba(DARK))
        d.line((x0 - 1, y0 - 1, x0 + 3, y0 - 1), fill=sh(base, 0.55))
        d.line((x0 - 1, y0 + 10, x0 + 3, y0 + 10), fill=sh(base, 1.3))
    dm = mask(w, hh, lambda dd: (dd.ellipse((11, 76, 22, 86), fill=FULL), dd.rectangle((11, 81, 22, hh - 1), fill=FULL)))
    dark_hole(im, dm, 78, 95, (50, 40, 40))
    for k in range(7):
        a = math.pi + k * math.pi / 6
        d.point((16.5 + math.cos(a) * 6.5, 81 + math.sin(a) * 6), fill=sh(base, 1.3 if k < 3 else 0.7))
    # cracks, a missing patch, banner remnant
    d.line((26, 20, 23, 34), fill=sh(base, 0.5))
    d.line((23, 34, 25, 40), fill=sh(base, 0.5))
    d.rectangle((5, 46, 9, 50), fill=sh(base, 0.45))
    d.line((31, 22, 31, 23), fill=sh(IRON, 1.0))
    d.polygon([(31, 24), (34, 24), (33, 33), (31, 30)], fill=(130, 40, 40, 255))
    d.line((31, 24, 34, 24), fill=(170, 60, 50, 255))
    moss_on(im, m, MOSS, 92, 0.75)
    for x0, y0, ln in ((4, 16, 30), (30, 12, 22), (12, 64, 12)):
        for k in range(ln):
            d.point((x0 + (k // 4) % 3, y0 + k), fill=sh(MOSS, 1.15 if k % 3 else 0.8))
    for x in (1, 6, 28, 34):
        d.ellipse((x - 2, hh - 3, x + 2, hh - 1), fill=sh(base, 0.9))
        d.point((x - 1, hh - 3), fill=sh(base, 1.35))
    grass_tufts(d, 0, w - 1, hh - 1, 93, GRASS, 4)
    save(im, "sprites/surface/tower_ruin.png")


def ore_vein():
    w, hh = 26, 18
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    m = mask(w, hh, lambda dd: dd.polygon([(0, 17), (2, 9), (7, 3), (13, 1), (19, 3), (24, 8), (25, 17)], fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: stone_rough(t, 0, 0, w - 1, hh - 1, (110, 106, 112), 101)))
    relight(im, m, 9, 5, 16, 16, 0.9)
    # ore nuggets: copper/iron glints
    for (x, y) in ((7, 8), (12, 5), (16, 10), (10, 13), (19, 7), (5, 13), (21, 13)):
        d.point((x, y), fill=(214, 134, 62, 255))
        d.point((x + 1, y), fill=(170, 96, 44, 255))
        d.point((x, y + 1), fill=(130, 70, 36, 255))
        d.point((x, y - 1) if y > 1 else (x, y), fill=(255, 210, 140, 255))
    d.line((13, 2, 11, 9), fill=sh((110, 106, 112), 0.55))
    moss_on(im, m, MOSS, 102, 0.3)
    save(im, "sprites/surface/ore_vein.png")


def herb():
    w, hh = 14, 12
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    leaf = (96, 156, 70)
    for (x0, y0, x1, y1) in ((7, 11, 2, 6), (7, 11, 12, 6), (7, 11, 4, 3), (7, 11, 10, 3)):
        d.line((x0, y0, x1, y1), fill=sh(leaf, 0.8))
        d.ellipse((x1 - 1, y1 - 1, x1 + 1, y1 + 1), fill=sh(leaf, 1.0))
        d.point((x1 - 1, y1 - 1), fill=sh(leaf, 1.35))
        d.point((x1 + 1, y1 + 1), fill=sh(leaf, 0.7))
    d.line((7, 11, 7, 3), fill=sh(leaf, 0.9))
    # violet blossoms on top
    for (x, y) in ((7, 1), (4, 3), (10, 2)):
        d.point((x, y), fill=(196, 150, 230, 255))
        d.point((x + 1, y), fill=(150, 104, 200, 255))
        d.point((x, y + 1), fill=(120, 80, 170, 255))
        d.point((x, y - 1) if y > 0 else (x, y), fill=(240, 220, 255, 255))
    d.line((3, 11, 11, 11), fill=sh(EARTH, 0.9))
    g = blank(w, hh)
    glow_dot(g, 7, 2, 3, (200, 160, 255), 0.4)
    save(im, "sprites/surface/herb.png", glow=g)


def dig_mark():
    w, hh = 14, 6
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    m = mask(w, hh, lambda dd: dd.ellipse((0, 1, 13, 7), fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: stone_rough(t, 0, 0, w - 1, hh - 1, (124, 92, 62), 111)))
    # an X scratched into loose earth
    for (a, b) in (((3, 1), (10, 5)), ((10, 1), (3, 5))):
        d.line((a[0], a[1], b[0], b[1]), fill=(170, 40, 30, 255))
    d.point((4, 1), fill=(230, 90, 60, 255))
    d.point((9, 1), fill=(230, 90, 60, 255))
    d.point((1, 2), fill=sh(EARTH, 1.3))
    d.point((12, 3), fill=sh(EARTH, 1.3))
    save(im, "sprites/surface/dig_mark.png", outline=False)


def barrel():
    w, hh = 14, 16
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    m = mask(w, hh, lambda dd: dd.rounded_rectangle((1, 0, 12, 15), radius=4, fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: planks(t, 0, 0, w - 1, hh - 1, (138, 92, 52), True, 3, 121)))
    relight(im, m, 4, 6, 8, 12, 0.9)
    for y in (3, 12):
        d.line((1, y, 12, y), fill=sh(IRON, 1.0))
        d.point((3, y), fill=sh(IRON, 1.7))
    d.line((2, 0, 11, 0), fill=sh((138, 92, 52), 1.3))
    d.point((7, 7), fill=sh(WOOD, 0.5))  # bung
    save(im, "sprites/surface/barrel.png")


def crate():
    w, hh = 16, 16
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    m = mask(w, hh, lambda dd: dd.rectangle((0, 0, 15, 15), fill=FULL))
    im.alpha_composite(textured(w, hh, m, lambda t: planks(t, 0, 0, w - 1, hh - 1, (150, 110, 64), False, 4, 131)))
    relight(im, m, 5, 5, 12, 12, 0.5)
    for (a, b) in (((1, 1), (14, 14)),):
        d.line((a[0], a[1], b[0], b[1]), fill=sh(WOOD, 1.0), width=2)
        d.line((a[0], a[1] - 1, b[0], b[1] - 1), fill=sh(WOOD, 1.35))
    d.rectangle((0, 0, 15, 15), outline=sh(WOOD, 0.9))
    d.line((0, 0, 15, 0), fill=sh(WOOD, 1.4))
    d.line((0, 0, 0, 15), fill=sh(WOOD, 1.2))
    for (x, y) in ((1, 1), (14, 1), (1, 14), (14, 14)):
        rivet(d, x - (1 if x > 7 else 0), y - (1 if y > 7 else 0))
    # a stencilled mark
    d.point((10, 5), fill=sh((60, 40, 24), 1.0))
    d.line((9, 4, 11, 4), fill=sh((60, 40, 24), 1.0))
    save(im, "sprites/surface/crate.png")


# ===================================================================== cage
def world_cage():
    w, hh = 28, 36
    im = blank(w, hh)
    d = ImageDraw.Draw(im)
    bar = (118, 120, 132)
    # straw floor
    for x in range(3, 25, 2):
        d.line((x, 32, x + 1, 31 - (x * 7) % 2), fill=(196, 168, 88, 255))
    # back bars (darker)
    for x in range(5, 24, 4):
        d.line((x, 8, x, 31), fill=sh(bar, 0.6))
    # front bars, lit
    for x in (2, 7, 12, 16, 21, 25):
        d.line((x, 7, x, 31), fill=rgba(bar))
        d.line((x, 10, x, 16), fill=sh(bar, 1.25))
        d.point((x, 9), fill=sh(bar, 1.6))
        d.point((x, 30), fill=sh(bar, 0.6))
    # dome
    d.pieslice((1, 1, 26, 14), 180, 360, fill=sh(IRON, 0.9))
    d.arc((1, 1, 26, 14), 180, 360, fill=sh(IRON, 1.45))
    d.arc((3, 3, 24, 12), 200, 340, fill=sh(IRON, 0.6))
    d.ellipse((12, -1, 15, 2), outline=sh(IRON, 1.3))
    d.rectangle((1, 7, 26, 8), fill=rgba(IRON))
    d.line((1, 7, 26, 7), fill=sh(IRON, 1.45))
    for x in (4, 13, 22):
        rivet(d, x, 8)
    d.line((1, 19, 26, 19), fill=sh(IRON, 1.1))
    # base
    d.rectangle((0, 32, 27, 35), fill=sh(IRON, 0.8))
    d.line((0, 32, 27, 32), fill=sh(IRON, 1.4))
    d.line((0, 35, 27, 35), fill=sh(IRON, 0.5))
    for x in (3, 10, 17, 24):
        rivet(d, x, 33)
    # padlock
    d.rectangle((13, 21, 15, 23), fill=(210, 168, 64, 255))
    d.point((13, 21), fill=(255, 230, 140, 255))
    d.arc((13, 18, 15, 22), 180, 360, fill=(170, 170, 180, 255))
    d.point((14, 22), fill=(60, 40, 20, 255))
    # rust
    for (x, y) in ((7, 13), (21, 25), (2, 22)):
        d.point((x, y), fill=(150, 80, 42, 255))
    save(im, "sprites/world/cage.png")


# ===================================================================== items
def icon_base():
    return blank(16, 16)


def pickaxe():
    im = icon_base()
    d = ImageDraw.Draw(im)
    # handle along the diagonal
    for k in range(11):
        x, y = 2 + k, 14 - k
        d.point((x, y), fill=sh((128, 86, 46), 1.0))
        d.point((x + 1, y), fill=sh((128, 86, 46), 0.65))
        d.point((x, y - 1), fill=sh((128, 86, 46), 1.3))
    d.point((3, 13), fill=sh(LEATHER, 1.2))
    d.point((4, 12), fill=sh(LEATHER, 0.8))
    # curved iron head across the top
    m = mask(16, 16, lambda dd: (dd.arc((3, 1, 17, 14), 200, 290, fill=FULL, width=3)))
    lit(im, m, (150, 154, 168), 8, 3, 6, 4)
    d.point((3, 7), fill=(230, 235, 245, 255))
    d.point((14, 1), fill=(230, 235, 245, 255))
    d.rectangle((10, 3, 12, 5), fill=sh(IRON, 1.0))
    d.point((10, 3), fill=sh(IRON, 1.6))
    save(im, "sprites/items/pickaxe.png")


def shovel():
    im = icon_base()
    d = ImageDraw.Draw(im)
    for k in range(9):
        x, y = 5 + k, 10 - k
        d.point((x, y), fill=sh((128, 86, 46), 1.0))
        d.point((x + 1, y), fill=sh((128, 86, 46), 0.65))
        d.point((x, y - 1), fill=sh((128, 86, 46), 1.3))
    # T grip
    d.line((12, 0, 15, 3), fill=sh((128, 86, 46), 1.2))
    d.point((15, 3), fill=sh((128, 86, 46), 0.7))
    # the blade: a rounded spade at the bottom left
    m = mask(16, 16, lambda dd: dd.polygon([(1, 11), (5, 7), (9, 11), (5, 15), (2, 15)], fill=FULL))
    lit(im, m, (140, 146, 158), 3, 10, 5, 5)
    d.line((5, 7, 9, 11), fill=sh(IRON, 0.9))
    d.point((2, 12), fill=(230, 235, 245, 255))
    d.point((5, 12), fill=sh(IRON, 0.7))
    d.point((4, 13), fill=(110, 80, 50, 255))  # a clod of earth
    save(im, "sprites/items/shovel.png")


def wild_berries():
    im = icon_base()
    d = ImageDraw.Draw(im)
    # leaves
    for (pts, f) in (([(2, 6), (7, 3), (8, 7), (4, 9)], 1.0), ([(9, 2), (14, 4), (11, 8), (8, 6)], 0.85)):
        m = mask(16, 16, lambda dd, pts=pts: dd.polygon(pts, fill=FULL))
        lit(im, m, sh((84, 148, 64), f), 5, 4, 5, 4)
    d.line((3, 8, 7, 4), fill=sh((84, 148, 64), 0.65))
    d.line((8, 3, 9, 6), fill=sh((80, 60, 40), 1.0))
    # a cluster of round berries
    for (cx, cy, r) in ((6, 10, 2.5), (10, 10, 2.5), (8, 13, 2.5), (4, 13, 2), (12, 13, 2)):
        m = mask(16, 16, lambda dd, cx=cx, cy=cy, r=r: dd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=FULL))
        lit(im, m, (176, 36, 66), cx - 0.5, cy - 0.5, r + 0.5, r + 0.5)
        d.point((int(cx - 1), int(cy - 1)), fill=(255, 200, 210, 255))
    save(im, "sprites/items/wild_berries.png")


def scroll(rel, paper, seal, mark):
    im = icon_base()
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.rectangle((3, 3, 12, 12), fill=FULL))
    t = blank(16, 16)
    td = ImageDraw.Draw(t)
    for y in range(16):
        for x in range(16):
            f = 1.08 - (x - 3) * 0.018 - (y - 3) * 0.01
            if h(x, y, 7) < 0.08:
                f *= 0.9
            td.point((x, y), fill=sh(paper, f))
    clip(t, m)
    im.alpha_composite(t)
    # rolled ends
    for y0 in (1, 12):
        rm = mask(16, 16, lambda dd, y0=y0: dd.rounded_rectangle((2, y0, 13, y0 + 2), radius=1, fill=FULL))
        lit(im, rm, sh(paper, 0.95), 5, y0, 8, 2.5)
        d.point((1, y0 + 1), fill=sh(paper, 0.6))
        d.point((14, y0 + 1), fill=sh(paper, 0.6))
    mark(d)
    # wax seal
    sm = mask(16, 16, lambda dd: dd.ellipse((9, 9, 13, 13), fill=FULL))
    lit(im, sm, seal, 10, 10, 2.5, 2.5)
    d.point((10, 10), fill=sh(seal, 1.7))
    save(im, rel)


def blueprint_mark(d):
    c = (60, 90, 160, 255)
    d.rectangle((4, 5, 9, 9), outline=c)
    d.line((5, 5, 7, 4), fill=c)
    d.line((7, 4, 9, 5), fill=c)
    d.line((10, 5, 11, 5), fill=(120, 140, 190, 255))
    d.line((10, 7, 11, 7), fill=(120, 140, 190, 255))
    d.point((6, 7), fill=(200, 80, 60, 255))


def revive_mark(d):
    c = (210, 170, 60, 255)
    d.line((6, 4, 6, 9), fill=c)
    d.line((4, 6, 8, 6), fill=c)
    d.point((6, 4), fill=(255, 240, 170, 255))
    for x in (9, 10):
        d.line((x, 5, x, 7 + (x - 9)), fill=(150, 120, 90, 255))


# ======================================================================= ui
MEDAL = {
    "level": (150, 134, 112), "elite": (190, 70, 60), "boss": (130, 60, 150), "cache": (210, 170, 70),
    "camp": (220, 130, 60), "crypt": (120, 130, 140), "event": (150, 120, 210), "lair": (170, 50, 50),
    "mine": (180, 150, 110), "rescue": (110, 150, 200), "special": (220, 180, 80), "unknown": (130, 120, 104),
}


def medallion(kind):
    im = blank(16, 16)
    base = MEDAL[kind]
    m = mask(16, 16, lambda dd: dd.ellipse((0, 0, 15, 15), fill=FULL))
    lit(im, m, sh(base, 0.8), 6, 6, 8, 8)
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, 15, 15), outline=sh(base, 0.5))
    d.arc((1, 1, 14, 14), 150, 300, fill=sh(base, 1.45))
    d.arc((1, 1, 14, 14), 330, 120, fill=sh(base, 0.6))
    inner = mask(16, 16, lambda dd: dd.ellipse((2, 2, 13, 13), fill=FULL))
    lit(im, inner, sh(base, 0.55), 9, 9, 7, 7)  # dished: lit bottom right
    INK = (30, 22, 20, 255)
    LITE = (250, 240, 210, 255)
    sym = SYMBOLS[kind]
    sym(d, INK, LITE)
    save(im, "ui/map/node_%s.png" % kind)


def s_level(d, ink, lite):
    for a, b in (((4, 4), (11, 11)), ((11, 4), (4, 11))):
        d.line((a[0], a[1], b[0], b[1]), fill=(220, 224, 236, 255))
    d.line((4, 10, 6, 12), fill=(150, 100, 50, 255))
    d.line((11, 10, 9, 12), fill=(150, 100, 50, 255))
    d.point((4, 4), fill=lite)
    d.point((11, 4), fill=lite)


def skull(d, y=0, col=(236, 230, 214, 255)):
    d.ellipse((4, 4 + y, 11, 10 + y), fill=col)
    d.rectangle((5, 9 + y, 10, 11 + y), fill=col)
    d.rectangle((5, 6 + y, 6, 8 + y), fill=(30, 20, 20, 255))
    d.rectangle((9, 6 + y, 10, 8 + y), fill=(30, 20, 20, 255))
    d.point((7, 9 + y), fill=(30, 20, 20, 255))
    d.point((8, 9 + y), fill=(30, 20, 20, 255))
    d.line((6, 11 + y, 9, 11 + y), fill=(120, 110, 100, 255))
    d.point((5, 5 + y), fill=(255, 255, 255, 255))


def s_boss(d, ink, lite):
    skull(d, 1)
    d.polygon([(4, 5), (4, 2), (6, 4), (8, 1), (10, 4), (12, 2), (12, 5)], fill=(255, 210, 60, 255))
    d.point((8, 3), fill=(220, 60, 60, 255))


def s_elite(d, ink, lite):
    skull(d, 1)
    d.line((4, 5, 2, 2), fill=(230, 210, 180, 255))
    d.line((11, 5, 13, 2), fill=(230, 210, 180, 255))
    d.point((6, 7), fill=(255, 90, 60, 255))
    d.point((9, 7), fill=(255, 90, 60, 255))


def s_cache(d, ink, lite):
    d.rectangle((3, 6, 12, 12), fill=(130, 84, 44, 255))
    d.rectangle((3, 4, 12, 7), fill=(150, 100, 54, 255))
    d.line((3, 4, 12, 4), fill=(200, 150, 90, 255))
    d.line((3, 8, 12, 8), fill=(220, 180, 70, 255))
    d.rectangle((7, 7, 8, 9), fill=(255, 220, 90, 255))
    d.line((3, 12, 12, 12), fill=(80, 50, 30, 255))


def s_camp(d, ink, lite):
    d.line((4, 12, 11, 10), fill=(110, 70, 40, 255), width=2)
    d.line((4, 10, 11, 12), fill=(110, 70, 40, 255), width=2)
    flame(d, 7.5, 10, 7, 0, 2)


def s_crypt(d, ink, lite):
    d.rounded_rectangle((4, 3, 11, 12), radius=3, fill=(176, 178, 186, 255))
    d.line((5, 4, 5, 11), fill=(220, 222, 230, 255))
    d.line((10, 5, 10, 12), fill=(110, 112, 120, 255))
    d.line((7, 5, 7, 10), fill=ink)
    d.line((6, 7, 9, 7), fill=ink)
    d.line((3, 12, 12, 12), fill=(90, 120, 60, 255))


def s_event(d, ink, lite):
    c = (255, 240, 200, 255)
    d.arc((5, 3, 10, 8), 180, 90, fill=c, width=2)
    d.line((7, 8, 7, 9), fill=c, width=2)
    d.rectangle((7, 11, 8, 12), fill=c)


def s_lair(d, ink, lite):
    d.ellipse((3, 4, 12, 12), fill=(40, 16, 18, 255))
    for x in (4, 7, 10):
        d.polygon([(x, 5), (x + 2, 5), (x + 1, 8)], fill=(245, 240, 225, 255))
    for x in (5, 8):
        d.polygon([(x, 11), (x + 2, 11), (x + 1, 9)], fill=(220, 214, 200, 255))
    d.point((5, 3), fill=(255, 80, 60, 255))
    d.point((10, 3), fill=(255, 80, 60, 255))


def s_mine(d, ink, lite):
    d.line((4, 12, 11, 5), fill=(150, 100, 56, 255))
    d.line((5, 12, 12, 5), fill=(100, 66, 36, 255))
    d.arc((3, 2, 14, 12), 210, 300, fill=(214, 220, 232, 255), width=2)
    d.point((3, 7), fill=(255, 255, 255, 255))
    d.point((4, 12), fill=(80, 50, 30, 255))


def s_rescue(d, ink, lite):
    d.pieslice((3, 2, 12, 9), 180, 360, fill=(90, 94, 106, 255))
    for x in (4, 6, 9, 11):
        d.line((x, 5, x, 12), fill=(200, 204, 216, 255))
    d.line((3, 12, 12, 12), fill=(120, 124, 136, 255))
    d.rectangle((7, 7, 8, 9), fill=(240, 200, 150, 255))
    d.point((7, 6), fill=(110, 70, 40, 255))


def s_special(d, ink, lite):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        r = 5 if k % 2 == 0 else 2.2
        pts.append((7.5 + math.cos(a) * r, 8 + math.sin(a) * r))
    d.polygon(pts, fill=(255, 236, 140, 255))
    d.polygon(pts[:3] + [(7.5, 8)], fill=(255, 252, 220, 255))
    d.point((7, 8), fill=(220, 160, 40, 255))


def s_unknown(d, ink, lite):
    c = (240, 226, 196, 255)
    d.arc((5, 3, 10, 8), 180, 90, fill=c, width=2)
    d.line((7, 8, 7, 9), fill=c, width=2)
    d.rectangle((7, 11, 8, 12), fill=c)
    d.point((4, 12), fill=(150, 140, 120, 255))
    d.point((11, 4), fill=(150, 140, 120, 255))


SYMBOLS = {"level": s_level, "elite": s_elite, "boss": s_boss, "cache": s_cache, "camp": s_camp, "crypt": s_crypt,
           "event": s_event, "lair": s_lair, "mine": s_mine, "rescue": s_rescue, "special": s_special, "unknown": s_unknown}


def hints():
    # blood: a lit drop
    im = blank(8, 8)
    m = mask(8, 8, lambda dd: (dd.polygon([(3.5, 0), (1, 4), (6, 4)], fill=FULL), dd.ellipse((1, 2, 6, 7), fill=FULL)))
    lit(im, m, (190, 30, 40), 3, 4, 3, 3)
    ImageDraw.Draw(im).point((2, 4), fill=(255, 190, 190, 255))
    save(im, "ui/map/hint_blood.png")
    # danger: a warning triangle
    im = blank(8, 8)
    d = ImageDraw.Draw(im)
    d.polygon([(3.5, 0), (0, 7), (7, 7)], fill=(232, 70, 40, 255))
    d.line((3.5, 0, 0, 7), fill=(255, 150, 100, 255))
    d.line((0, 7, 7, 7), fill=(150, 30, 20, 255))
    d.line((3, 2, 3, 4), fill=(255, 240, 200, 255))
    d.point((3, 6), fill=(255, 240, 200, 255))
    save(im, "ui/map/hint_danger.png")
    # gold: a coin
    im = blank(8, 8)
    m = mask(8, 8, lambda dd: dd.ellipse((0, 0, 7, 7), fill=FULL))
    lit(im, m, (230, 180, 50), 2.5, 2.5, 4.5, 4.5)
    d = ImageDraw.Draw(im)
    d.ellipse((2, 2, 5, 5), outline=(170, 120, 20, 255))
    d.point((2, 1), fill=(255, 250, 200, 255))
    save(im, "ui/map/hint_gold.png")


def hero_marker():
    im = blank(12, 16)
    d = ImageDraw.Draw(im)
    # banner on a pole
    d.line((2, 0, 2, 15), fill=sh(WOOD, 1.0))
    d.line((3, 1, 3, 15), fill=sh(WOOD, 0.65))
    d.point((2, 0), fill=(255, 220, 90, 255))
    d.polygon([(4, 1), (11, 2), (9, 4), (11, 6), (4, 6)], fill=(200, 44, 44, 255))
    d.line((4, 1, 11, 2), fill=(255, 110, 90, 255))
    d.line((4, 6, 11, 6), fill=(120, 20, 24, 255))
    d.point((6, 3), fill=(255, 220, 90, 255))
    # the little hero below
    d.rectangle((6, 8, 9, 10), fill=(230, 190, 150, 255))
    d.point((7, 9), fill=(20, 20, 30, 255))
    d.line((6, 8, 9, 8), fill=(90, 60, 40, 255))
    d.rectangle((5, 11, 10, 14), fill=(60, 90, 170, 255))
    d.line((5, 11, 10, 11), fill=(110, 140, 220, 255))
    d.line((10, 11, 10, 14), fill=(40, 60, 120, 255))
    d.line((6, 15, 9, 15), fill=(60, 40, 30, 255))
    save(im, "ui/map/hero_marker.png")


def res_icons():
    # wood: a log end-on with rings
    im = blank(10, 10)
    d = ImageDraw.Draw(im)
    m = mask(10, 10, lambda dd: dd.rectangle((0, 3, 8, 8), fill=FULL))
    lit(im, m, (126, 84, 46), 3, 4, 6, 4, flat=0.3)
    d.line((0, 5, 7, 5), fill=sh(WOOD, 0.7))
    d.ellipse((6, 3, 9, 8), fill=(206, 164, 104, 255))
    d.ellipse((7, 4, 8, 7), outline=(150, 110, 64, 255))
    save(im, "ui/res/wood.png")
    # stone: a lit chunk
    im = blank(10, 10)
    m = mask(10, 10, lambda dd: dd.polygon([(0, 8), (1, 3), (4, 1), (8, 2), (9, 7), (6, 9)], fill=FULL))
    lit(im, m, (140, 138, 146), 3, 3, 6, 6)
    ImageDraw.Draw(im).line((4, 2, 5, 6), fill=sh(STONE, 0.6))
    save(im, "ui/res/stone.png")
    # iron: an ingot
    im = blank(10, 10)
    d = ImageDraw.Draw(im)
    d.polygon([(0, 8), (2, 4), (9, 4), (9, 8)], fill=sh((150, 156, 170), 0.85))
    d.polygon([(2, 4), (3, 2), (9, 2), (9, 4)], fill=sh((150, 156, 170), 1.3))
    d.line((3, 2, 9, 2), fill=(240, 244, 255, 255))
    d.line((0, 8, 9, 8), fill=sh((150, 156, 170), 0.55))
    d.point((4, 6), fill=sh((150, 156, 170), 1.2))
    save(im, "ui/res/iron.png")
    # herbs: a sprig
    im = blank(10, 10)
    d = ImageDraw.Draw(im)
    d.line((5, 9, 5, 2), fill=(70, 120, 50, 255))
    for (x, y, s) in ((2, 4, -1), (8, 3, 1), (2, 7, -1), (8, 6, 1)):
        d.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(96, 164, 70, 255))
        d.point((x - 1, y - 1), fill=(170, 220, 120, 255))
        d.line((5, y + 1, x - s, y), fill=(80, 136, 56, 255))
    d.point((5, 1), fill=(200, 160, 240, 255))
    save(im, "ui/res/herbs.png")
    # crystal: a faceted shard
    im = blank(10, 10)
    d = ImageDraw.Draw(im)
    d.polygon([(5, 0), (8, 3), (7, 9), (3, 9), (2, 3)], fill=(70, 180, 220, 255))
    d.polygon([(5, 0), (2, 3), (3, 9), (5, 9)], fill=(150, 226, 250, 255))
    d.line((5, 0, 5, 9), fill=(40, 130, 180, 255))
    d.point((4, 2), fill=(255, 255, 255, 255))
    save(im, "ui/res/crystal.png")


def main():
    cave(False)
    cave(True)
    stairs(False)
    stairs(True)
    map_exit()
    arena_exit()
    lift()
    well("sprites/portals/well.png", 26, 30)
    crypt()
    ruin_stairs()
    sinkhole()
    tent()
    campfire()
    cart()
    gravestone()
    well("sprites/surface/well.png", 24, 30)
    reeds()
    bush("sprites/surface/bush.png", 24, 14, None, 5)
    bush("sprites/surface/berry_bush.png", 24, 16, ((190, 30, 70), 7), 9)
    ruin_wall()
    ruin_column()
    tower_ruin()
    ore_vein()
    herb()
    dig_mark()
    barrel()
    crate()
    world_cage()
    pickaxe()
    shovel()
    wild_berries()
    scroll("sprites/items/blueprint_scroll.png", (190, 210, 236), (60, 90, 170), blueprint_mark)
    scroll("sprites/items/revive_scroll.png", (236, 220, 180), (190, 40, 40), revive_mark)
    for k in MEDAL:
        medallion(k)
    hints()
    hero_marker()
    res_icons()
    print("quality art written")


if __name__ == "__main__":
    main()
