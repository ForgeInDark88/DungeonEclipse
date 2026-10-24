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

from PIL import ImageDraw

import gen_sheets as gs
from gen_placeholders import new, shade

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
    fw, fh = 48, 52
    lay = gs.monster_layout("crystal_titan_layout", fw, fh, (24, 52), counts={"windup": 3, "attack": 3, "death": 6})
    rng = random.Random(29)

    def titan(p, alpha=255, rubble=0, flare=False, fist=0):
        im = new(fw, fh)
        g = new(fw, fh)
        d = ImageDraw.Draw(im)
        stone = rgba(TEAL_STONE, alpha)
        stone_d = rgba(TEAL_DARK, alpha)
        stone_l = rgba(sh(TEAL_STONE, 1.3), alpha)
        if rubble:
            for bx, bw in ((11, 11), (23, 9), (33, 7)):
                d.rectangle((bx, 45, bx + bw, 51), fill=stone_d)
                d.rectangle((bx + 1, 45, bx + bw - 1, 50), fill=stone)
            for x, y in ((15, 47), (27, 45), (35, 48)):
                d.point((x, y), fill=rgba(CRYSTAL, alpha))
            glow(g, 24, 48, 7, CRYSTAL, 0.7 * alpha / 255)
            return im, g
        s = gs.skel(p, dict(leg=12, torso=16), cx=24, ground=51)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # thick stone legs
        for side, col in (("l", stone_d), ("r", stone)):
            c = rgba(col, alpha)
            d.line([s["hip"], s[side + "knee"], s[side + "foot"]], fill=c, width=6)
            d.line([(s[side + "knee"][0] - 2, s[side + "knee"][1]), (s[side + "foot"][0] - 2, s[side + "foot"][1])],
                   fill=rgba(sh(col, 0.7), alpha))
        # massive torso block, hewn shading
        d.polygon([(hx - 11, hy + 2), (hx + 11, hy + 2), (nx + 9, ny), (nx - 9, ny)], fill=stone)
        d.line((nx - 7, ny + 3, nx + 7, ny + 3), fill=stone_l)
        d.line((hx - 8, hy, hx - 5, hy + 1), fill=stone_d)
        for k in range(3):  # strata
            y = ny + 4 + k * 4
            d.line((nx - 8 + k % 2, y, nx + 8 - k % 2, y), fill=stone_d)
        # crystal growths on the back and shoulders
        for bx, by, bw, bh in ((nx - 11, ny - 3, 4, 9), (nx + 9, ny - 1, 3, 7), (nx - 4, ny - 6, 5, 11), (nx + 4, ny - 4, 4, 8)):
            d.polygon([(bx, by + bh), (bx + bw // 2, by), (bx + bw, by + bh)], fill=rgba(CRYSTAL, alpha))
            d.line((bx + bw // 2, by, bx + bw // 2, by + bh), fill=rgba((255, 255, 255), alpha))
            glow(g, bx + bw // 2, by + bh // 2, 3.4, CRYSTAL, (0.9 if flare else 0.55) * alpha / 255)
        # arms: huge fists
        d.line([s["shoulder"], s["lhand"]], fill=stone_d, width=5)
        d.line([s["shoulder"], s["rhand"]], fill=stone, width=5)
        for hnd, col in ((s["lhand"], stone_d), (s["rhand"], stone)):
            d.rectangle((hnd[0] - 4, hnd[1] - 3 - (fist if col is stone else 0), hnd[0] + 4, hnd[1] + 3), fill=rgba(col, alpha))
            d.line((hnd[0] - 3, hnd[1] - 2, hnd[0] + 3, hnd[1] - 2), fill=rgba(sh(col, 1.35), alpha))
        # head: low rock with a glowing eye slit
        hx2, hy2 = s["head"]
        d.rectangle((hx2 - 5, hy2 - 6, hx2 + 5, hy2 + 2), fill=stone)
        d.rectangle((hx2 - 5, hy2 - 6, hx2 + 5, hy2 - 6), fill=stone_l)
        slit = (200, 255, 255) if flare else CRYSTAL
        d.rectangle((hx2 - 4, hy2 - 3, hx2 + 4, hy2 - 2), fill=rgba(slit, alpha))
        glow(g, hx2, hy2 - 3, 5, CRYSTAL, (1.0 if flare else 0.6) * alpha / 255)
        d.point((hx2 - 3, hy2), fill=stone_d)
        d.point((hx2 + 3, hy2), fill=stone_d)
        sparks(g, rng, 3, (12, 10, 36, 48), (170, 240, 240))
        return im, g

    def composite(im, g):
        out = im.copy()
        out.alpha_composite(g)
        return out

    def fn(name, i, n):
        if name == "idle":
            im, g = titan(P(by=[0, 0, 1, 1][i]), flare=(i == 3))
        elif name == "walk":
            lx = [-4, -2, 2, 4, 2, -2][i]
            im, g = titan(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i]))
        elif name == "windup":
            im, g = titan(P(lean=-1 - i // 2, crouch=1 + i, ra=(-4, -12 - i * 3)), flare=True, fist=i)
        elif name == "attack":
            im, g = titan(P(lean=5, lf=(-6, 0), rf=(8, 0), crouch=2, ra=[(10, -6), (13, 0), (11, 6)][i]), flare=True, fist=[3, 0, 0][i])
        elif name == "hurt":
            im, g = titan(P(lean=-4, by=2))
        elif i < 2:
            im, g = titan(P(crouch=2 + i * 3, by=1 + i))
        else:
            im, g = titan(P(), rubble=1, alpha=255 - max(0, i - 2) * 30)
        return composite(im, g)

    gs.render_sheet(lay, fn, "sprites/bosses/crystal_titan_sheet.png", do_outline=False)
    lay.write_tres()


def main():
    os.makedirs(OUT, exist_ok=True)
    ashen_king()
    crystal_titan()
    print("deep bosses drawn")


if __name__ == "__main__":
    main()
