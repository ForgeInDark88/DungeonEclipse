#!/usr/bin/env python3
"""Application icon and store art.

* assets/ui/app_icon.png (256x256) and app_icon.ico (16..256, Windows): the
  eclipse - a black sun in a burning corona - over a dungeon arch, painted
  at 64x64 and scaled x4 (crisp pixel art);
* assets/ui/cover_460x215.png, cover_1280x720.png: the Heart of the
  Eclipse backdrop, the eclipse, the stone title.
Run from tools/:  python3 gen_app_icon.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
UI = os.path.join(HERE, "..", "assets", "ui")
BG = os.path.join(HERE, "..", "assets", "sprites", "backgrounds")


def eclipse(d, cx, cy, r, rays=24, seed=1):
    rnd = random.Random(seed)
    for i in range(rays):
        a = i * math.tau / rays + 0.07
        ln = r + (r * 0.55 if i % 2 == 0 else r * 0.25) * rnd.uniform(0.8, 1.2)
        d.line((cx + math.cos(a) * r, cy + math.sin(a) * r, cx + math.cos(a) * ln, cy + math.sin(a) * ln),
               fill=(255, 196, 90, 255) if i % 2 == 0 else (255, 150, 60, 255), width=max(1, r // 9 if i % 2 == 0 else 1))
    d.ellipse((cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2), fill=(255, 238, 170, 255))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(242, 168, 60, 255))
    d.ellipse((cx - r + 2, cy - r + 1, cx + r + 1, cy + r - 1), fill=(14, 8, 22, 255))
    d.arc((cx - r + 2, cy - r + 1, cx + r + 1, cy + r - 1), 200, 320, fill=(130, 70, 190, 255))
    d.point((cx + r // 4, cy - r // 6), fill=(210, 110, 255, 255))


def icon64():
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # rounded dark plate with a violet-to-ember gradient
    plate = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = plate.load()
    for y in range(64):
        for x in range(64):
            t = y / 63
            c = (int(30 + 40 * t), int(14 + 12 * t), int(46 - 10 * t))
            g = max(0.0, 1 - math.hypot(x - 32, y - 24) / 30)
            c = tuple(min(255, int(v + g * g * k)) for v, k in zip(c, (150, 80, 30)))
            px[x, y] = c + (255,)
    m = Image.new("L", (64, 64), 0)
    ImageDraw.Draw(m).rounded_rectangle((1, 1, 62, 62), radius=10, fill=255)
    im.paste(plate, (0, 0), m)
    d = ImageDraw.Draw(im)
    eclipse(d, 32, 24, 11)
    # the dungeon arch below: stone blocks, a dark doorway, two torches
    stone, lit_, dark = (92, 80, 100, 255), (132, 118, 140, 255), (48, 40, 56, 255)
    d.rectangle((10, 40, 53, 60), fill=stone)
    d.pieslice((18, 32, 45, 60), 180, 360, fill=stone)
    for y in range(41, 60, 4):
        d.line((10, y, 53, y), fill=dark)
        for x in range(10 + (y // 4 % 2) * 4, 54, 8):
            d.line((x, y, x, y + 3), fill=dark)
            d.point((x + 1, y + 1), fill=lit_)
    d.pieslice((23, 38, 40, 66), 180, 360, fill=(10, 6, 14, 255))
    d.rectangle((23, 52, 40, 60), fill=(10, 6, 14, 255))
    for tx in (16, 47):
        d.line((tx, 46, tx, 50), fill=(110, 80, 50, 255))
        d.ellipse((tx - 1, 42, tx + 1, 46), fill=(255, 170, 60, 255))
        d.point((tx, 43), fill=(255, 245, 200, 255))
    d.rounded_rectangle((1, 1, 62, 62), radius=10, outline=(12, 8, 16, 255), width=1)
    d.arc((2, 2, 22, 22), 180, 270, fill=(200, 170, 230, 255))
    return im


def cover(w, h):
    bg = Image.open(os.path.join(BG, "eclipse_heart_far.png")).convert("RGBA")
    for layer in ("mid", "near"):
        bg.alpha_composite(Image.open(os.path.join(BG, "eclipse_heart_%s.png" % layer)).convert("RGBA"))
    sc = max(w / bg.width, h / bg.height)
    bg = bg.resize((math.ceil(bg.width * sc), math.ceil(bg.height * sc)), Image.NEAREST)
    bg = bg.crop(((bg.width - w) // 2, 0, (bg.width - w) // 2 + w, h))
    title = Image.open(os.path.join(UI, "title_stone.png")).convert("RGBA")
    k = max(1, int(w * 0.62 / title.width))
    title = title.resize((title.width * k, title.height * k), Image.NEAREST)
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(h):
        a = int(150 * max(0.0, (y / h - 0.35)) / 0.65)
        sd.line((0, y, w, y), fill=(6, 3, 10, a))
    bg.alpha_composite(shade)
    bg.alpha_composite(title, ((w - title.width) // 2, int(h * 0.58) - title.height // 2))
    return bg


def main():
    big = icon64().resize((256, 256), Image.NEAREST)
    big.save(os.path.join(UI, "app_icon.png"))
    big.save(os.path.join(UI, "app_icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    cover(460, 215).save(os.path.join(UI, "cover_460x215.png"))
    cover(1280, 720).save(os.path.join(UI, "cover_1280x720.png"))
    print("icon and covers written")


if __name__ == "__main__":
    main()
