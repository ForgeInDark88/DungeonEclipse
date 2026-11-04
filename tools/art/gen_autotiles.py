#!/usr/bin/env python3
"""47-variant ("blob") autotiles for every biome tileset.

For assets/sprites/tiles/tiles_<biome>.png writes tiles_<biome>_blob.png:
the wall block for each of the 47 neighbourhoods a cell can have, built from
the biome's own atlas (so grass stays grass, lava drips stay lava drips):

  interior            the brick (row 1, columns 0 / 1: two variants)
  open above          the biome's top cap (row 2) - dust, moss, grass, magma
  open below          the biome's ceiling (row 3)
  open left / right   an outline with chipped pixels, light from the top left
                      (left rim brighter, right rim darker)
  outer corner        rounded off
  inner corner        a shaded notch (the open diagonal between two walls)

Atlas: 8 columns x 6 rows per variant (47 tiles + 1 spare), variant 0 above
variant 1: 128 x 192 px. Tile order = the 47 reduced masks sorted ascending
(scripts/level/autotile.gd builds the same table).

Mask bits (set = that neighbour is solid):
  N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128
A diagonal only counts when both its sides are solid (standard blob rule).

  python3 tools/art/gen_autotiles.py            every tiles_*.png
  python3 tools/art/gen_autotiles.py catacombs  one biome
Deterministic: the chips come from a hash of (mask, x, y, variant).
"""
import glob
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TILES = os.path.join(ROOT, "assets", "sprites", "tiles")
T = 16
COLS, ROWS = 8, 6
N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128

ROW_BRICK, ROW_TOP, ROW_BOTTOM = 1, 2, 3


def reduce_mask(m: int) -> int:
    if not (m & N and m & E):
        m &= ~NE
    if not (m & S and m & E):
        m &= ~SE
    if not (m & S and m & W):
        m &= ~SW
    if not (m & N and m & W):
        m &= ~NW
    return m


MASKS = sorted({reduce_mask(m) for m in range(256)})
assert len(MASKS) == 47, len(MASKS)


def tile(atlas: Image.Image, col: int, row: int) -> Image.Image:
    return atlas.crop((col * T, row * T, col * T + T, row * T + T)).copy()


def shade(p, k):
    if p[3] == 0:
        return p
    return (max(0, min(255, int(p[0] * k))), max(0, min(255, int(p[1] * k))),
            max(0, min(255, int(p[2] * k))), p[3])


def h(*a) -> int:
    v = 2166136261
    for x in a:
        v = ((v ^ (x & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return v


def build(atlas: Image.Image, mask: int, var: int) -> Image.Image:
    brick = tile(atlas, var, ROW_BRICK)
    top = tile(atlas, var, ROW_TOP)
    bottom = tile(atlas, var, ROW_BOTTOM)
    open_n, open_s = not mask & N, not mask & S
    open_w, open_e = not mask & W, not mask & E
    # 1. The body: cap above, ceiling below, brick between.
    if open_n and open_s:
        img = top.copy()
        img.paste(bottom.crop((0, T // 2, T, T)), (0, T // 2))
    elif open_n:
        img = top
    elif open_s:
        img = bottom
    else:
        img = brick
    px = img.load()
    # 2. Side rims: an outline, a lit (left) or shaded (right) inner line,
    #    and a few chipped pixels so the edge is not ruler straight.
    for y in range(T):
        if open_w:
            px[0, y] = shade(px[0, y], 0.42)
            px[1, y] = shade(px[1, y], 1.16)
            if h(mask, var, 0, y) % 7 == 0 and 2 < y < T - 2:
                px[0, y] = (0, 0, 0, 0)
                px[1, y] = shade(px[1, y], 0.5)
        if open_e:
            px[T - 1, y] = shade(px[T - 1, y], 0.38)
            px[T - 2, y] = shade(px[T - 2, y], 0.8)
            if h(mask, var, 15, y) % 7 == 0 and 2 < y < T - 2:
                px[T - 1, y] = (0, 0, 0, 0)
                px[T - 2, y] = shade(px[T - 2, y], 0.5)
    # A dark lip under an open top and over an open bottom keeps the
    # silhouette readable against the back wall (the caps themselves are lit).
    if open_s:
        for x in range(T):
            px[x, T - 1] = shade(px[x, T - 1], 0.5)
    if open_n:
        for x in range(T):
            if h(mask, var, x, 99) % 9 == 0 and 1 < x < T - 2:
                px[x, 0] = (0, 0, 0, 0)
    # 3. Outer corners: rounded, the next pixels in outline colour.
    for open_a, open_b, cx, cy, dx, dy in ((open_n, open_w, 0, 0, 1, 1), (open_n, open_e, T - 1, 0, -1, 1),
                                           (open_s, open_w, 0, T - 1, 1, -1), (open_s, open_e, T - 1, T - 1, -1, -1)):
        if open_a and open_b:
            px[cx, cy] = (0, 0, 0, 0)
            px[cx + dx, cy] = shade(px[cx + dx, cy], 0.45)
            px[cx, cy + dy] = shade(px[cx, cy + dy], 0.45)
            px[cx + dx, cy + dy] = shade(px[cx + dx, cy + dy], 0.7)
    # 4. Inner corners: both sides solid, the diagonal open - a shaded notch.
    for side_a, side_b, diag, cx, cy, dx, dy in ((N, W, NW, 0, 0, 1, 1), (N, E, NE, T - 1, 0, -1, 1),
                                                 (S, W, SW, 0, T - 1, 1, -1), (S, E, SE, T - 1, T - 1, -1, -1)):
        if mask & side_a and mask & side_b and not mask & diag:
            px[cx, cy] = shade(px[cx, cy], 0.4)
            px[cx + dx, cy] = shade(px[cx + dx, cy], 0.7)
            px[cx, cy + dy] = shade(px[cx, cy + dy], 0.7)
    return img


def gen(path: str) -> str:
    atlas = Image.open(path).convert("RGBA")
    out = Image.new("RGBA", (COLS * T, ROWS * T * 2), (0, 0, 0, 0))
    for var in range(2):
        for i, m in enumerate(MASKS):
            out.paste(build(atlas, m, var), ((i % COLS) * T, (var * ROWS + i // COLS) * T))
    dest = path[:-4] + "_blob.png"
    out.save(dest, optimize=True)
    return dest


def main() -> None:
    names = sys.argv[1:]
    files = sorted(f for f in glob.glob(os.path.join(TILES, "tiles_*.png")) if not f.endswith("_blob.png"))
    if names:
        files = [f for f in files if os.path.basename(f)[6:-4] in names]
    for f in files:
        print("blob", os.path.relpath(gen(f), ROOT))


if __name__ == "__main__":
    main()
