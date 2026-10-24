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
    fw, fh = 48, 48
    lay = gs.monster_layout("ashen_king_layout", fw, fh, (24, 48), counts={"windup": 3, "attack": 3, "death": 6})
    race = dict(leg=13, torso=15)
    rng = random.Random(11)

    def crown(d, cx, top, alpha):
        dark_iron = rgba(IRON, alpha)
        d.rectangle((cx - 6, top + 4, cx + 6, top + 6), fill=dark_iron)
        d.line((cx - 6, top + 4, cx + 6, top + 4), fill=rgba(sh(IRON, 1.4), alpha))
        for k, x in enumerate((cx - 6, cx - 3, cx, cx + 3, cx + 6)):
            h = 5 if k % 2 == 0 else 3
            d.polygon([(x - 1, top + 4), (x, top + 4 - h), (x + 1, top + 4)], fill=dark_iron)
            d.point((x, top + 3 - h), fill=rgba(EMBER, alpha))
        for x in (cx - 3, cx, cx + 3):
            d.point((x, top + 5), fill=rgba(EMBER_HOT, alpha))

    def king(p, arm_ang=40, alpha=255, ash=0, diss=0, flare=False):
        im = new(fw, fh)
        g = new(fw, fh)
        d = ImageDraw.Draw(im)
        bone = rgba(ASH_BONE, alpha)
        if ash:  # death pile: a mound of ash with embers and the crown
            d.ellipse((14, 38, 34, 47), fill=rgba((96, 86, 88), alpha))
            d.ellipse((18, 40, 30, 46), fill=rgba((120, 108, 108), alpha))
            crown(d, 24, 32, alpha)
            for x, y in ((16, 42), (22, 44), (29, 41), (33, 44), (24, 39)):
                d.point((x, y), fill=rgba(EMBER, alpha))
            glow(g, 24, 43, 6, EMBER, 0.8 * alpha / 255)
            return im, g
        s = gs.skel(p, race, cx=24, ground=47)
        # smouldering ash cape behind
        d.polygon([(s["neck"][0] - 9, s["neck"][1]), (s["hip"][0] - 11, s["hip"][1] + 10),
                   (s["hip"][0] - 4, s["hip"][1] + 6), (s["neck"][0] - 3, s["neck"][1] + 2)],
                  fill=rgba((70, 60, 62), alpha))
        for side, col in (("l", sh(ASH_BONE, 0.72)), ("r", ASH_BONE)):
            c = rgba(col, alpha)
            d.line([s["hip"], s[side + "knee"], s[side + "foot"]], fill=c, width=3)
        # ribs with ember cracks
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        for k in range(3):
            y = ny + 3 + k * 3
            d.line((nx - 5, y, nx + 5, y), fill=bone)
            if k != 1:
                d.point((nx + (k * 2 - 1), y + 1), fill=rgba(EMBER, alpha) if flare else rgba((120, 80, 50), alpha))
        d.line([s["shoulder"], s["lhand"]], fill=rgba(sh(ASH_BONE, 0.72), alpha), width=3)
        # skull: ashen, cracks with embers, charred jaw
        hx2, hy2 = s["head"]
        d.ellipse((hx2 - 6, hy2 - 6, hx2 + 6, hy2 + 5), fill=bone)
        d.line((hx2 - 5, hy2 - 3, hx2 - 2, hy2 - 1), fill=rgba(sh(ASH_BONE, 0.5), alpha))
        d.point((hx2 - 3, hy2 - 2), fill=rgba(EMBER, alpha))
        dark = (28, 18, 20, alpha)
        d.rectangle((hx2 - 4, hy2 - 2, hx2 - 2, hy2), fill=dark)
        d.rectangle((hx2 + 2, hy2 - 2, hx2 + 4, hy2), fill=dark)
        eye = EMBER_HOT if flare else EMBER
        d.point((hx2 - 3, hy2 - 1), fill=rgba(eye, alpha))
        d.point((hx2 + 3, hy2 - 1), fill=rgba(eye, alpha))
        d.line((hx2 - 3, hy2 + 4, hx2 + 4, hy2 + 4), fill=dark)
        crown(d, hx2, hy2 - 6, alpha)
        glow(g, hx2 - 3, hy2 - 1, 3, EMBER, (1.0 if flare else 0.6) * alpha / 255)
        glow(g, hx2 + 3, hy2 - 1, 3, EMBER, (1.0 if flare else 0.6) * alpha / 255)
        # right arm + great blade of charred iron
        d.line([s["shoulder"], s["rhand"]], fill=bone, width=3)
        rx, ry = s["rhand"]
        a = math.radians(arm_ang)
        ca, sa = math.cos(a), math.sin(a)
        steel = rgba((96, 84, 84), alpha)
        d.line((rx, ry, rx + 22 * ca, ry + 22 * sa), fill=steel, width=4)
        d.line((rx + 2 * ca, ry + 2 * sa - 1, rx + 20 * ca, ry + 20 * sa - 1), fill=rgba(sh((96, 84, 84), 1.35), alpha))
        for t in (8, 13, 18):  # glowing cracks down the blade
            pt = (rx + t * ca, ry + t * sa)
            d.point(pt, fill=rgba(EMBER, alpha))
            glow(g, pt[0], pt[1], 2.2, EMBER, 0.55 * alpha / 255)
        d.line((rx - 4 * sa, ry + 4 * ca, rx + 4 * sa, ry - 4 * ca), fill=rgba(IRON, alpha), width=2)
        # drifting embers
        sparks(g, rng, 3 + (2 if flare else 0), (12, 8, 36, 44), EMBER if flare else (200, 110, 60))
        return im, g

    def composite(im, g):
        out = im.copy()
        out.alpha_composite(g)
        return out

    def fn(name, i, n):
        if name == "idle":
            im, g = king(P(by=[0, 0, 1, 1][i], ra=(4, 10)), 70, flare=(i == 3))
        elif name == "walk":
            lx = [-5, -2, 2, 5, 2, -2][i]
            im, g = king(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(4, 10)), 60)
        elif name == "windup":
            im, g = king(P(lean=-2 - i, crouch=i, ra=(-3, -10 - i * 2)), -120 - i * 12, flare=True)
        elif name == "attack":
            im, g = king(P(lean=4, lf=(-5, 0), rf=(7, 0), crouch=2, ra=[(8, -4), (12, 2), (10, 8)][i]), [-30, 25, 70][i], flare=True)
        elif name == "hurt":
            im, g = king(P(lean=-4, by=2, ra=(4, 6)), 80)
        elif i < 2:
            im, g = king(P(crouch=3 + i * 3, by=2 + i, ra=(7, 8)), 90)
        else:
            im, g = king(P(), ash=1, alpha=255 - max(0, i - 2) * 30)
        return composite(im, g)

    gs.render_sheet(lay, fn, "sprites/bosses/ashen_king_sheet.png", do_outline=False)
    lay.write_tres()


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
