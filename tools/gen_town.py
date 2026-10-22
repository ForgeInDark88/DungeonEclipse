#!/usr/bin/env python3
"""Town before the dungeon (pixel art): tileset, night sky with the eclipse
(parallax), buildings (houses, tavern, shop, smithy, chapel, the dungeon
gate) and street props (lampposts, trees, well, fence, bench, signpost,
flower beds, crates).

Writes assets/sprites/tiles/tiles_town.png, assets/sprites/backgrounds/town_*.png
and assets/sprites/town/*.png. Called from gen_mechanics.py.
Run:  python3 tools/gen_town.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_biomes as gb
import gen_placeholders as gp
from gen_monsters import blank, lit, mask, rgba, sh, FULL
from gen_structures import bricks, column, finish, glow_dot, planks, rivet, slab

A = gp.A
OUT_DIR = "sprites/town/"

TOWN = dict(stone=(120, 112, 104), bedrock=(58, 48, 44), mortar=(70, 62, 56), back=(90, 84, 80),
            top=(86, 150, 64), top_kind="grass", ore=(200, 180, 120), ore_glow=(255, 220, 140),
            wood=(126, 86, 50), sky=(20, 22, 48), far=(40, 40, 70), mid=(30, 30, 52), near=(22, 22, 36),
            accent=(96, 150, 70))

PLASTER = (206, 188, 150)
TIMBER = (86, 56, 36)
ROOF_RED = (150, 62, 50)
ROOF_SLATE = (78, 84, 104)
WINDOW = (255, 206, 110)
STONE = (128, 122, 116)


def save(im, name):
    path = os.path.join(A, OUT_DIR + name + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)


# ----------------------------------------------------------------- pieces
def roof(im, x0, x1, top, base, color, overhang=3, gable=True):
    """Gable roof (triangle) or shed roof, shingles in staggered rows."""
    d = ImageDraw.Draw(im)
    cx = (x0 + x1) / 2
    pts = [(x0 - overhang, base), (cx, top), (x1 + overhang, base)] if gable else \
        [(x0 - overhang, base), (x0 - overhang + 2, top), (x1 + overhang - 2, top), (x1 + overhang, base)]
    m = mask(im.width, im.height, lambda dd: dd.polygon(pts, fill=FULL))
    px, mp = im.load(), m.load()
    for y in range(im.height):
        for x in range(im.width):
            if mp[x, y][3] == 0:
                continue
            row = (y - top) // 3
            fy = (y - top) % 3
            off = 2 if row % 2 else 0
            f = 1.0
            if fy == 2:
                f = 0.7  # shingle edge shadow
            elif (x + off) % 4 == 0:
                f = 0.82
            elif fy == 0:
                f = 1.12
            if gable and x > cx:
                f *= 0.84  # far slope in shade
            if (x * 7 + y * 3) % 23 == 0:
                f *= 0.88
            px[x, y] = sh(color, f)
    if gable:
        d.line((x0 - overhang, base, cx, top), fill=sh(color, 1.35))
        d.line((cx, top, x1 + overhang, base), fill=sh(color, 0.6))
        d.point((cx, top), fill=sh(color, 1.5))
    else:
        d.line((x0 - overhang + 2, top, x1 + overhang - 2, top), fill=sh(color, 1.35))
    d.line((x0 - overhang, base, x1 + overhang, base), fill=sh(color, 0.5))


def plaster_wall(im, x0, y0, x1, y1, color=PLASTER, seed=1):
    px = im.load()
    rnd = random.Random(seed)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            f = 1.0 + rnd.uniform(-0.035, 0.035)
            if (x * 13 + y * 7 + seed) % 29 == 0:
                f *= 0.9
            f *= 1.04 - 0.08 * (y - y0) / max(1, y1 - y0)  # darker toward the ground
            px[x, y] = sh(color, f)
    # a few cracked plaster patches showing bricks
    d = ImageDraw.Draw(im)
    for _ in range(2):
        x, y = rnd.randint(x0 + 2, x1 - 6), rnd.randint(y0 + 2, y1 - 4)
        d.rectangle((x, y, x + 3, y + 1), fill=sh((150, 96, 70), 0.95))
        d.line((x, y + 2, x + 2, y + 2), fill=sh(color, 0.8))


def timber_frame(im, x0, y0, x1, y1, beams=True, color=TIMBER):
    d = ImageDraw.Draw(im)
    for x in (x0, x1):
        d.line((x, y0, x, y1), fill=rgba(color), width=2)
    d.line((x0, y0, x1, y0), fill=rgba(color), width=2)
    if beams:
        mid = (y0 + y1) // 2
        d.line((x0, mid, x1, mid), fill=rgba(color), width=2)
        span = x1 - x0
        k = max(1, span // 18)
        for i in range(1, k):
            x = x0 + span * i // k
            d.line((x, y0, x, y1), fill=rgba(color), width=2)
        # diagonal braces in the upper panels
        d.line((x0 + 1, mid, x0 + 6, y0 + 1), fill=rgba(color))
        d.line((x1 - 1, mid, x1 - 6, y0 + 1), fill=rgba(color))
    # lit edges of the beams
    d.line((x0, y0, x0, y1), fill=sh(color, 1.3))


def window(im, g, x, y, w=8, h=9, lit_=True, shutters=True, arch=False):
    d = ImageDraw.Draw(im)
    frame = (70, 46, 30)
    d.rectangle((x - 1, y - 1, x + w, y + h), fill=rgba(frame))
    inner = WINDOW if lit_ else (40, 46, 70)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            t = (yy - y) / max(1, h - 1)
            f = 1.05 - 0.25 * t
            d.point((xx, yy), fill=sh(inner, f))
    if arch:
        d.arc((x - 1, y - 3, x + w, y + 3), 180, 360, fill=rgba(frame))
    d.line((x + w // 2, y, x + w // 2, y + h - 1), fill=rgba(frame))  # mullions
    d.line((x, y + h // 2, x + w - 1, y + h // 2), fill=rgba(frame))
    if lit_:
        d.point((x + 1, y + 1), fill=(255, 250, 220, 255))
        glow_dot(g, x + w / 2, y + h / 2, w * 0.9, (255, 190, 90), 0.55)
    d.line((x - 1, y + h, x + w, y + h), fill=sh(STONE, 1.2))  # sill
    if shutters:
        for sx in (x - 4, x + w + 1):
            planks(im, sx, y - 1, sx + 2, y + h - 1, (70, 100, 70), vertical=True, step=2, seed=sx)
    # flower box under some windows
    return d


def door(im, x, y_bottom, w=10, h=16, color=(110, 70, 40), arch=True):
    d = ImageDraw.Draw(im)
    y0 = y_bottom - h
    planks(im, x, y0, x + w - 1, y_bottom - 1, color, vertical=True, step=3, seed=x)
    if arch:
        d.pieslice((x, y0 - w // 2, x + w - 1, y0 + w // 2), 180, 360, fill=sh(color, 0.9))
        d.arc((x - 1, y0 - w // 2 - 1, x + w, y0 + w // 2), 180, 360, fill=sh(STONE, 0.9), width=2)
    d.line((x, y0 + 4, x + w - 1, y0 + 4), fill=(60, 60, 70, 255))  # iron bands
    d.line((x, y_bottom - 5, x + w - 1, y_bottom - 5), fill=(60, 60, 70, 255))
    d.point((x + w - 3, y0 + h // 2), fill=(220, 190, 90, 255))  # handle
    d.rectangle((x - 1, y_bottom, x + w, y_bottom + 1), fill=sh(STONE, 1.1))  # step


def foundation(im, x0, x1, y0, y1, seed=3):
    bricks(im, x0, y0, x1, y1, sh(STONE, 0.9)[:3], bw=5, bh=2, seed=seed)
    ImageDraw.Draw(im).line((x0, y0, x1, y0), fill=sh(STONE, 1.3))


def chimney(im, x, top, base, smoke=True):
    bricks(im, x, top, x + 5, base, (140, 80, 64), bw=2, bh=1, seed=x)
    d = ImageDraw.Draw(im)
    d.rectangle((x - 1, top - 1, x + 6, top), fill=(110, 64, 52, 255))
    if smoke:
        for k, (dx, dy) in enumerate(((2, -3), (3, -6), (1, -9), (4, -12))):
            c = 150 - k * 12
            d.ellipse((x + dx - 1, top + dy - 1, x + dx + 1 + k // 2, top + dy + 1), fill=(c, c, c + 10, 170 - k * 35))


def hanging_sign(im, x, y, icon_fn, board=(140, 96, 56)):
    d = ImageDraw.Draw(im)
    d.line((x - 2, y, x + 12, y), fill=(50, 50, 60, 255), width=1)  # iron bracket
    d.line((x - 2, y, x - 2, y + 2), fill=(50, 50, 60, 255))
    d.line((x + 1, y, x + 1, y + 2), fill=(70, 70, 80, 255))
    d.line((x + 10, y, x + 10, y + 2), fill=(70, 70, 80, 255))
    planks(im, x, y + 3, x + 11, y + 12, board, vertical=False, step=3, seed=x)
    d.rectangle((x, y + 3, x + 11, y + 12), outline=sh(board, 0.55))
    icon_fn(d, x + 6, y + 8)


# ----------------------------------------------------------- buildings
def house(name, w, h, wall=PLASTER, roof_c=ROOF_RED, seed=1, floors=1):
    im, g = blank(w, h), blank(w, h)
    roof_h = h * 2 // 5
    wall_top = roof_h - 2
    plaster_wall(im, 4, wall_top, w - 5, h - 6, wall, seed)
    timber_frame(im, 4, wall_top, w - 5, h - 6)
    foundation(im, 3, w - 4, h - 6, h - 1, seed)
    chimney(im, w - 16, 4, roof_h, smoke=seed % 2 == 1)
    roof(im, 4, w - 5, 2, roof_h, roof_c)
    # attic window
    window(im, g, w // 2 - 3, roof_h - 10, 6, 6, lit_=seed % 2 == 0, shutters=False, arch=True)
    door(im, w // 2 - 5 if seed % 2 else 8, h - 6, 10, 15)
    for wx in ((w - 18,) if seed % 2 == 0 else (10, w - 18)):
        if abs(wx - (w // 2 - 5 if seed % 2 else 8)) > 12:
            window(im, g, wx, wall_top + 8, 8, 9, lit_=(wx + seed) % 3 != 0)
    if floors > 1:
        window(im, g, 10, wall_top + 8, 8, 9)
    # flower box
    d = ImageDraw.Draw(im)
    fx = w - 19
    d.rectangle((fx, wall_top + 18, fx + 9, wall_top + 19), fill=(110, 70, 40, 255))
    for k in range(5):
        d.point((fx + 1 + k * 2, wall_top + 17), fill=(230, 80, 90, 255) if k % 2 else (250, 210, 80, 255))
    save(finish(im, g), name)


def tavern():
    w, h = 96, 84
    im, g = blank(w, h), blank(w, h)
    roof_h = 30
    plaster_wall(im, 4, roof_h - 2, w - 5, h - 6, (214, 196, 160), 7)
    timber_frame(im, 4, roof_h - 2, w - 5, h - 6)
    d = ImageDraw.Draw(im)
    mid = (roof_h - 2 + h - 6) // 2
    # balcony on the upper floor
    planks(im, 8, mid - 1, w - 9, mid + 1, (110, 72, 42), step=2, seed=4)
    for x in range(10, w - 9, 4):
        d.line((x, mid - 6, x, mid - 1), fill=(100, 66, 40, 255))
    d.line((8, mid - 6, w - 9, mid - 6), fill=(130, 88, 52, 255))
    foundation(im, 3, w - 4, h - 6, h - 1, 7)
    chimney(im, 14, 6, roof_h)
    chimney(im, w - 22, 4, roof_h)
    roof(im, 4, w - 5, 2, roof_h, (120, 54, 44))
    for x in (12, 30, 58, 76):
        window(im, g, x, roof_h + 4, 8, 8)
    for x in (12, 76):
        window(im, g, x, mid + 6, 8, 10)
    # big double door with a lantern above
    door(im, 40, h - 6, 16, 18)
    d.line((48, h - 24, 48, h - 7), fill=(70, 46, 30, 255))
    d.rectangle((46, h - 30, 50, h - 26), fill=(60, 56, 60, 255))
    d.rectangle((47, h - 29, 49, h - 27), fill=(255, 220, 120, 255))
    glow_dot(g, 48, h - 28, 6, (255, 190, 90), 0.7)
    # sign with a mug of ale

    def mug(dd, cx, cy):
        dd.rectangle((cx - 3, cy - 2, cx + 1, cy + 3), fill=(230, 180, 60, 255))
        dd.rectangle((cx - 3, cy - 3, cx + 1, cy - 2), fill=(250, 250, 240, 255))  # foam
        dd.arc((cx, cy - 1, cx + 3, cy + 2), 270, 90, fill=(230, 180, 60, 255))
    hanging_sign(im, 58, mid + 6, mug)
    # barrels by the door
    for bx in (26, 32):
        bm = mask(w, h, lambda dd, bx=bx: dd.rounded_rectangle((bx, h - 14, bx + 5, h - 6), 2, fill=FULL))
        lit(im, bm, (130, 84, 46), bx + 1, h - 12, 3, 4)
        d = ImageDraw.Draw(im)
        d.line((bx, h - 11, bx + 5, h - 11), fill=(60, 60, 70, 255))
    save(finish(im, g), "tavern")


def shop():
    w, h = 80, 70
    im, g = blank(w, h), blank(w, h)
    roof_h = 26
    plaster_wall(im, 4, roof_h - 2, w - 5, h - 6, (200, 184, 150), 11)
    timber_frame(im, 4, roof_h - 2, w - 5, h - 6)
    foundation(im, 3, w - 4, h - 6, h - 1, 11)
    roof(im, 4, w - 5, 3, roof_h, ROOF_SLATE)
    window(im, g, w // 2 - 3, roof_h - 10, 6, 6, shutters=False, arch=True)
    # big shop window with goods on shelves
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = 10, roof_h + 10, 44, h - 12
    d.rectangle((x0 - 1, y0 - 1, x1 + 1, y1 + 1), fill=(70, 46, 30, 255))
    d.rectangle((x0, y0, x1, y1), fill=(255, 214, 140, 255))
    for k, y in enumerate((y0 + 8, y1 - 1)):
        d.line((x0, y, x1, y), fill=(120, 80, 46, 255))
        for i, x in enumerate(range(x0 + 2, x1 - 2, 5)):
            c = [(200, 40, 50), (60, 120, 230), (80, 200, 90), (230, 190, 70), (170, 90, 220)][(i + k) % 5]
            d.rectangle((x, y - 3, x + 1, y - 1), fill=rgba(c))  # potions
            d.point((x, y - 4), fill=(150, 110, 70, 255))
    d.line((x0 + 17, y0, x0 + 17, y1), fill=(70, 46, 30, 255))
    glow_dot(g, (x0 + x1) / 2, (y0 + y1) / 2, 18, (255, 190, 100), 0.45)
    # striped awning
    ay = y0 - 6
    for x in range(x0 - 3, x1 + 4):
        c = (190, 50, 50) if (x // 4) % 2 else (236, 226, 200)
        for y in range(ay, ay + 4):
            d.point((x, y), fill=sh(c, 1.1 - (y - ay) * 0.08))
        if x % 4 == 1:
            d.point((x, ay + 4), fill=sh(c, 0.8))
    d.line((x0 - 3, ay, x1 + 3, ay), fill=(120, 40, 40, 255))
    door(im, 54, h - 6, 11, 17)

    def coin(dd, cx, cy):
        dd.ellipse((cx - 3, cy - 3, cx + 2, cy + 2), fill=(240, 200, 70, 255))
        dd.ellipse((cx - 1, cy - 1, cx, cy), fill=(180, 140, 30, 255))
    hanging_sign(im, 64, roof_h + 4, coin)
    # crates and a sack in front
    for cx in (46, 48):
        pass
    planks(im, 3, h - 13, 9, h - 7, (150, 110, 64), vertical=True, step=2, seed=2)
    d.rectangle((3, h - 13, 9, h - 7), outline=(90, 60, 36, 255))
    save(finish(im, g), "shop")


def smithy():
    w, h = 84, 66
    im, g = blank(w, h), blank(w, h)
    roof_h = 22
    bricks(im, 4, roof_h - 2, w - 5, h - 6, STONE, bw=6, bh=3, seed=21)
    d = ImageDraw.Draw(im)
    # open forge: dark hall with a glowing hearth
    fx0, fy0, fx1 = 30, roof_h + 6, w - 10
    d.rectangle((fx0, fy0, fx1, h - 6), fill=(36, 26, 24, 255))
    for x in (fx0, fx1):
        column(im, x - 2, fy0 - 2, x + 1, h - 6, (110, 72, 44))
    d = ImageDraw.Draw(im)
    d.line((fx0 - 2, fy0 - 2, fx1 + 1, fy0 - 2), fill=(110, 72, 44, 255), width=2)
    hx = (fx0 + fx1) // 2
    bricks(im, hx - 9, h - 18, hx + 9, h - 7, (120, 70, 56), bw=3, bh=2, seed=5)
    d = ImageDraw.Draw(im)
    d.rectangle((hx - 6, h - 15, hx + 6, h - 10), fill=(255, 120, 30, 255))
    d.rectangle((hx - 4, h - 14, hx + 4, h - 11), fill=(255, 200, 80, 255))
    for k in range(4):
        d.point((hx - 4 + k * 3, h - 16 - k % 2), fill=(255, 240, 160, 255))
    glow_dot(g, hx, h - 12, 16, (255, 130, 40), 0.8)
    # tools on the wall
    for k, tx in enumerate((fx0 + 4, fx0 + 8, fx1 - 6)):
        d.line((tx, fy0 + 4, tx, fy0 + 12), fill=(110, 76, 44, 255))
        d.rectangle((tx - 1, fy0 + 3, tx + 1, fy0 + 5), fill=(150, 154, 166, 255))
    # side room with a window
    window(im, g, 10, roof_h + 8, 8, 9)
    foundation(im, 3, w - 4, h - 6, h - 1, 21)
    chimney(im, 14, 2, roof_h, smoke=True)
    roof(im, 4, w - 5, 6, roof_h, (70, 64, 66), gable=False)
    # sparks out of the chimney
    for sx, sy in ((16, 0), (18, 3), (15, 5)):
        d.point((sx, sy), fill=(255, 190, 80, 255))
    # anvil sign

    def anvil(dd, cx, cy):
        dd.polygon([(cx - 4, cy - 2), (cx + 3, cy - 2), (cx + 4, cy - 1), (cx + 1, cy), (cx + 1, cy + 2), (cx + 3, cy + 3),
                    (cx - 3, cy + 3), (cx - 1, cy + 2), (cx - 1, cy)], fill=(70, 72, 84, 255))
        dd.line((cx - 4, cy - 2, cx + 3, cy - 2), fill=(170, 176, 190, 255))
    hanging_sign(im, 12, roof_h + 20, anvil)
    save(finish(im, g), "smithy")


def chapel():
    w, h = 64, 92
    im, g = blank(w, h), blank(w, h)
    body_top = 44
    bricks(im, 6, body_top, w - 7, h - 6, (150, 146, 150), bw=5, bh=3, seed=31)
    d = ImageDraw.Draw(im)
    # tower with a spire
    bricks(im, 22, 18, w - 23, body_top, (156, 152, 156), bw=4, bh=3, seed=32)
    roof(im, 22, w - 23, 0, 20, ROOF_SLATE, overhang=2)
    d = ImageDraw.Draw(im)
    d.line((w // 2, 0, w // 2, -4), fill=(220, 190, 90, 255))
    # bell
    d.rectangle((w // 2 - 4, 24, w // 2 + 3, 32), fill=(30, 26, 36, 255))
    d.pieslice((w // 2 - 3, 25, w // 2 + 2, 33), 180, 360, fill=(210, 170, 70, 255))
    d.point((w // 2 - 2, 27), fill=(255, 230, 150, 255))
    roof(im, 6, w - 7, body_top - 12, body_top, ROOF_SLATE, overhang=3, gable=True)
    # rose window with the eclipse
    cx, cy = w // 2, body_top + 12
    d = ImageDraw.Draw(im)
    d.ellipse((cx - 8, cy - 8, cx + 7, cy + 7), fill=(60, 50, 70, 255))
    d.ellipse((cx - 7, cy - 7, cx + 6, cy + 6), fill=(120, 80, 200, 255))
    for a in range(0, 360, 45):
        r = math.radians(a)
        d.line((cx - 0.5, cy - 0.5, cx - 0.5 + math.cos(r) * 6, cy - 0.5 + math.sin(r) * 6), fill=(60, 50, 70, 255))
    d.ellipse((cx - 3, cy - 3, cx + 2, cy + 2), fill=(255, 210, 120, 255))
    d.ellipse((cx - 2, cy - 3, cx + 2, cy + 1), fill=(30, 20, 40, 255))  # the moon covering the sun
    glow_dot(g, cx, cy, 10, (170, 110, 255), 0.5)
    # pointed door and side windows
    dx0 = cx - 6
    d.rectangle((dx0, h - 22, dx0 + 11, h - 7), fill=(90, 56, 34, 255))
    d.polygon([(dx0, h - 22), (cx - 0.5, h - 30), (dx0 + 11, h - 22)], fill=(90, 56, 34, 255))
    d.line((cx - 0.5, h - 29, cx - 0.5, h - 7), fill=(60, 36, 22, 255))
    d.point((cx + 2, h - 14), fill=(220, 190, 90, 255))
    for wx in (11, w - 17):
        d.rectangle((wx, body_top + 14, wx + 5, body_top + 26), fill=(60, 50, 70, 255))
        d.polygon([(wx, body_top + 14), (wx + 2.5, body_top + 10), (wx + 5, body_top + 14)], fill=(60, 50, 70, 255))
        d.rectangle((wx + 1, body_top + 13, wx + 4, body_top + 25), fill=(150, 110, 230, 255))
        d.line((wx + 1, body_top + 19, wx + 4, body_top + 19), fill=(60, 50, 70, 255))
        glow_dot(g, wx + 2.5, body_top + 19, 5, (170, 120, 255), 0.4)
    foundation(im, 5, w - 6, h - 6, h - 1, 31)
    save(finish(im, g), "chapel")


def dungeon_gate():
    """A crypt in a rocky hillside: stone arch, raised portcullis, stairs into
    the dark, violet light of the eclipse from below."""
    w, h = 96, 80
    im, g = blank(w, h), blank(w, h)
    # rocky mound
    rm = mask(w, h, lambda dd: dd.polygon([(0, h - 1), (6, 40), (18, 22), (34, 10), (52, 6), (70, 14), (84, 28), (92, 46),
                                           (w - 1, h - 1)], fill=FULL))
    lit(im, rm, (92, 86, 84), 30, 20, 50, 46, flat=0.25)
    d = ImageDraw.Draw(im)
    rnd = random.Random(5)
    for _ in range(40):
        x, y = rnd.randint(4, w - 5), rnd.randint(14, h - 4)
        if rm.getpixel((x, y))[3]:
            d.line((x, y, x + rnd.randint(1, 3), y), fill=(64, 58, 58, 255))
            d.point((x, y - 1), fill=(130, 124, 120, 255))
    # grass and moss on the hill
    for x in range(8, 88, 2):
        y = 6 + int(abs(x - 52) * 0.55) + (2 if x < 34 else 0)
        if rm.getpixel((x, y + 2))[3]:
            d.line((x, y + 1, x, y + 3), fill=(80, 140, 60, 255))
    # the arch: dark opening, voussoirs and a keystone with the eclipse
    ax0, ax1, ay = 30, 66, 30
    d.rectangle((ax0 + 4, ay + 8, ax1 - 4, h - 1), fill=(14, 10, 20, 255))
    d.pieslice((ax0 + 4, ay - 2, ax1 - 4, ay + 18), 180, 360, fill=(14, 10, 20, 255))
    # stairs going down into the dark
    for k in range(5):
        y = h - 2 - k * 3
        x0 = ax0 + 6 + k * 2
        x1 = ax1 - 6 - k * 2
        c = 120 - k * 20
        d.rectangle((x0, y - 1, x1, y), fill=(c, c - 6, c + 6, 255))
        d.line((x0, y - 1, x1, y - 1), fill=(c + 30, c + 24, c + 36, 255))
    glow_dot(g, (ax0 + ax1) / 2, h - 14, 16, (150, 80, 255), 0.55)
    for x0 in (ax0, ax1 - 5):
        bricks(im, x0, ay + 6, x0 + 5, h - 1, (136, 130, 128), bw=4, bh=3, seed=x0)
    ring = mask(w, h, lambda dd: (dd.pieslice((ax0, ay - 8, ax1, ay + 22), 180, 360, fill=FULL),
                                  dd.pieslice((ax0 + 5, ay - 2, ax1 - 5, ay + 18), 180, 360, fill=(0, 0, 0, 0))))
    px, rp = im.load(), ring.load()
    for y in range(h):
        for x in range(w):
            if rp[x, y][3]:
                a = math.degrees(math.atan2(y - (ay + 7), x - (ax0 + ax1) / 2)) % 360
                f = 1.1 if int(a / 20) % 2 else 0.92
                if int(a) % 20 == 0:
                    f = 0.55
                px[x, y] = sh((140, 134, 132), f)
    d = ImageDraw.Draw(im)
    kx = (ax0 + ax1) // 2
    d.rectangle((kx - 4, ay - 10, kx + 3, ay - 2), fill=(150, 144, 140, 255))
    d.line((kx - 4, ay - 10, kx + 3, ay - 10), fill=(190, 184, 180, 255))
    d.ellipse((kx - 3, ay - 9, kx + 2, ay - 4), fill=(255, 210, 120, 255))
    d.ellipse((kx - 2, ay - 9, kx + 2, ay - 5), fill=(40, 20, 60, 255))
    glow_dot(g, kx - 0.5, ay - 6.5, 5, (200, 140, 255), 0.6)
    # raised portcullis teeth
    for x in range(ax0 + 7, ax1 - 6, 4):
        d.line((x, ay + 2, x, ay + 8), fill=(70, 72, 84, 255))
        d.point((x, ay + 9), fill=(110, 112, 124, 255))
    d.line((ax0 + 6, ay + 4, ax1 - 6, ay + 4), fill=(70, 72, 84, 255))
    # skulls and bones by the entrance
    for sx in (ax0 - 6, ax1 + 3):
        d.ellipse((sx, h - 6, sx + 4, h - 2), fill=(220, 214, 196, 255))
        d.point((sx + 1, h - 4), fill=(30, 20, 20, 255))
        d.point((sx + 3, h - 4), fill=(30, 20, 20, 255))
    d.line((ax1 + 8, h - 2, ax1 + 13, h - 3), fill=(220, 214, 196, 255))
    save(finish(im, g), "dungeon_gate")


# --------------------------------------------------------------- props
def props():
    # lamppost: the lantern light is a PointLight2D added by the town code
    w, h = 12, 44
    im, g = blank(w, h), blank(w, h)
    d = ImageDraw.Draw(im)
    column(im, 5, 10, 6, h - 3, (54, 56, 66))
    d = ImageDraw.Draw(im)
    d.rectangle((3, h - 3, 8, h - 1), fill=(60, 62, 72, 255))
    d.line((3, h - 3, 8, h - 3), fill=(110, 112, 124, 255))
    d.line((2, 9, 9, 9), fill=(60, 62, 72, 255))
    d.rectangle((3, 2, 8, 8), fill=(50, 50, 60, 255))
    d.rectangle((4, 3, 7, 7), fill=(255, 214, 120, 255))
    d.point((4, 3), fill=(255, 250, 220, 255))
    d.polygon([(2, 2), (5.5, -1), (9, 2)], fill=(50, 50, 60, 255))
    glow_dot(g, 5.5, 5, 6, (255, 190, 90), 0.75)
    save(finish(im, g), "lamppost")
    # oak tree
    w, h = 52, 68
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    tm = mask(w, h, lambda dd: dd.polygon([(22, h - 1), (24, 34), (21, 26), (27, 30), (31, 24), (29, 36), (31, h - 1)], fill=FULL))
    lit(im, tm, (96, 66, 44), 24, 40, 6, 20, flat=0.3)
    d = ImageDraw.Draw(im)
    d.line((25, 44, 25, h - 3), fill=(70, 46, 30, 255))
    for cx, cy, r, f in ((16, 26, 13, 0.85), (36, 24, 13, 0.8), (26, 15, 15, 1.0), (14, 14, 9, 0.95), (38, 12, 9, 0.9)):
        cm = mask(w, h, lambda dd, cx=cx, cy=cy, r=r: dd.ellipse((cx - r, cy - r * 0.85, cx + r, cy + r * 0.85), fill=FULL))
        lit(im, cm, sh((70, 130, 60), f)[:3], cx - r * 0.3, cy - r * 0.35, r, r * 0.85)
    d = ImageDraw.Draw(im)
    rnd = random.Random(9)
    for _ in range(40):
        x, y = rnd.randint(3, w - 4), rnd.randint(3, 36)
        if im.getpixel((x, y))[3]:
            d.point((x, y), fill=(50, 96, 44, 255) if rnd.random() < 0.6 else (130, 190, 100, 255))
    for x, y in ((12, 22), (34, 18), (22, 30)):
        d.point((x, y), fill=(220, 60, 60, 255))  # apples
    save(gp.outline(im), "tree")
    # well with a little roof and a bucket
    w, h = 32, 40
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    for x in (5, w - 7):
        column(im, x, 8, x + 2, h - 10, (110, 72, 44))
    roof(im, 5, w - 6, 0, 10, ROOF_RED, overhang=3)
    d = ImageDraw.Draw(im)
    d.line((7, 13, w - 8, 13), fill=(110, 72, 44, 255))
    d.line((w // 2, 13, w // 2, 20), fill=(180, 160, 120, 255))
    d.rectangle((w // 2 - 2, 20, w // 2 + 1, 23), fill=(120, 84, 50, 255))
    bricks(im, 2, h - 12, w - 3, h - 1, STONE, bw=4, bh=2, seed=8)
    d = ImageDraw.Draw(im)
    d.rectangle((2, h - 13, w - 3, h - 12), fill=sh(STONE, 1.25))
    save(gp.outline(im), "well")
    # fence piece
    im = blank(32, 14)
    d = ImageDraw.Draw(im)
    for x in (1, 9, 17, 25):
        planks(im, x, 1, x + 4, 13, (150, 110, 70), vertical=True, step=2, seed=x)
        d.polygon([(x, 1), (x + 2, -1), (x + 4, 1)], fill=(150, 110, 70, 255))
    d.line((0, 5, 31, 5), fill=(120, 84, 50, 255), width=2)
    d.line((0, 10, 31, 10), fill=(120, 84, 50, 255), width=2)
    save(gp.outline(im), "fence")
    # bench
    im = blank(26, 12)
    planks(im, 0, 3, 25, 5, (140, 96, 56), step=2, seed=3)
    planks(im, 1, 0, 24, 1, (140, 96, 56), step=2, seed=4)
    d = ImageDraw.Draw(im)
    for x in (3, 21):
        d.line((x, 6, x, 11), fill=(90, 60, 36, 255), width=2)
    save(gp.outline(im), "bench")
    # signpost pointing to the dungeon (skull + arrow)
    im = blank(24, 30)
    d = ImageDraw.Draw(im)
    column(im, 11, 4, 12, 29, (110, 74, 44))
    planks(im, 2, 6, 21, 13, (160, 116, 70), step=3, seed=6)
    d = ImageDraw.Draw(im)
    d.polygon([(21, 6), (24, 9.5), (21, 13)], fill=(160, 116, 70, 255))
    d.ellipse((5, 7, 9, 11), fill=(230, 226, 210, 255))
    d.point((6, 9), fill=(30, 20, 20, 255))
    d.point((8, 9), fill=(30, 20, 20, 255))
    d.line((12, 9, 19, 9), fill=(60, 36, 22, 255))
    d.line((17, 7, 19, 9), fill=(60, 36, 22, 255))
    d.line((17, 11, 19, 9), fill=(60, 36, 22, 255))
    save(gp.outline(im), "signpost")
    # flower bed
    im = blank(32, 10)
    d = ImageDraw.Draw(im)
    bricks(im, 0, 6, 31, 9, STONE, bw=4, bh=1, seed=2)
    rnd = random.Random(4)
    for x in range(1, 31, 2):
        hgt = rnd.randint(2, 5)
        d.line((x, 6, x, 6 - hgt), fill=(70, 130, 60, 255))
        d.point((x, 5 - hgt), fill=rnd.choice([(230, 80, 90, 255), (250, 210, 80, 255), (170, 120, 240, 255), (250, 250, 250, 255)]))
    save(gp.outline(im), "flowers")
    # crates stack
    im = blank(20, 18)
    for (x, y, s) in ((0, 8, 10), (10, 8, 10), (5, 0, 9)):
        planks(im, x, y, x + s - 1, y + s - 1, (160, 118, 70), vertical=True, step=3, seed=x + y)
        d = ImageDraw.Draw(im)
        d.rectangle((x, y, x + s - 1, y + s - 1), outline=(100, 70, 40, 255))
        d.line((x, y, x + s - 1, y + s - 1), fill=(110, 78, 46, 255))
    save(gp.outline(im), "crates")


# ------------------------------------------------------------- parallax
def parallax():
    w, h = 320, 180
    # far: night sky, stars, the eclipse, distant mountains
    im = gb._gradient(w, h, (16, 16, 44), (70, 50, 90))
    d = ImageDraw.Draw(im)
    rnd = random.Random(11)
    for _ in range(120):
        x, y = rnd.randint(0, w - 1), rnd.randint(0, 110)
        c = rnd.choice([(255, 255, 255), (200, 210, 255), (255, 230, 200)])
        d.point((x, y), fill=c + (rnd.randint(110, 255),))
    for _ in range(6):
        x, y = rnd.randint(2, w - 3), rnd.randint(4, 90)
        d.point((x, y), fill=(255, 255, 255, 255))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            d.point((x + dx, y + dy), fill=(200, 210, 255, 150))
    ex, ey, r = 240, 42, 11
    # corona: smooth warm halo fading into the sky, a few long streamers
    px = im.load()
    for y in range(max(0, ey - 40), min(h, ey + 40)):
        for x in range(max(0, ex - 40), min(w, ex + 40)):
            dd = math.hypot(x - ex, y - ey)
            if dd <= r:
                continue
            ang = math.atan2(y - ey, x - ex)
            streak = 0.5 + 0.5 * math.cos(ang * 5 + 0.7) ** 8
            a = max(0.0, 1.0 - (dd - r) / (26 * streak + 6)) ** 2
            if a <= 0.02:
                continue
            c = px[x, y]
            col = (255, 214, 160) if dd < r + 3 else (230, 150, 120)
            px[x, y] = tuple(int(c[i] + (col[i] - c[i]) * a * 0.85) for i in range(3)) + (255,)
    d = ImageDraw.Draw(im)
    d.ellipse((ex - r - 1, ey - r - 1, ex + r + 1, ey + r + 1), fill=(255, 244, 214, 255))  # the sun's rim
    d.ellipse((ex - r + 1, ey - r, ex + r + 1, ey + r), fill=(18, 12, 30, 255))  # the moon covers the sun
    d.point((ex - r, ey - 3), fill=(255, 255, 255, 255))  # diamond ring
    d.point((ex - r - 1, ey - 3), fill=(255, 250, 230, 255))
    mtn = [(0, h)]
    for x in range(0, w + 1, 8):
        y = 118 + int(14 * math.sin(x * 0.02) + 9 * math.sin(x * 0.053 + 1.3))
        mtn.append((x, y))
    mtn.append((w, h))
    d.polygon(mtn, fill=(46, 40, 70, 255))
    for x, y in mtn[1:-1:3]:
        d.line((x, y, x + 3, y + 2), fill=(90, 80, 120, 255))  # snowy ridge light
    im.save(os.path.join(A, "sprites/backgrounds/town_far.png"))
    # mid: castle and rooftops with lit windows
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    base = (34, 30, 52, 255)
    d.rectangle((0, 140, w, h), fill=base)
    x = 0
    rnd = random.Random(21)
    while x < w:
        bw = rnd.randint(16, 30)
        top = rnd.randint(118, 134)
        d.rectangle((x, top, x + bw, 150), fill=base)
        d.polygon([(x - 2, top), (x + bw / 2, top - rnd.randint(8, 14)), (x + bw + 2, top)], fill=base)
        for _ in range(rnd.randint(1, 3)):
            wx, wy = rnd.randint(x + 3, x + bw - 4), rnd.randint(top + 3, 142)
            d.rectangle((wx, wy, wx + 1, wy + 2), fill=(255, 200, 110, 255))
        x += bw + rnd.randint(2, 8)
    # castle on a hill
    d.polygon([(150, 140), (170, 108), (210, 104), (230, 140)], fill=base)
    for tx, th in ((168, 86), (186, 78), (204, 90)):
        d.rectangle((tx, th, tx + 9, 112), fill=base)
        d.polygon([(tx - 2, th), (tx + 4.5, th - 12), (tx + 11, th)], fill=base)
        d.rectangle((tx + 4, th + 6, tx + 5, th + 9), fill=(255, 200, 110, 255))
    im.save(os.path.join(A, "sprites/backgrounds/town_mid.png"))
    # near: tree silhouettes and fireflies
    im = blank(w, h)
    d = ImageDraw.Draw(im)
    for tx in (20, 110, 196, 290):
        d.rectangle((tx - 2, 130, tx + 2, h), fill=(18, 20, 30, 230))
        for k in range(3):
            d.ellipse((tx - 16 + k * 6, 96 + k * 8 - 6, tx + 4 + k * 6, 124 + k * 6), fill=(18, 20, 30, 230))
    for _ in range(14):
        x, y = rnd.randint(0, w - 1), rnd.randint(70, 170)
        d.point((x, y), fill=(220, 255, 140, 230))
    im.save(os.path.join(A, "sprites/backgrounds/town_near.png"))


def main():
    os.makedirs(os.path.join(A, OUT_DIR), exist_ok=True)
    gb.tileset("town", TOWN)
    parallax()
    house("house_a", 60, 64, seed=2)
    house("house_b", 54, 58, wall=(196, 184, 160), roof_c=ROOF_SLATE, seed=3)
    house("house_c", 64, 66, wall=(214, 190, 150), roof_c=(130, 80, 50), seed=5)
    tavern()
    shop()
    smithy()
    chapel()
    dungeon_gate()
    props()
    print("town generated")


if __name__ == "__main__":
    main()
