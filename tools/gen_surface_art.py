#!/usr/bin/env python3
"""Placeholder art of the open surface (stage 15): per surface biome a tile
atlas (the town atlas recolored: grass / moss / mud / sand on top, soil or
rock below), three parallax layers (sky with clouds, far range, near
silhouettes) and the props (trees, rocks, ruins, the bandits' camp...).
docs/ASSET_LIST.md lists every file.

Run from the project root:  python3 tools/gen_surface_art.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

TILES = "assets/sprites/tiles"
BACK = "assets/sprites/backgrounds"
PROPS = "assets/sprites/surface"
INK = (24, 16, 12, 255)

# id: grass top, soil, rock, sky top, sky bottom, far, mid, near, kind of silhouettes
BIOMES = {
    "forest":    ((86, 150, 64), (112, 82, 54), (104, 100, 96), (120, 170, 230), (214, 232, 240), (130, 160, 180), (70, 110, 80), (40, 76, 46), "trees"),
    "hills":     ((128, 168, 74), (132, 100, 64), (120, 112, 100), (140, 180, 232), (236, 232, 210), (150, 170, 190), (110, 140, 90), (70, 100, 60), "hills"),
    "swamp":     ((96, 120, 62), (78, 70, 52), (88, 92, 80), (130, 150, 150), (196, 206, 186), (120, 136, 128), (70, 92, 76), (44, 60, 48), "willows"),
    "ruins":     ((118, 142, 80), (118, 100, 80), (150, 144, 132), (150, 168, 210), (230, 220, 200), (150, 150, 170), (110, 110, 120), (70, 72, 80), "ruins"),
    "mountains": ((120, 140, 110), (110, 104, 96), (132, 132, 138), (110, 150, 210), (220, 230, 240), (170, 180, 200), (120, 128, 140), (78, 84, 96), "peaks"),
    "wasteland": ((170, 150, 96), (140, 108, 74), (126, 104, 90), (190, 150, 130), (236, 206, 160), (170, 130, 110), (130, 96, 80), (86, 60, 52), "spires"),
}


def clamp(v: int) -> int:
    return max(0, min(255, v))


OUT = INK


def sh(c, k: float):
    """A color c (RGB) lightened/darkened by k, opaque."""
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


def shade(c, k: float):
    return tuple(clamp(int(x * k)) for x in c)


def recolor(src: Image.Image, top, soil, rock) -> Image.Image:
    """The town atlas, its rows recolored by luminance: row 0 bedrock (rock),
    1 soil, 2 the grassy top, 3 the soil's underside, 4 ledges and ladders,
    5 back wall (unused under the sky), 7 floor fringe (grass tufts)."""
    im = src.copy().convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        row = y // 16
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (r * 0.3 + g * 0.59 + b * 0.11) / 160.0
            if row == 0:
                base = rock
            elif row in (1, 3):
                base = soil
            elif row == 2:
                base = top if (y % 16) < 6 else soil
            elif row == 7:
                base = top
            else:
                continue
            px[x, y] = tuple(clamp(int(c * lum)) for c in base) + (a,)
    return im


def sky(name: str, top, bottom, rnd: random.Random) -> None:
    """The sky: a smooth gradient, a soft sun glow, layered clouds with a lit
    top and a shaded belly."""
    w, h = 320, 180
    im = Image.new("RGBA", (w, h))
    px = im.load()
    sun = (rnd.randint(60, 260), rnd.randint(30, 60))
    for y in range(h):
        t = y / (h - 1)
        base = [top[i] + (bottom[i] - top[i]) * (t ** 0.8) for i in range(3)]
        for x in range(w):
            dist = math.hypot(x - sun[0], (y - sun[1]) * 1.4)
            glow = max(0.0, 1.0 - dist / 90.0) ** 2 * 0.45
            px[x, y] = tuple(clamp_i(base[i] + (255 - base[i]) * glow) for i in range(3)) + (255,)
    d = ImageDraw.Draw(im)
    d.ellipse((sun[0] - 7, sun[1] - 7, sun[0] + 7, sun[1] + 7), fill=(255, 250, 225, 255))
    for _ in range(6):
        cx, cy = rnd.randint(0, w), rnd.randint(14, 90)
        n = rnd.randint(4, 7)
        for k in range(n):
            r = rnd.randint(7, 15)
            x = cx + k * 9 - n * 4
            d.ellipse((x - r, cy - r // 2 + 2, x + r, cy + r // 2 + 2), fill=(206, 214, 228, 200))
        for k in range(n):
            r = rnd.randint(6, 13)
            x = cx + k * 9 - n * 4
            d.ellipse((x - r, cy - r // 2 - 1, x + r, cy + r // 2 - 1), fill=(252, 252, 255, 220))
    im.save(os.path.join(BACK, f"surface_{name}_far.png"))


def clamp_i(v: float) -> int:
    return max(0, min(255, int(v)))


def silhouettes(name: str, color, kind: str, layer: str, rnd: random.Random) -> None:
    """Hills and their trees/rocks/ruins: a vertical gradient (lit tops,
    darker feet), a light rim along the crest, shapes with a lit side."""
    w, h = 320, 180
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    base = 104 if layer == "mid" else 134
    crest = []
    ph = rnd.random() * math.tau
    for x in range(w + 1):
        y = base + int(9 * math.sin(x / w * math.tau * 2 + ph) + 5 * math.sin(x / w * math.tau * 5 + ph * 2))
        crest.append(y)
    # body with a gradient
    for x in range(w):
        y0 = crest[x]
        for y in range(y0, h):
            k = 1.08 - 0.32 * ((y - y0) / max(1, h - y0))
            d.point((x, y), fill=tuple(clamp_i(c * k) for c in color) + (255,))
        d.point((x, y0), fill=tuple(clamp_i(c * 1.25) for c in color) + (255,))
    lit = tuple(clamp_i(c * 1.18) for c in color) + (255,)
    dark = tuple(clamp_i(c * 0.78) for c in color) + (255,)
    flat = color + (255,)
    count = 26 if layer == "near" else 16
    for i in range(count):
        x = rnd.randint(0, w)
        y = crest[min(w, max(0, x))] + 3
        if kind == "trees":
            hh = rnd.randint(18, 34) if layer == "mid" else rnd.randint(26, 44)
            for k in range(3):  # a fir in three tiers
                ty = y - hh + k * hh // 4
                hw = 4 + k * 3
                d.polygon([(x - hw, ty + hh // 3), (x, ty), (x + hw, ty + hh // 3)], fill=flat)
                d.polygon([(x, ty), (x + hw, ty + hh // 3), (x + 1, ty + hh // 3)], fill=dark)
            d.line((x, y - 4, x, y), fill=dark)
        elif kind == "willows":
            d.line((x, y - 16, x, y), fill=dark, width=2)
            d.ellipse((x - 12, y - 30, x + 12, y - 12), fill=flat)
            d.ellipse((x - 10, y - 30, x + 2, y - 18), fill=lit)
            for k in range(-9, 10, 3):
                d.line((x + k, y - 16, x + k, y - 8 + rnd.randint(-2, 2)), fill=dark)
        elif kind == "hills":
            r = rnd.randint(14, 34)
            d.pieslice((x - r, y - r // 2, x + r, y + r // 2), 180, 360, fill=flat)
            d.pieslice((x - r, y - r // 2, x, y + r // 2), 180, 270, fill=lit)
            if rnd.random() < 0.5:  # a lone round tree on the hill
                d.line((x, y - r // 2 - 6, x, y - r // 2), fill=dark)
                d.ellipse((x - 5, y - r // 2 - 14, x + 5, y - r // 2 - 4), fill=dark)
        elif kind == "ruins":
            hh = rnd.randint(14, 38)
            d.rectangle((x - 5, y - hh, x + 5, y), fill=flat)
            d.rectangle((x - 5, y - hh, x - 2, y), fill=lit)
            for k in range(rnd.randint(1, 3)):  # broken top
                d.rectangle((x - 5 + k * 4, y - hh - rnd.randint(2, 5), x - 3 + k * 4, y - hh), fill=flat)
            if rnd.random() < 0.4:
                d.arc((x + 2, y - hh - 4, x + 22, y - hh + 16), 180, 360, fill=flat, width=3)
        elif kind == "peaks":
            hh = rnd.randint(40, 80) if layer == "mid" else rnd.randint(18, 34)
            d.polygon([(x - hh, y), (x, y - hh), (x + hh, y)], fill=flat)
            d.polygon([(x, y - hh), (x + hh, y), (x + hh // 3, y)], fill=dark)
            if layer == "mid":
                d.polygon([(x - hh // 4, y - hh * 3 // 4), (x, y - hh), (x + hh // 4, y - hh * 3 // 4),
                           (x + 2, y - hh * 3 // 4 + 4), (x - 3, y - hh * 3 // 4 + 2)], fill=(238, 242, 248, 255))
        else:  # spires of the wasteland
            hh = rnd.randint(16, 46)
            d.polygon([(x - 6, y), (x - 1, y - hh), (x + 2, y - hh + 4), (x + 6, y)], fill=flat)
            d.polygon([(x - 1, y - hh), (x + 2, y - hh + 4), (x + 6, y), (x + 1, y)], fill=dark)
    im.save(os.path.join(BACK, f"surface_{name}_{layer}.png"))


# ------------------------------------------------------------------ props
def save_prop(im: Image.Image, name: str) -> None:
    im.save(os.path.join(PROPS, name + ".png"))


def tree(name: str, crown, trunk, kind: str, rnd: random.Random) -> None:
    """A tree 48×80: a shaded trunk with bark lines and roots; the crown in
    clusters (dark inside, lit on the upper left, a dark outline)."""
    w, h = 48, 80
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = w // 2
    # trunk and roots
    d.polygon([(cx - 4, h - 1), (cx - 3, 30), (cx + 3, 30), (cx + 5, h - 1)], fill=trunk + (255,))
    d.line((cx - 3, 30, cx - 4, h - 1), fill=sh(trunk, 1.3))
    d.line((cx + 3, 30, cx + 5, h - 1), fill=sh(trunk, 0.6))
    for y in range(34, h - 2, 5):
        d.line((cx - 1, y, cx + 1, y + 2), fill=sh(trunk, 0.7))
    d.line((cx - 4, h - 1, cx - 8, h - 1), fill=sh(trunk, 0.8))
    d.line((cx + 5, h - 1, cx + 9, h - 1), fill=sh(trunk, 0.8))
    if kind == "oak":
        blobs = [(rnd.randint(10, w - 10), rnd.randint(10, 34), rnd.randint(9, 13)) for _ in range(10)]
        for bx, by, r in blobs:  # outline pass
            d.ellipse((bx - r - 1, by - r - 1, bx + r + 1, by + r + 1), fill=OUT)
        for bx, by, r in blobs:
            d.ellipse((bx - r, by - r, bx + r, by + r), fill=sh(crown, 0.82))
        for bx, by, r in blobs:  # lit upper-left of each cluster
            d.ellipse((bx - r + 1, by - r + 1, bx + r // 3, by + r // 3), fill=sh(crown, 1.05))
            d.ellipse((bx - r + 3, by - r + 3, bx - r // 3, by - r // 3), fill=sh(crown, 1.25))
        for _ in range(14):
            x, y = rnd.randint(6, w - 6), rnd.randint(4, 40)
            if im.getpixel((x, y))[3] > 0:
                d.point((x, y), fill=sh(crown, 1.4))
    elif kind == "pine":
        for k in range(5):
            y = 4 + k * 10
            hw = 6 + k * 4
            pts = [(cx - hw, y + 14), (cx, y), (cx + hw, y + 14)]
            d.polygon(pts, fill=sh(crown, 0.9), outline=OUT)
            d.polygon([(cx, y), (cx + hw, y + 14), (cx + 1, y + 14)], fill=sh(crown, 0.7))
            for j in range(-hw + 2, hw - 1, 3):
                d.point((cx + j, y + 13), fill=sh(crown, 1.2))
    elif kind == "willow":
        d.ellipse((3, 4, w - 3, 40), fill=OUT)
        d.ellipse((4, 5, w - 4, 39), fill=sh(crown, 0.85))
        d.ellipse((7, 6, w - 14, 26), fill=sh(crown, 1.1))
        for x in range(6, w - 6, 3):
            ln = rnd.randint(10, 26)
            d.line((x, 30, x + rnd.randint(-1, 1), 30 + ln), fill=sh(crown, 0.75 + 0.2 * (x % 2)))
    else:  # dead
        for k in range(6):
            a = -math.pi / 2 + rnd.uniform(-1.2, 1.2)
            x0, y0 = cx, 28 + k * 4
            ln = rnd.randint(10, 18)
            x1, y1 = x0 + int(math.cos(a) * ln), y0 + int(math.sin(a) * ln)
            d.line((x0, y0, x1, y1), fill=trunk + (255,), width=2)
            d.line((x1, y1, x1 + rnd.randint(-4, 4), y1 - rnd.randint(2, 5)), fill=trunk + (255,))
    save_prop(im, name)


def rock(name: str, color, w: int, h: int, rnd: random.Random) -> None:
    """A boulder: lit top-left face, shaded right side, cracks and moss."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pts = [(1, h - 1), (2, h // 2), (w // 4, 2), (w * 2 // 3, 1), (w - 2, h // 3), (w - 1, h - 1)]
    d.polygon(pts, fill=sh(color, 0.85), outline=OUT)
    d.polygon([(3, h // 2), (w // 4, 3), (w * 2 // 3, 2), (w // 2, h // 2)], fill=sh(color, 1.15))
    d.polygon([(w * 2 // 3, 2), (w - 3, h // 3), (w - 2, h - 2), (w // 2, h - 2), (w // 2, h // 2)], fill=sh(color, 0.7))
    d.line((w // 4, 3, w * 2 // 3, 2), fill=sh(color, 1.4))
    for _ in range(2):
        x = rnd.randint(w // 4, w - w // 4)
        d.line((x, h // 3, x + rnd.randint(-3, 3), h - 3), fill=sh(color, 0.5))
    for _ in range(w // 4):  # moss on top
        x = rnd.randint(w // 5, w * 2 // 3)
        d.point((x, rnd.randint(2, 4)), fill=(96, 140, 70, 255))
    save_prop(im, name)


def simple_props(rnd: random.Random) -> None:
    # bush
    im = Image.new("RGBA", (24, 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k in range(4):
        d.ellipse((k * 5, 2 + (k % 2) * 2, k * 5 + 10, 14), fill=(70 + k * 6, 128, 60, 255))
    save_prop(im, "bush")
    # reeds
    im = Image.new("RGBA", (16, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for x in range(2, 15, 3):
        d.line((x, 19, x + rnd.randint(-1, 1), 4 + rnd.randint(0, 5)), fill=(110, 130, 60, 255))
        d.rectangle((x, 4, x + 1, 7), fill=(120, 80, 50, 255))
    save_prop(im, "reeds")
    # ruined wall and column
    im = Image.new("RGBA", (40, 34), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 33), (0, 8), (10, 4), (16, 12), (26, 2), (39, 10), (39, 33)], fill=(150, 144, 132, 255), outline=INK)
    for y in range(8, 33, 6):
        d.line((1, y, 38, y), fill=(120, 114, 104, 255))
    save_prop(im, "ruin_wall")
    im = Image.new("RGBA", (14, 46), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 6, 11, 45), fill=(160, 154, 142, 255), outline=INK)
    d.rectangle((0, 2, 13, 7), fill=(170, 164, 150, 255), outline=INK)
    save_prop(im, "ruin_column")
    # bandit tent and campfire, gravestone, cart, well
    im = Image.new("RGBA", (40, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 27), (20, 1), (39, 27)], fill=(150, 70, 50, 255), outline=INK)
    d.polygon([(16, 27), (20, 12), (24, 27)], fill=(40, 20, 16, 255))
    save_prop(im, "tent")
    im = Image.new("RGBA", (18, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line((2, 11, 15, 7), fill=(90, 60, 36, 255), width=2)
    d.line((2, 7, 15, 11), fill=(90, 60, 36, 255), width=2)
    d.polygon([(5, 9), (9, 0), (13, 9)], fill=(250, 170, 60, 255))
    d.polygon([(7, 9), (9, 4), (11, 9)], fill=(255, 236, 140, 255))
    save_prop(im, "campfire")
    im = Image.new("RGBA", (12, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((1, 1, 10, 15), radius=4, fill=(130, 130, 136, 255), outline=INK)
    d.line((4, 6, 7, 6), fill=INK)
    d.line((5, 4, 5, 10), fill=INK)
    save_prop(im, "gravestone")
    im = Image.new("RGBA", (44, 26), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 6, 41, 18), fill=(150, 108, 62, 255), outline=INK)
    d.arc((4, 0, 40, 16), 180, 360, fill=(230, 220, 190, 255), width=4)
    for x in (10, 34):
        d.ellipse((x - 6, 14, x + 6, 25), fill=(80, 56, 34, 255), outline=INK)
    save_prop(im, "cart")
    im = Image.new("RGBA", (24, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 16, 21, 29), fill=(140, 136, 128, 255), outline=INK)
    d.line((3, 4, 3, 16), fill=(100, 70, 40, 255), width=2)
    d.line((20, 4, 20, 16), fill=(100, 70, 40, 255), width=2)
    d.polygon([(0, 6), (12, 0), (23, 6)], fill=(150, 70, 50, 255), outline=INK)
    save_prop(im, "well")
    # tower ruin (tall)
    im = Image.new("RGBA", (36, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(2, 95), (4, 12), (12, 6), (18, 14), (26, 2), (33, 10), (33, 95)], fill=(146, 140, 128, 255), outline=INK)
    for y in range(16, 95, 8):
        d.line((4, y, 32, y), fill=(118, 112, 102, 255))
    d.rectangle((14, 30, 21, 42), fill=(30, 24, 26, 255))
    save_prop(im, "tower_ruin")


def main() -> None:
    os.makedirs(PROPS, exist_ok=True)
    src = Image.open(os.path.join(TILES, "tiles_town.png"))
    rnd = random.Random(15)
    for name, (top, soil, rk, s_top, s_bot, far, mid, near, kind) in BIOMES.items():
        sky(name, s_top, s_bot, rnd)
        silhouettes(name, mid, kind, "mid", rnd)
        silhouettes(name, near, kind, "near", rnd)
    tree("tree_oak", (70, 132, 58), (96, 66, 40), "oak", rnd)
    tree("tree_pine", (52, 100, 64), (90, 62, 40), "pine", rnd)
    tree("tree_willow", (96, 120, 70), (80, 66, 48), "willow", rnd)
    tree("tree_dead", (0, 0, 0), (96, 80, 66), "dead", rnd)
    rock("rock_big", (124, 120, 112), 34, 24, rnd)
    rock("rock_small", (130, 126, 118), 16, 10, rnd)
    rock("rock_red", (150, 110, 90), 26, 20, rnd)
    simple_props(rnd)
    # the tiles: tools/gen_surface_tiles.py (natural earth, not the town's bricks)
    import gen_surface_tiles
    for n, b in gen_surface_tiles.BIOMES.items():
        gen_surface_tiles.build(n, b)
    print("surface art: ok")
    # the finished art over the old placeholders (same names and sizes)
    import gen_quality_art
    gen_quality_art.main()


if __name__ == "__main__":
    main()
