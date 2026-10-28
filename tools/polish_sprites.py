#!/usr/bin/env python3
"""Polish pass for character sprite sheets (same size, same frames).

What hand-made pixel art does and generated sprites lack:
* hue shifting - shadows lean cool (toward blue-violet), lights lean warm
  (toward yellow), instead of the same hue only darker / lighter;
* selective outline - the black outline takes a dark tint of the colour it
  wraps on the lit side (top / left), stays dark on the shadow side;
* rim light - the first pixel inside the silhouette on the top-left edge is
  a step brighter, so the figure stands off the background.

The unpolished sources are kept in tools/sprite_src/ with the hash of the
polished result (index.json): re-running never compounds, and a sheet that a
generator rewrote since (its hash no longer matches) becomes the new source.
Run from tools/:  python3 polish_sprites.py [glob ...]
(default: hero layers, hero portraits and weapon icons)
"""
from __future__ import annotations

import colorsys
import glob
import hashlib
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(HERE, "sprite_src")
DEFAULT = ["assets/sprites/player/body_*.png", "assets/sprites/player/outfit_*.png",
           "assets/sprites/player/head_*.png", "assets/sprites/player/equip_*.png",
           "assets/sprites/portraits/hero_*.png"]  # weapons: gen_weapon_remaster polishes them


def _weapons():
    """Weapon icons: the items whose .tres is a WeaponItemData."""
    out = []
    for tres in glob.glob(os.path.join(ROOT, "data", "items", "**", "*.tres"), recursive=True):
        txt = open(tres, encoding="utf-8").read()
        if 'script_class="WeaponItemData"' not in txt:
            continue
        for line in txt.splitlines():
            if "sprites/items/" in line and "Texture2D" in line:
                out.append(os.path.join(ROOT, line.split('path="res://')[1].split('"')[0]))
    return sorted(set(out))


def _md5(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def _lum(c):
    return (0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]) / 255.0


def _hue_shift(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if s < 0.06:  # greys: a hint of temperature only
        t = v - 0.5
        r2, g2, b2 = r / 255 + t * 0.03, g / 255, b / 255 - t * 0.05
        return tuple(max(0, min(255, int(c * 255))) for c in (r2, g2, b2))
    t = v - 0.55  # >0 lights, <0 shadows
    target = 0.13 if t > 0 else 0.70  # warm yellow / cool blue-violet
    dh = ((target - h + 0.5) % 1.0) - 0.5
    h = (h + dh * min(0.22, abs(t) * 0.45)) % 1.0
    s = min(1.0, s * (1.08 if t < 0 else 0.97))
    r2, g2, b2 = colorsys.hsv_to_rgb(h, s, v)
    return int(r2 * 255), int(g2 * 255), int(b2 * 255)


def polish_frame(im):
    w, h = im.size
    src = im.load()
    out = im.copy()
    o = out.load()

    def solid(x, y):
        return 0 <= x < w and 0 <= y < h and src[x, y][3] > 0

    def is_outline(c):
        return c[3] > 0 and _lum(c) < 0.11

    def open_(x, y):  # background or outline next to this pixel
        return not solid(x, y) or is_outline(src[x, y])

    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if c[3] == 0:
                continue
            if is_outline(c):
                # the colour it wraps: the first non-outline neighbour
                inner = None
                lit_side = False
                for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    if solid(x + dx, y + dy) and not is_outline(src[x + dx, y + dy]):
                        inner = src[x + dx, y + dy]
                        lit_side = (dx, dy) in ((1, 0), (0, 1))  # the figure is right / below: top-left edge
                        break
                if inner is not None:
                    f = 0.42 if lit_side else 0.24
                    o[x, y] = (max(c[0], int(inner[0] * f)), max(c[1], int(inner[1] * f)),
                               max(c[2], int(inner[2] * f)), c[3])
                continue
            r, g, b = _hue_shift(c[0], c[1], c[2])
            # rim light: the edge facing the top-left light
            if open_(x - 1, y) or open_(x, y - 1):
                r, g, b = min(255, int(r * 1.12 + 10)), min(255, int(g * 1.12 + 9)), min(255, int(b * 1.1 + 6))
            o[x, y] = (r, g, b, c[3])
    return out


def run(patterns):
    os.makedirs(SRC, exist_ok=True)
    index_path = os.path.join(SRC, "index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {}
    n = 0
    for pat in patterns:
        paths = _weapons() if pat == "@weapons" else sorted(glob.glob(os.path.join(ROOT, pat)))
        for path in paths:
            if not os.path.exists(path):
                continue
            name = os.path.relpath(path, ROOT).replace(os.sep, "__")
            keep = os.path.join(SRC, name)
            if not os.path.exists(keep) or index.get(name) != _md5(path):
                shutil.copyfile(path, keep)  # first run, or a generator rewrote it
            polish_frame(Image.open(keep).convert("RGBA")).save(path)
            index[name] = _md5(path)
            n += 1
    json.dump(index, open(index_path, "w"), indent=0, sort_keys=True)
    print("polished:", n)


if __name__ == "__main__":
    run(sys.argv[1:] or DEFAULT)
