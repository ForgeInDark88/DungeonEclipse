#!/usr/bin/env python3
"""Night-town backdrop for the skill tree panel: the Town of the Eclipse at
game start — violet sky, the eclipse, house silhouettes with warm windows,
a cobbled street with lamps. Drawn at 2x (1000x524) for crisp 2x UI scale.
Run from tools/: python gen_tree_bg.py  -> ../assets/ui/tree_bg.png
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

W, H = 500, 262
S = 2  # every pixel is 2x2 for a chunky look at panel size

im = Image.new("RGB", (W, H), (0, 0, 0))
d = ImageDraw.Draw(im)
rng = random.Random(777)

SKY_TOP = (24, 16, 38)
SKY_MID = (44, 28, 66)
SKY_LOW = (66, 42, 88)
FAR = (30, 20, 44)
MID = (40, 27, 56)
NEAR = (22, 14, 30)
WINDOW = (255, 196, 96)
WINDOW_DIM = (196, 130, 60)
LAMP = (255, 214, 130)
COBBLE = (52, 42, 58)
COBBLE_D = (38, 30, 44)
CORONA = (150, 100, 235)
CORONA_HI = (205, 165, 255)


def rect(x, y, w, h, c):
    d.rectangle([x * S, y * S, (x + w) * S - 1, (y + h) * S - 1], fill=c)


def px(x, y, c):
    rect(x, y, 1, 1, c)


def house(x, y, w, h, body, roof, windows=True, lit=True):
    rect(x, y + 2, w, h, body)
    # pitched roof
    for i in range(3):
        rect(x - 1 + i, y + 2 - (3 - i), w + 2 - 2 * i, 1, roof)
    if windows:
        for wy in range(y + 5, y + h - 2, 4):
            for wx in range(x + 2, x + w - 2, 4):
                if rng.random() < (0.55 if lit else 0.15):
                    px(wx, wy, WINDOW if rng.random() < 0.7 else WINDOW_DIM)
                    px(wx, wy + 1, WINDOW_DIM)


# ------------------------------------------------------------------- sky
for y in range(H):
    t = y / H
    if t < 0.55:
        a, b = SKY_TOP, SKY_MID
    else:
        a, b = SKY_MID, SKY_LOW
    c = tuple(int(a[i] + (b[i] - a[i]) * (t if t < 0.55 else (t - 0.55) / 0.45)) for i in range(3))
    d.line([(0, y), (W, y)], fill=c)

# stars
for _ in range(90):
    x, y = rng.randrange(W), rng.randrange(0, int(H * 0.45))
    if rng.random() < 0.5:
        d.point((x, y), fill=(200, 190, 230))
    else:
        d.point((x, y), fill=(140, 130, 180))

# the eclipse (upper center-left, leaves room for the crest column feel)
ecx, ecy, r = W // 2, int(H * 0.20), 26
for yy in range(ecy - r - 8, ecy + r + 8):
    for xx in range(ecx - r - 8, ecx + r + 8):
        dist = math.hypot(xx - ecx, yy - ecy)
        if dist <= r:
            c = (16, 8, 24)
        elif dist <= r + 2:
            c = CORONA
        elif dist <= r + 6 and int(dist * 2) % 3:
            c = CORONA if rng.random() < 0.75 else CORONA_HI
        else:
            continue
        d.point((xx, yy), fill=c)
# corona spikes
for ang in range(0, 360, 30):
    a = math.radians(ang)
    for k in range(r + 3, r + 11):
        d.point((ecx + k * math.cos(a), ecy + k * math.sin(a)), fill=CORONA if k % 2 else CORONA_HI)

# ------------------------------------------------------------- skylines
horizon = int((H // S) * 0.52)
# far row: towers and dense blocks
x = 0
while x < W // S:
    w = rng.randrange(5, 12)
    h = rng.randrange(6, 16)
    house(x, horizon - h, w, h, FAR, FAR, windows=False)
    x += w + rng.randrange(0, 3)
# mid row: the lived-in street with lit windows
mid_line = int((H // S) * 0.62)
x = 0
while x < W // S:
    w = rng.randrange(7, 14)
    h = rng.randrange(8, 15)
    gap = rng.randrange(1, 4)
    if x + w > W // S - 40 and x < W // S - 20:  # leave a gap for the gate plaza
        x += 6
        continue
    house(x, mid_line - h, w, h, MID, (52, 34, 72), windows=True)
    x += w + gap
# a chapel with a spire and the dungeon gate silhouette on the right
spire_x = int(W // S * 0.16)
house(spire_x, mid_line - 26, 8, 26, MID, (52, 34, 72))
for i in range(8):
    rect(spire_x + 3 - i // 2, mid_line - 27 - i, 2 + i // 2, 1, (58, 38, 80))
gate_x = int(W // S * 0.84)
house(gate_x, mid_line - 20, 10, 20, (30, 20, 44), (34, 22, 50), windows=False)
rect(gate_x + 4, mid_line - 12, 2, 12, (96, 60, 150))  # violet gate glow

# --------------------------------------------------------------- street
street_top = int((H // S) * 0.80)
rect(0, street_top, W // S, H // S - street_top, NEAR)
for y in range(street_top + 1, H // S, 2):
    for x in range((y // 2) % 4, W // S, 4):
        rect(x, y, 3, 1, COBBLE if (x // 4 + y) % 3 else COBBLE_D)
# lamps with warm pools
for lx in (int(W // S * 0.08), int(W // S * 0.5), int(W // S * 0.9)):
    base_y = street_top + 2
    rect(lx, base_y - 14, 1, 14, (70, 55, 80))
    rect(lx - 1, base_y - 17, 3, 3, LAMP)
    rect(lx - 2, base_y - 18, 5, 1, (90, 70, 95))
    for dy in (-1, 1):
        for dx in (-2, -1, 0, 1, 2):
            d.point(((lx + dx) * S, (base_y - 15 + dy) * S), fill=(255, 214, 130))
    # light pool on the cobbles
    for k in range(3):
        rect(lx - 5 + k, base_y + 1 + k * 2, 11 - 2 * k, 1, (72, 58, 46))

# vignette + frame
for i in range(6):
    shade = 26 - i * 4
    d.rectangle([i * 3, i * 3, W - 1 - i * 3, H - 1 - i * 3], outline=(shade, shade // 2, shade + 12), width=2)
d.rectangle([0, 0, W - 1, H - 1], outline=(14, 8, 20), width=3)

out = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "tree_bg.png")
im.save(out)
print("wrote", out)
