#!/usr/bin/env python3
"""Detailed structures and props (pixel art): altars, fountain, prisoner
cage, puzzle barrier / lever / runes, exit portal, chests, wall torch,
merchant and blacksmith, anvil, rug and traps.

Frames are drawn bigger than the old placeholders where the scene allows it
(origins stay at the bottom centre, so nodes and hitboxes do not move);
traps and chests keep their sizes because their hitboxes follow the tiles.
Stone is laid in shaded blocks with mortar, wood in planks with grain,
metal with rivets and highlights; glows are added after the outline.
Called from gen_sheets.py / gen_mechanics.py.  Run:  python3 tools/gen_structures.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp
import gen_sheets as gs
from gen_monsters import blank, lit, mask, rgba, sh, FULL

A = gp.A

STONE = (96, 92, 106)
STONE_WARM = (124, 112, 104)
MARBLE = (150, 160, 182)
IRON = (84, 88, 98)
GOLD = (236, 190, 70)
WOOD = (126, 82, 46)


# ------------------------------------------------------------------ helpers
def finish(im, glow=None, outline=True):
    out = gp.outline(im) if outline else im
    if glow is not None:
        out.alpha_composite(glow)
    return out


def render(lay, fn, rel):
    gs.render_sheet(lay, fn, rel, do_outline=False)


def bricks(im, x0, y0, x1, y1, base, bw=6, bh=3, seed=1, mortar=0.55, rough=0.05):
    """Stone blocks with mortar: lit top/left edges, shaded bottom/right."""
    px = im.load()
    rnd = random.Random(seed)
    tones = {}
    for y in range(y0, y1 + 1):
        ry = (y - y0) // (bh + 1)
        fy = (y - y0) % (bh + 1)
        off = (bw + 1) // 2 if ry % 2 else 0
        for x in range(x0, x1 + 1):
            rx = (x - x0 + off) // (bw + 1)
            fx = (x - x0 + off) % (bw + 1)
            if fy == bh or fx == bw:
                px[x, y] = sh(base, mortar)
                continue
            t = tones.setdefault((rx, ry), 1.0 + rnd.uniform(-0.08, 0.08))
            f = t
            if fy == 0:
                f *= 1.2
            elif fy == bh - 1:
                f *= 0.84
            if fx == 0:
                f *= 1.08
            elif fx == bw - 1:
                f *= 0.9
            if rnd.random() < rough:
                f *= 0.85
            px[x, y] = sh(base, f)


def slab(d, x0, y0, x1, y1, base):
    d.rectangle((x0, y0, x1, y1), fill=sh(base, 1.0))
    d.line((x0, y0, x1, y0), fill=sh(base, 1.35))
    if y1 - y0 >= 2:
        d.line((x0, y0 + 1, x1, y0 + 1), fill=sh(base, 1.14))
    d.line((x0, y1, x1, y1), fill=sh(base, 0.68))
    d.point((x0, y0), fill=sh(base, 1.1))
    d.point((x1, y0), fill=sh(base, 1.1))


CYL = (1.3, 1.16, 1.04, 0.94, 0.84, 0.72, 0.62)


def column(im, x0, y0, x1, y1, base, fluted=False):
    """Vertical cylinder lit from the left."""
    px = im.load()
    w = x1 - x0 + 1
    for x in range(x0, x1 + 1):
        f = CYL[min(len(CYL) - 1, int((x - x0) / max(1, w) * len(CYL)))]
        if fluted and (x - x0) % 2 == 1 and 0 < x - x0 < w - 1:
            f *= 0.88
        for y in range(y0, y1 + 1):
            px[x, y] = sh(base, f)


def planks(im, x0, y0, x1, y1, base, vertical=False, step=3, seed=3):
    px = im.load()
    rnd = random.Random(seed)
    tones = {}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            k = (x - x0) if vertical else (y - y0)
            p, fk = k // step, k % step
            t = tones.setdefault(p, 1.0 + rnd.uniform(-0.07, 0.07))
            f = t
            if fk == step - 1:
                f *= 0.66
            elif fk == 0:
                f *= 1.12
            # grain
            g = (y if vertical else x) + p * 5
            if (g * 7 + p * 3) % 11 == 0:
                f *= 0.85
            px[x, y] = sh(base, f)


def rivet(d, x, y, base=IRON):
    d.point((x, y), fill=sh(base, 1.7))
    d.point((x + 1, y + 1), fill=sh(base, 0.6))


def glow_dot(g, cx, cy, r, col, strength=1.0):
    """Soft round glow, quantised to three alpha steps (pixel-art bloom)."""
    px = g.load()
    w, h = g.size
    for y in range(max(0, int(cy - r - 1)), min(h, int(cy + r + 2))):
        for x in range(max(0, int(cx - r - 1)), min(w, int(cx + r + 2))):
            dd = math.hypot(x - cx, y - cy) / max(r, 0.5)
            if dd >= 1.0:
                continue
            a = (1.0 - dd) ** 1.5 * strength
            a = 0.62 if a > 0.55 else (0.34 if a > 0.25 else (0.14 if a > 0.06 else 0.0))
            if a <= 0:
                continue
            ar, ag, ab, aa = px[x, y]
            na = int(a * 255)
            if na > aa:
                px[x, y] = (col[0], col[1], col[2], na)


def flame(d, cx, by, h, sway=0, w=2, palette=None):
    """Layered flame: red rim, orange body, yellow core, white heart."""
    pal = palette or ((200, 50, 20), (255, 120, 30), (255, 210, 70), (255, 250, 220))
    tip = (cx + sway, by - h)
    d.polygon([(cx - w - 1, by), (cx - w - 1, by - 2), tip, (cx + w + 1, by - 2), (cx + w + 1, by)], fill=rgba(pal[0]))
    d.polygon([(cx - w, by), (cx - w, by - 2), (cx + sway * 0.7, by - h + 1), (cx + w, by - 2), (cx + w, by)], fill=rgba(pal[1]))
    if h > 3:
        d.polygon([(cx - w + 1, by), (cx + sway * 0.4, by - h * 0.6), (cx + w - 1, by)], fill=rgba(pal[2]))
    d.point((cx, by - 1), fill=rgba(pal[3]))


def candle(d, x, by, lit_=True, i=0, h=4):
    d.rectangle((x, by - h + 1, x + 1, by), fill=(232, 222, 196, 255))
    d.point((x, by - h + 1), fill=(255, 250, 235, 255))
    d.point((x + 1, by), fill=(190, 176, 150, 255))
    d.point((x + 1, by - h + 2), fill=(214, 200, 170, 255))  # wax drip
    top = by - h
    if lit_:
        s = [0, 1, 0, -1, 0, 1][i % 6]
        d.point((x + (1 if s > 0 else 0), top - 2), fill=(255, 120, 30, 255))
        d.line((x, top, x + 1, top), fill=(255, 190, 60, 255))
        d.point((x, top - 1), fill=(255, 240, 170, 255))
    else:
        d.point((x, top), fill=(40, 30, 30, 255))


# ------------------------------------------------------------------- altars
def altar_frame(name, i, kind):
    """kind: "blood" (altar of sacrifice) or "fate" (altar of fate)."""
    fw, fh = 28, 30
    im = blank(fw, fh)
    g = blank(fw, fh)
    d = ImageDraw.Draw(im)
    used = name == "used"
    stone = STONE if kind == "blood" else MARBLE
    accent = (230, 40, 60) if kind == "blood" else (110, 190, 255)
    # plinth and step
    bricks(im, 2, 24, 25, 29, sh(stone, 0.85)[:3], bw=5, bh=2, seed=11)
    slab(d, 1, 22, 26, 23, stone)
    # body with side pillars and a carved panel
    bricks(im, 6, 14, 21, 21, stone, bw=4, bh=3, seed=12)
    for x0 in (4, 20):
        column(im, x0, 13, x0 + 3, 21, stone, fluted=True)
        slab(d, x0 - 1, 20, x0 + 4, 21, stone)
    d.rectangle((9, 15, 18, 20), fill=sh(stone, 0.62))
    d.rectangle((10, 16, 17, 20), fill=sh(stone, 0.5))
    d.line((9, 15, 18, 15), fill=sh(stone, 0.45))
    d.line((9, 20, 18, 20), fill=sh(stone, 0.9))
    # top slab
    slab(d, 2, 11, 25, 13, sh(stone, 1.06)[:3])
    d.line((3, 13, 24, 13), fill=sh(stone, 0.6))
    pulse = [0.55, 0.8, 1.0, 0.8, 0.55, 0.4][i % 6] if not used else 0.0
    # rune / sigil on the panel
    rc = rgba(accent) if not used else sh(stone, 0.35)
    if kind == "blood":
        d.line((13, 16, 13, 19), fill=rc)
        d.line((14, 16, 14, 19), fill=rc)
        d.line((11, 17, 16, 17), fill=rc)
        d.point((11, 19), fill=rc)
        d.point((16, 19), fill=rc)
    else:
        d.ellipse((11, 16, 16, 20), outline=rc)
        d.point((13, 18), fill=rc)
        d.point((14, 18), fill=rc)
    if not used:
        glow_dot(g, 13.5, 18, 5, accent, 0.5 + pulse * 0.4)
    # blood drip / mist down the front
    if kind == "blood":
        dc = (150, 20, 30, 255) if not used else (70, 40, 44, 255)
        d.line((7, 14, 7, 16 + (i % 3 if not used else 1)), fill=dc)
        d.point((20, 14), fill=dc)
        d.line((20, 14, 20, 15), fill=dc)
        d.rectangle((10, 11, 17, 11), fill=(120, 16, 26, 255) if not used else sh(stone, 0.55))  # basin edge
        d.line((11, 11, 16, 11), fill=(200, 30, 46, 255) if not used else sh(stone, 0.45))
    # candles on the corners
    candle(d, 3, 10, not used, i, 4)
    candle(d, 23, 10, not used, i + 3, 3)
    if not used:
        glow_dot(g, 3.5, 5, 3, (255, 170, 60), 0.6)
        glow_dot(g, 23.5, 6, 3, (255, 170, 60), 0.6)
    # floating focus above
    bob = [0, -1, -1, 0, 1, 1][i % 6]
    if kind == "blood":
        if not used:
            cy = 5 + bob
            d.polygon([(13, cy - 4), (16, cy), (13, cy + 4), (11, cy)], fill=(170, 20, 40, 255))
            d.polygon([(13, cy - 4), (14, cy - 4), (16, cy), (14, cy)], fill=(255, 90, 100, 255))
            d.line((13, cy - 3, 12, cy), fill=(255, 170, 170, 255))
            d.point((14, cy + 2), fill=(110, 10, 26, 255))
            glow_dot(g, 13.5, cy, 6, accent, 0.45 + pulse * 0.4)
            # drops of light falling to the basin
            d.point((13 + (i % 2), cy + 6 + (i % 3)), fill=(255, 80, 90, 200))
        else:
            d.polygon([(10, 10), (13, 8), (15, 10)], fill=(70, 40, 46, 255))
            d.point((17, 10), fill=(70, 40, 46, 255))
    else:
        if not used:
            # wheel of fate turning
            cx, cy = 13.5, 5.5 + bob * 0.5
            d.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), outline=(200, 220, 255, 255))
            d.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), outline=(90, 120, 190, 255))
            for k in range(4):
                a = i * math.pi / 12 + k * math.pi / 4
                d.line((cx - math.cos(a) * 4, cy - math.sin(a) * 4, cx + math.cos(a) * 4, cy + math.sin(a) * 4), fill=(150, 190, 250, 255))
            d.rectangle((cx - 1, cy - 1, cx, cy), fill=(255, 250, 220, 255))
            gk = i % 6
            a = gk * math.pi / 3
            d.point((cx + math.cos(a) * 5, cy + math.sin(a) * 5), fill=(255, 255, 255, 255))
            glow_dot(g, cx, cy, 8, accent, 0.4 + pulse * 0.35)
        else:
            d.arc((8, 6, 19, 17), 200, 340, fill=(110, 116, 130, 255))
            d.line((10, 10, 17, 10), fill=(100, 104, 118, 255))
    # cracks and moss
    d.line((22, 25, 23, 27), fill=sh(stone, 0.45))
    d.point((5, 28), fill=(70, 110, 60, 255))
    d.point((6, 28), fill=(90, 130, 70, 255))
    if used:
        d.line((15, 12, 17, 15), fill=sh(stone, 0.4))
        d.line((17, 15, 16, 18), fill=sh(stone, 0.4))
    return finish(im, g)


def altars():
    lay = gs.simple_layout("altar_layout", 28, 30, (14, 30), [("idle", 6, 7, True), ("used", 1, 1, False)])
    render(lay, lambda n, i, c: altar_frame(n, i, "blood"), "sprites/events/altar_sheet.png")
    render(lay, lambda n, i, c: altar_frame(n, i, "fate"), "sprites/events/fate_altar_sheet.png")


# ----------------------------------------------------------------- fountain
def fountain():
    fw, fh = 32, 36
    lay = gs.simple_layout("fountain_layout", fw, fh, (16, 36), [("flow", 6, 9, True), ("dry", 1, 1, False)])
    stone = (150, 146, 140)
    water = (80, 160, 235)

    def fn(name, i, n):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        flow = name == "flow"
        # lower basin
        bricks(im, 2, 28, 29, 35, stone, bw=5, bh=2, seed=21)
        slab(d, 0, 26, 31, 27, stone)
        if flow:
            d.rectangle((2, 25, 29, 25), fill=rgba(water))
            for k in range(4):
                x = 3 + (k * 7 + i * 2) % 26
                d.line((x, 25, x + 1, 25), fill=(190, 230, 255, 255))
        else:
            d.line((2, 25, 29, 25), fill=(70, 66, 60, 255))
            d.point((6, 28), fill=(80, 120, 60, 255))
            d.point((24, 29), fill=(80, 120, 60, 255))
            d.line((20, 29, 21, 32), fill=sh(stone, 0.45))
        # carved face on the basin front
        d.rectangle((13, 29, 18, 33), fill=sh(stone, 0.7))
        d.point((14, 30), fill=sh(stone, 0.35))
        d.point((17, 30), fill=sh(stone, 0.35))
        d.line((15, 32, 16, 32), fill=sh(stone, 0.35))
        # pedestal
        column(im, 13, 12, 18, 25, stone, fluted=True)
        slab(d, 11, 22, 20, 23, stone)
        slab(d, 12, 15, 19, 16, stone)
        # upper bowl
        d.pieslice((6, 4, 25, 15), 0, 180, fill=sh(stone, 0.95))
        d.arc((6, 4, 25, 15), 20, 160, fill=sh(stone, 0.7))
        slab(d, 6, 9, 25, 10, stone)
        if flow:
            d.line((8, 9, 23, 9), fill=rgba(water))
        # little statue: a fish spouting water
        d.ellipse((13, 1, 18, 7), fill=sh(stone, 1.0))
        d.point((14, 2), fill=sh(stone, 1.35))
        d.polygon([(15, 7), (13, 9), (18, 9), (16, 7)], fill=sh(stone, 0.85))
        d.point((17, 3), fill=sh(stone, 0.4))
        if flow:
            wa = (110, 180, 245, 220)
            hi = (210, 240, 255, 255)
            # top jet
            d.point((16, 0), fill=hi)
            # sheets of water falling from the bowl rim into the basin
            for side in (-1, 1):
                x0 = 16 + side * 10
                for y in range(10, 25):
                    t = (y - 10) / 15
                    x = x0 + side * int(t * t * 4)
                    d.point((x, y), fill=wa)
                    d.point((x - side, y), fill=(150, 205, 250, 200))
                    if (y + i * 2) % 5 == 0:
                        d.point((x - side * ((y // 2) % 2), y), fill=hi)
                # splash
                sx = 16 + side * 14
                sp = i % 3
                d.point((sx - side * sp, 24 - sp), fill=hi)
                d.point((sx + side, 23 - (2 - sp)), fill=wa)
            for k in range(3):
                y = 11 + ((i * 2 + k * 5) % 13)
                d.point((16 - 11 - (y - 10) // 4, y), fill=hi)
            glow_dot(g, 16, 25, 9, (120, 200, 255), 0.35)
            glow_dot(g, 16, 9, 6, (120, 200, 255), 0.25)
        return finish(im, g)

    render(lay, fn, "sprites/events/fountain_sheet.png")


# --------------------------------------------------------------------- cage
def cage():
    fw, fh = 24, 32
    lay = gs.simple_layout("cage_layout", fw, fh, (12, 32), [("idle", 4, 3, True), ("open", 1, 1, False)])
    bar = (118, 120, 132)

    def prisoner(d, i):
        b = [0, 0, 1, 0][i]
        rag = (128, 112, 92)
        skin = (222, 182, 150)
        # legs sitting / kneeling
        d.rectangle((9, 24, 15, 28), fill=sh(rag, 0.8))
        d.rectangle((8, 27, 10, 28), fill=(80, 60, 44, 255))
        # torso
        d.polygon([(8, 15 + b), (16, 15 + b), (16, 25), (8, 25)], fill=rgba(rag))
        d.line((8, 15 + b, 8, 25), fill=sh(rag, 1.2))
        d.line((16, 16 + b, 16, 25), fill=sh(rag, 0.7))
        d.line((10, 20, 13, 23), fill=sh(rag, 0.65))  # tear
        d.point((14, 18 + b), fill=sh(rag, 0.6))
        # head
        d.rectangle((9, 9 + b, 15, 15 + b), fill=rgba(skin))
        d.line((9, 9 + b, 15, 9 + b), fill=(96, 70, 50, 255))
        d.line((9, 10 + b, 9, 12 + b), fill=(96, 70, 50, 255))
        d.rectangle((10, 13 + b, 14, 15 + b), fill=(120, 96, 76, 255))  # stubble beard
        look = 1 if i == 2 else 0
        d.point((11 + look, 11 + b), fill=(30, 24, 20, 255))
        d.point((14 + look, 11 + b), fill=(30, 24, 20, 255))
        d.point((12 + look, 13 + b), fill=sh(skin, 0.8))
        d.line((15, 10 + b, 15, 14 + b), fill=sh(skin, 0.8))
        # hands clutching the bars
        hy = 17 + (0 if i != 3 else -3)
        d.rectangle((5, 18, 6, 19), fill=rgba(skin))
        d.line((7, 17 + b, 8, 17 + b), fill=rgba(rag))
        d.rectangle((17, hy, 18, hy + 1), fill=rgba(skin))
        d.line((16, hy + 1, 17, hy + 1), fill=rgba(rag))
        # shackle
        d.point((17, hy + 2), fill=(80, 80, 90, 255))

    def bars(im, d, xs, top=6, bottom=28):
        for x in xs:
            d.line((x, top, x, bottom), fill=rgba(bar))
            d.point((x, top + 3), fill=sh(bar, 1.5))
            d.line((x, top + 4, x, top + 9), fill=sh(bar, 1.18))
            d.point((x, bottom - 1), fill=sh(bar, 0.6))

    def fn(name, i, n):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        # straw on the floor
        for x in range(2, 22, 2):
            d.line((x, 29, x + 1, 28 - (x * 7) % 2), fill=(196, 168, 88, 255))
        if name == "idle":
            prisoner(d, i)
            bars(im, d, (2, 6, 10, 14, 18, 21))
        else:
            bars(im, d, (2, 21))
            # the door swung open on its hinge
            for k, x in enumerate((-3, 0)):
                d.line((x + 3, 8 + k, x + 3, 27 - k), fill=sh(bar, 0.8))
            d.line((0, 14, 3, 15), fill=sh(bar, 0.8))
            # broken chain on the floor
            for k in range(4):
                d.ellipse((8 + k * 3, 26 - k % 2, 10 + k * 3, 27 - k % 2), outline=(90, 92, 104, 255))
            d.point((13, 23), fill=(210, 180, 80, 255))  # forgotten coin
        # dome top with a ring
        d.pieslice((1, 1, 22, 12), 180, 360, fill=sh(IRON, 0.9))
        d.arc((1, 1, 22, 12), 180, 360, fill=sh(IRON, 1.4))
        d.arc((3, 3, 20, 10), 200, 340, fill=sh(IRON, 0.65))
        d.ellipse((10, -1, 13, 2), outline=sh(IRON, 1.3))
        d.rectangle((1, 6, 22, 7), fill=rgba(IRON))
        d.line((1, 6, 22, 6), fill=sh(IRON, 1.45))
        for x in (4, 12, 19):
            rivet(d, x, 7)
        # middle band and base
        d.line((1, 16, 22, 16), fill=sh(IRON, 1.1))
        d.rectangle((0, 28, 23, 31), fill=sh(IRON, 0.8))
        d.line((0, 28, 23, 28), fill=sh(IRON, 1.4))
        d.line((0, 31, 23, 31), fill=sh(IRON, 0.5))
        for x in (2, 8, 15, 21):
            rivet(d, x, 29)
        # padlock (open: hanging loose)
        if name == "idle":
            d.rectangle((11, 18, 13, 20), fill=(200, 160, 60, 255))
            d.arc((11, 16, 13, 19), 180, 360, fill=(170, 170, 180, 255))
            d.point((12, 19), fill=(60, 40, 20, 255))
        else:
            d.rectangle((19, 25, 21, 27), fill=(200, 160, 60, 255))
        # rust
        d.point((6, 12), fill=(140, 76, 40, 255))
        d.point((18, 22), fill=(140, 76, 40, 255))
        return finish(im)

    render(lay, fn, "sprites/events/cage_sheet.png")


# ------------------------------------------------- puzzle: barrier / lever
def barrier():
    lay = gs.simple_layout("barrier_layout", 16, 32, (8, 32), [("hum", 6, 9, True)])

    def fn(name, i, n):
        im = blank(16, 32)
        px = im.load()
        ph = i * math.tau / 6
        for y in range(3, 29):
            for x in range(1, 15):
                v = math.sin(y * 0.45 - ph * 1.0) * 0.5 + math.sin((x + y) * 0.7 + ph) * 0.3
                # hexagonal cells
                hx = (x + (y // 4 % 2) * 2) % 4
                edge = hx == 0 or y % 4 == 0
                a = 70 + int(50 * v) + (60 if edge else 0)
                col = (150 + int(40 * v), 100, 255) if edge else (110, 70, 230)
                px[x, y] = (col[0], col[1], col[2], max(30, min(220, a)))
        d = ImageDraw.Draw(im)
        # bright edges and travelling sparks
        for x in (1, 14):
            d.line((x, 3, x, 28), fill=(210, 180, 255, 230))
        for k in range(3):
            y = 3 + (i * 4 + k * 9) % 26
            d.point((1 + (k * 5 + i) % 13, y), fill=(255, 255, 255, 255))
        # emitters top and bottom
        for y0 in (0, 29):
            d.rectangle((0, y0, 15, y0 + 2), fill=sh(STONE, 0.9))
            d.line((0, y0, 15, y0), fill=sh(STONE, 1.35))
            d.line((0, y0 + 2, 15, y0 + 2), fill=sh(STONE, 0.6))
            c = (220, 170, 255, 255) if i % 2 == 0 else (170, 120, 255, 255)
            d.rectangle((6, y0 + 1, 9, y0 + 1), fill=c)
        return im

    render(lay, fn, "sprites/events/barrier_sheet.png")


def lever():
    lay = gs.simple_layout("lever_layout", 12, 16, (6, 16), [("up", 1, 1, False), ("down", 1, 1, False)])

    def fn(name, i, n):
        im = blank(12, 16)
        g = blank(12, 16)
        d = ImageDraw.Draw(im)
        up = name == "up"
        # handle
        tip = (2, 3) if up else (10, 3)
        d.line((6, 12, tip[0], tip[1]), fill=(128, 88, 50, 255), width=2)
        d.line((6, 12, tip[0] + (1 if up else -1), tip[1]), fill=(170, 120, 72, 255))
        kc = (200, 50, 50) if up else (70, 210, 90)
        d.ellipse((tip[0] - 2, tip[1] - 2, tip[0] + 1, tip[1] + 1), fill=rgba(kc))
        d.point((tip[0] - 1, tip[1] - 1), fill=sh(kc, 1.6))
        # stone base with an iron slot
        bricks(im, 1, 12, 10, 15, STONE, bw=4, bh=1, seed=5)
        d.line((1, 12, 10, 12), fill=sh(STONE, 1.35))
        d.rectangle((3, 11, 8, 12), fill=sh(IRON, 0.9))
        d.line((3, 11, 8, 11), fill=sh(IRON, 1.4))
        d.point((6, 11), fill=(30, 26, 30, 255))
        # indicator gem
        d.point((9, 14), fill=rgba(kc))
        glow_dot(g, 9, 14, 2.2, kc, 0.8)
        glow_dot(g, tip[0] - 0.5, tip[1] - 0.5, 3, kc, 0.4)
        return finish(im, g)

    render(lay, fn, "sprites/events/lever_sheet.png")


def runes():
    im = blank(32, 8)
    d = ImageDraw.Draw(im)
    core = (200, 245, 255, 255)
    rim = (60, 150, 230, 255)
    shapes = [
        lambda o, c: (d.line((o + 1, 1, o + 6, 6), fill=c), d.line((o + 6, 1, o + 1, 6), fill=c)),
        lambda o, c: d.ellipse((o + 1, 1, o + 6, 6), outline=c),
        lambda o, c: d.polygon([(o + 3.5, 0.5), (o + 7, 7), (o, 7)], outline=c),
        lambda o, c: d.rectangle((o + 1, 1, o + 6, 6), outline=c),
    ]
    for k, s in enumerate(shapes):
        o = k * 8
        # soft rim one pixel down/right, bright core on top
        tmp = blank(32, 8)
        dd = ImageDraw.Draw(tmp)
        d0 = d
        d = dd
        s(o, rim)
        d = d0
        im.alpha_composite(tmp, (1, 0))
        im.alpha_composite(tmp, (0, 1))
        s(o, core)
    # centre dots
    for o in (8, 24):
        d.point((o + 3, 3), fill=core)
        d.point((o + 4, 4), fill=core)
    im.save(os.path.join(A, "sprites/events/runes.png"))


# --------------------------------------------------------------- exit portal
def portal():
    fw, fh = 28, 32
    lay = gs.simple_layout("portal_layout", fw, fh, (14, 32), [("swirl", 8, 10, True)])

    def fn(name, i, n):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        # vortex inside the arch
        inner = mask(fw, fh, lambda dd: (dd.rectangle((6, 9, 21, 29), fill=FULL), dd.pieslice((6, 3, 21, 18), 180, 360, fill=FULL)))
        px, mp = im.load(), inner.load()
        cx, cy = 13.5, 17.0
        ph = i * math.tau / 8
        for y in range(fh):
            for x in range(fw):
                if mp[x, y][3] == 0:
                    continue
                dx, dy = x - cx, (y - cy) / 1.45
                r = math.hypot(dx, dy)
                a = math.atan2(dy, dx)
                v = math.sin(a * 3 - r * 0.9 + ph * 3 / 3 * 3)
                t = max(0.0, 1.0 - r / 9.0)
                if v > 0.55:
                    col = (150 + int(90 * t), 70 + int(80 * t), 255)
                elif v > -0.1:
                    col = (70 + int(60 * t), 30 + int(30 * t), 150 + int(60 * t))
                else:
                    col = (24, 12, 44)
                if r < 1.6:
                    col = (255, 230, 255)
                px[x, y] = rgba(col)
        # sparks spiralling in
        for k in range(5):
            a = ph + k * math.tau / 5
            r = 8 - (i + k * 3) % 8
            d.point((cx + math.cos(a) * r, cy + math.sin(a) * r * 1.4), fill=(255, 240, 255, 255))
        # stone arch: pillars, voussoirs, keystone
        for x0 in (1, 22):
            bricks(im, x0, 8, x0 + 4, 29, STONE, bw=4, bh=3, seed=31 + x0)
            d.line((x0, 8, x0, 29), fill=sh(STONE, 1.3))
            d.line((x0 + 4, 8, x0 + 4, 29), fill=sh(STONE, 0.6))
        ring = mask(fw, fh, lambda dd: (dd.pieslice((1, -2, 26, 22), 180, 360, fill=FULL), dd.pieslice((6, 3, 21, 18), 180, 360, fill=(0, 0, 0, 0))))
        rp = ring.load()
        for y in range(0, 10):
            for x in range(fw):
                if rp[x, y][3] and mp[x, y][3] == 0:
                    a = math.degrees(math.atan2(y - 10, x - 13.5)) % 360
                    seg = int(a / 22)
                    f = 1.15 if seg % 2 else 0.95
                    if int(a) % 22 == 0:
                        f = 0.55
                    if math.hypot(x - 13.5, (y - 10) * 1.0) > 11.5:
                        f *= 1.2
                    px[x, y] = sh(STONE, f)
        d.rectangle((12, 0, 15, 4), fill=sh(STONE, 1.1))
        d.line((12, 0, 15, 0), fill=sh(STONE, 1.4))
        d.point((13, 2), fill=(220, 160, 255, 255))
        d.point((14, 2), fill=(220, 160, 255, 255))
        glow_dot(g, 13.5, 2, 3, (200, 120, 255), 0.7)
        # glowing runes on the pillars, lit one after another
        for k in range(4):
            y = 12 + k * 4
            on = (i // 2) % 4 == k
            c = (230, 180, 255, 255) if on else (120, 80, 170, 255)
            for x0 in (3, 24):
                d.point((x0, y), fill=c)
                d.point((x0, y + 1), fill=c)
                d.point((x0 - 1 + k % 2 * 2, y), fill=c)
                if on:
                    glow_dot(g, x0, y + 0.5, 3, (190, 120, 255), 0.7)
        # threshold steps
        slab(d, 0, 29, 27, 31, sh(STONE, 0.95)[:3])
        d.line((6, 29, 21, 29), fill=(160, 110, 240, 255))
        glow_dot(g, 13.5, 18, 11, (150, 80, 255), 0.35)
        return finish(im, g)

    render(lay, fn, "sprites/props/portal_sheet.png")
    # Static door (codex / fallback): the first frame.
    sheet = Image.open(os.path.join(A, "sprites/props/portal_sheet.png"))
    sheet.crop((0, 0, fw, fh)).save(os.path.join(A, "sprites/props/exit_door.png"))


# ------------------------------------------------------------------- chests
CHESTS = {
    # body, band, trim (lock / corners), inside
    "wood": ((128, 84, 46), (66, 64, 72), (176, 150, 96), (255, 214, 90)),
    "iron": ((100, 106, 118), (60, 62, 72), (196, 200, 210), (150, 220, 255)),
    "gold": ((112, 40, 124), GOLD, (255, 230, 140), (255, 120, 220)),
    "cursed": ((62, 44, 60), (40, 36, 46), (150, 110, 190), (190, 90, 255)),
}


def chest_frame(tier, name, i):
    body, band, trim, inside = CHESTS[tier]
    im = blank(16, 16)
    g = blank(16, 16)
    d = ImageDraw.Draw(im)
    stage = 0 if name == "closed" else (4 if name == "open" else i)  # 0..4
    # base box y 9..15
    if tier == "iron":
        d.rectangle((1, 9, 14, 15), fill=rgba(body))
        for x in (1, 5, 10, 14):
            d.line((x, 9, x, 15), fill=sh(body, 0.75 if x in (5, 10) else 1.0))
        d.line((1, 10, 14, 10), fill=sh(body, 1.25))
    else:
        planks(im, 1, 9, 14, 15, body, vertical=False, step=3, seed=7 + len(tier))
    d.line((1, 15, 14, 15), fill=sh(body, 0.55))
    # bands and corner plates
    for x in (3, 12):
        d.line((x, 9, x, 15), fill=rgba(band))
        d.point((x, 10), fill=sh(band, 1.5))
    for x in (1, 14):
        d.rectangle((x, 13, x, 15), fill=rgba(trim))
    rivet(d, 3, 13, band)
    rivet(d, 12, 13, band)
    if stage < 2:
        # domed lid, rising a bit while unlatching
        lift = 1 if stage == 1 else 0
        top = 4 - lift
        lidm = mask(16, 16, lambda dd: (dd.pieslice((1, top, 14, top + 8), 180, 360, fill=FULL), dd.rectangle((1, top + 4, 14, 8 - lift), fill=FULL)))
        if tier == "iron":
            lit(im, lidm, body, 6, top + 1, 9, 5)
        else:
            tmp = blank(16, 16)
            planks(tmp, 1, top, 14, 8, sh(body, 1.08)[:3], vertical=True, step=3, seed=9)
            im.paste(tmp, (0, 0), lidm)
        d.arc((1, top, 14, top + 8), 190, 350, fill=sh(body, 1.35))
        for x in (3, 12):
            d.line((x, top + 2, x, 8 - lift), fill=rgba(band))
        d.line((1, 8 - lift, 14, 8 - lift), fill=rgba(band))
        d.line((1, 9, 14, 9), fill=sh(body, 0.45))
        if lift:
            d.line((2, 8, 13, 8), fill=rgba(inside))  # light leaking out
            glow_dot(g, 7.5, 8, 6, inside, 0.6)
        # lock plate
        ly = 8 - lift
        d.rectangle((6, ly - 1, 9, ly + 2), fill=rgba(trim))
        d.point((6, ly - 1), fill=sh(trim, 1.3))
        d.point((7, ly + 1), fill=(30, 20, 20, 255))
        d.point((8, ly + 1), fill=(30, 20, 20, 255) if tier != "gold" else (80, 220, 255, 255))
    else:
        # open: inside of the lid behind, glittering contents
        lid_top = [0, 0, 5, 4, 3][stage]
        d.rectangle((1, lid_top, 14, 8), fill=sh(body, 0.55))
        d.line((1, lid_top, 14, lid_top), fill=sh(body, 0.9))
        for x in (3, 12):
            d.line((x, lid_top, x, 8), fill=sh(band, 0.7))
        d.rectangle((2, 8, 13, 9), fill=(26, 16, 12, 255))
        if stage >= 3:
            heap = rgba(inside)
            d.rectangle((3, 7, 12, 9), fill=heap)
            d.line((4, 6, 11, 6), fill=heap)
            d.point((5, 7), fill=(255, 255, 230, 255))
            d.point((9, 6), fill=(255, 255, 255, 255))
            d.point((11, 8), fill=sh(inside, 0.7))
            glow_dot(g, 7.5, 6, 7, inside, 0.7 if stage == 3 else 0.5)
            if stage == 3:
                d.point((7, 3), fill=(255, 255, 255, 255))
                d.point((11, 4), fill=(255, 250, 200, 255))
        d.line((1, 9, 14, 9), fill=rgba(band))
    if tier == "gold":
        d.point((7, 12), fill=(90, 230, 255, 255))  # gem
        d.point((8, 12), fill=(40, 140, 220, 255))
    if tier == "cursed":
        # chains across the lid and a skull lock
        if stage < 2:
            for k in range(7):
                d.point((1 + k * 2, 6 + k % 2), fill=(150, 150, 164, 255))
            d.rectangle((6, 7, 9, 9), fill=(214, 206, 186, 255))
            d.point((7, 8), fill=(20, 0, 30, 255))
            d.point((8, 8), fill=(20, 0, 30, 255))
        wisp = (i + (2 if name == "closed" else 0)) % 3
        d.point((2 + wisp, 3 - wisp % 2), fill=(200, 120, 255, 200))
        glow_dot(g, 7.5, 11, 6, (170, 80, 255), 0.35)
    return finish(im, g)


def chests():
    lay = gs.simple_layout("chest_layout", 16, 16, (8, 16), [("closed", 1, 1, False), ("opening", 4, 12, False), ("open", 1, 1, False)])
    for tier in CHESTS:
        render(lay, lambda n, i, c, t=tier: chest_frame(t, n, i), f"sprites/props/chest_{tier}_sheet.png")
        if tier != "cursed":
            sheet = Image.open(os.path.join(A, f"sprites/props/chest_{tier}_sheet.png"))
            sheet.crop((0, 2, 16, 16)).save(os.path.join(A, f"sprites/props/chest_{tier}.png"))
            sheet.crop((0, 34, 16, 48)).save(os.path.join(A, f"sprites/props/chest_{tier}_open.png"))


# -------------------------------------------------------------------- torch
def torch():
    lay = gs.simple_layout("torch_layout", 16, 16, (8, 16), [("burn", 6, 10, True)])

    def fn(name, i, n):
        im = blank(16, 16)
        d = ImageDraw.Draw(im)
        # wall bracket
        d.rectangle((6, 12, 9, 13), fill=rgba(IRON))
        d.line((6, 12, 9, 12), fill=sh(IRON, 1.5))
        d.line((7, 14, 8, 15), fill=sh(IRON, 0.8))
        # wooden handle wrapped in cloth
        d.rectangle((7, 9, 8, 15), fill=(110, 72, 40, 255))
        d.line((7, 9, 7, 15), fill=(150, 104, 60, 255))
        d.rectangle((6, 7, 9, 9), fill=(96, 80, 64, 255))
        d.line((6, 8, 9, 8), fill=(70, 56, 46, 255))
        d.point((6, 7), fill=(130, 110, 86, 255))
        h = [6, 7, 6, 8, 7, 6][i]
        sx = [0, 1, 0, -1, 0, 1][i]
        flame(d, 7.5, 7, h, sx, 2)
        # sparks
        d.point((7 + (i * 3) % 4 - 1, 7 - h - 1 - i % 2), fill=(255, 200, 90, 255))
        return finish(im)

    render(lay, fn, "sprites/props/torch_sheet.png")


# ------------------------------------------------------- merchant / smith
def _robe_figure(d, im, i, name, kind):
    fw = 28
    bob = [0, 0, 1, 1][i] if name == "idle" else 0
    if kind == "merchant":
        robe = (78, 66, 124)
        skin = (226, 182, 142)
        # huge backpack with goods
        bp = (128, 86, 48)
        planks(im, 2, 10 + bob, 9, 24 + bob, bp, vertical=True, step=2, seed=41)
        d.rectangle((1, 7 + bob, 8, 10 + bob), fill=(170, 60, 50, 255))  # rolled rug
        d.line((1, 7 + bob, 8, 7 + bob), fill=(220, 110, 80, 255))
        d.point((1, 9 + bob), fill=(230, 190, 80, 255))
        d.rectangle((3, 4 + bob, 5, 6 + bob), fill=(90, 160, 90, 255))  # potion
        d.point((3, 4 + bob), fill=(180, 240, 180, 255))
        d.line((4, 2 + bob, 4, 3 + bob), fill=(160, 120, 80, 255))
        d.rectangle((6, 5 + bob, 7, 6 + bob), fill=(220, 210, 180, 255))  # scroll
        d.line((2, 14 + bob, 9, 14 + bob), fill=(80, 54, 30, 255))  # strap
        d.point((2, 18 + bob), fill=(200, 170, 70, 255))  # pan
        d.ellipse((0, 17 + bob, 3, 21 + bob), outline=(70, 70, 80, 255))
        # robe body
        body = mask(fw, 32, lambda dd: dd.polygon([(9, 13 + bob), (19, 13 + bob), (23, 31), (5, 31)], fill=FULL))
        lit(im, body, robe, 11, 15 + bob, 9, 14, flat=0.2)
        d.line((14, 18 + bob, 14, 31), fill=sh(robe, 0.7))  # fold
        d.line((6, 30, 22, 30), fill=sh(robe, 0.6))
        d.rectangle((9, 21 + bob, 19, 22 + bob), fill=(110, 76, 40, 255))  # belt
        d.point((14, 21 + bob), fill=(230, 190, 80, 255))
        d.rectangle((16, 22 + bob, 18, 25 + bob), fill=(140, 96, 52, 255))  # purse
        d.point((17, 23 + bob), fill=(230, 190, 80, 255))
        # hood and face
        hood = mask(fw, 32, lambda dd: dd.polygon([(9, 14 + bob), (11, 3 + bob), (17, 3 + bob), (20, 14 + bob)], fill=FULL))
        lit(im, hood, sh(robe, 0.85)[:3], 12, 6 + bob, 6, 8)
        d.rectangle((12, 7 + bob, 17, 11 + bob), fill=rgba(skin))
        d.line((12, 7 + bob, 17, 7 + bob), fill=sh(skin, 0.6))  # shadow of the hood
        d.point((16, 9 + bob), fill=(20, 20, 30, 255))
        d.point((14, 9 + bob), fill=(20, 20, 30, 255))
        d.point((17, 10 + bob), fill=sh(skin, 0.8))  # nose
        beard = (214, 214, 220)
        d.polygon([(12, 11 + bob), (18, 11 + bob), (16, 16 + bob), (13, 16 + bob)], fill=rgba(beard))
        d.line((14, 12 + bob, 15, 15 + bob), fill=sh(beard, 0.75))
        # arm with a lantern on a stick
        arm_y = 17 + bob - (i * 3 if name == "greet" else 0)
        d.line((19, 15 + bob, 22, arm_y), fill=sh(robe, 0.95), width=2)
        d.point((22, arm_y), fill=rgba(skin))
        sway = [0, 1, 0, -1][i] if name == "idle" else 0
        lx = 23 + sway
        d.line((22, arm_y, lx, arm_y + 2), fill=(70, 70, 80, 255))
        d.rectangle((lx - 1, arm_y + 2, lx + 2, arm_y + 6), fill=(60, 56, 60, 255))
        d.rectangle((lx, arm_y + 3, lx + 1, arm_y + 5), fill=(255, 214, 100, 255))
        d.point((lx, arm_y + 3), fill=(255, 250, 210, 255))
        return (lx + 0.5, arm_y + 4)
    # ---- dwarf blacksmith with a hammer, facing the anvil on the right
    skin = (214, 156, 118)
    shirt = (92, 100, 118)
    apron = (112, 72, 44)
    beard = (176, 90, 40)
    strike = name == "greet"
    # stout legs and boots
    d.rectangle((9, 26, 12, 31), fill=(70, 60, 64, 255))
    d.rectangle((15, 26, 18, 31), fill=(70, 60, 64, 255))
    d.rectangle((8, 29, 12, 31), fill=(54, 40, 32, 255))
    d.rectangle((15, 29, 19, 31), fill=(54, 40, 32, 255))
    # broad torso
    torso = mask(fw, 32, lambda dd: dd.rounded_rectangle((6, 13 + bob, 21, 27), 3, fill=FULL))
    lit(im, torso, shirt, 10, 16 + bob, 10, 10, flat=0.2)
    # leather apron
    d.rectangle((9, 17 + bob, 18, 28), fill=rgba(apron))
    d.line((9, 17 + bob, 9, 28), fill=sh(apron, 1.3))
    d.line((18, 17 + bob, 18, 28), fill=sh(apron, 0.7))
    d.point((12, 23), fill=sh(apron, 0.6))
    d.point((15, 25), fill=(30, 26, 26, 255))  # scorch
    d.line((6, 21 + bob, 21, 21 + bob), fill=(60, 44, 30, 255))  # belt
    d.point((13, 21 + bob), fill=(200, 190, 170, 255))
    # head: bald with a headband, huge braided beard
    head = mask(fw, 32, lambda dd: dd.ellipse((9, 3 + bob, 18, 12 + bob), fill=FULL))
    lit(im, head, skin, 12, 6 + bob, 5, 5)
    d.line((9, 6 + bob, 18, 6 + bob), fill=(170, 40, 40, 255))
    d.point((9, 7 + bob), fill=(170, 40, 40, 255))
    d.point((15, 8 + bob), fill=(20, 20, 20, 255))
    d.point((17, 8 + bob), fill=(20, 20, 20, 255))
    d.line((14, 7 + bob, 17, 7 + bob), fill=sh(beard, 0.6))  # brows
    d.point((18, 9 + bob), fill=sh(skin, 0.8))  # nose
    bd = mask(fw, 32, lambda dd: dd.polygon([(10, 10 + bob), (19, 10 + bob), (18, 18 + bob), (15, 21 + bob), (12, 18 + bob)], fill=FULL))
    lit(im, bd, beard, 13, 12 + bob, 5, 6)
    d.line((15, 12 + bob, 15, 20 + bob), fill=sh(beard, 0.7))
    d.point((14, 19 + bob), fill=(200, 190, 170, 255))  # braid rings
    d.point((16, 19 + bob), fill=(200, 190, 170, 255))
    # hammer arm: resting / raised / striking
    pose = (0 if not strike else [1, 2, 0][i])
    if pose == 0:
        hx, hy, tx, ty = 21, 22 + bob, 25, 18 + bob
    elif pose == 1:
        hx, hy, tx, ty = 21, 13, 22, 6
    else:
        hx, hy, tx, ty = 22, 16, 27, 14
    d.line((19, 16 + bob, hx, hy), fill=rgba(skin), width=2)
    d.line((hx, hy, tx, ty), fill=(120, 84, 50, 255))
    ang = math.atan2(ty - hy, tx - hx)
    nx, ny = -math.sin(ang), math.cos(ang)
    hp = [(tx + nx * 2, ty + ny * 2), (tx - nx * 2, ty - ny * 2)]
    d.line((hp[0][0], hp[0][1], hp[1][0], hp[1][1]), fill=(150, 154, 166, 255), width=2)
    d.point(hp[1], fill=(210, 214, 226, 255))
    # left arm
    d.line((7, 16 + bob, 6, 22 + bob), fill=rgba(skin), width=2)
    return None


def npcs():
    fw, fh = 28, 32
    lay = gs.simple_layout("merchant_layout", fw, fh, (14, 32), [("idle", 4, 4, True), ("greet", 3, 8, False)])

    def make(kind):
        def fn(name, i, n):
            im = blank(fw, fh)
            d = ImageDraw.Draw(im)
            lamp = _robe_figure(d, im, i, name, kind)
            g = blank(fw, fh)
            if lamp:
                glow_dot(g, lamp[0], lamp[1], 5, (255, 200, 90), 0.6)
            elif name == "greet" and i == 2:
                # sparks from the strike
                for k, (sx, sy) in enumerate(((27, 11), (25, 9), (27, 16))):
                    d.point((sx, sy), fill=(255, 220, 120, 255))
                glow_dot(g, 26, 13, 4, (255, 170, 60), 0.6)
            return finish(im, g)
        return fn

    render(lay, make("merchant"), "sprites/npc/merchant_sheet.png")
    render(lay, make("smith"), "sprites/npc/blacksmith_sheet.png")
    # Shop rug under the merchant.
    rug = blank(44, 6)
    d = ImageDraw.Draw(rug)
    d.rectangle((1, 1, 42, 4), fill=(130, 32, 44, 255))
    d.rectangle((3, 2, 40, 3), fill=(90, 24, 40, 255))
    for x in range(4, 40, 4):
        d.point((x, 2), fill=(230, 190, 80, 255))
        d.point((x + 2, 3), fill=(60, 110, 150, 255))
    d.line((1, 1, 42, 1), fill=(170, 60, 60, 255))
    for x in range(1, 43, 2):
        d.point((x, 5), fill=(220, 200, 150, 255))  # fringe
    d.point((0, 2), fill=(220, 200, 150, 255))
    d.point((43, 3), fill=(220, 200, 150, 255))
    rug.save(os.path.join(A, "sprites/npc/rug.png"))
    # Anvil with a glowing ingot.
    im = blank(20, 12)
    d = ImageDraw.Draw(im)
    body = mask(20, 12, lambda dd: dd.polygon([(0, 2), (3, 1), (17, 1), (19, 2), (16, 4), (13, 5), (13, 8), (16, 11), (4, 11), (7, 8), (7, 5), (3, 4)], fill=FULL))
    lit(im, body, (78, 80, 92), 7, 2, 9, 5, flat=0.3)
    d.line((3, 1, 17, 1), fill=(170, 176, 190, 255))
    d.line((4, 11, 16, 11), fill=(44, 44, 52, 255))
    d.rectangle((9, -1 + 1, 13, 0 + 1), fill=(255, 150, 50, 255))
    d.line((9, 0, 13, 0), fill=(255, 230, 140, 255))
    g = blank(20, 12)
    glow_dot(g, 11, 0.5, 3, (255, 140, 40), 0.7)
    finish(im, g).save(os.path.join(A, "sprites/npc/anvil.png"))


# -------------------------------------------------------------------- traps
def traps():
    lay = gs.simple_layout("spikes_layout", 16, 16, (8, 16), [("hidden", 1, 1, False), ("rise", 3, 20, False), ("up", 1, 1, False), ("retract", 3, 12, False)])

    def spikes(name, i, n):
        im = blank(16, 16)
        d = ImageDraw.Draw(im)
        h = {"hidden": 0, "up": 10}.get(name, [3, 7, 10][i] if name == "rise" else [7, 4, 1][i])
        steel = (196, 198, 210)
        for k, x in enumerate((1, 4, 7, 10, 13)):
            hh = h - (2 if k % 2 else 0) if h > 2 else h
            if hh <= 0:
                continue
            d.polygon([(x, 13), (x + 1, 13 - hh), (x + 2, 13)], fill=rgba(steel))
            d.line((x + 1, 13 - hh, x + 1, 12), fill=sh(steel, 1.25))
            d.line((x + 2, 13, x + 2, 13 - hh // 2), fill=sh(steel, 0.65))
            d.point((x + 1, 13 - hh), fill=(255, 255, 255, 255))
            if k in (1, 3) and hh > 4:
                d.point((x + 1, 14 - hh), fill=(150, 30, 30, 255))  # dried blood
        # metal grate with slots and bolts
        d.rectangle((0, 13, 15, 15), fill=rgba(IRON))
        d.line((0, 13, 15, 13), fill=sh(IRON, 1.5))
        d.line((0, 15, 15, 15), fill=sh(IRON, 0.55))
        for x in (2, 5, 8, 11, 14):
            d.point((x, 14), fill=(20, 18, 22, 255))
        rivet(d, 0, 14)
        rivet(d, 14, 14)
        return finish(im)

    render(lay, spikes, "sprites/traps/spikes_sheet.png")

    lay = gs.simple_layout("acid_layout", 16, 8, (8, 8), [("bubble", 6, 8, True)])

    def acid(name, i, n):
        im = blank(16, 8)
        d = ImageDraw.Draw(im)
        for y in range(3, 8):
            f = 1.0 - (y - 3) * 0.12
            d.line((0, y, 15, y), fill=(int(80 * f), int(200 * f), int(56 * f), 230))
        for x in range(16):
            yy = 3 + (1 if math.sin(x * 0.9 + i) > 0.6 else 0)
            d.point((x, yy - 1 if yy == 3 else 3), fill=(180, 255, 120, 255))
        d.point(((i * 5) % 16, 5), fill=(40, 120, 30, 255))
        for k in range(2):
            x = (k * 8 + i * 2 + 3) % 15
            ph = (i + k * 3) % 6
            if ph < 3:
                d.ellipse((x, 2 - ph, x + 2, 4 - ph), outline=(200, 255, 160, 255))
            elif ph == 3:
                d.point((x, 0), fill=(220, 255, 190, 200))
                d.point((x + 2, 1), fill=(220, 255, 190, 200))
        return im

    render(lay, acid, "sprites/traps/acid_sheet.png")

    lay = gs.simple_layout("plate_layout", 16, 4, (8, 4), [("up", 1, 1, False), ("down", 1, 1, False)])

    def plate(name, i, n):
        im = blank(16, 4)
        d = ImageDraw.Draw(im)
        top = 1 if name == "up" else 2
        stone = (134, 124, 112)
        d.rectangle((2, top, 13, 3), fill=rgba(stone))
        d.line((2, top, 13, top), fill=sh(stone, 1.35))
        d.point((2, top), fill=sh(stone, 1.1))
        d.point((13, 3), fill=sh(stone, 0.6))
        rc = (110, 100, 92, 255) if name == "up" else (220, 90, 60, 255)
        d.point((7, top + 1), fill=rc)
        d.point((8, top + 1), fill=rc)
        d.point((5, top + 1), fill=sh(stone, 0.75))
        d.point((10, top + 1), fill=sh(stone, 0.75))
        return finish(im)

    render(lay, plate, "sprites/traps/plate_sheet.png")

    lay = gs.simple_layout("arrow_trap_layout", 16, 16, (8, 16), [("idle", 1, 1, False), ("fire", 3, 14, False)])

    def arrow_trap(name, i, n):
        im = blank(16, 16)
        g = blank(16, 16)
        d = ImageDraw.Draw(im)
        bricks(im, 0, 0, 15, 15, STONE, bw=7, bh=3, seed=51)
        # carved gargoyle head facing right, the shot comes from its mouth
        face = (118, 112, 124)
        hm = mask(16, 16, lambda dd: dd.polygon([(4, 3), (11, 2), (15, 5), (15, 11), (11, 13), (4, 12)], fill=FULL))
        lit(im, hm, face, 8, 5, 6, 5, flat=0.2)
        d.line((6, 3, 9, 5), fill=sh(face, 0.5))  # brow
        eye = (255, 70, 40, 255) if name == "fire" else (140, 40, 40, 255)
        d.point((10, 5), fill=eye)
        d.point((11, 5), fill=eye)
        d.polygon([(4, 3), (5, 0), (7, 3)], fill=sh(face, 0.9))  # horn
        d.ellipse((11, 7, 15, 11), fill=(16, 12, 16, 255))
        d.line((11, 7, 15, 7), fill=sh(face, 1.3))
        d.point((12, 11), fill=(220, 210, 190, 255))  # fang
        if name == "fire":
            a = [1.0, 0.6, 0.3][i]
            c = (255, 220, 140)
            d.ellipse((12, 8, 14, 10), fill=(255, 230, 160, 255))
            glow_dot(g, 14, 9, 4 + 2 * (1 - a), c, a)
            if i > 0:
                d.point((13 + i, 7 - i), fill=(150, 146, 150, 200))  # smoke
                d.point((14 + i, 6 - i), fill=(120, 116, 120, 160))
        else:
            glow_dot(g, 10.5, 5, 2.2, (255, 60, 30), 0.4)
        return finish(im, g)

    render(lay, arrow_trap, "sprites/traps/arrow_trap_sheet.png")

    rock = blank(14, 14)
    m = mask(14, 14, lambda dd: dd.polygon([(2, 3), (6, 0), (11, 1), (13, 6), (12, 11), (7, 13), (2, 12), (0, 7)], fill=FULL))
    lit(rock, m, (118, 108, 100), 5, 4, 7, 7)
    d = ImageDraw.Draw(rock)
    d.line((5, 5, 8, 8), fill=(70, 62, 58, 255))
    d.line((8, 8, 8, 11), fill=(70, 62, 58, 255))
    d.point((4, 9), fill=(80, 110, 64, 255))
    d.point((10, 3), fill=(160, 150, 140, 255))
    gp.save(rock, "sprites/traps/rock.png")
    crack = blank(16, 4)
    d = ImageDraw.Draw(crack)
    d.line((1, 0, 4, 2), fill=(30, 22, 22, 255))
    d.line((4, 2, 7, 1), fill=(30, 22, 22, 255))
    d.line((7, 1, 10, 3), fill=(30, 22, 22, 255))
    d.line((10, 3, 14, 1), fill=(30, 22, 22, 255))
    d.point((5, 3), fill=(30, 22, 22, 255))
    d.point((12, 0), fill=(30, 22, 22, 255))
    for x in (3, 8, 13):
        d.point((x, 3), fill=(150, 140, 130, 200))  # dust
    crack.save(os.path.join(A, "sprites/traps/ceiling_crack.png"))


def main():
    altars()
    fountain()
    cage()
    barrier()
    lever()
    runes()
    portal()
    chests()
    torch()
    npcs()
    traps()
    print("structures generated")


if __name__ == "__main__":
    main()
