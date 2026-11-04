#!/usr/bin/env python3
"""Small life of the surface (scripts/world/surface_life.gd):

  butterfly_<n>.png  10x4: two frames (wings open / closed) side by side,
                     four colourings
  firefly.png        5x5: a glowing dot (drawn additively at night)
  bird.png           24x6: three frames 8x6 - perched, wings up, wings down
  fish_jump.png      7x4: a silver fish leaping out of a pond

Run from the project root:  python3 tools/gen_critters.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

OUT = "assets/sprites/critters"


def save(im, name):
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".png"))


def butterflies():
    palettes = [((240, 180, 60), (180, 90, 30)), ((120, 180, 240), (60, 90, 170)),
                ((250, 250, 245), (190, 190, 180)), ((230, 110, 150), (150, 50, 90))]
    for i, (wing, edge) in enumerate(palettes):
        im = Image.new("RGBA", (10, 4), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # frame 0: wings open
        d.point((2, 1), fill=(40, 30, 30, 255))
        d.point((2, 2), fill=(40, 30, 30, 255))
        for x, y in ((0, 0), (1, 0), (3, 0), (4, 0), (0, 1), (1, 1), (3, 1), (4, 1)):
            d.point((x, y), fill=wing + (255,))
        for x, y in ((1, 2), (3, 2), (0, 2), (4, 2)):
            d.point((x, y), fill=edge + (255,))
        # frame 1: wings closed up
        d.point((7, 2), fill=(40, 30, 30, 255))
        d.point((7, 3), fill=(40, 30, 30, 255))
        for x, y in ((6, 0), (7, 0), (8, 0), (6, 1), (8, 1)):
            d.point((x, y), fill=wing + (255,))
        d.point((7, 1), fill=edge + (255,))
        save(im, "butterfly_%d" % i)


def firefly():
    im = Image.new("RGBA", (5, 5), (0, 0, 0, 0))
    px = im.load()
    for y in range(5):
        for x in range(5):
            d = abs(x - 2) + abs(y - 2)
            if d == 0:
                px[x, y] = (255, 255, 200, 255)
            elif d == 1:
                px[x, y] = (220, 255, 120, 170)
            elif d == 2:
                px[x, y] = (160, 230, 80, 60)
    save(im, "firefly")


def bird():
    im = Image.new("RGBA", (24, 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body, lit, beak = (54, 50, 58, 255), (96, 90, 104, 255), (200, 160, 70, 255)
    # perched (facing right): round body, tail, head
    d.rectangle((2, 2, 5, 4), fill=body)
    d.point((3, 2), fill=lit)
    d.point((6, 2), fill=body)
    d.point((6, 1), fill=body)
    d.point((7, 2), fill=beak)
    d.point((1, 3), fill=body)
    d.point((0, 4), fill=body)
    d.point((3, 5), fill=(120, 100, 70, 255))
    # wings up
    o = 8
    d.rectangle((o + 2, 3, o + 5, 4), fill=body)
    d.line((o + 1, 0, o + 3, 3), fill=body)
    d.line((o + 6, 0, o + 4, 3), fill=lit)
    d.point((o + 6, 3), fill=body)
    d.point((o + 7, 3), fill=beak)
    # wings down
    o = 16
    d.rectangle((o + 2, 2, o + 5, 3), fill=body)
    d.line((o + 1, 5, o + 3, 3), fill=body)
    d.line((o + 6, 5, o + 4, 3), fill=lit)
    d.point((o + 6, 2), fill=body)
    d.point((o + 7, 2), fill=beak)
    save(im, "bird")


def fish():
    im = Image.new("RGBA", (7, 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((1, 1, 4, 2), fill=(170, 186, 196, 255))
    d.line((1, 1, 4, 1), fill=(230, 240, 245, 255))
    d.point((5, 0), fill=(120, 140, 150, 255))
    d.point((5, 3), fill=(120, 140, 150, 255))
    d.point((6, 1), fill=(120, 140, 150, 255))
    d.point((6, 2), fill=(120, 140, 150, 255))
    d.point((1, 1), fill=(20, 20, 30, 255))
    save(im, "fish_jump")


def raindrop():
    """1x7: a falling streak, bright at the head (the particles align it
    with their motion)."""
    im = Image.new("RGBA", (1, 7), (0, 0, 0, 0))
    for y in range(7):
        im.putpixel((0, y), (200, 220, 255, 40 + y * 30))
    save(im, "raindrop")


def main():
    raindrop()
    butterflies()
    firefly()
    bird()
    fish()
    print("critters: ok")


if __name__ == "__main__":
    main()
