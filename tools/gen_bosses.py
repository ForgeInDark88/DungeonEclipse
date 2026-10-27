#!/usr/bin/env python3
"""Detailed boss sprite sheets (pixel art): the Bone King, the Flame Witch
and the Illusionist.

Frame sizes and animation layouts stay the same (hitboxes and attack points
in data/bosses/* stay valid); the drawing gets volume shading, materials
(bone, rusted plate, cloth, fire), small details and glows added after the
outline (eyes, runes, flames).
Called from gen_mechanics.py.  Run:  python3 tools/gen_bosses.py
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

import gen_placeholders as gp
import gen_sheets as gs
from gen_monsters import blank, fade, lit, mask, rgba, sh, FULL
from gen_structures import finish, glow_dot

A = gp.A
P = gs.P


def dissolve(im, amount, seed=7, color=None):
    """Death: pixels crumble away in a scattered (hashed) pattern, the top
    first, leaving sparks / ash at the edge."""
    if amount <= 0:
        return im
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            v = ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) % 1000 / 100.0
            v += (y / h - 0.5) * 2.0  # lower parts last
            if v < amount:
                px[x, y] = (0, 0, 0, 0)
            elif color and v < amount + 0.6:
                px[x, y] = color
    return im


def render(lay, fn, rel):
    gs.render_sheet(lay, fn, rel, do_outline=False)
    lay.write_tres()


def thick_line(d, a, b, col, w=2, hi=None, lo=None):
    """A limb / bone: body colour, lit upper edge, shaded lower edge."""
    d.line((a[0], a[1], b[0], b[1]), fill=col, width=w)
    if hi:
        d.line((a[0], a[1] - (w // 2), b[0], b[1] - (w // 2)), fill=hi)
    if lo:
        d.line((a[0] + 1, a[1] + (w - 1) // 2 + 0, b[0] + 1, b[1] + (w - 1) // 2), fill=lo)


def post(im, g, alpha=255, diss=0, seed=7, spark=None):
    out = finish(im, g)
    if diss:
        dissolve(out, diss, seed, spark)
    return fade(out, alpha)


# ================================================================ bone king
def bone_king():
    fw, fh = 48, 48
    lay = gs.monster_layout("bone_king_layout", fw, fh, (24, 48), counts={"windup": 3, "attack": 3, "death": 6})
    bone = (232, 226, 204)
    plate = (122, 96, 84)  # rusted iron
    royal = (92, 34, 96)
    gold = (232, 186, 60)
    race = dict(leg=13, torso=15)

    def crown(d, g, cx, top, alpha=255):
        # band with gems and five points
        d.rectangle((cx - 6, top + 4, cx + 6, top + 6), fill=rgba(gold, alpha))
        d.line((cx - 6, top + 4, cx + 6, top + 4), fill=rgba(sh(gold, 1.3), alpha))
        d.line((cx - 6, top + 6, cx + 6, top + 6), fill=rgba(sh(gold, 0.6), alpha))
        for k, x in enumerate((cx - 6, cx - 3, cx, cx + 3, cx + 6)):
            h = 4 if k % 2 == 0 else 2
            d.polygon([(x - 1, top + 4), (x, top + 4 - h), (x + 1, top + 4)], fill=rgba(gold, alpha))
            d.point((x, top + 4 - h), fill=(255, 245, 190, alpha))
        for x, c in ((cx - 3, (220, 30, 40)), (cx, (60, 200, 255)), (cx + 3, (220, 30, 40))):
            d.point((x, top + 5), fill=rgba(c, alpha))
        d.point((cx - 5, top + 5), fill=rgba(sh(gold, 1.4), alpha))

    def skull(d, im, g, sx, sy, eye, alpha, jaw=0):
        m = mask(fw, fh, lambda dd: (dd.ellipse((sx - 6, sy - 6, sx + 6, sy + 4), fill=FULL),
                                     dd.rectangle((sx - 3, sy + 2, sx + 5, sy + 6 + jaw), fill=FULL)))
        lit(im, m, bone, sx - 2, sy - 3, 7, 6, alpha)
        d = ImageDraw.Draw(im)
        dark = (34, 20, 24, alpha)
        # deep sockets with embers, nose cavity, teeth
        d.rectangle((sx - 1, sy - 2, sx + 1, sy + 0), fill=dark)
        d.rectangle((sx + 3, sy - 2, sx + 5, sy + 0), fill=dark)
        d.point((sx + 0, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 4, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 2, sy + 1), fill=dark)
        d.point((sx + 3, sy + 2), fill=dark)
        d.line((sx - 2, sy + 4 + jaw // 2, sx + 5, sy + 4 + jaw // 2), fill=dark)
        for tx in range(sx - 1, sx + 5, 2):
            d.point((tx, sy + 3), fill=rgba(sh(bone, 1.1), alpha))
            d.point((tx, sy + 5 + jaw), fill=rgba(sh(bone, 0.9), alpha))
        d.line((sx - 4, sy - 4, sx - 2, sy - 2), fill=rgba(sh(bone, 0.55), alpha))  # crack
        d.point((sx - 5, sy + 1), fill=rgba(sh(bone, 0.6), alpha))
        glow_dot(g, sx + 0, sy - 1, 2.6, eye, 0.9 * alpha / 255)
        glow_dot(g, sx + 4, sy - 1, 2.6, eye, 0.9 * alpha / 255)
        return d

    def sword(d, g, rx, ry, ang, alpha, runes=False):
        a = math.radians(ang)
        ca, sa = math.cos(a), math.sin(a)
        nx, ny = -sa, ca
        L = 22
        tip = (rx + L * ca, ry + L * sa)
        base = (rx + 3 * ca, ry + 3 * sa)
        steel = (168, 166, 178)
        # blade: 3px, lit edge, dark fuller, notches
        d.polygon([(base[0] + nx * 1.5, base[1] + ny * 1.5), (tip[0] + nx * 0.5, tip[1] + ny * 0.5), (tip[0] + ca, tip[1] + sa),
                   (tip[0] - nx * 0.5, tip[1] - ny * 0.5), (base[0] - nx * 1.5, base[1] - ny * 1.5)], fill=rgba(steel, alpha))
        d.line((base[0] - nx, base[1] - ny, tip[0] - nx * 0.4, tip[1] - ny * 0.4), fill=rgba(sh(steel, 1.35), alpha))
        d.line((base[0] + ca * 2, base[1] + sa * 2, rx + (L - 6) * ca, ry + (L - 6) * sa), fill=rgba(sh(steel, 0.62), alpha))
        for t in (9, 15):
            d.point((rx + t * ca + nx * 1.5, ry + t * sa + ny * 1.5), fill=rgba((120, 70, 44), alpha))  # rust nick
        if runes:
            for t in (7, 11, 15, 19):
                p = (rx + t * ca, ry + t * sa)
                d.point(p, fill=(150, 240, 255, alpha))
                glow_dot(g, p[0], p[1], 2.5, (110, 210, 255), 0.7)
        # crossguard, grip, pommel
        gx, gy = nx * 4, ny * 4
        d.line((rx + ca * 2 + gx, ry + sa * 2 + gy, rx + ca * 2 - gx, ry + sa * 2 - gy), fill=rgba(gold, alpha), width=2)
        d.point((rx + ca * 2 + gx, ry + sa * 2 + gy), fill=(255, 240, 180, alpha))
        d.point((rx + ca * 2, ry + sa * 2), fill=(220, 30, 40, alpha))
        d.line((rx, ry, rx - 3 * ca, ry - 3 * sa), fill=(80, 50, 40, alpha), width=2)
        d.point((rx - 4 * ca, ry - 4 * sa), fill=rgba(gold, alpha))

    def king(p, sword_ang=40, alpha=255, pile=0, eye=(255, 70, 30), runes=False, cape=0, diss=0):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            # bones, plate and the crown in a heap
            for k in range(pile + 4):
                x = 5 + (k * 7) % 36
                y = 46 - (k % 3)
                thick_line(d, (x, y), (x + 6, y - 1 + (k % 2) * 2), rgba(bone, alpha), 2, rgba(sh(bone, 1.25), alpha))
                d.point((x, y), fill=rgba(sh(bone, 1.3), alpha))
            pm = mask(fw, fh, lambda dd: dd.chord((12, 38, 30, 52), 180, 360, fill=FULL))
            lit(im, pm, plate, 18, 40, 9, 6, alpha)
            sk = mask(fw, fh, lambda dd: dd.ellipse((26, 37, 35, 46), fill=FULL))
            lit(im, sk, bone, 29, 39, 5, 5, alpha)
            d.rectangle((29, 40, 30, 41), fill=(34, 20, 24, alpha))
            d.rectangle((32, 40, 33, 41), fill=(34, 20, 24, alpha))
            crown(d, g, 38 - min(pile, 4), 38, alpha)
            sword(d, g, 6, 44, -8, alpha)
            return post(im, g, alpha)
        s = gs.skel(p, race, cx=24, ground=47)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # tattered cape behind
        sway = cape
        cm = mask(fw, fh, lambda dd: dd.polygon([(nx - 7, ny + 1), (nx + 3, ny + 1), (hx - 2 + sway, 44), (hx - 6 + sway, 42),
                                                 (hx - 9 + sway, 45), (hx - 12 + sway, 41), (hx - 14 + sway, 43)], fill=FULL))
        lit(im, cm, royal, nx - 6, ny + 6, 8, 14, alpha, flat=0.15)
        d = ImageDraw.Draw(im)
        d.line((nx - 6, ny + 2, hx - 12 + sway, 41), fill=rgba(sh(royal, 0.6), alpha))
        # legs: femur, kneecap, greave and sabaton
        for side in ("l", "r"):
            back = side == "l"
            col = rgba(sh(bone, 0.78 if back else 1.0), alpha)
            k, f = s[side + "knee"], s[side + "foot"]
            thick_line(d, (hx + (-1 if back else 1), hy), k, col, 2, rgba(sh(bone, 1.2 if not back else 0.9), alpha))
            gm = sh(plate, 0.75 if back else 1.0)
            d.line((k[0], k[1] + 1, f[0], f[1] - 2), fill=rgba(gm, alpha), width=3)
            d.line((k[0] - 1, k[1] + 1, f[0] - 1, f[1] - 2), fill=rgba(sh(gm, 1.35), alpha))
            d.ellipse((k[0] - 2, k[1] - 1, k[0] + 1, k[1] + 2), fill=rgba(sh(gm, 1.1), alpha))
            d.point((k[0] - 1, k[1]), fill=rgba(sh(gm, 1.6), alpha))
            d.polygon([(f[0] - 2, f[1] - 2), (f[0] + 4, f[1] - 1), (f[0] + 4, f[1]), (f[0] - 2, f[1])], fill=rgba(sh(gm, 0.9), alpha))
            d.point((f[0] + 3, f[1] - 1), fill=rgba(sh(gm, 1.4), alpha))
        # pelvis and royal tabard with gold trim
        d.line((hx - 4, hy, hx + 4, hy), fill=rgba(bone, alpha), width=2)
        tm = mask(fw, fh, lambda dd: dd.polygon([(hx - 4, hy - 1), (hx + 4, hy - 1), (hx + 3, hy + 9), (hx, hy + 7), (hx - 3, hy + 9)], fill=FULL))
        lit(im, tm, royal, hx - 1, hy + 2, 4, 6, alpha, flat=0.2)
        d = ImageDraw.Draw(im)
        d.line((hx - 3, hy + 8, hx - 1, hy + 7), fill=rgba(gold, alpha))
        d.line((hx + 1, hy + 7, hx + 3, hy + 8), fill=rgba(gold, alpha))
        d.point((hx, hy + 3), fill=rgba(gold, alpha))
        # back arm
        thick_line(d, s["shoulder"], s["lhand"], rgba(sh(bone, 0.75), alpha), 2)
        d.ellipse((s["lhand"][0] - 1, s["lhand"][1] - 1, s["lhand"][0] + 2, s["lhand"][1] + 2), fill=rgba(sh(plate, 0.7), alpha))
        # breastplate: rusted iron with rivets and a gold skull emblem
        bm = mask(fw, fh, lambda dd: dd.polygon([(hx - 6, hy), (hx + 6, hy), (nx + 8, ny + 1), (nx + 6, ny - 1), (nx - 6, ny - 1), (nx - 8, ny + 1)], fill=FULL))
        lit(im, bm, plate, nx - 2, ny + 4, 8, 9, alpha)
        d = ImageDraw.Draw(im)
        for k in range(3):
            y = ny + 6 + k * 3
            d.line((nx - 5 + k, y, nx + 5 - k, y), fill=rgba(sh(plate, 0.62), alpha))
        for x, y in ((nx - 6, ny + 1), (nx + 6, ny + 1), (hx - 5, hy - 1), (hx + 5, hy - 1)):
            d.point((x, y), fill=rgba(sh(plate, 1.7), alpha))
        d.ellipse((nx - 2, ny + 2, nx + 2, ny + 5), fill=rgba(gold, alpha))
        d.point((nx - 1, ny + 3), fill=(40, 20, 20, alpha))
        d.point((nx + 1, ny + 3), fill=(40, 20, 20, alpha))
        d.point((nx - 1, ny + 2), fill=rgba(sh(gold, 1.4), alpha))
        d.point((nx + 4, ny + 9), fill=rgba((150, 80, 40), alpha))  # rust streak
        d.line((nx + 4, ny + 10, nx + 4, ny + 12), fill=rgba((140, 74, 40), alpha))
        # ribs peeking out under the plate
        for k in range(2):
            d.arc((hx - 4, hy - 4 + k * 2, hx + 4, hy + 1 + k * 2), 20, 160, fill=rgba(sh(bone, 0.85), alpha))
        # skull and crown
        sx, sy = int(s["head"][0]), int(s["head"][1]) - 2
        skull(d, im, g, sx, sy, eye, alpha, jaw=1 if runes else 0)
        d = ImageDraw.Draw(im)
        crown(d, g, sx, sy - 10, alpha)
        # pauldrons: domed with a spike
        for side, f in ((-1, 0.8), (1, 1.0)):
            px_, py_ = nx + side * 6, ny + 1
            pm = mask(fw, fh, lambda dd: dd.chord((px_ - 4, py_ - 3, px_ + 4, py_ + 5), 180, 360, fill=FULL))
            lit(im, pm, sh(plate, f)[:3], px_ - 1, py_ - 1, 4, 3, alpha)
            d = ImageDraw.Draw(im)
            d.line((px_ - 3, py_ + 1, px_ + 3, py_ + 1), fill=rgba(gold, alpha))
            d.polygon([(px_ - 1, py_ - 2), (px_ + side, py_ - 6), (px_ + 1, py_ - 2)], fill=rgba(sh(bone, 0.95), alpha))
        # sword arm, gauntlet and the greatsword
        rx, ry = s["rhand"]
        thick_line(d, s["shoulder"], (rx, ry), rgba(bone, alpha), 2, rgba(sh(bone, 1.25), alpha))
        sword(d, g, rx, ry, sword_ang, alpha, runes)
        d.ellipse((rx - 2, ry - 2, rx + 1, ry + 1), fill=rgba(sh(plate, 0.95), alpha))
        d.point((rx - 1, ry - 2), fill=rgba(sh(plate, 1.6), alpha))
        return post(im, g, alpha, diss)

    def fn(name, i, n):
        if name == "idle":
            return king(P(by=[0, 0, 1, 1][i], ra=(4, 10)), 70, cape=[0, 1, 1, 0][i])
        if name == "walk":
            lx = [-5, -2, 2, 5, 2, -2][i]
            return king(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(4, 10)), 60, cape=[1, 2, 2, 1, 0, 0][i])
        if name == "windup":
            return king(P(lean=-2 - i, crouch=i, ra=(-3, -10 - i * 2)), -120 - i * 12, eye=(120, 230, 255), runes=True, cape=2)
        if name == "attack":
            return king(P(lean=4, lf=(-5, 0), rf=(7, 0), crouch=2, ra=[(8, -4), (12, 2), (10, 8)][i]), [-30, 25, 70][i],
                        eye=(160, 240, 255), runes=i == 0, cape=-2)
        if name == "hurt":
            return king(P(lean=-4, by=2, ra=(4, 6)), 80, eye=(255, 255, 255), cape=2)
        if i < 2:
            return king(P(crouch=3 + i * 3, by=2 + i, ra=(7, 8)), 90, eye=(120, 40, 20), cape=1)
        return king(P(), pile=i, alpha=255 - (i - 2) * 25)

    render(lay, fn, "sprites/bosses/bone_king_sheet.png")


# =============================================================== flame witch
def flame_witch():
    fw, fh = 40, 44
    lay = gs.monster_layout("flame_witch_layout", fw, fh, (20, 44), "fly", {"idle": 4, "fly": 4, "windup": 4, "attack": 3, "death": 6})
    robe = (150, 32, 26)
    dark = (70, 14, 20)
    skin = (246, 216, 196)
    gold = (240, 190, 70)
    FIRE = ((150, 24, 10), (232, 70, 20), (255, 140, 30), (255, 214, 80), (255, 250, 210))

    def fire_tongue(d, x, y, h, phase, w=2):
        sway = math.sin(phase) * 1.5
        d.polygon([(x - w, y), (x + sway, y - h), (x + w, y)], fill=rgba(FIRE[1]))
        if h > 3:
            d.polygon([(x - w + 1, y), (x + sway * 0.6, y - h * 0.6), (x + w - 1, y)], fill=rgba(FIRE[3]))

    def witch(phase=0.0, hands_up=0, orb=0, alpha=255, diss=0, flash=False, scream=False):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        dy = int(round(math.sin(phase) * 2))
        # ember halo behind: ring of flames
        for k in range(8):
            a = phase * 0.7 + k * math.tau / 8
            x, y = 20 + math.cos(a) * 13, 13 + dy + math.sin(a) * 6
            behind = math.sin(a) < 0
            if behind:
                fire_tongue(d, x, y + 2, 4 + (k + int(phase * 2)) % 3, phase + k)
                glow_dot(g, x, y, 3, FIRE[2], 0.45)
        # flaming hair streaming up behind the head
        for k, x in enumerate((14, 16, 18, 20, 22, 24, 26)):
            h = 8 + (3 if k in (2, 4) else 0) + int(2 * math.sin(phase * 2 + k))
            fire_tongue(d, x, 9 + dy, h, phase * 2 + k, 2)
        glow_dot(g, 20, 4 + dy, 9, FIRE[2], 0.4)
        # robe: hem turns into fire
        rm = mask(fw, fh, lambda dd: dd.polygon([(14, 15 + dy), (26, 15 + dy), (31, 36 + dy), (9, 36 + dy)], fill=FULL))
        lit(im, rm, robe, 17, 20 + dy, 10, 14, flat=0.2)
        d = ImageDraw.Draw(im)
        for x in (15, 20, 25):
            d.line((x, 22 + dy, x + (x - 20) // 3, 35 + dy), fill=rgba(sh(robe, 0.7)))  # folds
        d.polygon([(17, 15 + dy), (23, 15 + dy), (22, 23 + dy), (18, 23 + dy)], fill=rgba(dark))  # bodice
        d.line((18, 16 + dy, 22, 22 + dy), fill=rgba(gold))
        d.line((22, 16 + dy, 18, 22 + dy), fill=rgba(gold))
        d.rectangle((15, 23 + dy, 25, 24 + dy), fill=rgba(gold))  # belt
        d.point((20, 23 + dy), fill=(255, 80, 40, 255))
        d.point((15, 23 + dy), fill=rgba(sh(gold, 1.4)))
        for k in range(9):
            x = 9 + k * 2.6
            h = 4 + (k * 5 + int(phase * 3)) % 5
            fire_tongue(d, x, 41 + dy, h + 3, phase * 3 + k * 1.3, 2)
            d.line((x - 1, 36 + dy, x + 1, 36 + dy), fill=rgba(FIRE[2]))
        d.line((9, 36 + dy, 31, 36 + dy), fill=rgba(FIRE[3]))
        glow_dot(g, 20, 38 + dy, 12, FIRE[2], 0.45)
        # face with a horned golden diadem
        fm = mask(fw, fh, lambda dd: dd.ellipse((16, 6 + dy, 24, 15 + dy), fill=FULL))
        lit(im, fm, skin, 18, 9 + dy, 4, 5)
        d = ImageDraw.Draw(im)
        d.line((16, 7 + dy, 24, 7 + dy), fill=rgba(gold))
        d.point((20, 6 + dy), fill=(255, 60, 40, 255))
        for x, s_ in ((16, -1), (24, 1)):
            d.line((x, 7 + dy, x + s_ * 2, 3 + dy), fill=rgba(sh(gold, 0.85)))
            d.point((x + s_ * 2, 3 + dy), fill=rgba(sh(gold, 1.4)))
        eye = (255, 255, 255, 255) if flash else (255, 210, 60, 255)
        d.line((18, 10 + dy, 18, 10 + dy), fill=eye)
        d.line((22, 10 + dy, 22, 10 + dy), fill=eye)
        d.point((17, 10 + dy), fill=(120, 30, 30, 255))
        d.point((23, 10 + dy), fill=(120, 30, 30, 255))
        glow_dot(g, 18, 10 + dy, 2, (255, 200, 60), 0.8)
        glow_dot(g, 22, 10 + dy, 2, (255, 200, 60), 0.8)
        d.line((19, 13 + dy, 21, 13 + dy), fill=(170, 40, 50, 255))  # lips
        if scream:
            d.rectangle((19, 13 + dy, 21, 14 + dy), fill=(60, 10, 14, 255))
        d.point((20, 11 + dy), fill=rgba(sh(skin, 0.8)))
        # arms with gold bracers; fireballs in the hands
        hy = 23 + dy - hands_up * 7
        for side in (-1, 1):
            sx0 = 20 + side * 6
            hx = 20 + side * 12
            d.line((sx0, 17 + dy, hx, hy), fill=rgba(sh(robe, 0.85 if side < 0 else 1.05)), width=2)
            mx, my = (sx0 + hx) / 2, (17 + dy + hy) / 2
            d.point((mx, my), fill=rgba(gold))
            d.point((hx, hy), fill=rgba(skin))
            if orb:
                r = orb
                om = mask(fw, fh, lambda dd: dd.ellipse((hx - r, hy - r - 1, hx + r, hy + r - 1), fill=FULL))
                lit(im, om, FIRE[2], hx - r / 3, hy - 1 - r / 3, r, r)
                d = ImageDraw.Draw(im)
                d.point((hx, hy - 1), fill=rgba(FIRE[4]))
                fire_tongue(d, hx, hy - r, r + 2, phase * 3 + side, max(1, r - 1))
                glow_dot(g, hx, hy - 1, r + 4, FIRE[2], 0.7)
            else:
                d.point((hx, hy - 1), fill=rgba(FIRE[2]))
                glow_dot(g, hx, hy - 1, 2.5, FIRE[2], 0.5)
        # front flames of the halo and floating embers
        for k in range(8):
            a = phase * 0.7 + k * math.tau / 8
            x, y = 20 + math.cos(a) * 13, 13 + dy + math.sin(a) * 6
            if math.sin(a) >= 0:
                fire_tongue(d, x, y + 2, 4 + (k + int(phase * 2)) % 3, phase + k)
                glow_dot(g, x, y, 3, FIRE[3], 0.5)
        for k in range(4):
            ex = 6 + (k * 9 + int(phase * 5)) % 28
            ey = 30 - ((k * 7 + int(phase * 8)) % 26)
            d.point((ex, ey), fill=rgba(FIRE[3]))
        return post(im, g, alpha, diss, 3, (255, 160, 60, 255))

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return witch(i * math.tau / 4)
        if name == "windup":
            return witch(i, hands_up=1, orb=1 + i)
        if name == "attack":
            return witch(i, hands_up=2, orb=[4, 2, 0][i], flash=i == 0, scream=True)
        if name == "hurt":
            return witch(0, flash=True, scream=True)
        return witch(i, diss=1 + i * 2 if i < 4 else 8 + (i - 4), alpha=255 - i * 30, scream=i < 2)

    render(lay, fn, "sprites/bosses/flame_witch_sheet.png")


# =============================================================== illusionist
def illusionist():
    fw, fh = 40, 46
    lay = gs.monster_layout("illusionist_layout", fw, fh, (20, 46), "fly", {"idle": 4, "fly": 4, "windup": 4, "attack": 3, "death": 6})
    cloak = (92, 42, 136)
    inner = (34, 16, 56)
    gold = (232, 192, 72)
    mask_c = (242, 238, 230)
    SUITS = ((200, 30, 50), (30, 30, 44))

    def card(d, x, y, k, tilt):
        w = 2 if abs(tilt) > 0.4 else 1  # edge-on cards look thinner
        d.rectangle((x - w, y - 3, x + w, y + 3), fill=(246, 240, 228, 255))
        d.rectangle((x - w, y - 3, x + w, y + 3), outline=(70, 46, 80, 255))
        d.point((x, y), fill=rgba(SUITS[k % 2]))
        if w == 2:
            d.point((x - 1, y - 2), fill=rgba(SUITS[k % 2]))
            d.point((x + 1, y + 2), fill=rgba(SUITS[k % 2]))

    def mage(phase=0.0, arms=0, glow=0, alpha=255, diss=0, flash=False, split=0):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        dy = int(round(math.sin(phase) * 2))
        cards = []
        for k in range(5):
            ang = phase * 0.8 + k * math.tau / 5
            x, y = 20 + math.cos(ang) * 16, 22 + dy + math.sin(ang) * 6
            cards.append((math.sin(ang), x, y, k, math.cos(ang)))
        for z, x, y, k, t in cards:
            if z < 0:
                card(d, x, y, k, t)
        # cloak with tattered hem, lined with stars
        cm = mask(fw, fh, lambda dd: dd.polygon([(12, 14 + dy), (28, 14 + dy), (33, 40 + dy), (29, 37 + dy), (26, 43 + dy), (22, 39 + dy),
                                                 (18, 43 + dy), (14, 38 + dy), (10, 41 + dy), (7, 39 + dy)], fill=FULL))
        lit(im, cm, cloak, 15, 20 + dy, 11, 16, flat=0.15)
        d = ImageDraw.Draw(im)
        d.polygon([(16, 16 + dy), (24, 16 + dy), (25, 38 + dy), (20, 36 + dy), (15, 38 + dy)], fill=rgba(inner))
        for sx_, sy_ in ((17, 25), (23, 22), (18, 32), (22, 34), (21, 28)):
            tw = (sx_ + sy_ + int(phase * 2)) % 3
            d.point((sx_, sy_ + dy), fill=(220, 200, 255, 255) if tw == 0 else (120, 90, 180, 255))
        for x in (11, 29):
            d.line((x, 18 + dy, x + (x - 20) // 4, 38 + dy), fill=rgba(sh(cloak, 0.7)))
        # gold trim and diamond pattern on the hem
        d.line((16, 16 + dy, 15, 38 + dy), fill=rgba(gold))
        d.line((24, 16 + dy, 25, 38 + dy), fill=rgba(sh(gold, 0.8)))
        for k in range(5):
            x = 9 + k * 5
            d.polygon([(x, 39 + dy), (x + 1, 38 + dy), (x + 2, 39 + dy), (x + 1, 40 + dy)], fill=rgba(gold))
        d.line((20, 17 + dy, 20, 35 + dy), fill=rgba(sh(gold, 0.9)))
        for yy in (21, 26, 31):
            d.point((20, yy + dy), fill=(255, 240, 160, 255))
            glow_dot(g, 20, yy + dy, 1.8, (255, 220, 120), 0.4)
        # tall collar
        d.polygon([(11, 15 + dy), (14, 3 + dy), (16, 13 + dy)], fill=rgba(sh(cloak, 1.25)))
        d.polygon([(29, 15 + dy), (26, 3 + dy), (24, 13 + dy)], fill=rgba(sh(cloak, 0.8)))
        d.line((12, 14 + dy, 14, 4 + dy), fill=rgba(gold))
        d.line((28, 14 + dy, 26, 4 + dy), fill=rgba(sh(gold, 0.7)))
        # hood and the two-faced mask
        hm = mask(fw, fh, lambda dd: dd.ellipse((14, 3 + dy, 26, 17 + dy), fill=FULL))
        lit(im, hm, sh(cloak, 0.9)[:3], 17, 6 + dy, 6, 7)
        d = ImageDraw.Draw(im)
        mm = mask(fw, fh, lambda dd: dd.ellipse((15, 5 + dy, 25, 16 + dy), fill=FULL))
        lit(im, mm, mask_c, 22, 8 + dy, 5, 6, flat=0.8)
        d = ImageDraw.Draw(im)
        d.chord((15, 5 + dy, 25, 16 + dy), 90, 270, fill=(30, 26, 40, 255))  # black half
        d.ellipse((15, 5 + dy, 25, 16 + dy), outline=rgba(gold))
        eye = (255, 255, 255, 255) if flash else (180, 100, 255, 255)
        d.point((18, 10 + dy), fill=eye)
        glow_dot(g, 18, 10 + dy, 2.5, (170, 90, 255), 0.85)
        d.line((21, 10 + dy, 22, 10 + dy), fill=(30, 25, 40, 255))  # closed laughing eye
        d.point((21, 9 + dy), fill=(30, 25, 40, 255))
        d.arc((20, 11 + dy, 24, 15 + dy), 20, 160, fill=(30, 25, 40, 255))  # smile
        d.line((17, 11 + dy, 17, 13 + dy), fill=(150, 200, 255, 255))  # tear on the dark half
        d.point((22, 8 + dy), fill=(200, 40, 70, 255))  # diamond mark
        # hands with violet magic
        hy = 24 + dy - arms * 6
        for side, x in ((-1, 7), (1, 33)):
            d.line((20 + side * 7, 18 + dy, x, hy), fill=rgba(sh(cloak, 0.9 if side < 0 else 1.05)), width=2)
            d.point((x, hy), fill=(230, 220, 240, 255))  # white glove
            if glow:
                gm = mask(fw, fh, lambda dd: dd.ellipse((x - glow, hy - glow, x + glow, hy + glow), fill=FULL))
                lit(im, gm, (190, 120, 255), x - glow / 3, hy - glow / 3, glow, glow)
                d = ImageDraw.Draw(im)
                d.point((x, hy), fill=(255, 240, 255, 255))
                glow_dot(g, x, hy, glow + 4, (170, 100, 255), 0.75)
            else:
                d.point((x + side, hy - 2), fill=(200, 150, 255, 255))
        for z, x, y, k, t in cards:
            if z >= 0:
                card(d, x, y, k, t)
        out = finish(im, g)
        if split:
            ghost = fade(out.copy(), 85)
            res = blank(fw, fh)
            res.alpha_composite(ghost, (-split, 0))
            res.alpha_composite(ghost, (split, 0))
            res.alpha_composite(out)
            out = res
        if diss:
            dissolve(out, diss, 5, (200, 140, 255, 255))
        return fade(out, alpha)

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return mage(i * math.tau / 4)
        if name == "windup":
            return mage(i, arms=1, glow=1 + i, split=i + 1)
        if name == "attack":
            return mage(i, arms=2, glow=[4, 2, 0][i], flash=i == 0)
        if name == "hurt":
            return mage(0, flash=True, split=2)
        return mage(i, diss=1 + i * 2 if i < 4 else 8 + (i - 4), alpha=255 - i * 30)

    render(lay, fn, "sprites/bosses/illusionist_sheet.png")
    mage(0.0).save(os.path.join(A, "sprites/bosses/illusionist.png"))


# ============================================================== ashen king
def ashen_king():
    """The Ashen King: a burned monarch in blackened plate split by magma
    veins, a molten heart behind the ribs of the cuirass, a skull crowned
    with iron spikes and live embers, a cape smouldering at the hem and a
    greatsword with a molten edge. Dies into a heap of ash, crown and sword."""
    fw, fh = 48, 48
    lay = gs.monster_layout("ashen_king_layout", fw, fh, (24, 48), counts={"windup": 3, "attack": 3, "death": 6})
    char = (62, 54, 58)  # blackened iron
    ash = (150, 140, 136)
    bone = (196, 184, 170)
    ember = (255, 130, 50)
    hot = (255, 214, 120)
    cloth = (50, 42, 48)
    race = dict(leg=13, torso=15)

    def crown(d, g, cx, top, alpha, flare):
        d.rectangle((cx - 6, top + 4, cx + 6, top + 6), fill=rgba(char, alpha))
        d.line((cx - 6, top + 4, cx + 6, top + 4), fill=rgba(sh(char, 1.6), alpha))
        d.line((cx - 6, top + 6, cx + 6, top + 6), fill=rgba(sh(char, 0.6), alpha))
        for k, x in enumerate((cx - 6, cx - 3, cx, cx + 3, cx + 6)):
            h = 5 if k % 2 == 0 else 3
            d.polygon([(x - 1, top + 4), (x, top + 4 - h), (x + 1, top + 4)], fill=rgba(char, alpha))
            d.point((x - 1, top + 4 - h // 2), fill=rgba(sh(char, 1.5), alpha))
            tip = (x, top + 3 - h)
            d.point(tip, fill=rgba(hot if flare else ember, alpha))
            glow_dot(g, tip[0], tip[1], 2.2, ember, (0.8 if flare else 0.5) * alpha / 255)
        for x in (cx - 3, cx + 3):
            d.point((x, top + 5), fill=rgba(ember, alpha))  # ember gems

    def sword(d, g, rx, ry, ang, alpha, flare):
        a = math.radians(ang)
        ca, sa = math.cos(a), math.sin(a)
        nx, ny = -sa, ca
        L = 23
        tip = (rx + L * ca, ry + L * sa)
        base = (rx + 3 * ca, ry + 3 * sa)
        steel = (84, 76, 80)
        d.polygon([(base[0] + nx * 1.8, base[1] + ny * 1.8), (tip[0] + nx * 0.6, tip[1] + ny * 0.6), (tip[0] + ca, tip[1] + sa),
                   (tip[0] - nx * 0.6, tip[1] - ny * 0.6), (base[0] - nx * 1.8, base[1] - ny * 1.8)], fill=rgba(steel, alpha))
        d.line((base[0] + ca * 2, base[1] + sa * 2, rx + (L - 5) * ca, ry + (L - 5) * sa), fill=rgba(sh(steel, 0.6), alpha))
        # the molten cutting edge
        edge = hot if flare else ember
        d.line((base[0] - nx * 1.5, base[1] - ny * 1.5, tip[0] - nx * 0.5, tip[1] - ny * 0.5), fill=rgba(edge, alpha))
        for t in (7, 12, 17, 21):
            p = (rx + t * ca - nx * 1.2, ry + t * sa - ny * 1.2)
            glow_dot(g, p[0], p[1], 2.4 if flare else 1.8, ember, (0.8 if flare else 0.5) * alpha / 255)
        for t in (10, 15):  # cracks across the blade
            d.point((rx + t * ca + nx * 0.6, ry + t * sa + ny * 0.6), fill=rgba(ember, alpha))
        gx, gy = nx * 4, ny * 4
        d.line((rx + ca * 2 + gx, ry + sa * 2 + gy, rx + ca * 2 - gx, ry + sa * 2 - gy), fill=rgba(char, alpha), width=2)
        d.point((rx + ca * 2 + gx, ry + sa * 2 + gy), fill=rgba(sh(char, 1.7), alpha))
        d.point((rx + ca * 2, ry + sa * 2), fill=rgba(ember, alpha))
        d.line((rx, ry, rx - 3 * ca, ry - 3 * sa), fill=(50, 34, 30, alpha), width=2)
        d.point((rx - 4 * ca, ry - 4 * sa), fill=rgba(ember, alpha))

    def king(p, sword_ang=60, alpha=255, pile=0, flare=False, cape=0, diss=0, smoke=0):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            # a heap of ash with the plates, the crown and the sword on top
            pm = mask(fw, fh, lambda dd: dd.chord((8, 36, 38, 54), 180, 360, fill=FULL))
            lit(im, pm, ash, 16, 39, 13, 7, alpha)
            d = ImageDraw.Draw(im)
            for k in range(5):
                x = 10 + k * 6
                d.point((x, 45 - (k % 2)), fill=rgba(sh(ash, 0.7), alpha))
            cm = mask(fw, fh, lambda dd: dd.chord((14, 38, 26, 48), 180, 360, fill=FULL))
            lit(im, cm, char, 17, 40, 5, 4, alpha)
            d = ImageDraw.Draw(im)
            sword(d, g, 4, 45, -6, alpha, False)
            crown(d, g, 31, 34 + min(pile, 4), alpha, False)
            fade_embers = max(0, 6 - pile)
            for k in range(fade_embers):
                x, y = 12 + (k * 7) % 24, 42 + (k % 2)
                d.point((x, y), fill=rgba(ember, alpha))
                glow_dot(g, x, y, 1.8, ember, 0.5 * alpha / 255)
            return post(im, g, alpha)
        s = gs.skel(p, race, cx=24, ground=47)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # cape of ash cloth, the hem burning
        cm = mask(fw, fh, lambda dd: dd.polygon([(nx - 7, ny + 1), (nx + 3, ny + 1), (hx - 1 + cape, 44), (hx - 6 + cape, 42),
                                                 (hx - 9 + cape, 45), (hx - 13 + cape, 41)], fill=FULL))
        lit(im, cm, cloth, nx - 6, ny + 6, 8, 14, alpha, flat=0.15)
        d = ImageDraw.Draw(im)
        d.line((nx - 5, ny + 3, hx - 10 + cape, 41), fill=rgba(sh(cloth, 0.62), alpha))
        for k, (x, y) in enumerate(((hx - 1 + cape, 44), (hx - 6 + cape, 42), (hx - 9 + cape, 45), (hx - 12 + cape, 42))):
            d.point((x, y), fill=rgba(ember if k % 2 else hot, alpha))
            glow_dot(g, x, y - 1, 2.2, ember, 0.6 * alpha / 255)
        # legs: charred greaves
        for side in ("l", "r"):
            back = side == "l"
            k_, f_ = s[side + "knee"], s[side + "foot"]
            base = sh(char, 1.0 if back else 1.35)[:3]  # lighter than the cape so the legs read
            thick_line(d, (hx + (-1 if back else 1), hy), k_, rgba(base, alpha), 3, rgba(sh(base, 1.5), alpha))
            thick_line(d, k_, (f_[0], f_[1] - 2), rgba(base, alpha), 3, rgba(sh(base, 1.5), alpha))
            d.ellipse((k_[0] - 2, k_[1] - 1, k_[0] + 1, k_[1] + 2), fill=rgba(sh(base, 1.2), alpha))
            d.point((k_[0] - 1, k_[1] + 1), fill=rgba(ember, alpha))  # vein at the knee
            d.polygon([(f_[0] - 2, f_[1] - 2), (f_[0] + 4, f_[1] - 1), (f_[0] + 4, f_[1]), (f_[0] - 2, f_[1])], fill=rgba(sh(base, 0.9), alpha))
        # tasset skirt of iron strips
        for k in range(4):
            x = hx - 5 + k * 3
            d.rectangle((x, hy, x + 2, hy + 5 + (k % 2)), fill=rgba(sh(char, 0.85 + 0.1 * (k % 2)), alpha))
            d.point((x, hy), fill=rgba(sh(char, 1.6), alpha))
        # back arm
        thick_line(d, s["shoulder"], s["lhand"], rgba(sh(bone, 0.6), alpha), 2)
        # cuirass: blackened plate split by glowing veins, the molten heart
        bm = mask(fw, fh, lambda dd: dd.polygon([(hx - 6, hy), (hx + 6, hy), (nx + 8, ny + 1), (nx + 6, ny - 1), (nx - 6, ny - 1), (nx - 8, ny + 1)], fill=FULL))
        lit(im, bm, char, nx - 2, ny + 3, 8, 9, alpha)
        d = ImageDraw.Draw(im)
        heart = hot if flare else ember
        d.ellipse((nx - 2, ny + 4, nx + 2, ny + 8), fill=rgba(sh(ember, 0.6), alpha))
        d.ellipse((nx - 1, ny + 5, nx + 1, ny + 7), fill=rgba(heart, alpha))
        glow_dot(g, nx, ny + 6, 5 if flare else 4, ember, (0.9 if flare else 0.6) * alpha / 255)
        for (x0, y0, x1, y1) in ((nx - 2, ny + 6, nx - 6, ny + 3), (nx + 2, ny + 6, nx + 5, ny + 10), (nx, ny + 8, nx - 1, hy - 1),
                                 (nx + 1, ny + 4, nx + 4, ny + 1)):
            d.line((x0, y0, x1, y1), fill=rgba(sh(ember, 0.85), alpha))
        for k in range(3):  # plate ridges
            y = ny + 10 + k * 2
            d.line((nx - 5 + k, y, nx - 3 + k, y), fill=rgba(sh(char, 1.5), alpha))
        # skull under the crown: ash bone, cracked, burning sockets, smoke
        sx, sy = int(s["head"][0]), int(s["head"][1]) - 2
        km = mask(fw, fh, lambda dd: (dd.ellipse((sx - 6, sy - 6, sx + 6, sy + 4), fill=FULL),
                                      dd.rectangle((sx - 3, sy + 2, sx + 5, sy + 6), fill=FULL)))
        lit(im, km, (58, 48, 46), sx - 2, sy - 3, 7, 6, alpha)  # charred, blackened skull
        d = ImageDraw.Draw(im)
        soot = (16, 10, 12, alpha)
        # ash-grey flakes where the light catches the burned bone
        for fx, fy in ((sx - 4, sy - 4), (sx - 2, sy - 5), (sx - 5, sy - 1), (sx + 1, sy - 4)):
            d.point((fx, fy), fill=rgba(ash, alpha))
        # a web of smouldering cracks over the face
        for (x0, y0, x1, y1) in ((sx - 5, sy - 3, sx - 2, sy - 5), (sx + 2, sy - 6, sx + 3, sy - 3), (sx + 5, sy + 1, sx + 6, sy - 2),
                                 (sx - 3, sy + 1, sx - 4, sy + 3)):
            d.line((x0, y0, x1, y1), fill=rgba(sh(ember, 0.8), alpha))
        d.point((sx - 2, sy - 5), fill=rgba(hot, alpha))
        glow_dot(g, sx - 3, sy - 4, 2.0, ember, 0.5 * alpha / 255)
        d.rectangle((sx - 1, sy - 2, sx + 1, sy), fill=soot)
        d.rectangle((sx + 3, sy - 2, sx + 5, sy), fill=soot)
        eye = hot if flare else ember
        d.point((sx, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 4, sy - 1), fill=rgba(eye, alpha))
        glow_dot(g, sx, sy - 1, 2.8, ember, 0.9 * alpha / 255)
        glow_dot(g, sx + 4, sy - 1, 2.8, ember, 0.9 * alpha / 255)
        d.point((sx + 2, sy + 1), fill=soot)
        d.line((sx - 2, sy + 4, sx + 5, sy + 4), fill=soot)
        for tx in range(sx - 1, sx + 5, 2):
            d.point((tx, sy + 3), fill=rgba((120, 100, 90), alpha))  # scorched teeth
        d.point((sx + 1, sy + 4), fill=rgba(ember, alpha))  # ember glow inside the jaw
        crown(d, g, sx, sy - 10, alpha, flare)
        # smoke curling from the crown
        for k in range(3):
            yy = sy - 15 - ((smoke + k * 3) % 8)
            xx = sx - 3 + k * 3 + (1 if (smoke + k) % 2 else 0)
            if yy >= 0:
                d.point((xx, yy), fill=(110, 104, 104, int(alpha * 0.7)))
        # pauldrons: blackened domes with spikes
        for side, f in ((-1, 0.8), (1, 1.0)):
            px_, py_ = nx + side * 6, ny + 1
            pm = mask(fw, fh, lambda dd: dd.chord((px_ - 4, py_ - 3, px_ + 4, py_ + 5), 180, 360, fill=FULL))
            lit(im, pm, sh(char, f)[:3], px_ - 1, py_ - 1, 4, 3, alpha)
            d = ImageDraw.Draw(im)
            d.line((px_ - 3, py_ + 1, px_ + 3, py_ + 1), fill=rgba(sh(ember, 0.7), alpha))
            d.polygon([(px_ - 1, py_ - 2), (px_ + side, py_ - 6), (px_ + 1, py_ - 2)], fill=rgba(sh(char, 1.2), alpha))
            d.point((px_ + side, py_ - 6), fill=rgba(ember, alpha))
        # sword arm in a charred gauntlet
        rx, ry = s["rhand"]
        thick_line(d, s["shoulder"], (rx, ry), rgba(sh(char, 1.1), alpha), 3, rgba(sh(char, 1.6), alpha))
        sword(d, g, rx, ry, sword_ang, alpha, flare)
        d.ellipse((rx - 2, ry - 2, rx + 1, ry + 1), fill=rgba(char, alpha))
        d.point((rx - 1, ry - 2), fill=rgba(sh(char, 1.8), alpha))
        # drifting embers
        for k in range(3 + (2 if flare else 0)):
            ex = 12 + (k * 11 + smoke * 3) % 26
            ey = 40 - (k * 9 + smoke * 4) % 34
            if im.getpixel((ex, ey))[3] == 0:
                d.point((ex, ey), fill=rgba(ember if k % 2 else hot, alpha))
        return post(im, g, alpha, diss, 11, (180, 170, 166, 255))

    def fn(name, i, n):
        if name == "idle":
            return king(P(by=[0, 0, 1, 1][i], ra=(4, 10)), 70, cape=[0, 1, 1, 0][i], smoke=i, flare=i == 2)
        if name == "walk":
            lx = [-5, -2, 2, 5, 2, -2][i]
            return king(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(4, 10)), 60,
                        cape=[1, 2, 2, 1, 0, 0][i], smoke=i)
        if name == "windup":
            return king(P(lean=-2 - i, crouch=i, ra=(-3, -10 - i * 2)), -120 - i * 12, flare=True, cape=2, smoke=i)
        if name == "attack":
            return king(P(lean=4, lf=(-5, 0), rf=(7, 0), crouch=2, ra=[(8, -4), (12, 2), (10, 8)][i]), [-30, 25, 70][i],
                        flare=True, cape=-2, smoke=i)
        if name == "hurt":
            return king(P(lean=-4, by=2, ra=(4, 6)), 80, cape=2)
        if i < 2:
            return king(P(crouch=3 + i * 3, by=2 + i, ra=(7, 8)), 90, cape=1, diss=2 + i * 2)
        return king(P(), pile=i, alpha=255 - (i - 2) * 25)

    render(lay, fn, "sprites/bosses/ashen_king_sheet.png")


# ============================================================ drowned bell
def drowned_bell():
    """The Drowned Bell: a bloated drowned titan swinging a huge bronze bell
    on an anchor chain. Swollen lit flesh with folds and barnacles, a fishing
    net over the shoulder, kelp hair and belt, lantern eyes; the bell has
    verdigris streaks, an inscribed band and a clapper; its toll sends out
    rings of sound. Collapses with the bell on top of the body."""
    fw, fh = 48, 48
    lay = gs.monster_layout("drowned_bell_layout", fw, fh, (24, 48), counts={"windup": 3, "attack": 3, "death": 6})
    skin = (112, 142, 120)
    weed = (52, 104, 70)
    bronze = (176, 132, 66)
    verd = (96, 184, 156)
    eye_c = (150, 255, 220)
    chain = (98, 92, 96)
    race = dict(leg=12, torso=14)

    def bell(im, g, bx, top, alpha, ring=0):
        """Bell with its crown at (bx, top): 13 px wide, 12 px tall."""
        d = ImageDraw.Draw(im)
        d.rectangle((bx - 2, top, bx + 2, top + 1), fill=rgba(sh(bronze, 0.75), alpha))  # crown loop
        bm = mask(fw, fh, lambda dd: dd.polygon([(bx - 3, top + 1), (bx + 3, top + 1), (bx + 5, top + 5), (bx + 6, top + 10),
                                                 (bx + 7, top + 12), (bx - 7, top + 12), (bx - 6, top + 10), (bx - 5, top + 5)], fill=FULL))
        lit(im, bm, bronze, bx - 2, top + 4, 6, 7, alpha)
        d = ImageDraw.Draw(im)
        d.line((bx - 6, top + 8, bx + 6, top + 8), fill=rgba(sh(bronze, 0.6), alpha))  # inscribed band
        for x in range(bx - 5, bx + 6, 2):
            d.point((x, top + 7), fill=rgba(sh(bronze, 1.35), alpha))
        d.line((bx - 7, top + 12, bx + 7, top + 12), fill=rgba(sh(bronze, 1.4), alpha))  # rim highlight
        d.point((bx - 3, top + 3), fill=(255, 236, 170, alpha))  # glint
        for k, (vx, vy, ln) in enumerate(((bx - 4, top + 5, 4), (bx + 1, top + 3, 3), (bx + 4, top + 6, 5))):
            d.line((vx, vy, vx, vy + ln), fill=rgba(verd if k % 2 else sh(verd, 0.8), alpha))  # verdigris streaks
        d.point((bx + 5, top + 11), fill=rgba(verd, alpha))
        d.ellipse((bx - 1, top + 11, bx + 1, top + 13), fill=rgba(sh(bronze, 0.45), alpha))  # clapper
        if ring:
            for rr, st in ((9, 0.8), (13, 0.55), (17, 0.35)):
                r = rr + ring
                gd = ImageDraw.Draw(g)
                gd.arc((bx - r, top + 6 - r, bx + r, top + 6 + r), 200, 520 - 180, fill=(190, 255, 235, int(255 * st * alpha / 255)))
        return d

    def body(p, alpha=255, eye=eye_c, ring=0, pile=0, swing=0, drip=0, diss=0):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            pm = mask(fw, fh, lambda dd: dd.ellipse((4, 37, 34, 49), fill=FULL))
            lit(im, pm, skin, 12, 39, 14, 5, alpha)
            d = ImageDraw.Draw(im)
            for k in range(4):
                d.line((7 + k * 7, 44, 8 + k * 7, 47), fill=rgba(weed, alpha))
            bell(im, g, 30, 35, alpha)
            for k in range(max(0, 4 - pile // 2)):
                d.point((10 + k * 6, 47), fill=(150, 220, 210, alpha))  # water pooling
            return post(im, g, alpha)
        s = gs.skel(p, race, cx=22, ground=47)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # legs: swollen, barnacled
        for side in ("l", "r"):
            back = side == "l"
            base = sh(skin, 0.68 if back else 0.95)[:3]
            thick_line(d, (hx + (-2 if back else 2), hy), s[side + "knee"], rgba(base, alpha), 4, None if back else rgba(sh(skin, 1.2), alpha))
            thick_line(d, s[side + "knee"], s[side + "foot"], rgba(base, alpha), 3)
            fx, fy = s[side + "foot"]
            d.line((fx, fy, fx + 3, fy), fill=rgba(sh(base, 0.8), alpha), width=2)
        # back arm, hanging
        thick_line(d, (nx - 3, ny + 2), s["lhand"], rgba(sh(skin, 0.6), alpha), 3)
        # bloated torso: lit belly with folds and a stretched navel
        tm = mask(fw, fh, lambda dd: dd.ellipse((hx - 11, ny + 1, hx + 10, hy + 7), fill=FULL))
        lit(im, tm, skin, hx - 4, ny + 5, 10, 9, alpha)
        d = ImageDraw.Draw(im)
        d.arc((hx - 9, hy - 6, hx + 8, hy + 4), 20, 160, fill=rgba(sh(skin, 0.6), alpha))  # fold
        d.arc((hx - 7, ny + 3, hx + 6, ny + 11), 20, 160, fill=rgba(sh(skin, 0.7), alpha))  # chest fold
        d.ellipse((hx - 1, hy - 4, hx + 1, hy - 2), fill=rgba(sh(skin, 0.45), alpha))  # navel
        d.point((hx - 6, ny + 5), fill=rgba(sh(skin, 1.4), alpha))
        for bx_, by_ in ((hx + 6, ny + 6), (hx + 7, ny + 7), (hx - 7, hy - 1), (hx + 3, hy + 3)):
            d.point((bx_, by_), fill=(222, 216, 198, alpha))  # barnacles
            d.point((bx_ + 1, by_), fill=(150, 140, 126, alpha))
        # fishing net over the shoulder and across the chest
        net = (176, 166, 130)
        d.line((nx - 7, ny + 1, nx + 3, ny + 10), fill=rgba(net, alpha))  # the net's rope over the shoulder
        for k in range(3):
            x0 = nx - 6 + k * 3
            d.line((x0, ny + 2 + k * 3, x0 - 2, ny + 6 + k * 3), fill=rgba(sh(net, 0.75), alpha))
        d.point((nx + 1, ny + 8), fill=(220, 140, 60, alpha))  # cork float
        # kelp belt with an anchor-chain buckle
        d.line((hx - 10, hy + 2, hx + 9, hy + 2), fill=rgba(weed, alpha), width=2)
        for k, x in enumerate((hx - 8, hx - 4, hx + 1, hx + 6)):
            d.polygon([(x - 1, hy + 3), (x + 1, hy + 3), (x + (k % 2), hy + 8 + (k % 2))], fill=rgba(sh(weed, 0.8 + 0.2 * (k % 2)), alpha))
        for k in range(3):
            d.ellipse((hx + 2 + k * 2, hy + 1, hx + 3 + k * 2, hy + 3), outline=rgba(chain, alpha))
        # head: sunken into the shoulders, kelp hair, lantern eyes, slack jaw
        sx, sy = s["head"]
        sy += 2
        hm = mask(fw, fh, lambda dd: dd.ellipse((sx - 5, sy - 5, sx + 5, sy + 4), fill=FULL))
        lit(im, hm, (146, 168, 150), sx - 2, sy - 3, 5, 5, alpha)  # paler face than the body
        d = ImageDraw.Draw(im)
        for k, (kx, ln) in enumerate(((sx - 5, 9), (sx - 4, 7), (sx - 2, 4), (sx, 3))):
            d.line((kx, sy - 4, kx - 1, sy - 4 + ln), fill=rgba(sh(weed, 1.1 if k % 2 else 0.8), alpha))
        hole = (14, 30, 24, alpha)
        d.rectangle((sx, sy - 1, sx + 1, sy + 1), fill=hole)
        d.rectangle((sx + 3, sy - 1, sx + 4, sy + 1), fill=hole)
        d.point((sx, sy), fill=rgba(eye, alpha))
        d.point((sx + 3, sy), fill=rgba(eye, alpha))
        glow_dot(g, sx + 0.5, sy, 2.6, eye, 0.9 * alpha / 255)
        glow_dot(g, sx + 3.5, sy, 2.6, eye, 0.9 * alpha / 255)
        d.rectangle((sx, sy + 3, sx + 4, sy + 4), fill=hole)  # slack mouth
        for tx in (sx, sx + 2, sx + 4):
            d.point((tx, sy + 3), fill=(220, 214, 196, alpha))
        d.point((sx + 5, sy + 5 + drip % 2), fill=(150, 230, 210, alpha))  # drip
        # front arm and the anchor chain down to the bell
        rx, ry = s["rhand"]
        thick_line(d, (nx + 2, ny + 2), (rx, ry), rgba(skin, alpha), 4, rgba(sh(skin, 1.25), alpha))
        d.ellipse((rx - 2, ry - 2, rx + 2, ry + 2), fill=rgba(sh(skin, 1.05), alpha))  # fist
        bx = int(min(fw - 8, max(8, rx + 6 + swing)))
        btop = int(min(fh - 14, max(2, ry + 4)))
        for k in range(4):  # chain links from the fist to the bell crown
            t = k / 3
            cx_ = rx + (bx - rx) * t
            cy_ = ry + (btop - ry) * t
            d.ellipse((cx_ - 1, cy_ - 1, cx_ + 1, cy_ + 1), outline=rgba(sh(chain, 1.2 if k % 2 else 0.9), alpha))
        bell(im, g, bx, btop, alpha, ring)
        return post(im, g, alpha, diss, 13, (150, 230, 210, 255))

    def fn(name, i, n):
        if name == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(6, 6 + [0, 1, 0, -1][i])), swing=[0, 1, 0, -1][i], drip=i)
        if name == "walk":
            lx = [-4, -2, 2, 4, 2, -2][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(6, 8)), swing=[-1, 0, 1, 1, 0, -1][i], drip=i)
        if name == "windup":
            return body(P(lean=-2 - i, crouch=i, ra=(8, -8 - i * 2)), eye=(255, 236, 170), swing=-2 - i)
        if name == "attack":
            return body(P(lean=4, lf=(-5, 0), rf=(7, 0), crouch=3, ra=[(10, -2), (14, 6), (12, 12)][i]),
                        ring=[0, 1, 3][i], eye=(220, 255, 245), swing=[2, 3, 1][i])
        if name == "hurt":
            return body(P(lean=-4, by=2, ra=(6, 8)), eye=(255, 255, 255), swing=-2)
        if i < 2:
            return body(P(crouch=3 + i * 3, by=2 + i, ra=(8, 10)), eye=(90, 160, 130), diss=2 + i * 2)
        return body(P(), pile=i, alpha=255 - (i - 2) * 30)

    render(lay, fn, "sprites/bosses/drowned_bell_sheet.png")


# ================================================================ eclipse
def eclipse():
    """The final boss: a black sun with a burning corona and one eye, shadow
    tendrils hanging below and shards of the broken moon in orbit."""
    fw, fh = 56, 58
    lay = gs.monster_layout("eclipse_layout", fw, fh, (28, 58), "fly", {"idle": 4, "fly": 4, "windup": 4, "attack": 3, "death": 6})
    cx, cy, r = 28, 24, 12
    corona = (255, 170, 60)
    hot = (255, 236, 170)
    void = (16, 8, 26)
    rim = (150, 60, 220)

    def sun(phase=0.0, open_=1.0, flare=0, alpha=255, diss=0, flash=False, wrath=0.0):
        im = blank(fw, fh)
        g = blank(fw, fh)
        d = ImageDraw.Draw(im)
        dy = int(round(math.sin(phase) * 2))
        y0 = cy + dy
        # shadow tendrils hanging from the disc, swaying
        for k in range(5):
            bx = cx - 8 + k * 4
            pts = []
            for j in range(9):
                t = j / 8
                sway = math.sin(phase * 1.3 + k * 1.7 + t * 3.0) * (1 + t * 3)
                pts.append((bx + sway, y0 + r - 2 + t * (18 + (k % 2) * 6)))
            for j in range(len(pts) - 1):
                w = 3 if j < 3 else 2 if j < 6 else 1
                d.line((pts[j][0], pts[j][1], pts[j + 1][0], pts[j + 1][1]), fill=rgba(sh(void, 1.6 - j * 0.08)), width=w)
            tip = pts[-1]
            d.point((round(tip[0]), round(tip[1])), fill=rgba(rim))
            glow_dot(g, tip[0], tip[1], 1.5, rim, 0.5)
        # corona: long rotating rays, longer during a flare
        n_rays = 14
        for k in range(n_rays):
            ang = phase * 0.35 + k * math.tau / n_rays
            ln = r + 5 + (3 if k % 2 else 0) + flare * 2 + math.sin(phase * 2 + k) * 1.5
            ax, ay = cx + math.cos(ang) * (r - 1), y0 + math.sin(ang) * (r - 1)
            bx, by = cx + math.cos(ang) * ln, y0 + math.sin(ang) * ln
            col = sh(corona, 1.0 + wrath * 0.1)
            if wrath > 0.5:
                col = (255, 90 + (k % 3) * 20, 70)
            d.line((ax, ay, bx, by), fill=rgba(col), width=2 if k % 2 == 0 else 1)
            d.point((round(bx), round(by)), fill=rgba(hot))
            glow_dot(g, bx, by, 2.0 + flare * 0.6, col, 0.55)
        # bright ring of light around the black disc
        d.ellipse((cx - r - 2, y0 - r - 2, cx + r + 2, y0 + r + 2), fill=rgba(hot))
        d.ellipse((cx - r - 1, y0 - r - 1, cx + r + 1, y0 + r + 1), fill=rgba(corona))
        for k in range(12):  # halo along the rim, the disc itself stays black
            a = k * math.tau / 12
            glow_dot(g, cx + math.cos(a) * (r + 2), y0 + math.sin(a) * (r + 2), 4 + flare, corona, 0.35)
        # the moon's shadow: the disc, slightly shifted (thin crescent on the left)
        dm = mask(fw, fh, lambda dd: dd.ellipse((cx - r + 1, y0 - r, cx + r + 1, y0 + r), fill=FULL))
        lit(im, dm, void, cx + 5, y0 - 5, r, r, flat=0.9)
        d = ImageDraw.Draw(im)
        d.arc((cx - r + 1, y0 - r, cx + r + 1, y0 + r), 200, 330, fill=rgba(sh(rim, 0.7)))
        # cracks of violet light across the disc
        for a, b in (((cx - 7, y0 - 4), (cx - 2, y0 - 7)), ((cx + 6, y0 + 3), (cx + 9, y0 + 7)), ((cx - 6, y0 + 6), (cx - 3, y0 + 9))):
            d.line((a[0], a[1], b[0], b[1]), fill=rgba(sh(rim, 1.1)))
            glow_dot(g, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 2.0, rim, 0.45)
        # the eye: slit opens wider in windup / attack
        eh = max(0, round(4 * open_))
        if eh > 0:
            d.ellipse((cx - 7, y0 - eh, cx + 7, y0 + eh), fill=(236, 226, 214, 255))
            d.ellipse((cx - 7, y0 - eh, cx + 7, y0 + eh), outline=rgba(sh(rim, 0.6)))
            iris = (255, 255, 255) if flash else (220, 40, 60) if wrath > 0.5 else (200, 70, 255)
            ir = min(eh, 3)
            d.ellipse((cx - ir, y0 - ir, cx + ir, y0 + ir), fill=rgba(iris))
            d.line((cx, y0 - ir, cx, y0 + ir), fill=(10, 4, 16, 255))  # slit pupil
            glow_dot(g, cx, y0, 4 + flare, iris, 0.9)
        else:
            d.line((cx - 7, y0, cx + 7, y0), fill=rgba(sh(rim, 0.8)))
        # crown of black thorns on top
        for k in range(5):
            tx = cx - 8 + k * 4
            th = 5 + (2 if k == 2 else 0)
            d.polygon([(tx - 1, y0 - r + 2), (tx + 1, y0 - r + 2), (tx, y0 - r - th)], fill=rgba(sh(void, 1.4)))
            d.point((tx, y0 - r - th), fill=rgba(hot))
        # orbiting shards of the broken moon
        for k in range(4):
            ang = -phase * 0.7 + k * math.tau / 4
            sx_, sy_ = cx + math.cos(ang) * (r + 11), y0 + math.sin(ang) * (r + 4)
            col = (210, 214, 236) if math.sin(ang) > 0 else (130, 130, 160)
            d.polygon([(sx_, sy_ - 2), (sx_ + 2, sy_), (sx_, sy_ + 2), (sx_ - 1, sy_)], fill=rgba(col))
            glow_dot(g, sx_, sy_, 1.6, (190, 170, 255), 0.4)
        out = finish(im, g)
        if diss:
            dissolve(out, diss, 11, (255, 200, 120, 255))
        return fade(out, alpha)

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return sun(i * math.tau / 4)
        if name == "windup":
            return sun(i * 0.5, open_=0.3 + i * 0.25, flare=i)
        if name == "attack":
            return sun(i * 0.5, open_=1.2, flare=[4, 2, 1][i], flash=i == 0, wrath=1.0 if i == 0 else 0.0)
        if name == "hurt":
            return sun(0, open_=0.0, flash=True)
        return sun(i, open_=1.0 - i * 0.2, flare=6 - i, diss=1 + i * 2 if i < 4 else 8 + (i - 4), alpha=255 - i * 30)

    render(lay, fn, "sprites/bosses/eclipse_sheet.png")
    sun(0.0).save(os.path.join(A, "sprites/bosses/eclipse.png"))


def main():
    bone_king()
    flame_witch()
    illusionist()
    drowned_bell()
    eclipse()
    print("bosses generated")


if __name__ == "__main__":
    main()
