#!/usr/bin/env python3
"""The guardian room portcullis: iron bars with riveted frame and a lock
plate, tileable vertically (16 px wide). Run from tools/."""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "props")

W, H = 16, 16
IRON = (74, 74, 88)
IRON_D = (40, 40, 52)
IRON_L = (128, 128, 148)
RIVET = (168, 168, 188)
INK = (14, 10, 18)


def px(im, x, y, c):
    im.putpixel((x, y), c)


def bar(im, x):
    """One vertical bar: lit left edge, dark right, 3px wide."""
    for y in range(H):
        px(im, x, y, IRON)
        px(im, x + 1, y, IRON_L if y % 7 else IRON)
        px(im, x + 2, y, IRON_D)


def make():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # frame
    d.rectangle((0, 0, 1, H - 1), fill=IRON_D)
    d.rectangle((W - 2, 0, W - 1, H - 1), fill=IRON_D)
    d.line((0, 0, 0, H - 1), fill=IRON_L)
    d.line((W - 1, 0, W - 1, H - 1), fill=(24, 24, 34, 255))
    # bars
    for x in (4, 9, 13):
        bar(im, x)
    # cross beam in the middle
    d.rectangle((0, 6, W - 1, 8), fill=IRON)
    d.line((0, 6, W - 1, 6), fill=IRON_L)
    d.line((0, 8, W - 1, 8), fill=INK)
    # rivets on the frame
    for y in (2, 13):
        px(im, 0, y, RIVET)
        px(im, W - 1, y, RIVET)
    # lock plate on the middle beam
    d.rectangle((6, 7, 9, 9), fill=(120, 92, 44))
    px(im, 7, 8, (40, 28, 16, 255))
    px(im, 8, 8, (232, 196, 64))
    # outline hints on bars
    for x in (4, 9, 13):
        if x + 3 < W:
            px(im, x + 3, 3, INK)
            px(im, x + 3, 11, INK)
    im.save(os.path.join(OUT, "gate_bars.png"))
    print("wrote gate_bars.png")


if __name__ == "__main__":
    make()
