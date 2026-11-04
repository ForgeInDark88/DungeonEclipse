#!/usr/bin/env python3
"""Town buildings that grow with their level.

For every building of data/buildings/*.tres with its texture
assets/sprites/town/<id>.png (level 1), writes <id>_2.png and <id>_3.png:

  level 2  a side annex (its own lean-to roof, a lit window) on the right,
           a stone porch in front of the door
  level 3  level 2 + an annex on the left, a cupola with a pennant on the
           ridge, gilded eaves

Everything is drawn in the building's own colours: the roof, wall and
outline tones are sampled from its sprite. The canvas grows by the same
amount on both sides, so the house stays centred on its lot
(TownBuilding centres the sprite). Deterministic.

  python3 tools/art/gen_building_levels.py [id ...]
"""
import glob
import os
import re
import sys
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOWN = os.path.join(ROOT, "assets", "sprites", "town")
BUILDINGS = os.path.join(ROOT, "data", "buildings")
ANNEX_W = 14
GOLD = [(120, 84, 30), (176, 128, 46), (222, 176, 70), (250, 220, 130)]
GLASS = (255, 214, 130)
STONE = [(70, 66, 70), (104, 100, 104), (140, 136, 138), (178, 174, 172)]


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def dominant(im, y0, y1):
    """The most common opaque colour of rows y0..y1 (not the outline)."""
    c = Counter()
    for y in range(max(0, y0), min(im.height, y1)):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if p[3] > 200 and 40 < lum(p) < 235:
                c[p[:3]] += 1
    return c.most_common(1)[0][0] if c else (120, 100, 80)


def outline_colour(im):
    c = Counter(p[:3] for p in im.getdata() if p[3] > 200 and lum(p) < 45)
    return c.most_common(1)[0][0] if c else (30, 22, 20)


def roofline(im):
    """For each column the first opaque row (or None)."""
    out = []
    for x in range(im.width):
        top = None
        for y in range(im.height):
            if im.getpixel((x, y))[3] > 128:
                top = y
                break
        out.append(top)
    return out


def put(px, w, h, x, y, c):
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = tuple(c[:3]) + (255,)


def annex(canvas, x0, side, roof, wall, dark, height, seed):
    """A lean-to annex ANNEX_W wide standing on the ground, at x0..x0+W-1.
    side: +1 = right of the house (roof slopes down to the right)."""
    w, h = canvas.size
    px = canvas.load()
    ground = h - 1
    top = ground - height
    # wall with planks / stones
    for y in range(top + 4, ground + 1):
        for x in range(x0, x0 + ANNEX_W):
            c = wall
            if (y - top) % 5 == 0:
                c = shade(wall, 0.82)
            elif (x * 3 + y // 5) % 7 == 0:
                c = shade(wall, 0.9)
            put(px, w, h, x, y, c)
    # lean-to roof: high against the house, low at the far edge, with an
    # eave that overhangs by 2 px and a dark line under it
    for i in range(ANNEX_W + 3):
        x = x0 - 1 + i if side > 0 else x0 + ANNEX_W - i
        ry = top - 3 + (i * 2) // 3
        for k, y in enumerate(range(ry, ry + 6)):
            c = shade(roof, 1.2 if k == 0 else (0.8 if k >= 4 else (1.0 if (x + k) % 4 else 0.9)))
            put(px, w, h, x, y, c)
        put(px, w, h, x, ry - 1, dark)
        put(px, w, h, x, ry + 6, shade(dark, 1.0))
    # corner posts
    for y in range(top + 4, ground + 1):
        put(px, w, h, x0, y, shade(wall, 0.72))
        put(px, w, h, x0 + ANNEX_W - 1, y, shade(wall, 0.72))
    # window with warm light and a sill
    wx = x0 + ANNEX_W // 2 - 2
    wy = top + 9
    for y in range(wy, wy + 5):
        for x in range(wx, wx + 4):
            put(px, w, h, x, y, GLASS if (x - wx in (1, 2) or y - wy in (1, 3)) else shade(GLASS, 0.75))
    for x in range(wx - 1, wx + 5):
        put(px, w, h, x, wy - 1, dark)
        put(px, w, h, x, wy + 5, shade(wall, 1.2))
    for y in range(wy, wy + 5):
        put(px, w, h, wx - 1, y, dark)
        put(px, w, h, wx + 4, y, dark)
    # outline on the outer side and the bottom of the roof
    far = x0 + ANNEX_W - 1 if side > 0 else x0
    for y in range(top + 4, ground + 1):
        put(px, w, h, far + (1 if side > 0 else -1), y, dark)
    # a barrel or crates by the annex
    bx = far - (4 if side > 0 else -1)
    for y in range(ground - 4, ground + 1):
        for x in range(bx, bx + 4):
            put(px, w, h, x, y, shade(wall, 0.7) if y in (ground - 4, ground - 1) else shade(wall, 0.95))


def porch(canvas, cx, dark):
    w, h = canvas.size
    px = canvas.load()
    for i, y in enumerate((h - 2, h - 1)):
        half = 8 + i * 2
        for x in range(cx - half, cx + half):
            c = STONE[2 + (x + y) % 2] if y == h - 2 else STONE[1]
            put(px, w, h, x, y, c)
        put(px, w, h, cx - half - 1, y, dark)
        put(px, w, h, cx + half, y, dark)


def cupola(canvas, cx, ridge_y, roof, wall, dark):
    w, h = canvas.size
    px = canvas.load()
    base = ridge_y + 2
    for y in range(base - 8, base + 1):
        for x in range(cx - 4, cx + 4):
            put(px, w, h, x, y, wall if (x + y) % 6 else shade(wall, 0.85))
    for y in range(base - 6, base - 2):  # a round window
        for x in range(cx - 1, cx + 1):
            put(px, w, h, x, y, GLASS)
    for i in range(6):  # pointed roof
        for x in range(cx - 5 + i, cx + 5 - i):
            put(px, w, h, x, base - 9 - i, shade(roof, 1.1 if x < cx else 0.9))
    for y in range(base - 9, base + 1):
        put(px, w, h, cx - 5, y, dark)
        put(px, w, h, cx + 4, y, dark)
    # pole and pennant
    top = base - 15
    for y in range(top - 6, top):
        put(px, w, h, cx, y, dark)
    for i in range(5):
        for y in range(top - 6 + i // 2, top - 3 - i // 2):
            put(px, w, h, cx + 1 + i, y, GOLD[2] if i < 3 else GOLD[1])


def gild_eaves(canvas, line, off):
    w, h = canvas.size
    px = canvas.load()
    for x, top in enumerate(line):
        if top is None:
            continue
        put(px, w, h, x + off, top + 1, GOLD[2 + (x % 3 == 0)])


def build_levels(bid, tex_path):
    base = Image.open(tex_path).convert("RGBA")
    W, H = base.size
    roof = dominant(base, 0, H // 3)
    wall = dominant(base, H // 2, H - 4)
    dark = outline_colour(base)
    line = roofline(base)
    tops = [t for t in line if t is not None]
    ridge = min(tops) if tops else 0
    ridge_x = line.index(ridge)
    ridge_xs = [x for x, t in enumerate(line) if t == ridge]
    ridge_cx = (ridge_xs[0] + ridge_xs[-1]) // 2 if ridge_xs else W // 2
    annex_h = max(18, min(30, H // 2 - 4))
    extra_top = 18  # room for the cupola and pennant
    pad = ANNEX_W + 2
    out = []
    for lvl in (2, 3):
        cw, ch = W + pad * 2, H + extra_top
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        # annexes first (behind the house), then the house over them
        annex(canvas, pad + W - 4, +1, roof, wall, dark, annex_h, 1)
        if lvl == 3:
            annex(canvas, pad - ANNEX_W + 4, -1, roof, wall, dark, annex_h - 2, 2)
        canvas.alpha_composite(base, (pad, extra_top))
        porch(canvas, pad + W // 2, dark)
        if lvl == 3:
            gild_eaves(canvas, [t + extra_top if t is not None else None for t in line], pad)
            if ridge > 6 or W > 40:
                cupola(canvas, pad + ridge_cx, ridge + extra_top, roof, wall, dark)
        bbox = canvas.getbbox()
        # trim the empty top, keep the width symmetric (centring)
        canvas = canvas.crop((0, bbox[1], cw, ch))
        path = os.path.join(TOWN, "%s_%d.png" % (bid, lvl))
        canvas.save(path, optimize=True)
        out.append(path)
    return out


def building_textures():
    res = {}
    for f in sorted(glob.glob(os.path.join(BUILDINGS, "*.tres"))):
        text = open(f, encoding="utf-8").read()
        idm = re.search(r'^id = &"([^"]+)"', text, re.M)
        tm = re.search(r'^texture = ExtResource\("([^"]+)"\)', text, re.M)
        if not idm or not tm:
            continue
        pm = re.search(r'path="([^"]+)" id="%s"' % re.escape(tm.group(1)), text)
        if pm:
            res[idm.group(1)] = os.path.join(ROOT, pm.group(1).replace("res://", ""))
    return res


def main():
    wanted = set(sys.argv[1:])
    for bid, path in building_textures().items():
        if wanted and bid not in wanted:
            continue
        for p in build_levels(bid, path):
            print("level", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
