#!/usr/bin/env python3
"""The deep guardians: the Ashen King and the Crystal Titan.

Two new bosses for the biomes past floor 15, drawn in the same 48px sheet
format as the Bone King (idle/walk/windup/attack/hurt/death), with volume
shading, ember / crystal glow particles and a crumbling death.
Run from tools/: python gen_deep_bosses.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_sheets as gs
from gen_placeholders import new, shade
from gen_monsters import lit, mask, fade
from gen_structures import finish, glow_dot

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "bosses")

P = gs.P
EMBER = (255, 130, 50)
EMBER_HOT = (255, 200, 110)
ASH_BONE = (172, 162, 158)
IRON = (74, 62, 66)
TEAL_STONE = (58, 92, 100)
TEAL_DARK = (36, 60, 68)
CRYSTAL = (120, 226, 226)


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def sh(c, f):
    return shade(rgba(c), f)


def glow(im, x, y, r, col, strength=1.0):
    """Soft additive glow dots on their own layer pixels."""
    px = im.load()
    for yy in range(int(y - r), int(y + r) + 1):
        for xx in range(int(x - r), int(x + r) + 1):
            if 0 <= xx < im.width and 0 <= yy < im.height:
                d = math.hypot(xx - x, yy - y)
                if d <= r:
                    a = int(90 * strength * (1 - d / r))
                    cur = px[xx, yy]
                    if cur[3] == 0 and a > 8:
                        px[xx, yy] = (col[0], col[1], col[2], a)


def sparks(im, rng, n, box, col, alpha=170):
    px = im.load()
    for _ in range(n):
        x = rng.randint(box[0], box[2])
        y = rng.randint(box[1], box[3])
        if px[x, y][3] == 0:
            px[x, y] = (col[0], col[1], col[2], alpha)


# ============================================================== Ashen King
def ashen_king():
    """Drawn in gen_bosses.py now, in the house style of the other bosses."""
    import gen_bosses
    gen_bosses.ashen_king()


# =========================================================== Crystal Titan
def crystal_titan():
    """Volume-lit stone colossus: ellipsoid-shaded rock body, glowing crystal
    growths, strata cracks; the death crumbles into a crystal rubble pile."""
    fw, fh = 48, 52
    lay = gs.monster_layout("crystal_titan_layout", fw, fh, (24, 52), counts={"windup": 3, "attack": 3, "death": 6})
    rng = random.Random(29)
    stone = (58, 92, 100)
    stone_d = (34, 56, 64)
    crystal = (110, 220, 228)

    def crystal_cluster(d, g, bx, by, w, h, alpha, flare=False):
        """A shard family: big spike + side spikes, white core, glow."""
        pts = [(bx, by), (bx + w // 2, by - h), (bx + w, by)]
        d.polygon(pts, fill=rgba(crystal, alpha))
        d.line((bx + w // 2, by - h, bx + w // 2, by), fill=(235, 255, 255, alpha))
        d.line((bx, by, pts[1][0] - 1, pts[1][1] + 1), fill=rgba(sh(crystal, 0.6), alpha))
        if w >= 4:
            d.polygon([(bx + w - 1, by), (bx + w + 2, by - h // 2), (bx + w + 1, by)], fill=rgba(sh(crystal, 0.8), alpha))
            d.polygon([(bx - 1, by), (bx - 3, by - h // 3), (bx, by)], fill=rgba(sh(crystal, 0.7), alpha))
        glow_dot(g, bx + w // 2, by - h // 2, 2.6 + w * 0.25, crystal, (1.0 if flare else 0.55) * alpha / 255)

    def dissolve_soft(im, amount, col):
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                if px[x, y][3] == 0:
                    continue
                v = ((x * 73856093) ^ (y * 19349663) ^ (29 * 83492791)) % 1000 / 100.0
                v += (y / im.height - 0.5) * 2.0
                if v < amount:
                    px[x, y] = (0, 0, 0, 0)
                elif v < amount + 0.5:
                    px[x, y] = col + (200,)
        return im

    def titan(p, alpha=255, rubble=0, flare=False, fist=0, diss=0):
        im = new(fw, fh)
        g = new(fw, fh)
        d = ImageDraw.Draw(im)
        if rubble:
            m = mask(fw, fh, lambda dd: dd.polygon([(8, 51), (13, 45), (20, 47), (26, 44), (33, 46), (40, 51)],
                                                   fill=(255, 255, 255, 255)))
            lit(im, m, stone, 24, 48, 16, 7, alpha)
            d = ImageDraw.Draw(im)
            crystal_cluster(d, g, 14, 48, 3, 7, alpha, flare)
            crystal_cluster(d, g, 25, 47, 4, 9, alpha, flare)
            crystal_cluster(d, g, 33, 48, 3, 6, alpha, flare)
            d.point((11, 49), fill=rgba(stone_d, alpha))
            d.point((37, 49), fill=rgba(stone_d, alpha))
            out = finish(im, g)
            if diss:
                out = dissolve_soft(out, diss, crystal)
            return fade(out, alpha)

        s2 = gs.skel(p, dict(leg=12, torso=16), cx=24, ground=51)
        hx, hy = s2["hip"]
        nx, ny = s2["neck"]
        # legs: thick stone columns, volume lit
        for side, col in (("l", stone_d), ("r", stone)):
            a = (hx + (-3 if side == "l" else 3), hy)
            b = s2[side + "knee"]
            c = s2[side + "foot"]
            b = (b[0] + (-2 if side == "l" else 2), b[1])
            c = (c[0] + (-2 if side == "l" else 2), c[1])
            m = mask(fw, fh, lambda dd, a=a, b=b, c=c: dd.line([a, b, c], fill=(255, 255, 255, 255), width=7))
            lit(im, m, col, (a[0] + b[0] + c[0]) / 3, hy - 4, 6, 14, alpha)
            d = ImageDraw.Draw(im)
            d.rectangle((c[0] - 3, c[1] - 1, c[0] + 3, c[1]), fill=rgba(sh(col, 0.55), alpha))
        d = ImageDraw.Draw(im)
        # torso: a hewn boulder, volume lit
        m = mask(fw, fh, lambda dd: dd.polygon([(hx - 12, hy + 3), (hx + 12, hy + 3), (nx + 10, ny), (nx - 10, ny)],
                                               fill=(255, 255, 255, 255)))
        lit(im, m, stone, nx, (ny + hy) / 2 + 2, 11, 11, alpha)
        d = ImageDraw.Draw(im)
        for k in range(3):
            y = ny + 4 + k * 4
            d.line((nx - 9 + k, y, nx + 9 - k % 2, y), fill=rgba(sh(stone, 0.7), alpha))
        d.line((nx - 6, ny + 2, nx - 3, ny + 7), fill=rgba(sh(stone, 0.6), alpha))
        d.line((nx + 5, hy, nx + 7, hy - 3), fill=rgba(sh(stone, 0.6), alpha))
        d.point((nx - 7, ny + 8), fill=rgba(sh(stone, 1.3), alpha))
        # chest rune that flares with the phases
        rune_col = (200, 255, 255, alpha) if flare else rgba(sh(stone, 1.2), alpha)
        d.line((nx - 1, ny + 5, nx - 1, ny + 9), fill=rune_col)
        d.point((nx - 3, ny + 7), fill=rune_col)
        d.point((nx + 1, ny + 7), fill=rune_col)
        if flare:
            glow_dot(g, nx - 1, ny + 7, 3.2, crystal, 0.8)
        # crystal growths along the back and shoulders
        for bx, by, w, h in ((nx - 13, ny + 2, 4, 10), (nx + 10, ny + 1, 4, 9), (nx - 6, ny - 2, 5, 12),
                             (nx + 2, ny - 1, 5, 10), (hx - 9, hy + 4, 3, 7), (hx + 8, hy + 5, 3, 6)):
            crystal_cluster(d, g, bx, by, w, h, alpha, flare)
        # arms + huge fists
        for side, col in (("l", stone_d), ("r", stone)):
            shd = s2["shoulder"]
            hnd = s2[side + "hand"]
            m = mask(fw, fh, lambda dd, a=shd, b=hnd: dd.line([a, b], fill=(255, 255, 255, 255), width=6))
            lit(im, m, col, (shd[0] + hnd[0]) / 2, (shd[1] + hnd[1]) / 2, 5, 8, alpha)
            d = ImageDraw.Draw(im)
            lift = fist if side == "r" else 0
            m = mask(fw, fh, lambda dd, b=hnd, l=lift: dd.rectangle((b[0] - 4, b[1] - 3 - l, b[0] + 4, b[1] + 3),
                                                                    fill=(255, 255, 255, 255)))
            lit(im, m, col, hnd[0], hnd[1], 5, 4, alpha)
            d = ImageDraw.Draw(im)
            d.point((hnd[0] - 2, hnd[1] - 2 - lift), fill=rgba(sh(col, 1.35), alpha))
        # head: a low rock with a glowing eye slit and a crown shard
        hx2, hy2 = s2["head"]
        m = mask(fw, fh, lambda dd: dd.rectangle((hx2 - 5, hy2 - 6, hx2 + 5, hy2 + 2), fill=(255, 255, 255, 255)))
        lit(im, m, stone, hx2, hy2 - 2, 6, 5, alpha)
        d = ImageDraw.Draw(im)
        slit = (215, 255, 255, alpha) if flare else rgba(crystal, alpha)
        d.rectangle((hx2 - 4, hy2 - 3, hx2 + 4, hy2 - 2), fill=slit)
        d.point((hx2 - 3, hy2 + 1), fill=rgba(sh(stone, 0.6), alpha))
        d.point((hx2 + 3, hy2 + 1), fill=rgba(sh(stone, 0.6), alpha))
        crystal_cluster(d, g, hx2 - 2, hy2 - 5, 4, 7, alpha, flare)
        glow_dot(g, hx2, hy2 - 3, 4.5, crystal, (1.0 if flare else 0.55) * alpha / 255)
        # faint crystal motes around the titan
        for _ in range(3):
            x = rng.randint(10, 38)
            y = rng.randint(10, 46)
            if im.getpixel((x, y))[3] == 0 and g.getpixel((x, y))[3] == 0:
                g.putpixel((x, y), (170, 240, 240, int(150 * alpha / 255)))
        out = finish(im, g)
        if diss:
            out = dissolve_soft(out, diss, crystal)
        return fade(out, alpha)

    def fn(name, i, n):
        if name == "idle":
            return titan(P(by=[0, 0, 1, 1][i]), flare=(i == 3))
        if name == "walk":
            lx = [-4, -2, 2, 4, 2, -2][i]
            return titan(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i]))
        if name == "windup":
            return titan(P(lean=-1 - i // 2, crouch=1 + i, ra=(-4, -12 - i * 3)), flare=True, fist=i)
        if name == "attack":
            return titan(P(lean=5, lf=(-6, 0), rf=(8, 0), crouch=2, ra=[(10, -6), (13, 0), (11, 6)][i]), flare=True, fist=[3, 0, 0][i])
        if name == "hurt":
            return titan(P(lean=-4, by=2))
        if i < 2:
            return titan(P(crouch=2 + i * 3, by=1 + i), diss=0.25 * i)
        return titan(P(), rubble=1, diss=0.2 * (i - 2), flare=(i == 2))

    gs.render_sheet(lay, fn, "sprites/bosses/crystal_titan_sheet.png", do_outline=False)
    lay.write_tres()


def main():
    os.makedirs(OUT, exist_ok=True)
    ashen_king()
    crystal_titan()
    print("deep bosses drawn")


if __name__ == "__main__":
    main()
