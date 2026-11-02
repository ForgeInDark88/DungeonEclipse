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
    w, h = 320, 180
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        d.line((0, y, w, y), fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    for _ in range(7):  # clouds
        cx, cy = rnd.randint(0, w), rnd.randint(10, 80)
        for k in range(5):
            r = rnd.randint(6, 14)
            d.ellipse((cx + k * 9 - r, cy - r // 2, cx + k * 9 + r, cy + r // 2), fill=(250, 250, 252, 170))
    im.save(os.path.join(BACK, f"surface_{name}_far.png"))


def silhouettes(name: str, color, kind: str, layer: str, rnd: random.Random) -> None:
    w, h = 320, 180
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    base = 110 if layer == "mid" else 140
    c = color + (255,)
    # rolling ground line, tiling left-right
    pts = [(0, h)]
    for x in range(0, w + 1, 4):
        y = base + int(10 * math.sin(x / w * math.tau * 2 + rnd.random()) + 6 * math.sin(x / w * math.tau * 5))
        pts.append((x, y))
    pts.append((w, h))
    d.polygon(pts, fill=c)
    for i in range(14 if layer == "near" else 9):
        x = rnd.randint(0, w)
        y = base + 4
        if kind == "trees":
            d.polygon([(x - 8, y), (x, y - rnd.randint(22, 40)), (x + 8, y)], fill=c)
        elif kind == "hills":
            r = rnd.randint(16, 40)
            d.ellipse((x - r, y - r // 2, x + r, y + r // 2), fill=c)
        elif kind == "willows":
            d.rectangle((x - 1, y - 20, x + 1, y), fill=c)
            d.ellipse((x - 12, y - 32, x + 12, y - 14), fill=c)
        elif kind == "ruins":
            hh = rnd.randint(14, 36)
            d.rectangle((x - 4, y - hh, x + 4, y), fill=c)
            if rnd.random() < 0.5:
                d.rectangle((x - 4, y - hh, x + 16, y - hh + 4), fill=c)
        elif kind == "peaks":
            hh = rnd.randint(30, 70) if layer == "mid" else rnd.randint(14, 30)
            d.polygon([(x - hh, y), (x, y - hh), (x + hh, y)], fill=c)
            if layer == "mid":
                d.polygon([(x - 6, y - hh + 6), (x, y - hh), (x + 6, y - hh + 6)], fill=(236, 240, 246, 255))
        else:  # spires of the wasteland
            hh = rnd.randint(16, 46)
            d.polygon([(x - 5, y), (x - 1, y - hh), (x + 2, y - hh + 4), (x + 5, y)], fill=c)
    im.save(os.path.join(BACK, f"surface_{name}_{layer}.png"))


# ------------------------------------------------------------------ props
def save_prop(im: Image.Image, name: str) -> None:
    im.save(os.path.join(PROPS, name + ".png"))


def tree(name: str, crown, trunk, kind: str, rnd: random.Random) -> None:
    w, h = 48, 80
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((w // 2 - 3, 30, w // 2 + 3, h - 1), fill=trunk + (255,), outline=INK)
    if kind == "oak":
        for _ in range(9):
            cx, cy, r = rnd.randint(10, w - 10), rnd.randint(8, 34), rnd.randint(9, 14)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=shade(crown, rnd.uniform(0.8, 1.15)) + (255,))
    elif kind == "pine":
        for k in range(4):
            y = 8 + k * 12
            hw = 8 + k * 4
            d.polygon([(w // 2 - hw, y + 16), (w // 2, y), (w // 2 + hw, y + 16)], fill=shade(crown, 0.9 + k * 0.05) + (255,), outline=INK)
    elif kind == "willow":
        d.ellipse((4, 6, w - 4, 40), fill=crown + (255,))
        for x in range(8, w - 8, 4):
            d.line((x, 30, x + rnd.randint(-2, 2), 30 + rnd.randint(10, 24)), fill=shade(crown, 0.8) + (255,))
    else:  # dead
        for k in range(5):
            a = -math.pi / 2 + rnd.uniform(-1.1, 1.1)
            x0, y0 = w // 2, 30 + k * 4
            d.line((x0, y0, x0 + int(math.cos(a) * 16), y0 + int(math.sin(a) * 16)), fill=trunk + (255,), width=2)
    save_prop(im, name)


def rock(name: str, color, w: int, h: int, rnd: random.Random) -> None:
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(1, h - 1), (3, h // 3), (w // 3, 1), (w - w // 4, 3), (w - 2, h // 2), (w - 1, h - 1)],
              fill=color + (255,), outline=INK)
    for _ in range(w // 3):
        x, y = rnd.randint(4, w - 5), rnd.randint(h // 3, h - 3)
        d.point((x, y), fill=shade(color, 0.75) + (255,))
    d.line((w // 3, 3, w // 4, h // 2), fill=shade(color, 1.2) + (255,))
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
        recolor(src, top, soil, rk).save(os.path.join(TILES, f"tiles_surface_{name}.png"))
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
    print("surface art: ok")


if __name__ == "__main__":
    main()
