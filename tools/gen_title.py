#!/usr/bin/env python3
"""The game's title in its own style: «DUNGEON» carved in dungeon stone
(bevelled blocks, cracks, a little moss) with the O replaced by the eclipse -
a black sun in a golden corona - and «ECLIPSE» in gilded letters between two
ornamental rules. Cropped tight: the menu scales it into the title block.

Writes assets/ui/title_stone.png (the old assets/ui/title.png stays as is;
the menu picks one). Run from tools/:  python3 gen_title.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

import gen_placeholders as gp

W, H = 432, 152

GLYPHS = {
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],  # replaced by the eclipse
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "N": ["10001", "11001", "11101", "10111", "10011", "10001", "10001"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "I": ["111", "010", "010", "010", "010", "010", "111"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
}

STONE = (96, 88, 108)
OUTLINE = (22, 15, 28, 255)
GOLD = (232, 182, 72)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


def glyph_w(ch):
    return len(GLYPHS[ch][0])


def stone_letter(im, ch, x0, y0, s, rnd):
    """One carved letter: each glyph pixel is an s*s stone block with a lit
    top / left bevel, a dark bottom / right edge, cracks and moss."""
    px = im.load()
    rows = GLYPHS[ch]
    for gy, row in enumerate(rows):
        for gx, bit in enumerate(row):
            if bit != "1":
                continue
            bx, by = x0 + gx * s, y0 + gy * s
            up = gy == 0 or rows[gy - 1][gx] != "1"
            down = gy == len(rows) - 1 or rows[gy + 1][gx] != "1"
            left = gx == 0 or row[gx - 1] != "1"
            right = gx == len(row) - 1 or row[gx + 1] != "1"
            base = shade(STONE, rnd.uniform(0.92, 1.08))
            for y in range(s):
                for x in range(s):
                    c = base
                    if up and y < 2:
                        c = shade(base, 1.45 if y == 0 else 1.25)
                    elif left and x < 2:
                        c = shade(base, 1.2)
                    elif down and y >= s - 2:
                        c = shade(base, 0.55 if y == s - 1 else 0.7)
                    elif right and x >= s - 2:
                        c = shade(base, 0.7)
                    elif (x + y * 3 + gx * 7 + gy * 5) % 11 == 0:
                        c = shade(base, 0.85)  # stone grain
                    px[bx + x, by + y] = c
            if up and rnd.random() < 0.25:  # moss on top edges
                for x in range(rnd.randint(1, 3), rnd.randint(4, s)):
                    px[bx + x, by] = (86, 140, 84, 255)
                    if rnd.random() < 0.4:
                        px[bx + x, by + 1] = (64, 110, 70, 255)
    # a crack or two through the letter
    d = ImageDraw.Draw(im)
    for _ in range(2):
        gx = rnd.randrange(len(rows[0]))
        gy = rnd.randrange(len(rows))
        if rows[gy][gx] != "1":
            continue
        x, y = x0 + gx * s + rnd.randint(2, s - 3), y0 + gy * s + 1
        for _ in range(rnd.randint(3, 6)):
            nx, ny = x + rnd.choice((-1, 0, 1)), y + 2
            d.line((x, y, nx, ny), fill=(36, 28, 44, 255))
            x, y = nx, ny


def gold_letter(im, ch, x0, y0, s):
    px = im.load()
    rows = GLYPHS[ch]
    n = len(rows) * s
    for gy, row in enumerate(rows):
        for gx, bit in enumerate(row):
            if bit != "1":
                continue
            for y in range(s):
                for x in range(s):
                    t = (gy * s + y) / n  # vertical gradient: bright top, deep bottom
                    c = (int(255 - 40 * t), int(230 - 120 * t), int(150 - 115 * t), 255)
                    if y == 0 and (gy == 0 or rows[gy - 1][gx] != "1"):
                        c = (255, 248, 210, 255)
                    px[x0 + gx * s + x, y0 + gy * s + y] = c


def outline(im, width=2, color=OUTLINE):
    a = im.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    back = Image.new("RGBA", im.size, color)
    back.putalpha(grown)
    back.alpha_composite(im)
    return back


def eclipse(cx, cy, r):
    """The O: a black sun with a golden corona and a thin bright rim."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(22):
        ang = i * math.tau / 22 + 0.1
        ln = r + 5 + (4 if i % 2 == 0 else 1)
        a = (cx + math.cos(ang) * (r + 2), cy + math.sin(ang) * (r + 2))
        b = (cx + math.cos(ang) * ln, cy + math.sin(ang) * ln)
        d.line((a, b), fill=(255, 196, 80, 255), width=2 if i % 2 == 0 else 1)
        d.point((round(b[0]), round(b[1])), fill=(255, 245, 200, 255))
    d.ellipse((cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3), fill=(255, 236, 160, 255))
    d.ellipse((cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1), fill=(242, 170, 60, 255))
    d.ellipse((cx - r + 1, cy - r, cx + r + 1, cy + r), fill=(14, 8, 22, 255))  # the moon's shadow
    d.arc((cx - r + 1, cy - r, cx + r + 1, cy + r), 200, 320, fill=(120, 60, 170, 255))
    d.point((cx + 2, cy - 1), fill=(200, 90, 255, 255))  # the eye glints
    return layer


def glow(cx, cy, r):
    g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    for i in range(8, 0, -1):
        d.ellipse((cx - r - i * 3, cy - r - i * 3, cx + r + i * 3, cy + r + i * 3), fill=(255, 180, 70, 10))
    return g


def main():
    rnd = random.Random(7)
    s = 7
    word = "DUNGEON"
    gap = 6
    widths = [glyph_w(c) * s for c in word]
    total = sum(widths) + gap * (len(word) - 1)
    x = (W - total) // 2
    y = 8
    stone = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    o_center = None
    for ch, w in zip(word, widths):
        if ch == "O":
            o_center = (x + w // 2, y + 7 * s // 2)
        else:
            stone_letter(stone, ch, x, y, s, rnd)
        x += w + gap
    stone = outline(stone, 2)
    # the second word, gilded, between two rules
    s2 = 4
    word2 = "ECLIPSE"
    gap2 = 4
    w2 = sum(glyph_w(c) * s2 for c in word2) + gap2 * (len(word2) - 1)
    gold = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = (W - w2) // 2
    y2 = y + 7 * s + 18
    for ch in word2:
        gold_letter(gold, ch, x, y2, s2)
        x += glyph_w(ch) * s2 + gap2
    gold = outline(gold, 2, (48, 26, 12, 255))
    rules = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(rules)
    ry = y2 + 7 * s2 // 2
    lx0, lx1 = (W - w2) // 2 - 70, (W - w2) // 2 - 12
    rx0, rx1 = (W + w2) // 2 + 12, (W + w2) // 2 + 70
    for a, b, tip in ((lx0, lx1, lx1), (rx0, rx1, rx0)):
        d.line((a, ry, b, ry), fill=(48, 26, 12, 255), width=4)
        d.line((a, ry, b, ry), fill=(232, 182, 72, 255), width=2)
        d.polygon([(tip - 4 if tip == lx1 else tip + 4, ry), (tip, ry - 4), (tip + 4 if tip == lx1 else tip - 4, ry), (tip, ry + 4)],
                  fill=(255, 230, 150, 255), outline=(48, 26, 12, 255))
    for a in (lx0, rx1):
        d.ellipse((a - 3, ry - 3, a + 3, ry + 3), fill=(150, 60, 200, 255), outline=(48, 26, 12, 255))  # violet gems
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste((10, 6, 14, 120), (0, 0), stone.split()[3])
    out.alpha_composite(shadow, (3, 3))
    if o_center:
        out.alpha_composite(glow(o_center[0], o_center[1], 18))
    out.alpha_composite(stone)
    if o_center:
        out.alpha_composite(outline(eclipse(o_center[0], o_center[1], 16), 1))
    out.alpha_composite(rules)
    out.alpha_composite(gold)
    # Tight crop (a few pixels of air): the menu scales it to its block.
    box = out.getbbox()
    if box:
        out = out.crop((max(0, box[0] - 4), max(0, box[1] - 4), min(W, box[2] + 4), min(H, box[3] + 4)))
    path = os.path.join(gp.A, "ui", "title_stone.png")
    out.save(path)
    print("title:", path)


if __name__ == "__main__":
    main()
