#!/usr/bin/env python3
"""Book frames (assets/ui/book.png, book_panel.png): the corner caps were
flat pure yellow (#FBF004). Recolours only those pixels into shaded brass:
light along the outer edges, dark toward the inner edge, a dark rim where
the cap meets the leather, and a rivet. The shape of the art is kept.
Idempotent: a second run finds no pure yellow and changes nothing."""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FILES = ["assets/ui/book.png", "assets/ui/book_panel.png"]
LIGHT, MID, DARK, RIM = (238, 204, 120, 255), (201, 152, 66, 255), (140, 94, 40, 255), (74, 46, 24, 255)
RIVET_HI, RIVET = (255, 240, 190, 255), (110, 74, 34, 255)


def is_yellow(p):
    # the flat yellow and its antialiased edge (parchment has blue > 100)
    return p[3] > 0 and p[0] > 180 and p[1] > 160 and p[2] < 70


def fix(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    mask = {(x, y) for y in range(h) for x in range(w) if is_yellow(px[x, y])}
    if not mask:
        return 0
    def corner(x, y):
        return (0 if x < w / 2 else w - 1), (0 if y < h / 2 else h - 1)

    far = {}
    for (x, y) in mask:
        c = corner(x, y)
        far[c] = max(far.get(c, 1), abs(x - c[0]) + abs(y - c[1]))
    for (x, y) in mask:
        c = corner(x, y)
        t = (abs(x - c[0]) + abs(y - c[1])) / far[c]
        inner = any(0 <= x + dx < w and 0 <= y + dy < h and (x + dx, y + dy) not in mask
                    and px[x + dx, y + dy][3] > 0
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if inner:
            col = RIM
        elif t < 0.3:
            col = LIGHT
        elif t < 0.72:
            col = MID
        else:
            col = DARK
        px[x, y] = col
    # a rivet in each cap, 1/3 of the way in
    for qx, qy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        q = [(x, y) for (x, y) in mask if (x >= w / 2) == qx and (y >= h / 2) == qy]
        if not q:
            continue
        cx = 0 if not qx else w - 1
        cy = 0 if not qy else h - 1
        far = max(abs(x - cx) + abs(y - cy) for x, y in q)
        rx = cx + (1 if not qx else -1) * max(2, far // 5)
        ry = cy + (1 if not qy else -1) * max(2, far // 5)
        for dx, dy, c in ((0, 0, RIVET_HI), (1, 0, RIVET), (0, 1, RIVET), (1, 1, RIVET)):
            x, y = rx + (dx if not qx else -dx), ry + (dy if not qy else -dy)
            if (x, y) in mask:
                px[x, y] = c
    im.save(path)
    return len(mask)


if __name__ == "__main__":
    for f in FILES:
        print(f, fix(os.path.join(ROOT, f)), "pixels")
