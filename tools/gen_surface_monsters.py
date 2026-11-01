#!/usr/bin/env python3
"""Placeholder sheets of the surface's monsters (stage 16): beasts (wolf,
boar, deer, snake), people (bandits, the thief, goblins, ghouls) and the
ogre. Rows follow the layouts in data/animations/: idle 4, walk 6,
windup 4, attack 3, hurt 2, death 6. Colored stand-ins until real sprites
(docs/ASSET_LIST.md).

Run from the project root:  python3 tools/gen_surface_monsters.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

OUT = "assets/sprites/enemies"
INK = (24, 16, 12, 255)
ROWS = [("idle", 4), ("walk", 6), ("windup", 4), ("attack", 3), ("hurt", 2), ("death", 6)]


def sheet(fw: int, fh: int, draw_frame, name: str) -> None:
    cols = max(n for _, n in ROWS)
    im = Image.new("RGBA", (fw * cols, fh * len(ROWS)), (0, 0, 0, 0))
    for r, (anim, n) in enumerate(ROWS):
        for i in range(n):
            fr = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
            draw_frame(ImageDraw.Draw(fr), fw, fh, anim, i, n)
            im.paste(fr, (i * fw, r * fh), fr)
    im.save(os.path.join(OUT, name + "_sheet.png"))
    # the icon (bestiary, tooltips): the first idle frame
    im.crop((0, 0, fw, fh)).save(os.path.join(OUT, name + ".png"))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c) + (255,)


# ------------------------------------------------------------------ beasts
def beast(body, belly, *, tusk=False, antlers=False, long=False, low=False, fw=32, fh=22):
    def frame(d, w, h, anim, i, n):
        t = i / max(1, n)
        bob = int(math.sin(t * math.tau) * (1 if anim in ("idle", "walk") else 0))
        lean = 0
        if anim == "windup":
            lean = -2 - i
        elif anim == "attack":
            lean = 3 + i
        if anim == "death":
            # falls over and fades
            k = i / (n - 1)
            y0 = h - 6
            d.ellipse((4, y0 - 6 + int(k * 3), w - 4, y0 + 2), fill=shade(body, 1 - 0.4 * k), outline=INK)
            return
        bh = 6 if low else 9
        top = h - (5 if low else 12) - bh + bob
        x0, x1 = 5 + lean, w - 7 + lean
        if long:  # snake: a sine body
            for x in range(4, w - 4):
                y = h - 5 + int(math.sin((x / 5.0) + t * math.tau) * 2)
                d.rectangle((x, y - 2, x, y + 1), fill=shade(body, 1.0))
            d.ellipse((w - 9 + lean, h - 9, w - 2 + lean, h - 3), fill=shade(body, 1.1), outline=INK)
            d.point((w - 4 + lean, h - 7), fill=(255, 220, 60, 255))
            return
        d.rounded_rectangle((x0, top, x1, top + bh), radius=3, fill=shade(body, 1.0), outline=INK)
        d.rectangle((x0 + 3, top + bh - 3, x1 - 4, top + bh - 1), fill=shade(belly, 1.0))
        # legs
        for k, lx in enumerate((x0 + 3, x0 + 7, x1 - 7, x1 - 3)):
            sw = int(math.sin(t * math.tau + k * math.pi / 2) * 2) if anim == "walk" else 0
            d.line((lx, top + bh, lx + sw, h - 2), fill=shade(body, 0.75), width=2)
        # head
        hx = x1 - 1
        d.rounded_rectangle((hx - 2, top - 4, hx + 6, top + 4), radius=2, fill=shade(body, 1.05), outline=INK)
        d.point((hx + 3, top - 1), fill=(250, 230, 120, 255) if anim != "hurt" else (255, 60, 60, 255))
        if tusk:
            d.line((hx + 5, top + 3, hx + 7, top + 1), fill=(240, 236, 220, 255))
        if antlers:
            d.line((hx, top - 4, hx - 2, top - 9), fill=(150, 120, 80, 255))
            d.line((hx + 3, top - 4, hx + 5, top - 9), fill=(150, 120, 80, 255))
        if anim == "attack":
            d.line((hx + 6, top, hx + 9, top - 2), fill=(255, 255, 255, 200))
    return frame


# ------------------------------------------------------------------ people
def person(skin, cloth, gear, *, bow=False, hood=False, small=False, big=False, pale=False):
    def frame(d, w, h, anim, i, n):
        t = i / max(1, n)
        s = 0.75 if small else (1.4 if big else 1.0)
        cx = w // 2
        foot = h - 1
        if anim == "death":
            k = i / (n - 1)
            d.rectangle((cx - int(9 * s), foot - 5, cx + int(9 * s), foot - 1), fill=shade(cloth, 1 - 0.4 * k), outline=INK)
            return
        bob = int(math.sin(t * math.tau) * 1) if anim in ("idle", "walk") else 0
        body_h = int(11 * s)
        leg_h = int(7 * s)
        head = int(4 * s)
        top = foot - leg_h - body_h - head * 2 + bob
        for k, lx in enumerate((cx - int(2 * s), cx + int(2 * s))):
            sw = int(math.sin(t * math.tau + k * math.pi) * 2) if anim == "walk" else 0
            d.line((lx, foot - leg_h, lx + sw, foot), fill=shade(cloth, 0.6), width=max(1, int(2 * s)))
        d.rectangle((cx - int(4 * s), top + head * 2, cx + int(4 * s), foot - leg_h), fill=shade(cloth, 1.0), outline=INK)
        hc = (200, 210, 200) if pale else skin
        d.ellipse((cx - head, top, cx + head, top + head * 2), fill=shade(hc, 1.0), outline=INK)
        if hood:
            d.pieslice((cx - head - 1, top - 1, cx + head + 1, top + head * 2), 180, 360, fill=shade(cloth, 0.8))
        d.point((cx + head // 2, top + head), fill=(255, 60, 60, 255) if (pale or anim == "hurt") else INK)
        # arm and weapon
        reach = {"windup": -3, "attack": 5}.get(anim, 0)
        ay = top + head * 2 + 2
        if bow:
            d.arc((cx + 2 + reach // 2, ay - 4, cx + 8 + reach // 2, ay + 8), 270, 90, fill=gear, width=1)
            if anim == "attack":
                d.line((cx + 8, ay + 2, cx + 14, ay + 2), fill=(230, 220, 200, 255))
        else:
            d.line((cx + 2, ay, cx + 6 + reach, ay + 2), fill=shade(skin, 0.9), width=max(1, int(2 * s)))
            blade = int(8 * s)
            if anim == "windup":
                d.line((cx + 3 + reach, ay, cx + 3 + reach, ay - blade), fill=gear, width=max(1, int(s)))
            else:
                d.line((cx + 6 + reach, ay + 2, cx + 6 + reach + blade, ay + 2 - (blade // 2 if anim == "attack" else 0)),
                       fill=gear, width=max(1, int(s)))
    return frame


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sheet(32, 22, beast((110, 110, 118), (170, 170, 176)), "wolf")
    sheet(32, 22, beast((112, 80, 60), (150, 118, 90), tusk=True), "boar")
    sheet(32, 26, beast((160, 112, 70), (210, 180, 140), antlers=True), "deer")
    sheet(32, 22, beast((96, 140, 60), (150, 170, 80), long=True, low=True), "snake")
    sheet(24, 28, person((214, 170, 130), (120, 70, 50), (210, 210, 220, 255)), "bandit")
    sheet(24, 28, person((214, 170, 130), (90, 100, 60), (140, 100, 60, 255), bow=True, hood=True), "bandit_archer")
    sheet(24, 28, person((214, 170, 130), (50, 50, 60), (200, 200, 210, 255), hood=True), "thief")
    sheet(24, 28, person((110, 160, 80), (110, 80, 50), (170, 170, 170, 255), small=True), "goblin")
    sheet(24, 28, person((140, 150, 140), (70, 70, 80), (200, 200, 200, 255), pale=True), "ghoul")
    sheet(36, 40, person((150, 160, 110), (110, 90, 60), (120, 100, 80, 255), big=True), "ogre")
    print("surface monsters: ok")
