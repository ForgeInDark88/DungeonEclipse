#!/usr/bin/env python3
"""Skill tree chrome: the eclipse crest and the branch node frames.

Pale tintable bodies with a dark outline (the eclipse palette), corner
notches like the concept art — big keystones get a chunky octagon.
Run from tools/: python gen_tree_ui.py  -> ../assets/ui/
"""
from __future__ import annotations

import os

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")

INK = (26, 16, 34, 255)        # near-black violet outline
BODY = (232, 226, 244, 255)    # pale body for branch tinting
LITE = (255, 253, 255, 255)
SHADE = (198, 188, 218, 255)
CORONA = (160, 108, 255, 255)
CORONA_D = (96, 60, 160, 255)
DISC = (24, 14, 36, 255)


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(px, x, y, c, w, h):
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = c


def node_frame(size: int, corners: int) -> Image.Image:
    """Square frame with cut corners, 2px inner slot ring, pale body."""
    im = img(size, size)
    px = im.load()
    c = size // 2
    for y in range(size):
        for x in range(size):
            d = max(abs(x - c), abs(y - c))  # chebyshev ring thickness
            ring = size // 2 - 1
            # corner notches: skip the corner triangles
            dx = abs(x - c) - (size // 2 - corners)
            dy = abs(y - c) - (size // 2 - corners)
            if dx + dy > size // 2 - 1 and max(abs(x - c), abs(y - c)) > ring - 1:
                continue
            if d == ring:
                put(px, x, y, INK, size, size)
            elif d == ring - 1:
                put(px, x, y, LITE if (x + y) < size else SHADE, size, size)
            elif d == ring - 2:
                put(px, x, y, INK, size, size)
            else:
                put(px, x, y, BODY, size, size)
    return im


def keystone(size: int) -> Image.Image:
    """Chunky octagon with a double ring and edge spikes for tier-5 nodes."""
    im = img(size, size)
    px = im.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            dx = abs(x + 0.5 - c)
            dy = abs(y + 0.5 - c)
            # octagon mask (cut corners)
            r = size / 2.0 - 1
            cut = size / 6.0
            if dx > r or dy > r or (dx + dy) > (r + cut + 1):
                continue
            edge = (dx > r - 1.5) or (dy > r - 1.5) or (dx + dy > r + cut - 0.5)
            inner = (dx > r - 4.0) or (dy > r - 4.0) or (dx + dy > r + cut - 3.0)
            if edge:
                px[x, y] = INK
            elif inner:
                px[x, y] = LITE if (x + y) < size else SHADE
            elif (dx > r - 5.5) or (dy > r - 5.5) or (dx + dy > r + cut - 5.0):
                px[x, y] = INK
            else:
                px[x, y] = BODY
    # spikes on the four cardinal edges
    for cx0, cy0 in ((c - 0.5, 0), (c - 0.5, size - 1), (0, c - 0.5), (size - 1, c - 0.5)):
        px[int(cx0), int(cy0)] = INK
    return im


def crest(size: int) -> Image.Image:
    """The eclipse itself: dark disc, violet corona, thin rays."""
    im = img(size, size)
    px = im.load()
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if d <= size * 0.30:
                px[x, y] = DISC
            elif d <= size * 0.30 + 1.0:
                px[x, y] = CORONA_D
            elif d <= size * 0.40:
                px[x, y] = CORONA
            elif d <= size * 0.40 + 1.0:
                px[x, y] = CORONA_D
    # rays: cardinal + diagonal
    rays = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    for rx, ry in rays:
        for i in range(2):
            x = int(c + rx * (size * 0.42 + i))
            y = int(c + ry * (size * 0.42 + i))
            put(px, x, y, CORONA, size, size)
    for rx, ry in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        put(px, int(c + rx * size * 0.44), int(c + ry * size * 0.44), CORONA_D, size, size)
    # top-left highlight on the corona
    put(px, int(c - size * 0.32), int(c - size * 0.30), LITE, size, size)
    return im


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    node_frame(22, 3).save(os.path.join(OUT, "tree_node.png"))
    keystone(30).save(os.path.join(OUT, "tree_keystone.png"))
    crest(20).save(os.path.join(OUT, "tree_crest.png"))
    print("wrote tree_node.png, tree_keystone.png, tree_crest.png")
