#!/usr/bin/env python3
"""Weapons remastered: the original 16 px designs, finished at 32x32.

The look stays the one the weapons always had (tools/weapon_src16 keeps the
originals); only the finish is new:
* Scale2x (EPX) doubles the icon - same shapes and the same grip, smooth
  diagonals instead of doubled stairs;
* every flat colour region gets volume light from the top left (dithered
  bands, lit and shaded rims - icon_detail.detail at 32 px);
* metal gets an edge highlight and a star glint, gems and magic tips a
  soft glow and a sparkle;
* the polish pass: hue-shifted shades, colour-tinted outline, rim light.

Writes assets/sprites/items/<id>.png for every icon in weapon_src16. The
grip stays where it was (hands scale 32 px icons by 16 / width).
Run from tools/:  python3 gen_weapon_remaster.py
"""
from __future__ import annotations

import colorsys
import glob
import os

from PIL import Image

import icon_detail
import polish_sprites

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "weapon_src16")
OUT = os.path.join(HERE, "..", "assets", "sprites", "items")


def scale2x(im):
    w, h = im.size
    s = im.load()
    out = Image.new("RGBA", (w * 2, h * 2))
    o = out.load()

    def px(x, y):
        x = min(max(x, 0), w - 1)
        y = min(max(y, 0), h - 1)
        return s[x, y]

    for y in range(h):
        for x in range(w):
            p = s[x, y]
            a, b, c, d = px(x, y - 1), px(x + 1, y), px(x - 1, y), px(x, y + 1)
            e0 = e1 = e2 = e3 = p
            if c == a and c != d and a != b:
                e0 = a
            if a == b and a != c and b != d:
                e1 = b
            if d == c and d != b and c != a:
                e2 = c
            if b == d and b != a and d != c:
                e3 = d
            o[2 * x, 2 * y], o[2 * x + 1, 2 * y], o[2 * x, 2 * y + 1], o[2 * x + 1, 2 * y + 1] = e0, e1, e2, e3
    return out


def _hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)


def _is_metal(c):
    h, s, v = _hsv(c)
    return s < 0.22 and v > 0.55


def _is_magic(c):
    h, s, v = _hsv(c)
    wood = 0.04 < h < 0.12 and v < 0.75  # browns are wood / leather, not magic
    return s > 0.5 and v > 0.7 and not wood


def finish(im):
    w, h = im.size
    px = im.load()
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gp = glow.load()
    metal = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 0 and _is_metal(px[x, y])]
    magic = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 0 and _is_magic(px[x, y])]

    def empty(x, y):
        return not (0 <= x < w and 0 <= y < h) or px[x, y][3] == 0

    # metal: the edge facing the light is honed bright, a star glint near the tip
    for x, y in metal:
        if empty(x - 1, y - 1) or empty(x, y - 1) and empty(x - 1, y):
            r, g, b, a = px[x, y]
            px[x, y] = (min(255, r + 40), min(255, g + 40), min(255, b + 44), a)
    if metal:
        gx, gy = min(metal, key=lambda p: p[0] * 0.3 - p[1] + (p[0] - p[1]) * 0.1 - p[0])  # top-right-most
        for dx, dy, c in ((0, 0, (255, 255, 255)), (1, 0, (230, 236, 250)), (-1, 0, (230, 236, 250)),
                          (0, 1, (230, 236, 250)), (0, -1, (230, 236, 250))):
            x, y = gx + dx, gy + dy
            if 0 <= x < w and 0 <= y < h and px[x, y][3] > 0:
                px[x, y] = c + (255,)
    # magic: a soft glow around gems / burning tips, a sparkle in the middle
    if magic:
        cx = sum(p[0] for p in magic) / len(magic)
        cy = sum(p[1] for p in magic) / len(magic)
        col = px[int(round(magic[len(magic) // 2][0])), int(round(magic[len(magic) // 2][1]))]
        for y in range(h):
            for x in range(w):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d < 7 and px[x, y][3] == 0:
                    a = int(90 * (1 - d / 7) ** 1.5)
                    a = 70 if a > 50 else (36 if a > 20 else (14 if a > 5 else 0))
                    if a:
                        gp[x, y] = (col[0], col[1], col[2], a)
        x0, y0 = int(round(cx)), int(round(cy))
        if 0 <= x0 < w and 0 <= y0 < h and px[x0, y0][3] > 0:
            px[x0, y0] = (255, 255, 255, 255)
            if y0 > 0 and px[x0, y0 - 1][3] > 0:
                r, g, b, a = px[x0, y0 - 1]
                px[x0, y0 - 1] = (min(255, r + 70), min(255, g + 70), min(255, b + 70), a)
    glow.alpha_composite(im)
    return glow


def remaster(path):
    src = Image.open(path).convert("RGBA")
    big = scale2x(src)
    big = icon_detail.detail(big)
    big = finish(big)
    return polish_sprites.polish_frame(big)


def main():
    n = 0
    for path in sorted(glob.glob(os.path.join(SRC, "*.png"))):
        remaster(path).save(os.path.join(OUT, os.path.basename(path)))
        n += 1
    print("weapons remastered:", n)


if __name__ == "__main__":
    main()
