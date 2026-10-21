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
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp
import gen_sheets as gs

A = gp.A

BIOMES = {
    "catacombs": dict(stone=(92, 70, 58), bedrock=(46, 42, 52), mortar=(50, 36, 30), back=(34, 28, 32),
                      top=(150, 140, 120), top_kind="dust", ore=(200, 140, 90), ore_glow=(255, 170, 90),
                      wood=(120, 82, 48), sky=(18, 14, 22), far=(30, 24, 34), mid=(44, 36, 46), near=(60, 50, 58)),
    "fungal": dict(stone=(52, 74, 78), bedrock=(30, 40, 46), mortar=(24, 36, 40), back=(20, 32, 34),
                   top=(60, 200, 170), top_kind="moss", ore=(80, 230, 240), ore_glow=(120, 255, 255),
                   wood=(90, 70, 60), sky=(8, 18, 20), far=(16, 34, 36), mid=(22, 50, 52), near=(30, 70, 70)),
    "ruins": dict(stone=(150, 132, 100), bedrock=(80, 72, 60), mortar=(100, 86, 64), back=(58, 50, 42),
                  top=(80, 150, 60), top_kind="grass", ore=(230, 200, 80), ore_glow=(255, 230, 120),
                  wood=(130, 95, 60), sky=(26, 22, 18), far=(44, 38, 32), mid=(64, 56, 46), near=(84, 74, 60)),
    "lava": dict(stone=(70, 40, 38), bedrock=(30, 18, 18), mortar=(40, 20, 18), back=(36, 18, 16),
                 top=(255, 120, 30), top_kind="magma", ore=(255, 80, 40), ore_glow=(255, 140, 60),
                 wood=(70, 50, 40), sky=(30, 8, 6), far=(50, 16, 12), mid=(70, 24, 16), near=(90, 34, 20)),
}


def c4(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


def noise_tile(base, seed, var=0.12):
    return gp.tile_noise(c4(base), seed, var)


def brick(b, seed, cracked=False, ore=False):
    im = noise_tile(b["stone"], seed)
    d = ImageDraw.Draw(im)
    m = c4(b["mortar"])
    for y in (0, 5, 10, 15):
        d.line((0, y, 15, y), fill=m)
    off = seed % 2 * 4
    for y0, xs in ((0, (4 + off, 12)), (5, (0 + off, 8)), (10, (4, 12 - off))):
        for x in xs:
            d.line((x % 16, y0, x % 16, y0 + 5), fill=m)
    d.line((1, 1, 3, 1), fill=gp.shade(c4(b["stone"]), 1.3))
    if cracked:
        d.line((5, 6, 8, 9), fill=m)
        d.line((8, 9, 7, 13), fill=m)
        d.line((8, 9, 11, 10), fill=m)
    if ore:
        rnd = random.Random(seed)
        for _ in range(5):
            x, y = rnd.randint(2, 12), rnd.randint(2, 12)
            d.rectangle((x, y, x + 1, y + 1), fill=c4(b["ore"]))
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
            d.point((x, y), fill=gp.shade(t, 1.0 - y * 0.15))
        if kind in ("moss", "grass") and rnd.random() < 0.25:
            d.point((x, h), fill=gp.shade(t, 0.7))
        if kind == "grass" and rnd.random() < 0.3:
            # blades sticking up are inside the tile (top rows)
            d.point((x, 0), fill=gp.shade(t, 1.25))
    if kind == "magma":
        for x in range(0, 16, 5):
            d.line((x + rnd.randint(0, 3), 2, x + rnd.randint(0, 3), 5), fill=c4((255, 200, 80)))
    return im


def bottom_edge(b, seed):
    im = brick(b, seed + 21)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for x in range(1, 15, 3):
        if rnd.random() < 0.6:
            h = rnd.randint(1, 3)
            d.line((x, 15 - h, x, 15), fill=gp.shade(c4(b["stone"]), 0.6))
    d.line((0, 15, 15, 15), fill=gp.shade(c4(b["stone"]), 0.5))
    return im


def bedrock(b, seed):
    im = noise_tile(b["bedrock"], seed + 40)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    d.line((0, 0, 15, 0), fill=gp.shade(c4(b["bedrock"]), 1.5))
    for _ in range(2):
        x, y = rnd.randint(1, 12), rnd.randint(2, 12)
        d.line((x, y, x + 3, y + 2), fill=gp.shade(c4(b["bedrock"]), 0.6))
    return im


def platform(b, part):
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    w = c4(b["wood"])
    d.rectangle((0, 0, 15, 4), fill=w)
    d.line((0, 0, 15, 0), fill=gp.shade(w, 1.35))
    d.line((0, 4, 15, 4), fill=gp.shade(w, 0.6))
    if part == 0:
        d.line((0, 0, 0, 4), fill=gp.shade(w, 0.6))
        d.line((2, 5, 2, 9), fill=gp.shade(w, 0.6))
        d.line((2, 9, 6, 5), fill=gp.shade(w, 0.6))
    elif part == 2:
        d.line((15, 0, 15, 4), fill=gp.shade(w, 0.6))
        d.line((13, 5, 13, 9), fill=gp.shade(w, 0.6))
        d.line((13, 9, 9, 5), fill=gp.shade(w, 0.6))
    else:
        d.point((7, 2), fill=gp.shade(w, 0.6))
    return im


def backwall(b, seed):
    im = noise_tile(b["back"], seed + 70, 0.08)
    d = ImageDraw.Draw(im)
    m = gp.shade(c4(b["back"]), 0.7)
    for y in (7, 15):
        d.line((0, y, 15, y), fill=m)
    d.line((7 if seed % 2 else 3, 0, 7 if seed % 2 else 3, 7), fill=m)
    d.line((15, 8, 15, 15), fill=m)
    if seed == 3:
        d.ellipse((5, 9, 10, 13), fill=gp.shade(c4(b["back"]), 0.5))  # hole
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


def tileset(name, b):
    atlas = gp.new(16 * 4, 16 * 7)
    rows = [
        [bedrock(b, i) for i in range(4)],
        [brick(b, 0), brick(b, 1), brick(b, 2, cracked=True), brick(b, 3, ore=True)],
        [top_edge(b, i) for i in range(4)],
        [bottom_edge(b, i) for i in range(4)],
        [platform(b, 0), platform(b, 1), platform(b, 2), gp.tile_ladder()],
        [backwall(b, i) for i in range(4)],
        [ore_glow(b)],
    ]
    for y, row in enumerate(rows):
        for x, t in enumerate(row):
            atlas.alpha_composite(t, (x * 16, y * 16))
    atlas.save(os.path.join(A, f"sprites/tiles/tiles_{name}.png"))


# ------------------------------------------------------------------ parallax
def parallax(name, b):
    w, h = 320, 180
    rnd = random.Random(hash(name) & 0xFFFF)
    # far: big dark silhouettes (cavern walls / distant arches)
    far = Image.new("RGBA", (w, h), c4(b["sky"]))
    d = ImageDraw.Draw(far)
    for i in range(6):
        x = i * 60 + rnd.randint(-10, 10)
        top = rnd.randint(40, 90)
        d.polygon([(x - 40, h), (x, top), (x + 40, h)], fill=c4(b["far"]))
    for i in range(30):
        x, y = rnd.randint(0, w - 1), rnd.randint(0, h // 2)
        d.point((x, y), fill=c4(gp.shade(c4(b["far"]), 1.6)))
    far.save(os.path.join(A, f"sprites/backgrounds/{name}_far.png"))
    # mid: pillars / mushrooms / arches with transparency
    mid = gp.new(w, h)
    d = ImageDraw.Draw(mid)
    col = c4(b["mid"])
    for i in range(4):
        x = i * 80 + rnd.randint(10, 50)
        if name == "fungal":
            d.rectangle((x - 3, 70, x + 3, h), fill=col)
            d.pieslice((x - 26, 40, x + 26, 100), 180, 360, fill=gp.shade(col, 1.2))
            for k in range(5):
                d.point((x - 20 + k * 10, 62), fill=c4((90, 255, 220)))
        elif name == "ruins":
            d.rectangle((x - 8, 50, x + 8, h), fill=col)
            d.rectangle((x - 12, 44, x + 12, 50), fill=gp.shade(col, 1.2))
            d.arc((x + 8, 40, x + 72, 110), 180, 360, fill=col, width=6)
        elif name == "lava":
            d.polygon([(x - 18, h), (x - 6, 60), (x + 6, 80), (x + 20, h)], fill=col)
            d.line((x - 30, h - 6, x + 40, h - 10), fill=c4((255, 110, 30)), width=2)
        else:
            d.rectangle((x - 7, 30, x + 7, h), fill=col)
            for y in range(40, h, 18):
                d.line((x - 7, y, x + 7, y), fill=gp.shade(col, 0.7))
            d.ellipse((x - 4, 60, x + 4, 66), fill=c4((25, 20, 28)))
    mid.save(os.path.join(A, f"sprites/backgrounds/{name}_mid.png"))
    # near: hanging things from the top (chains, vines, stalactites)
    near = gp.new(w, h)
    d = ImageDraw.Draw(near)
    col = c4(b["near"], 200)
    for i in range(10):
        x = rnd.randint(0, w - 1)
        ln = rnd.randint(20, 70)
        if name in ("fungal", "ruins"):
            for y in range(0, ln, 3):
                d.point((x + int(2 * math.sin(y * 0.3)), y), fill=col)
                d.point((x + int(2 * math.sin(y * 0.3)) + 1, y + 1), fill=col)
        elif name == "lava":
            d.polygon([(x - 6, 0), (x + 6, 0), (x, ln)], fill=col)
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
    im, d = img(16, 16)  # small mushrooms (glow)
    for x, h, r in ((4, 5, 3), (10, 8, 4)):
        d.rectangle((x, 16 - h, x + 1, 15), fill=(210, 220, 200, 255))
        d.pieslice((x - r + 1, 16 - h - r, x + r + 1, 16 - h + r), 180, 360, fill=(70, 230, 200, 255))
    D["mushrooms"] = im
    im, d = img(16, 32)  # big mushroom
    d.rectangle((6, 14, 9, 31), fill=(200, 210, 190, 255))
    d.pieslice((0, 4, 16, 24), 180, 360, fill=(60, 200, 210, 255))
    for x in (3, 7, 11):
        d.point((x, 10), fill=(220, 255, 255, 255))
    D["big_mushroom"] = im
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
    for name, im in D.items():
        gp.save(im, f"sprites/decor/{name}.png", do_outline=name not in ("cobweb",))


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


def main():
    os.makedirs(os.path.join(A, "sprites/backgrounds"), exist_ok=True)
    for name, b in BIOMES.items():
        tileset(name, b)
        parallax(name, b)
    decor_all()
    gen_hero_extra_layers()
    misc_ui()
    print("biomes generated")


if __name__ == "__main__":
    main()
