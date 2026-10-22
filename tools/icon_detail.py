#!/usr/bin/env python3
"""Detail pass for flat item icons (applied by gen_placeholders.save to every
sprites/items/* icon).

Each flat colour region gets volume lit from the top left: a lit rim on the
edges facing the light, a shaded rim on the far edges, a soft gradient across
the region (dithered steps), a little material grain and a glint on bigger
shapes. The black outline becomes a selective outline: on the shadow side it
takes a dark tint of the colour it borders, like hand-made pixel art.
"""
from __future__ import annotations

from PIL import Image

OUT = (24, 16, 12)


def _f(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


def _lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def detail(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    src = im.load()
    out = im.copy()
    dst = out.load()

    def is_out(c):
        return c[3] > 0 and abs(c[0] - OUT[0]) + abs(c[1] - OUT[1]) + abs(c[2] - OUT[2]) < 12

    # flat regions: 4-connected pixels of exactly the same colour
    region = [[-1] * w for _ in range(h)]
    regions = []
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if c[3] == 0 or is_out(c) or region[y][x] >= 0:
                continue
            rid = len(regions)
            stack = [(x, y)]
            region[y][x] = rid
            pts = []
            while stack:
                px, py = stack.pop()
                pts.append((px, py))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = px + dx, py + dy
                    if 0 <= nx < w and 0 <= ny < h and region[ny][nx] < 0 and src[nx, ny] == c:
                        region[ny][nx] = rid
                        stack.append((nx, ny))
            regions.append((c, pts))

    def same(x, y, rid):
        return 0 <= x < w and 0 <= y < h and region[y][x] == rid

    for rid, (c, pts) in enumerate(regions):
        n = len(pts)
        if n < 3:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        span = max(1, (x1 - x0) + (y1 - y0))
        dark = _lum(c) < 45
        bright = _lum(c) > 215
        glint = None
        for x, y in pts:
            t = ((x - x0) + (y - y0)) / span  # 0 at the top left .. 1 at the bottom right
            f = 1.0
            if n >= 6:
                # three dithered tone bands across the region
                v = t * 3.0 + (0.18 if (x + y) % 2 else -0.18)
                f = (1.1, 1.0, 0.88)[min(2, max(0, int(v)))]
            lit = not same(x - 1, y, rid) or not same(x, y - 1, rid)
            shade = not same(x + 1, y, rid) or not same(x, y + 1, rid)
            if lit and not shade:
                f *= 1.2
            elif shade and not lit:
                f *= 0.78
            elif lit and shade and n >= 6:
                f *= 1.08 if t < 0.5 else 0.86
            if n >= 20 and ((x * 7 + y * 13) % 17 == 0):
                f *= 0.9  # grain
            if bright:
                f = min(f, 1.0) if f > 1.0 else f
            if dark:
                f = 1.0 + (f - 1.0) * 1.6
            dst[x, y] = _f(c, f)
            if n >= 10 and not lit and not shade and t < 0.35:
                if glint is None or (x + y) < glint[0] + glint[1]:
                    glint = (x, y)
        if glint and not dark:
            gx, gy = glint
            dst[gx, gy] = _f(c, 1.55) if not bright else (255, 255, 255, 255)

    # selective outline: shadow-side outline tinted by the neighbouring colour
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if not is_out(c):
                continue
            # neighbour inside the shape to the left / above => this is a bottom/right edge
            for dx, dy in ((-1, 0), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    nc = src[nx, ny]
                    if nc[3] and not is_out(nc):
                        tint = _f(nc, 0.32)
                        dst[x, y] = (max(tint[0], OUT[0]), max(tint[1], OUT[1]), max(tint[2], OUT[2]), 255)
                        break
    return out
