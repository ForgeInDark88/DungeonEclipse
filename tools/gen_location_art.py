#!/usr/bin/env python3
"""Placeholder art of the layered locations (surface + dungeon): the ways
between the layers. Colored stand-ins until the real sprites arrive
(docs/ASSET_LIST.md lists them).

Run from the project root:  python3 tools/gen_location_art.py
"""
from __future__ import annotations

import os
import random

from PIL import Image, ImageDraw

OUT = "assets/sprites/portals"
INK = (24, 16, 12, 255)


def save(im: Image.Image, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".png"))


def cave(name: str, rock: tuple, seed: int) -> None:
    """A cave mouth in a rock mound: 44×36, the dark hole in the middle."""
    w, h = 44, 36
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    d.ellipse((1, 4, w - 2, h + 24), fill=rock + (255,), outline=INK)
    for _ in range(26):
        x, y = rnd.randint(4, w - 6), rnd.randint(6, h - 4)
        c = tuple(max(0, min(255, v + rnd.randint(-24, 18))) for v in rock)
        d.rectangle((x, y, x + rnd.randint(1, 3), y + 1), fill=c + (255,))
    d.ellipse((11, 12, w - 12, h + 14), fill=(14, 10, 12, 255), outline=INK)
    d.ellipse((15, 18, w - 16, h + 10), fill=(4, 3, 6, 255))
    for x in range(12, w - 12, 5):  # grass on the brow
        d.line((x, 6 + abs(x - w // 2) // 5, x + 1, 2 + abs(x - w // 2) // 5), fill=(84, 140, 60, 255))
    save(im, name)


def hatch(name: str, down: bool) -> None:
    """Stairs between floors: a stone arch, steps going down or up into light."""
    w, h = 28, 36
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((1, 6, w - 2, h - 1), fill=(96, 88, 84, 255), outline=INK)
    d.pieslice((1, 0, w - 2, 14), 180, 360, fill=(110, 102, 96, 255), outline=INK)
    d.rectangle((5, 8, w - 6, h - 1), fill=(10, 8, 10, 255) if down else (230, 210, 150, 255))
    for k in range(5):
        y = h - 4 - k * 5 if down else 10 + k * 5
        shade = 70 + k * 18 if down else 150 - k * 14
        d.rectangle((6, y, w - 7, y + 2), fill=(shade, shade - 6, shade - 10, 255))
    d.polygon([(w // 2 - 3, 3), (w // 2 + 3, 3), (w // 2, 7 if down else -1)], fill=(240, 200, 90, 255))
    save(im, name)


def signpost(name: str) -> None:
    """Back to the expedition map: a road sign, 22×32."""
    w, h = 22, 32
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((9, 6, 12, h - 1), fill=(110, 76, 44, 255), outline=INK)
    d.polygon([(1, 6), (17, 6), (21, 10), (17, 14), (1, 14)], fill=(170, 124, 72, 255), outline=INK)
    d.line((4, 10, 15, 10), fill=(70, 46, 26, 255))
    d.polygon([(4, 16), (20, 16), (20, 23), (4, 23), (1, 19)], fill=(150, 108, 62, 255), outline=INK)
    save(im, name)


def lift(name: str) -> None:
    """A guardian's way out: a glowing rune circle, 32×36."""
    w, h = 32, 36
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((2, h - 10, w - 3, h - 1), fill=(120, 90, 200, 255), outline=INK)
    d.ellipse((7, h - 8, w - 8, h - 3), fill=(210, 190, 255, 255))
    for k in range(4):
        d.line((8 + k * 5, h - 6, 10 + k * 5, 4 + k * 3), fill=(190, 160, 255, 160))
    save(im, name)


def well_entrance(name: str) -> None:
    """A dry well with a rope down: 26×30."""
    w, h = 26, 30
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 14, w - 3, h - 1), fill=(138, 134, 126, 255), outline=INK)
    for y in range(17, h, 4):
        d.line((3, y, w - 4, y), fill=(110, 106, 98, 255))
    d.rectangle((5, 12, w - 6, 16), fill=(12, 10, 12, 255))
    d.line((4, 2, 4, 14), fill=(100, 70, 40, 255), width=2)
    d.line((w - 5, 2, w - 5, 14), fill=(100, 70, 40, 255), width=2)
    d.line((4, 3, w - 5, 3), fill=(100, 70, 40, 255), width=2)
    d.line((w // 2, 3, w // 2, 14), fill=(200, 180, 130, 255))
    save(im, name)


def crypt(name: str) -> None:
    """A crypt door in a mound with a stone cross: 34×32."""
    w, h = 34, 32
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.pieslice((0, 6, w - 1, h + 22), 180, 360, fill=(110, 112, 104, 255), outline=INK)
    d.rectangle((0, 18, w - 1, h - 1), fill=(110, 112, 104, 255), outline=INK)
    d.rectangle((10, 14, w - 11, h - 1), fill=(20, 16, 18, 255), outline=INK)
    d.line((w // 2, 0, w // 2, 10), fill=(160, 160, 150, 255), width=2)
    d.line((w // 2 - 4, 4, w // 2 + 4, 4), fill=(160, 160, 150, 255), width=2)
    save(im, name)


def ruin_stairs(name: str) -> None:
    """Steps down between two broken walls: 36×28."""
    w, h = 36, 28
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(0, h - 1), (0, 6), (6, 2), (9, h - 1)], fill=(150, 144, 132, 255), outline=INK)
    d.polygon([(w - 1, h - 1), (w - 1, 10), (w - 8, 4), (w - 10, h - 1)], fill=(150, 144, 132, 255), outline=INK)
    d.rectangle((9, 12, w - 11, h - 1), fill=(14, 12, 14, 255))
    for k in range(4):
        y = 14 + k * 3
        d.rectangle((10 + k, y, w - 12 - k, y + 1), fill=(120 - k * 18, 114 - k * 18, 104 - k * 18, 255))
    save(im, name)


def sinkhole(name: str) -> None:
    """A ragged pit in the ground: 40×14 (a hole, roots at the rim)."""
    w, h = 40, 14
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((1, 2, w - 2, h + 8), fill=(70, 52, 36, 255), outline=INK)
    d.ellipse((6, 5, w - 7, h + 6), fill=(8, 6, 8, 255))
    for x in range(6, w - 6, 6):
        d.line((x, 5, x + 2, 11), fill=(110, 80, 50, 255))
    save(im, name)


def lift(name: str) -> None:
    """A mine lift: a wooden frame, a cage on ropes, 30×40."""
    w, h = 30, 40
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((2, 0, 5, h - 1), fill=(110, 76, 44, 255), outline=INK)
    d.rectangle((w - 6, 0, w - 3, h - 1), fill=(110, 76, 44, 255), outline=INK)
    d.rectangle((2, 0, w - 3, 3), fill=(130, 90, 52, 255), outline=INK)
    d.line((10, 3, 10, 18), fill=(200, 180, 130, 255))
    d.line((w - 11, 3, w - 11, 18), fill=(200, 180, 130, 255))
    d.rectangle((7, 18, w - 8, h - 2), outline=(150, 150, 160, 255))
    for x in range(9, w - 8, 3):
        d.line((x, 18, x, h - 2), fill=(120, 120, 130, 255))
    d.rectangle((7, h - 4, w - 8, h - 2), fill=(130, 90, 52, 255))
    save(im, name)


if __name__ == "__main__":
    lift("lift")
    well_entrance("well")
    crypt("crypt")
    ruin_stairs("ruin_stairs")
    sinkhole("sinkhole")
    cave("cave", (110, 104, 96), 1)
    cave("cave_mossy", (86, 104, 76), 2)
    hatch("stairs_down", True)
    hatch("stairs_up", False)
    signpost("map_exit")
    lift("arena_exit")
    print("portals: ok")
