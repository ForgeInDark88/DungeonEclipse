#!/usr/bin/env python3
"""Detailed 48x48 hero portraits: a race face layer and a class overlay
(headgear, collar, shoulders) drawn over it (UIStyle.portrait stacks them).

Shading: light from the top left, three tones per material (pixel-art bands).
Writes assets/sprites/portraits/race_*.png and class_*.png.
Run:  python3 tools/gen_portraits.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

import gen_placeholders as gp

S = 48
CX = 23.5
OUT_DIR = "sprites/portraits/"


def c4(rgb, a=255):
    return (rgb[0], rgb[1], rgb[2], a)


def tone(c, f):
    return gp.shade(c4(c) if len(c) == 3 else c, f)


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def shade_region(im, mask, base, cx, cy, rx, ry, levels=(1.18, 1.0, 0.82, 0.66)):
    """Paints the opaque pixels of `mask` with `base` in bands lit from the top left."""
    px = im.load()
    m = mask.load()
    for y in range(S):
        for x in range(S):
            if m[x, y][3] == 0:
                continue
            nx = (x - cx) / max(rx, 1)
            ny = (y - cy) / max(ry, 1)
            light = -0.55 * nx - 0.65 * ny + 0.25 * (1 - min(1.0, nx * nx + ny * ny))
            i = 0 if light > 0.45 else 1 if light > -0.05 else 2 if light > -0.55 else 3
            px[x, y] = tone(base, levels[i])


def shape(draw_fn):
    m = new()
    draw_fn(ImageDraw.Draw(m))
    return m


def put(im, layer):
    im.alpha_composite(layer)


def dither_line(d, pts, c):
    d.line(pts, fill=c)


# --------------------------------------------------------------------- faces
def face(skin, hair, style, eyes=(70, 110, 160), beard=None, ears="round", tusks=False, tunic=(95, 75, 55),
         brow=None, scar=False):
    im = new()
    # Shoulders and tunic (class overlays draw armour over them).
    torso = shape(lambda d: d.polygon([(3, 47), (6, 40), (16, 36), (31, 36), (41, 40), (44, 47)], fill=(255,) * 4))
    shade_region(im, torso, tunic, 18, 38, 22, 10)
    d = ImageDraw.Draw(im)
    d.line((18, 36, 23, 41, 29, 36), fill=tone(tunic, 0.55))  # collar
    # Neck.
    neck = shape(lambda dd: dd.rectangle((18, 29, 29, 38), fill=(255,) * 4))
    shade_region(im, neck, tone(skin, 0.86), 21, 32, 6, 6)
    d.line((19, 37, 28, 37), fill=tone(skin, 0.6))
    # Long hair behind the head.
    if style in ("long", "braids"):
        back = shape(lambda dd: dd.polygon([(11, 14), (36, 14), (38, 34), (34, 40), (13, 40), (9, 34)], fill=(255,) * 4))
        shade_region(im, back, tone(hair, 0.8), 18, 20, 14, 16)
    # Ears.
    if ears == "long":
        for sx in (-1, 1):
            base_x = CX + sx * 10.5
            ear = shape(lambda dd, sx=sx, bx=base_x: dd.polygon(
                [(bx, 17), (bx + sx * 9, 10), (bx + sx * 7, 15), (bx + sx * 2, 26)], fill=(255,) * 4))
            shade_region(im, ear, skin, base_x + sx * 4, 16, 6, 8)
            d.line((base_x + sx * 2, 19, base_x + sx * 6, 15), fill=tone(skin, 0.7))
    else:
        big = 1 if ears == "big" else 0
        for sx in (-1, 1):
            ex = CX + sx * 10.5
            ear = shape(lambda dd, ex=ex: dd.ellipse((ex - 2 - big, 17 - big, ex + 2 + big, 25 + big), fill=(255,) * 4))
            shade_region(im, ear, skin, ex, 20, 3, 4)
            d.point((ex + sx * 0.0, 21), fill=tone(skin, 0.65))
    # Head.
    head = shape(lambda dd: dd.ellipse((13, 7, 34, 34), fill=(255,) * 4))
    jaw = shape(lambda dd: dd.polygon([(14, 24), (33, 24), (30, 32), (24, 35), (17, 32)], fill=(255,) * 4))
    head.alpha_composite(jaw)
    shade_region(im, head, skin, 20, 15, 12, 15)
    d = ImageDraw.Draw(im)
    # Cheeks / blush and chin shadow.
    d.point((17, 26), fill=tone(skin, 0.92)[:3] + (255,))
    d.line((19, 33, 28, 33), fill=tone(skin, 0.78))
    # Eyes: white, iris, pupil, highlight, upper lid, brow.
    brow_c = brow or tone(hair, 0.8)
    for ex in (18, 28):
        d.rectangle((ex - 2, 19, ex + 2, 21), fill=(240, 236, 228, 255))
        d.rectangle((ex - 1, 19, ex + 1, 21), fill=c4(eyes))
        d.point((ex, 20), fill=(20, 15, 20, 255))
        d.point((ex - 1, 19), fill=(255, 255, 255, 255))
        d.line((ex - 3, 18, ex + 2, 18), fill=tone(skin, 0.55))
        d.line((ex - 2, 22, ex + 2, 22), fill=tone(skin, 0.8))
    d.line((15, 16, 20, 15), fill=c4(brow_c), width=1)
    d.line((15, 15, 19, 15), fill=c4(brow_c))
    d.line((27, 15, 32, 16), fill=c4(brow_c), width=1)
    d.line((28, 15, 32, 15), fill=c4(brow_c))
    # Nose: shadow side, tip highlight, nostrils.
    d.line((24, 20, 24, 25), fill=tone(skin, 0.75))
    d.point((23, 24), fill=tone(skin, 1.15))
    d.point((22, 26), fill=tone(skin, 0.6))
    d.point((25, 26), fill=tone(skin, 0.6))
    d.line((23, 26, 24, 26), fill=tone(skin, 0.82))
    # Mouth.
    d.line((21, 29, 26, 29), fill=tone(skin, 0.5))
    d.line((22, 30, 25, 30), fill=tone(skin, 1.08))
    if scar:
        d.line((29, 14, 31, 24), fill=tone(skin, 0.68))
    if tusks:
        for tx in (20, 27):
            d.polygon([(tx, 30), (tx + 1, 30), (tx + 1, 26), (tx, 27)], fill=(240, 235, 210, 255))
            d.point((tx + 1, 26), fill=(255, 255, 245, 255))
    # Hair on top.
    if style != "bald":
        top = shape(lambda dd: dd.chord((12, 5, 35, 24), 180, 360, fill=(255,) * 4))
        if style == "mohawk":
            top = shape(lambda dd: dd.polygon([(20, 2), (27, 2), (28, 12), (19, 12)], fill=(255,) * 4))
        shade_region(im, top, hair, 19, 8, 12, 8)
        d = ImageDraw.Draw(im)
        if style != "mohawk":
            # Fringe and strands.
            for x0 in range(14, 34, 3):
                d.line((x0, 12, x0 + 1, 15), fill=c4(hair))
                d.line((x0 + 1, 7, x0 + 2, 11), fill=tone(hair, 1.25))
        else:
            for y0 in range(3, 12, 2):
                d.point((22, y0), fill=tone(hair, 1.3))
        if style in ("long", "braids"):
            for sx, x0 in ((-1, 12), (1, 33)):
                d.line((x0, 15, x0 - sx, 34), fill=tone(hair, 0.7))
                d.line((x0 + sx, 15, x0, 30), fill=tone(hair, 1.15))
            if style == "braids":
                for bx in (12, 34):
                    for by in range(26, 41, 3):
                        d.ellipse((bx - 2, by, bx + 1, by + 2), fill=c4(hair), outline=tone(hair, 0.6))
    # Beard (dwarf): mustache, braided beard with clasps.
    if beard:
        bmask = shape(lambda dd: dd.polygon([(13, 23), (34, 23), (34, 31), (29, 40), (24, 46), (18, 40), (13, 31)],
                                            fill=(255,) * 4))
        hole = shape(lambda dd: dd.ellipse((20, 27, 27, 32), fill=(255,) * 4))
        bm = bmask.load()
        hm = hole.load()
        for y in range(S):
            for x in range(S):
                if hm[x, y][3]:
                    bm[x, y] = (0, 0, 0, 0)
        shade_region(im, bmask, beard, 20, 28, 11, 12)
        d = ImageDraw.Draw(im)
        for x0 in range(15, 33, 2):
            d.line((x0, 31, x0 + (1 if x0 < 24 else -1), 38), fill=tone(beard, 0.72))
        d.polygon([(17, 26), (23, 25), (24, 27), (30, 25), (31, 27), (24, 29), (16, 28)], fill=tone(beard, 1.1))
        d.line((21, 30, 26, 30), fill=tone(skin, 0.45))
        for by in (40, 43):
            d.rectangle((22, by, 25, by + 1), fill=(220, 180, 70, 255))
    return gp.outline(im)


# ----------------------------------------------------------------- overlays
def pauldrons(im, metal, trim=None, rivets=True):
    for sx in (-1, 1):
        cx = CX + sx * 15
        p = shape(lambda dd, cx=cx: dd.ellipse((cx - 10, 35, cx + 10, 52), fill=(255,) * 4))
        shade_region(im, p, metal, cx - 3, 38, 10, 8)
        d = ImageDraw.Draw(im)
        d.arc((cx - 10, 35, cx + 10, 52), 180, 360, fill=c4(trim) if trim else tone(metal, 1.3))
        d.arc((cx - 7, 39, cx + 7, 52), 190, 350, fill=tone(metal, 0.7))
        if rivets:
            for rx in (-5, 0, 5):
                d.point((cx + rx, 38 + abs(rx) // 3), fill=tone(metal, 1.45))


def warrior():
    im = new()
    metal = (120, 110, 100)
    pauldrons(im, metal)
    d = ImageDraw.Draw(im)
    # Leather straps across the chest.
    d.line((14, 40, 33, 47), fill=(90, 60, 35, 255), width=2)
    d.rectangle((22, 42, 25, 44), fill=(200, 170, 80, 255))
    # Miner's helmet: dome, brim, ridge, rivets, lamp.
    dome = shape(lambda dd: dd.chord((11, 1, 36, 26), 180, 360, fill=(255,) * 4))
    shade_region(im, dome, metal, 18, 6, 13, 10)
    d = ImageDraw.Draw(im)
    brim = shape(lambda dd: dd.rectangle((9, 12, 38, 15), fill=(255,) * 4))
    shade_region(im, brim, tone(metal, 0.85)[:3], 18, 12, 15, 3)
    d = ImageDraw.Draw(im)
    d.line((10, 15, 37, 15), fill=tone(metal, 0.55))
    d.line((23, 2, 23, 12), fill=tone(metal, 1.4))
    d.line((24, 2, 24, 12), fill=tone(metal, 0.75))
    for rx in (13, 18, 29, 34):
        d.point((rx, 13), fill=tone(metal, 1.5))
    d.rectangle((20, 4, 27, 10), fill=(70, 60, 50, 255))
    d.ellipse((21, 5, 26, 9), fill=(255, 235, 150, 255))
    d.point((22, 6), fill=(255, 255, 255, 255))
    # Lamp glow.
    glow = new()
    gd = ImageDraw.Draw(glow)
    gd.ellipse((17, 1, 30, 13), fill=(255, 230, 140, 50))
    im = Image.alpha_composite(glow, im)
    return gp.outline(im)


def paladin():
    im = new()
    steel = (215, 215, 225)
    gold = (225, 180, 60)
    # Tabard with a sun cross.
    tab = shape(lambda dd: dd.polygon([(17, 37), (30, 37), (31, 47), (16, 47)], fill=(255,) * 4))
    shade_region(im, tab, (235, 230, 215), 20, 40, 8, 6)
    d = ImageDraw.Draw(im)
    d.rectangle((23, 39, 24, 47), fill=c4(gold))
    d.rectangle((20, 42, 27, 43), fill=c4(gold))
    pauldrons(im, steel, trim=gold, rivets=False)
    # Open great helm: dome, gold band, cheek guards, crest plume.
    plume = shape(lambda dd: dd.polygon([(22, 0), (26, 0), (31, -2), (33, 3), (27, 6), (21, 6)], fill=(255,) * 4))
    shade_region(im, plume, (190, 40, 45), 24, 1, 6, 3)
    dome = shape(lambda dd: dd.chord((11, 3, 36, 28), 180, 360, fill=(255,) * 4))
    shade_region(im, dome, steel, 18, 7, 13, 10)
    for sx in (-1, 1):
        cheek = shape(lambda dd, sx=sx: dd.polygon(
            [(CX + sx * 12, 14), (CX + sx * 9, 14), (CX + sx * 9, 26), (CX + sx * 12, 30)], fill=(255,) * 4))
        shade_region(im, cheek, steel, CX + sx * 10, 18, 3, 8)
    d = ImageDraw.Draw(im)
    d.rectangle((11, 13, 36, 15), fill=c4(gold))
    d.line((11, 13, 36, 13), fill=tone(gold, 1.3))
    d.line((23, 4, 23, 13), fill=c4(gold))
    d.line((24, 4, 24, 13), fill=tone(gold, 0.7))
    for rx in (14, 33):
        d.point((rx, 14), fill=(255, 250, 220, 255))
    return gp.outline(im)


def rogue():
    im = new()
    cloth = (55, 80, 55)
    # Cloak over the shoulders with a clasp.
    cloak = shape(lambda dd: dd.polygon([(2, 47), (5, 38), (15, 33), (32, 33), (42, 38), (45, 47)], fill=(255,) * 4))
    shade_region(im, cloak, cloth, 16, 36, 22, 10)
    d = ImageDraw.Draw(im)
    for x0 in (9, 15, 32, 38):
        d.line((x0, 40, x0 + 1, 47), fill=tone(cloth, 0.65))
    d.ellipse((21, 38, 26, 43), fill=(190, 190, 200, 255), outline=(90, 90, 100, 255))
    d.point((22, 39), fill=(255, 255, 255, 255))
    # Hood: outer shell with a dark opening around the face.
    hood = shape(lambda dd: dd.polygon([(8, 36), (9, 16), (14, 6), (23, 1), (33, 6), (38, 16), (39, 36), (33, 34),
                                         (33, 18), (28, 11), (19, 11), (14, 18), (14, 34)], fill=(255,) * 4))
    shade_region(im, hood, cloth, 17, 10, 15, 16)
    d = ImageDraw.Draw(im)
    d.line((14, 18, 19, 11, 28, 11, 33, 18), fill=tone(cloth, 0.45))
    d.line((15, 19, 15, 33), fill=tone(cloth, 0.45))
    d.line((32, 19, 32, 33), fill=tone(cloth, 0.45))
    d.line((23, 2, 22, 10), fill=tone(cloth, 1.25))
    # Mask over the lower face.
    mask = shape(lambda dd: dd.polygon([(15, 25), (32, 25), (31, 33), (24, 36), (16, 33)], fill=(255,) * 4))
    shade_region(im, mask, (40, 40, 45), 20, 27, 9, 6)
    d = ImageDraw.Draw(im)
    for x0 in (18, 22, 26, 30):
        d.line((x0, 26, x0 - 1, 33), fill=(30, 30, 35, 255))
    d.line((15, 25, 32, 25), fill=(75, 75, 85, 255))
    return gp.outline(im)


def mage():
    im = new()
    robe = (70, 50, 150)
    # High collar and robe with gold trim, amulet.
    collar = shape(lambda dd: dd.polygon([(3, 47), (6, 39), (13, 33), (18, 37), (29, 37), (34, 33), (41, 39), (44, 47)],
                                         fill=(255,) * 4))
    shade_region(im, collar, robe, 16, 37, 22, 10)
    d = ImageDraw.Draw(im)
    d.line((13, 33, 18, 37, 23, 43, 29, 37, 34, 33), fill=(220, 180, 70, 255))
    d.line((23, 43, 23, 47), fill=(220, 180, 70, 255))
    d.ellipse((21, 42, 26, 47), fill=(80, 220, 255, 255), outline=(220, 180, 70, 255))
    d.point((22, 43), fill=(255, 255, 255, 255))
    # Pointed hat: wide brim, bent cone, band with a gem, stars.
    cone = shape(lambda dd: dd.polygon([(13, 13), (34, 13), (29, 6), (31, 1), (37, -1), (30, -1), (24, 1), (18, 6)],
                                       fill=(255,) * 4))
    shade_region(im, cone, robe, 20, 5, 10, 8)
    brim = shape(lambda dd: dd.ellipse((4, 10, 43, 19), fill=(255,) * 4))
    shade_region(im, brim, tone(robe, 0.9)[:3], 18, 12, 18, 4)
    d = ImageDraw.Draw(im)
    d.arc((4, 10, 43, 19), 0, 180, fill=tone(robe, 0.55))
    d.rectangle((14, 10, 33, 12), fill=(220, 180, 70, 255))
    d.ellipse((21, 9, 25, 13), fill=(255, 80, 90, 255), outline=(150, 30, 40, 255))
    for sx, sy in ((19, 5), (27, 8), (29, 2)):
        d.point((sx, sy), fill=(255, 240, 150, 255))
        d.point((sx + 1, sy), fill=(255, 220, 120, 160))
    return gp.outline(im)


def main():
    faces = {
        "human": dict(skin=(232, 186, 148), hair=(95, 60, 32), style="short", eyes=(70, 110, 160)),
        "dwarf": dict(skin=(214, 158, 118), hair=(140, 70, 35), style="short", eyes=(90, 70, 40),
                      beard=(150, 78, 38), ears="big", tunic=(110, 70, 45)),
        "elf": dict(skin=(242, 218, 190), hair=(235, 220, 150), style="long", eyes=(60, 170, 120), ears="long",
                    tunic=(70, 100, 70)),
        "orc": dict(skin=(112, 162, 82), hair=(35, 35, 35), style="mohawk", eyes=(200, 60, 40), tusks=True,
                    ears="big", tunic=(80, 60, 45), scar=True, brow=(40, 50, 30)),
    }
    for name, kw in faces.items():
        gp.save(face(**kw), OUT_DIR + "race_%s.png" % name, do_outline=False)
    for name, fn in (("warrior", warrior), ("paladin", paladin), ("rogue", rogue), ("mage", mage)):
        gp.save(fn(), OUT_DIR + "class_%s.png" % name, do_outline=False)
    print("portraits generated")


if __name__ == "__main__":
    main()
