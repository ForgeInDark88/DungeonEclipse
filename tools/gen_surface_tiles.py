#!/usr/bin/env python3
"""Natural tiles of the open surface (one atlas per surface biome, the same
rows as every biome atlas, AssetPaths.TILE_ROW_*):
  0 bedrock — layered rock with cracks;
  1 soil — earth with clumps, pebbles and roots (col 2 rocky, col 3 ore);
  2 the top — grass (moss, sand, snow, ash, mud by biome) over the soil;
  3 the soil's underside — a dark rim, hanging roots;
  4 ledges (log / stone / plank) L, M, R and the ladder;
  5 back wall (dark earth), 6 ore glow, 7 floor fringe (tufts, flowers,
  stones, mushrooms), 8 hanging roots, 9 wall marks, 10 back-wall rims.
Every tile tiles with its neighbours (no pattern breaks at the seams).

Run from the project root:  python3 tools/gen_surface_tiles.py
"""
from __future__ import annotations

import os
import random

from PIL import Image, ImageDraw

T = 16
OUT = "assets/sprites/tiles"
INK = (24, 16, 12, 255)

#            top (grass)        top light        soil             soil dark        rock             ledge kind  flowers                       top style
BIOMES = {
    "forest":    ((74, 140, 56), (128, 190, 84), (122, 88, 58), (86, 60, 40), (112, 108, 104), "log", [(240, 220, 90), (230, 120, 140), (250, 250, 250)], "grass"),
    "hills":     ((112, 160, 64), (170, 206, 96), (140, 106, 68), (102, 76, 48), (128, 120, 108), "plank", [(250, 230, 120), (200, 160, 230)], "grass"),
    "swamp":     ((84, 124, 58), (132, 162, 78), (104, 84, 58), (70, 58, 42), (92, 96, 86), "log", [(210, 200, 120), (170, 200, 220)], "moss"),
    "ruins":     ((104, 132, 74), (150, 176, 100), (124, 106, 86), (90, 76, 62), (150, 144, 132), "stone", [(230, 210, 120), (240, 240, 230)], "grass"),
    "mountains": ((120, 138, 110), (230, 236, 242), (112, 104, 98), (80, 74, 70), (134, 134, 142), "stone", [(220, 230, 250)], "snow"),
    "wasteland": ((176, 150, 96), (214, 190, 130), (144, 108, 74), (104, 76, 52), (128, 102, 88), "plank", [(200, 90, 60)], "sand"),
}


def clamp(v):
    return max(0, min(255, int(v)))


def mix(c, k):
    return tuple(clamp(x * k) for x in c[:3]) + (255,)


def noise_fill(im, x0, y0, base, dark, rnd, density=0.22):
    """Earth: base color, darker clumps and lighter grains, tiling (all
    marks stay inside the tile)."""
    d = ImageDraw.Draw(im)
    d.rectangle((x0, y0, x0 + T - 1, y0 + T - 1), fill=base + (255,) if len(base) == 3 else base)
    for _ in range(int(T * T * density / 3)):
        x, y = rnd.randint(0, T - 2), rnd.randint(0, T - 2)
        c = mix(dark, rnd.uniform(0.9, 1.1)) if rnd.random() < 0.6 else mix(base, rnd.uniform(1.08, 1.2))
        w = 2 if rnd.random() < 0.5 else 1
        d.rectangle((x0 + x, y0 + y, x0 + x + w - 1, y0 + y), fill=c)


def pebble(im, x, y, rock, rnd):
    d = ImageDraw.Draw(im)
    w, h = rnd.randint(2, 4), rnd.randint(2, 3)
    d.rectangle((x, y, x + w - 1, y + h - 1), fill=mix(rock, 0.95))
    d.point((x, y), fill=mix(rock, 1.3))
    d.line((x, y + h - 1, x + w - 1, y + h - 1), fill=mix(rock, 0.7))


def root(im, x, y, soil_dark, rnd, down=True, length=5):
    d = ImageDraw.Draw(im)
    for i in range(length):
        d.point((x, y), fill=mix(soil_dark, 0.75))
        y += 1 if down else -1
        x += rnd.choice((-1, 0, 0, 1))


def clods(im, x0, y0, base, rnd, seeds=7, stones=0, rock=None, var=0.10, edge=True):
    """Earth like the dungeon's bricks: a tile split into clods (a Voronoi
    that wraps around the tile, so it tiles with itself), each clod its own
    tone, per-pixel grain, a lit upper-left rim and a dark crack on the
    lower right; `stones` of them are pebbles of `rock`."""
    pts = [(rnd.uniform(0, T), rnd.uniform(0, T)) for _ in range(seeds)]
    tone = [rnd.uniform(0.86, 1.1) for _ in range(seeds)]
    stone = set(rnd.sample(range(seeds), min(stones, seeds)))
    owner = [[0] * T for _ in range(T)]
    for y in range(T):
        for x in range(T):
            best, bi = 1e9, 0
            for i, (px, py) in enumerate(pts):
                dx = min(abs(x - px), T - abs(x - px))
                dy = min(abs(y - py), T - abs(y - py))
                dd = dx * dx + dy * dy * 1.3
                if dd < best:
                    best, bi = dd, i
            owner[y][x] = bi
    pix = im.load()
    for y in range(T):
        for x in range(T):
            i = owner[y][x]
            # a pebble: the earth's own hue mixed with the rock (not a grey slab)
            c = tuple((r + 2 * e) / 3 for r, e in zip(rock[:3], base[:3])) if i in stone and rock else base
            k = tone[i] * (1.0 + rnd.uniform(-var, var))
            if edge:
                up = owner[(y - 1) % T][x] != i or owner[y][(x - 1) % T] != i
                down = owner[(y + 1) % T][x] != i or owner[y][(x + 1) % T] != i
                if up:
                    k *= 1.22 if i in stone else 1.12
                elif down:
                    k *= 0.62 if i in stone else 0.72
            pix[x0 + x, y0 + y] = tuple(clamp(v * k) for v in c[:3]) + (255,)


def tile_soil(im, cx, cy, b, rnd, kind="plain"):
    top, light, soil, dark, rock = b[0], b[1], b[2], b[3], b[4]
    x0, y0 = cx * T, cy * T
    stones = {"plain": 0, "rocky": 1, "ore": 0}[kind]
    clods(im, x0, y0, soil, rnd, seeds=7 if kind != "rocky" else 9, stones=stones, rock=rock)
    if kind == "ore":
        d = ImageDraw.Draw(im)
        for _ in range(5):
            x, y = rnd.randint(2, T - 4), rnd.randint(2, T - 4)
            d.rectangle((x0 + x, y0 + y, x0 + x + 1, y0 + y + 1), fill=(196, 120, 60, 255))
            d.point((x0 + x, y0 + y), fill=(255, 210, 140, 255))
            d.point((x0 + x + 1, y0 + y + 1), fill=(120, 70, 36, 255))


def tile_top(im, cx, cy, b, style, rnd):
    top, light, soil, dark, rock = b[0], b[1], b[2], b[3], b[4]
    tile_soil(im, cx, cy, b, rnd)
    x0, y0 = cx * T, cy * T
    d = ImageDraw.Draw(im)
    pix = im.load()
    if style in ("sand", "snow"):
        cover = top if style == "sand" else (232, 236, 244)
        hi = light if style == "sand" else (255, 255, 255)
        for x in range(T):
            h = 4 + ((x * 3 + cx) % 4 == 0) + ((x * 7 + cx) % 5 == 0) + (1 if style == "snow" else 0)
            for y in range(h):
                k = (1.08 if y == 0 else 1.0 - 0.05 * y) * (1.0 + rnd.uniform(-0.04, 0.04))
                pix[x0 + x, y0 + y] = tuple(clamp(v * k) for v in (hi if y == 0 else cover)[:3]) + (255,)
            pix[x0 + x, y0 + h] = tuple(clamp(v * 0.72) for v in cover[:3]) + (255,)  # rim shadow
        return
    # a mat of grass (moss): shaded blades on top, a ragged lower edge whose
    # tufts hang over the earth, a dark shadow line under it
    depth = [4 + ((x * 5 + cx * 3) % 3) + (1 if style == "moss" else 0) for x in range(T)]
    for x in range(T):
        for y in range(depth[x] + 1):
            k = 1.0 - 0.06 * y + rnd.uniform(-0.07, 0.07)
            pix[x0 + x, y0 + y] = tuple(clamp(v * k) for v in top[:3]) + (255,)
        pix[x0 + x, y0 + depth[x] + 1] = tuple(clamp(v * 0.55) for v in dark[:3]) + (255,)
        if rnd.random() < 0.3:  # a tuft hangs over the edge
            pix[x0 + x, y0 + depth[x] + 1] = tuple(clamp(v * 0.8) for v in top[:3]) + (255,)
            pix[x0 + x, y0 + depth[x] + 2] = tuple(clamp(v * 0.5) for v in dark[:3]) + (255,)
    for x in range(0, T):  # lit blade tips along the top
        if (x + cx) % 2 == 0:
            pix[x0 + x, y0] = tuple(clamp(v) for v in light[:3]) + (255,)
        if rnd.random() < 0.35:
            pix[x0 + x, y0 + 1] = tuple(clamp(v * 0.95) for v in light[:3]) + (255,)
    for _ in range(4):  # darker blades inside the mat
        x = rnd.randint(0, T - 1)
        d.line((x0 + x, y0 + 1, x0 + x, y0 + 3), fill=mix(top, 0.7))


def tile_bottom(im, cx, cy, b, rnd):
    tile_soil(im, cx, cy, b, rnd)
    x0, y0 = cx * T, cy * T
    d = ImageDraw.Draw(im)
    for x in range(T):
        d.point((x0 + x, y0 + T - 1), fill=mix(b[3], 0.7))
        if (x + cx) % 3 == 0:
            d.point((x0 + x, y0 + T - 2), fill=mix(b[3], 0.8))
    for _ in range(2):
        root(im, x0 + rnd.randint(2, T - 3), y0 + T - 5, b[3], rnd, True, 4)


def tile_bedrock(im, cx, cy, b, rnd):
    """Layered rock: big slabs (dark) with lit rims and cracks."""
    rock = tuple(clamp(v * 0.62) for v in b[4][:3])
    clods(im, cx * T, cy * T, rock, rnd, seeds=5, var=0.06)


def tile_ledge(im, cx, cy, b, kind, part):
    x0, y0 = cx * T, cy * T
    d = ImageDraw.Draw(im)
    if kind == "log":
        bark = (110, 76, 46)
        d.rectangle((x0, y0, x0 + T - 1, y0 + 5), fill=bark + (255,))
        d.line((x0, y0, x0 + T - 1, y0), fill=(150, 108, 66, 255))
        d.line((x0, y0 + 5, x0 + T - 1, y0 + 5), fill=(70, 46, 28, 255))
        for x in range(2, T, 5):
            d.line((x0 + x, y0 + 2, x0 + x + 2, y0 + 2), fill=(88, 60, 36, 255))
        if part == 0:
            d.ellipse((x0, y0, x0 + 5, y0 + 5), fill=(190, 150, 100, 255), outline=(70, 46, 28, 255))
        if part == 2:
            d.ellipse((x0 + T - 6, y0, x0 + T - 1, y0 + 5), fill=(190, 150, 100, 255), outline=(70, 46, 28, 255))
    elif kind == "stone":
        rock = b[4]
        d.rectangle((x0, y0, x0 + T - 1, y0 + 5), fill=mix(rock, 1.0))
        d.line((x0, y0, x0 + T - 1, y0), fill=mix(rock, 1.3))
        d.line((x0, y0 + 5, x0 + T - 1, y0 + 5), fill=mix(rock, 0.6))
        d.line((x0 + 8, y0 + 1, x0 + 8, y0 + 4), fill=mix(rock, 0.7))
        if part == 0:
            d.polygon([(x0, y0 + 5), (x0, y0 + 9), (x0 + 6, y0 + 6)], fill=mix(rock, 0.8))
        if part == 2:
            d.polygon([(x0 + T - 1, y0 + 5), (x0 + T - 1, y0 + 9), (x0 + T - 7, y0 + 6)], fill=mix(rock, 0.8))
    else:  # plank with nails and props
        wood = (156, 112, 66)
        d.rectangle((x0, y0, x0 + T - 1, y0 + 4), fill=wood + (255,))
        d.line((x0, y0, x0 + T - 1, y0), fill=(196, 150, 96, 255))
        d.line((x0, y0 + 4, x0 + T - 1, y0 + 4), fill=(90, 62, 36, 255))
        d.point((x0 + 2, y0 + 2), fill=(70, 70, 76, 255))
        d.point((x0 + 13, y0 + 2), fill=(70, 70, 76, 255))
        if part in (0, 2):
            sx = x0 + (3 if part == 0 else T - 4)
            d.line((sx, y0 + 5, sx + (3 if part == 0 else -3), y0 + 11), fill=(110, 76, 44, 255))


def tile_ladder(im, cx, cy, kind):
    x0, y0 = cx * T, cy * T
    d = ImageDraw.Draw(im)
    if kind in ("log", "stone"):  # rope ladder
        rope = (196, 170, 120)
        d.line((x0 + 3, y0, x0 + 3, y0 + T - 1), fill=rope + (255,))
        d.line((x0 + 12, y0, x0 + 12, y0 + T - 1), fill=rope + (255,))
        for y in (3, 11):
            d.rectangle((x0 + 3, y0 + y, x0 + 12, y0 + y + 1), fill=(130, 92, 56, 255))
            d.point((x0 + 3, y0 + y + 2), fill=(90, 62, 36, 255))
    else:
        d.rectangle((x0 + 2, y0, x0 + 4, y0 + T - 1), fill=(140, 98, 58, 255))
        d.rectangle((x0 + 11, y0, x0 + 13, y0 + T - 1), fill=(140, 98, 58, 255))
        for y in (2, 7, 12):
            d.rectangle((x0 + 4, y0 + y, x0 + 11, y0 + y + 1), fill=(170, 124, 74, 255))


def fringe(im, cx, cy, b, flowers, style, rnd, variant):
    """Tufts standing on the top of a tile below (drawn in the empty cell
    above the ground: bottom-aligned)."""
    x0, y0 = cx * T, cy * T
    d = ImageDraw.Draw(im)
    top, light = b[0], b[1]
    if style in ("snow", "sand") and variant < 2:
        for _ in range(2):
            x = rnd.randint(2, T - 4)
            pebble(im, x0 + x, y0 + T - 3, b[4], rnd)
        if style == "sand" and variant == 1:
            d.line((x0 + 8, y0 + T - 1, x0 + 8, y0 + T - 8), fill=(110, 140, 70, 255))  # a dry stalk
        return
    if variant in (0, 1):  # grass tufts
        for _ in range(4 + variant * 2):
            x = rnd.randint(1, T - 2)
            h = rnd.randint(2, 6)
            d.line((x0 + x, y0 + T - 1, x0 + x + rnd.choice((-1, 0, 1)), y0 + T - h), fill=mix(top if rnd.random() < 0.6 else light, 1.0))
    elif variant == 2:  # flowers
        for _ in range(3):
            x = rnd.randint(2, T - 3)
            h = rnd.randint(3, 6)
            d.line((x0 + x, y0 + T - 1, x0 + x, y0 + T - h), fill=mix(top, 0.9))
            c = flowers[rnd.randint(0, len(flowers) - 1)]
            d.point((x0 + x, y0 + T - h - 1), fill=c + (255,))
            d.point((x0 + x - 1, y0 + T - h), fill=c + (255,))
            d.point((x0 + x + 1, y0 + T - h), fill=c + (255,))
    else:  # stones and a mushroom
        pebble(im, x0 + rnd.randint(1, 6), y0 + T - 3, b[4], rnd)
        mx = rnd.randint(8, T - 4)
        d.line((x0 + mx, y0 + T - 1, x0 + mx, y0 + T - 4), fill=(230, 220, 200, 255))
        d.rectangle((x0 + mx - 2, y0 + T - 6, x0 + mx + 2, y0 + T - 5), fill=(190, 70, 50, 255) if style != "moss" else (150, 120, 80, 255))


def hanging(im, cx, cy, b, rnd):
    for _ in range(3):
        root(im, cx * T + rnd.randint(2, T - 3), cy * T, b[3], rnd, True, rnd.randint(3, 8))


def build(name: str, b) -> None:
    src = Image.open(os.path.join(OUT, "tiles_town.png")).convert("RGBA")
    im = Image.new("RGBA", (T * 4, T * 11), (0, 0, 0, 0))
    rnd = random.Random(hash(name) & 0xFFFF)
    kind, flowers, style = b[5], b[6], b[7]
    for c in range(4):
        tile_bedrock(im, c, 0, b, rnd)
        tile_soil(im, c, 1, b, rnd, ["plain", "plain", "rocky", "ore"][c])
        tile_top(im, c, 2, b, style, rnd)
        tile_bottom(im, c, 3, b, rnd)
        clods(im, c * T, 5 * T, mix(b[3], 0.7)[:3], rnd, seeds=6, var=0.06)
        fringe(im, c, 7, b, flowers, style, rnd, c)
        hanging(im, c, 8, b, rnd)
    for part in range(3):
        tile_ledge(im, part, 4, b, kind, part)
    tile_ladder(im, 3, 4, kind)
    # ore glow, wall marks and back-wall rims: as in the town's atlas
    for row in (6, 9, 10):
        im.paste(src.crop((0, row * T, T * 4, row * T + T)), (0, row * T))
    im.save(os.path.join(OUT, f"tiles_surface_{name}.png"))


if __name__ == "__main__":
    for n, b in BIOMES.items():
        build(n, b)
    print("surface tiles: ok")
