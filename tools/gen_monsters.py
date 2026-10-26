#!/usr/bin/env python3
"""Detailed monster sprite sheets (pixel art).

Every monster keeps its frame size and animation layout (data/animations/*,
hitboxes in data/enemies/* stay valid); only the drawing is richer: volume
shading lit from the top left (4 tones, dithered borders), materials (bone,
cloth, stone, jelly, fur, membrane), small details and readable eyes.
Also writes the static icon (first idle frame) used by the bestiary.
Run:  python3 tools/gen_monsters.py
"""
from __future__ import annotations

import math
import os
import random

from PIL import Image, ImageDraw

import gen_placeholders as gp
import gen_sheets as gs

A = gp.A
LIGHT = (-0.55, -0.62, 0.56)
_ln = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _ln for v in LIGHT)
LEVELS = (1.32, 1.08, 0.86, 0.66)
CUTS = (0.7, 0.38, 0.02)
FULL = (255, 255, 255, 255)


def rgba(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


def sh(c, f, a=None):
    r = gp.shade(rgba(c[:3], c[3] if len(c) > 3 else 255), f)
    return r if a is None else (r[0], r[1], r[2], a)


def blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def mask(w, h, fn):
    m = blank(w, h)
    fn(ImageDraw.Draw(m))
    return m


def lit(im, m, base, cx, cy, rx, ry, alpha=255, levels=LEVELS, flat=0.0):
    """Fills mask m with `base` shaded like an ellipsoid lit from the top left."""
    px, mp = im.load(), m.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if mp[x, y][3] == 0:
                continue
            nx, ny = (x - cx) / max(rx, 0.5), (y - cy) / max(ry, 0.5)
            nz = math.sqrt(max(0.0, 1 - min(1.0, nx * nx + ny * ny))) + flat
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            dd = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
            i = 0
            while i < len(CUTS) and dd <= CUTS[i]:
                i += 1
            if i > 0 and dd > CUTS[i - 1] - 0.06 and (x + y) % 2 == 0:
                i -= 1
            px[x, y] = sh(base, levels[i], alpha)


def dissolve(im, amount, seed=7, color=None):
    """Death: pixels drop out in a scattered pattern (optionally leave sparks)."""
    if amount <= 0:
        return im
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            v = (x * 7 + y * 13 + seed) % 10
            if v < amount:
                px[x, y] = (0, 0, 0, 0)
            elif color and v == amount and amount > 2:
                px[x, y] = color
    return im


def fade(im, alpha):
    if alpha >= 255:
        return im
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, a * alpha // 255)
    return im


# ===================================================================== slime
def slime():
    fw, fh = 20, 16
    lay = gs.monster_layout("slime_layout", fw, fh, (10, 16))
    base = (72, 196, 86)

    def body(w, h, dx=0, dy=0, eyes="o", alpha=230, base=base, core=(56, 160, 70), mouth=False, drip=0):
        im = blank(fw, fh)
        x0 = 10 - w / 2 + dx
        top = 15 - int(h * 1.35) + dy
        # dome: the upper half of an ellipse whose centre line is the floor
        m = mask(fw, fh, lambda d: (d.pieslice((x0, top, x0 + w - 1, 2 * (15 + dy) - top), 180, 360, fill=FULL),
                                    d.rectangle((x0, 14 + dy, x0 + w - 1, 15 + dy), fill=FULL)))
        lit(im, m, base, 10 + dx - w * 0.15, 15 + dy - h * 0.9, w * 0.55, h * 0.9, alpha)
        d = ImageDraw.Draw(im)
        # inner core and bubbles seen through the jelly
        cx, cy = 10 + dx - 2, 15 + dy - h * 0.35
        d.ellipse((cx - w * 0.15, cy - h * 0.2, cx + w * 0.12, cy + h * 0.25), fill=rgba(core, alpha))
        for bx, by in ((x0 + w * 0.7, 15 + dy - h * 0.5), (x0 + w * 0.3, 15 + dy - h * 0.35)):
            d.point((bx, by), fill=(200, 255, 210, alpha))
        d.arc((x0 + 1, top + 1, x0 + w * 0.6, top + h), 200, 260, fill=(225, 255, 230, alpha))  # gloss
        d.line((x0 + 1, 15 + dy, x0 + w - 2, 15 + dy), fill=sh(base, 0.55, alpha))
        if drip:
            d.line((x0 + w * 0.75, 15 + dy, x0 + w * 0.75, 15 + dy + drip), fill=sh(base, 0.9, alpha))
        ey = int(15 - h * 0.8 + dy)
        ex = int(10 + dx + 1)
        dark = (12, 36, 16, 255)
        for e in (ex - 2, ex + 2):
            if eyes == "o":
                d.rectangle((e - 1, ey - 1, e, ey), fill=(240, 255, 240, 255))
                d.point((e, ey), fill=dark)
            elif eyes == "x":
                d.point((e - 1, ey - 1), fill=dark)
                d.point((e, ey), fill=dark)
                d.point((e - 1, ey + 1), fill=dark)
                d.point((e + 1, ey - 1), fill=dark)
            elif eyes == "angry":
                d.rectangle((e - 1, ey, e, ey), fill=(255, 240, 200, 255))
                d.point((e, ey), fill=dark)
        if eyes == "angry":
            d.line((ex - 4, ey - 2, ex - 1, ey - 1), fill=dark)
            d.line((ex + 4, ey - 2, ex + 1, ey - 1), fill=dark)
        if mouth:
            d.rectangle((ex - 2, ey + 2, ex + 2, ey + 3), fill=(20, 60, 25, 255))
            d.point((ex - 1, ey + 2), fill=(240, 255, 240, 255))
            d.point((ex + 1, ey + 2), fill=(240, 255, 240, 255))
        return im

    def fn(name, i, n):
        if name == "idle":
            k = [0, 1, 0, -1][i]
            return body(16 - k, 7 + k)
        if name == "walk":
            hop = [0, -2, -4, -4, -2, 0][i]
            sq = [2, -1, -2, -1, 0, 2][i]
            return body(16 + sq, 7 - sq // 2, dy=hop, drip=1 if hop < -2 else 0)
        if name == "windup":
            return body(16 + i, 6 - i, eyes="angry")
        if name == "attack":
            return body([18, 19, 17][i], [6, 7, 7][i], dx=[2, 3, 1][i], eyes="angry", mouth=True)
        if name == "hurt":
            return body(17, 6 + i, eyes="x")
        k = i + 1
        return fade(body(16 + k, max(1, 7 - k), eyes="x"), 255 - i * 35)

    return lay, fn, body


# ================================================================== skeleton
def skeleton():
    fw, fh = 24, 28
    lay = gs.monster_layout("skeleton_layout", fw, fh, (12, 28))
    bone = (228, 222, 200)
    race = dict(leg=7, torso=8)

    def body(p, sword_ang=30, pile=0, alpha=255, eye=(255, 70, 40)):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(bone, alpha)
        dark = sh(bone, 0.62, alpha)
        if pile:
            for k in range(pile):
                x = 3 + (k * 5) % 16
                d.line((x, 27 - (k % 2), x + 4, 26 + (k % 2)), fill=c if k % 2 else dark)
                d.point((x, 27 - (k % 2)), fill=sh(bone, 1.2, alpha))
            d.ellipse((9, 21 + max(0, 3 - pile // 2), 15, 27), fill=c)
            d.point((11, 24 + max(0, 3 - pile // 2) // 2), fill=(30, 20, 20, alpha))
            return im
        s = gs.skel(p, race, cx=12, ground=27)
        # legs: thigh, shin, knee joint, foot
        for side in ("l", "r"):
            col = c if side == "r" else dark
            d.line([s["hip"], s[side + "knee"]], fill=col)
            d.line([s[side + "knee"], s[side + "foot"]], fill=col)
            kx, ky = s[side + "knee"]
            d.point((round(kx), round(ky)), fill=sh(bone, 1.25, alpha) if side == "r" else dark)
            fx, fy = s[side + "foot"]
            d.line((fx, fy, fx + 2, fy), fill=col)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # pelvis, loincloth rag, spine, ribcage
        d.line((hx - 2, hy, hx + 2, hy), fill=c)
        d.polygon([(hx - 2, hy), (hx + 2, hy), (hx + 1, hy + 4), (hx - 1, hy + 3)], fill=(110, 80, 60, alpha))
        d.line((hx, hy, nx, ny), fill=dark)
        for k in range(3):
            t = (k + 1) / 4
            y = ny + 1 + k * 2
            x = nx + (hx - nx) * t
            d.arc((x - 3, y - 1, x + 3, y + 2), 200, 340, fill=c)
            d.point((x - 3, y + 1), fill=dark)
        d.line([s["shoulder"], s["lhand"]], fill=dark)
        # skull: cranium, eye sockets with embers, jaw with teeth
        sx, sy = s["head"]
        d.ellipse((sx - 3, sy - 3, sx + 3, sy + 2), fill=c)
        d.point((sx - 2, sy - 2), fill=sh(bone, 1.3, alpha))
        d.rectangle((sx, sy - 1, sx + 1, sy), fill=(30, 18, 18, alpha))
        d.rectangle((sx + 2, sy - 1, sx + 3, sy), fill=(30, 18, 18, alpha))
        d.point((sx + 1, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 3, sy - 1), fill=rgba(eye, alpha))
        d.line((sx - 1, sy + 2, sx + 3, sy + 2), fill=dark)
        for tx in (sx, sx + 2):
            d.point((tx, sy + 2), fill=c)
        d.point((sx - 3, sy), fill=dark)  # cheekbone shadow
        d.line([s["shoulder"], s["rhand"]], fill=c)
        d.point(s["shoulder"], fill=sh(bone, 1.2, alpha))
        # rusty sword: blade with a notch, guard, grip
        rx, ry = s["rhand"]
        a = math.radians(sword_ang)
        tip = (rx + 9 * math.cos(a), ry + 9 * math.sin(a))
        d.line((rx, ry, tip[0], tip[1]), fill=(160, 140, 120, alpha), width=1)
        d.point((rx + 5 * math.cos(a), ry + 5 * math.sin(a)), fill=(120, 70, 40, alpha))  # rust
        d.point((round(tip[0]), round(tip[1])), fill=(210, 205, 195, alpha))
        gx, gy = -math.sin(a) * 2, math.cos(a) * 2
        d.line((rx + gx, ry + gy, rx - gx, ry - gy), fill=(120, 90, 50, alpha))
        return im

    P = gs.P

    def fn(name, i, n):
        if name == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(2, 6)), 70)
        if name == "walk":
            lx = [-3, -1, 1, 3, 1, -1][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(2 + lx // 2, 6)), 60)
        if name == "windup":
            return body(P(lean=-1 - i, ra=(-2, -6 - i)), -120 - i * 10, eye=(255, 160, 60))
        if name == "attack":
            return body(P(lean=2, lf=(-3, 0), rf=(4, 0), ra=[(4, -3), (7, 1), (6, 4)][i]), [-40, 20, 60][i], eye=(255, 220, 120))
        if name == "hurt":
            return body(P(lean=-3, by=1, ra=(3, 3)), 80, eye=(255, 255, 255))
        if i < 2:
            return body(P(crouch=2 + i * 2, by=1 + i, ra=(5, 5)), 90, eye=(90, 30, 20))
        return body(P(), pile=2 + i, alpha=255 - (i - 2) * 30)

    return lay, fn, None


# ======================================================================= bat
def bat():
    fw, fh = 20, 16
    lay = gs.monster_layout("bat_layout", fw, fh, (10, 12), "fly", {"idle": 4, "fly": 4, "windup": 2, "attack": 3, "death": 5})
    fur = (92, 62, 112)
    mem = (130, 70, 120)

    def body(wing, dy=0, rot=0, eyes=True, alpha=255, tilt=0, mouth=False):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + dy
        wy = cy - wing
        # wings: membrane between finger bones, scalloped trailing edge
        for side in (-1, 1):
            sx = 10 + side
            tipx = 10 + side * 9
            pts = [(sx, cy - 1), (10 + side * 5, wy - 1), (tipx, wy), (10 + side * 8, cy + 2), (10 + side * 6, cy + 1),
                   (10 + side * 4, cy + 3), (sx, cy + 1)]
            d.polygon(pts, fill=rgba(sh(mem, 0.85 if side < 0 else 1.0), alpha))
            d.line((sx, cy - 1, 10 + side * 5, wy - 1, tipx, wy), fill=rgba(sh(fur, 0.7), alpha))  # arm bone
            d.line((10 + side * 5, wy - 1, 10 + side * 8, cy + 2), fill=rgba(sh(mem, 0.6), alpha))  # finger
            d.line((10 + side * 5, wy - 1, 10 + side * 4, cy + 3), fill=rgba(sh(mem, 0.6), alpha))
        # furry body, ears, face
        m = mask(fw, fh, lambda dd: dd.ellipse((7, cy - 3 + tilt, 12, cy + 3 + tilt), fill=FULL))
        lit(im, m, fur, 9, cy - 1 + tilt, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        for ex in (8, 11):
            d.polygon([(ex - 1, cy - 2 + tilt), (ex, cy - 5 + tilt), (ex + 1, cy - 2 + tilt)], fill=rgba(fur, alpha))
            d.point((ex, cy - 3 + tilt), fill=(220, 130, 150, alpha))
        d.point((9, cy + 2 + tilt), fill=rgba(sh(fur, 1.4), alpha))  # fur tuft
        if eyes:
            d.point((9, cy + tilt), fill=(255, 70, 60, alpha))
            d.point((11, cy + tilt), fill=(255, 70, 60, alpha))
        if mouth or eyes:
            d.point((9, cy + 2 + tilt), fill=(255, 255, 255, alpha))  # fangs
            d.point((10, cy + 2 + tilt), fill=(255, 255, 255, alpha))
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST, center=(10, 8))
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body([4, 1, -3, 1][i], dy=[0, 0, 1, 1][i] if name == "idle" else 0)
        if name == "windup":
            return body(5 + i, dy=-1 - i)
        if name == "attack":
            return body(-2, dy=1, rot=[-20, -35, -25][i], tilt=1, mouth=True)
        if name == "hurt":
            return body(2, eyes=False)
        return body(-3, dy=i, rot=i * 60, eyes=False, alpha=255 - i * 40)

    return lay, fn, None


# =================================================================== cultist
def robed(fw, fh, robe, hood_in=(20, 10, 15), eye=(255, 200, 40), trim=(200, 160, 60), sigil=True):
    """Shared robed caster: robe with folds and a sash, deep hood, sleeves."""

    def body(sway=0, hands=(14, 15), orb=0, flash=False, dis=0, alpha=255, lean=0, orb_col=(200, 90, 255)):
        im = blank(fw, fh)
        L = lean
        m = mask(fw, fh, lambda d: d.polygon([(8 + L, 10), (15 + L, 10), (18 + sway, 27), (5 + sway, 27)], fill=FULL))
        lit(im, m, robe, 9 + L, 14, 7, 12, alpha, flat=0.3)
        d = ImageDraw.Draw(im)
        for fx in (8, 11, 14):  # folds
            d.line((fx + L, 14, fx + sway + (fx - 11) // 2, 26), fill=sh(robe, 0.68, alpha))
        d.line((6 + sway, 26, 17 + sway, 26), fill=sh(robe, 0.55, alpha))  # hem shadow
        d.line((5 + sway, 27, 18 + sway, 27), fill=rgba(trim, alpha))  # hem trim
        d.line((8 + L, 17, 15 + L, 17), fill=rgba(trim, alpha))  # sash
        if sigil:
            d.point((12 + L, 18), fill=rgba(trim, alpha))
            d.point((11 + L, 19), fill=rgba(trim, alpha))
            d.point((13 + L, 19), fill=rgba(trim, alpha))
        hood = mask(fw, fh, lambda dd: dd.polygon([(7 + L, 12), (9 + L, 3), (13 + L, 2), (16 + L, 5), (17 + L, 12)], fill=FULL))
        lit(im, hood, robe, 10 + L, 5, 5, 6, alpha)
        d = ImageDraw.Draw(im)
        d.polygon([(11 + L, 5), (15 + L, 5), (16 + L, 10), (11 + L, 10)], fill=rgba(hood_in, alpha))
        e = (255, 255, 255, alpha) if flash else rgba(eye, alpha)
        d.point((12 + L, 7), fill=e)
        d.point((14 + L, 7), fill=e)
        d.point((13 + L, 9), fill=sh(hood_in, 1.8, alpha))  # chin glint
        hx, hy = hands
        d.line((12 + L, 12, hx + L, hy), fill=sh(robe, 0.85, alpha), width=2)  # sleeve
        d.rectangle((hx + L, hy, hx + 2 + L, hy + 1), fill=(205, 175, 155, alpha))
        if orb:
            d.ellipse((hx + 2 + L - orb, hy - orb, hx + 2 + L + orb, hy + orb), fill=rgba(orb_col, alpha))
            d.ellipse((hx + 2 + L - orb + 1, hy - orb + 1, hx + 2 + L, hy), fill=rgba(sh(orb_col, 1.4), alpha))
            d.point((hx + 2 + L, hy), fill=(255, 240, 255, alpha))
        if dis:
            dissolve(im, dis, color=rgba(sh(orb_col, 1.2), alpha))
        return im

    return body


def cultist():
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    body = robed(fw, fh, (116, 26, 42))

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i])
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i], hands=(14, 15 + (i % 2)))
        if name == "windup":
            return body(hands=(14, 13), orb=1 + i, lean=-1)
        if name == "attack":
            return body(hands=(16, 13), orb=[3, 1, 0][i], flash=i == 0, lean=1)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    return lay, fn, None


# ================================================================ frost imp
def frost_imp():
    """Small horned imp of frost (cultist frame layout): pale blue skin, white
    mane, icicle horns, a tail, a snowball in the hand."""
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    skin = (120, 170, 220)

    def body(sway=0, hand_y=17, ball=0, flash=False, dis=0, alpha=255, lean=0, step=0):
        im = blank(fw, fh)
        L = lean
        d = ImageDraw.Draw(im)
        # tail
        d.line((8 + L, 21, 4 + sway, 23, 3 + sway, 19), fill=rgba(sh(skin, 0.75), alpha))
        d.polygon([(2 + sway, 17), (5 + sway, 18), (3 + sway, 20)], fill=rgba(sh(skin, 0.6), alpha))
        # legs (digitigrade) with claws
        for k, x in enumerate((10 + step, 14 - step)):
            col = rgba(sh(skin, 0.8 if k == 0 else 1.0), alpha)
            d.line((x + L, 21, x - 1 + L, 24, x + 1, 27), fill=col, width=2)
            d.point((x + 2, 27), fill=(240, 250, 255, alpha))
        # body and belly
        m = mask(fw, fh, lambda dd: dd.ellipse((8 + L, 11, 17 + L, 23), fill=FULL))
        lit(im, m, skin, 11 + L, 14, 5, 6, alpha)
        d = ImageDraw.Draw(im)
        d.ellipse((11 + L, 15, 15 + L, 21), fill=rgba(sh(skin, 1.25), alpha))
        # head, mane, horns
        hm = mask(fw, fh, lambda dd: dd.ellipse((9 + L, 4, 17 + L, 12), fill=FULL))
        lit(im, hm, skin, 11 + L, 6, 4, 4, alpha)
        d = ImageDraw.Draw(im)
        for k, x in enumerate(range(8, 12)):
            d.line((x + L, 6 + (k % 2), x - 1 + L, 11), fill=(200, 225, 245, alpha) if k % 2 else (235, 245, 255, alpha))  # mane
        for hx, tip in ((11, (10, 2)), (15, (16, 2))):
            d.polygon([(hx + L, 5), (hx + 1 + L, 5), (tip[0] + L, tip[1])], fill=(150, 205, 240, alpha))
            d.point((tip[0] + L, tip[1]), fill=(235, 250, 255, alpha))
        e = (255, 255, 255, alpha) if flash else (40, 230, 255, alpha)
        d.point((14 + L, 7), fill=e)
        d.point((16 + L, 7), fill=e)
        d.line((14 + L, 10, 16 + L, 10), fill=rgba(sh(skin, 0.45), alpha))
        d.point((15 + L, 11), fill=(255, 255, 255, alpha))  # fang
        # frost crystals on the shoulder
        d.point((9 + L, 12), fill=(255, 255, 255, alpha))
        d.point((8 + L, 13), fill=(200, 240, 255, alpha))
        # arm with a snowball
        d.line((15 + L, 13, 18 + L, hand_y), fill=rgba(sh(skin, 0.9), alpha), width=2)
        if ball:
            d.ellipse((17 + L - ball, hand_y - ball, 19 + L + ball, hand_y + ball), fill=(235, 248, 255, alpha))
            d.point((17 + L, hand_y - 1), fill=(255, 255, 255, alpha))
            d.point((19 + L, hand_y + 1), fill=(160, 205, 240, alpha))
        if dis:
            dissolve(im, dis, color=(220, 245, 255, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i], ball=1)
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i], step=[-1, 0, 1, 1, 0, -1][i], ball=1)
        if name == "windup":
            return body(hand_y=12 - i, ball=1 + i // 2, lean=-1)
        if name == "attack":
            return body(hand_y=[11, 14, 16][i], ball=[2, 0, 0][i], flash=i == 0, lean=1)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    return lay, fn, None


# ============================================================== bog spitter
def bog_spitter():
    """A toad of bog mud (slime frame layout): warty back, wide mouth that
    spits, moss on top, bubbles."""
    fw, fh = 20, 16
    lay = gs.monster_layout("slime_layout", fw, fh, (10, 16))
    mud = (110, 100, 50)

    def body(w=16, h=7, dx=0, dy=0, mouth=0, eyes="o", alpha=255):
        im = blank(fw, fh)
        x0 = 10 - w / 2 + dx
        m = mask(fw, fh, lambda d: d.ellipse((x0, 15 - 2 * h + dy, x0 + w - 1, 16 + dy), fill=FULL))
        lit(im, m, mud, 9 + dx, 15 - h * 1.4 + dy, w * 0.5, h * 1.0, alpha)
        d = ImageDraw.Draw(im)
        rnd = random.Random(3)
        for _ in range(6):  # warts
            x = rnd.uniform(x0 + 2, x0 + w - 3)
            y = rnd.uniform(15 - 1.6 * h + dy, 14 + dy)
            d.point((x, y), fill=rgba(sh(mud, 0.6), alpha))
            d.point((x - 1, y - 1), fill=rgba(sh(mud, 1.3), alpha))
        d.line((x0 + 3, 15 - 2 * h + dy + 1, x0 + w - 5, 15 - 2 * h + dy + 1), fill=(80, 140, 50, alpha))  # moss
        d.point((x0 + 5, 15 - 2 * h + dy), fill=(110, 170, 60, alpha))
        # front legs
        for lx in (x0 + 3, x0 + w - 5):
            d.line((lx, 15 + dy, lx + 2, 15 + dy), fill=rgba(sh(mud, 0.7), alpha))
        # bulging eyes on top: yellow with a slit pupil
        ey = int(15 - 2 * h + dy + 1)
        for ex in (int(10 + dx), int(10 + dx + 4)):
            d.ellipse((ex - 2, ey - 3, ex + 1, ey), fill=rgba(sh(mud, 1.15), alpha))
            if eyes == "o":
                d.rectangle((ex - 1, ey - 2, ex, ey - 1), fill=(250, 210, 50, alpha))
                d.point((ex, ey - 2), fill=(30, 20, 10, alpha))
            else:
                d.line((ex - 1, ey - 2, ex, ey - 1), fill=(30, 25, 10, alpha))
        # wide mouth across the front (open: goo inside)
        my = int(15 - h * 0.7 + dy)
        if mouth:
            d.ellipse((10 + dx - 1, my - mouth, 10 + dx + 8, my + mouth), fill=(60, 26, 24, alpha))
            d.line((10 + dx, my - mouth + 1, 10 + dx + 7, my - mouth + 1), fill=(150, 140, 60, alpha))
        else:
            d.line((10 + dx - 2, my - 1, 10 + dx + 1, my, 10 + dx + 8, my), fill=(50, 40, 20, alpha))
            d.line((10 + dx - 1, my + 1, 10 + dx + 7, my + 1), fill=rgba(sh(mud, 1.2), alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            k = [0, 1, 0, -1][i]
            return body(16 - k, 7 + k)
        if name == "walk":
            hop = [0, -2, -4, -4, -2, 0][i]
            return body(16, 7, dy=hop)
        if name == "windup":
            return body(16 + i, 6 - i // 2, mouth=1)
        if name == "attack":
            return body(17, 7, dx=1, mouth=[3, 2, 1][i])
        if name == "hurt":
            return body(17, 6 + i, eyes="x")
        k = i + 1
        return fade(body(16 + k, max(1, 7 - k), eyes="x"), 255 - i * 35)

    return lay, fn, None


# ==================================================================== spider
def spider():
    fw, fh = 22, 14
    lay = gs.monster_layout("spider_layout", fw, fh, (11, 14), counts={"windup": 3, "attack": 3, "death": 5})
    chit = (72, 48, 66)

    def body(leg=0, crouch=0, eyes=(255, 40, 40), alpha=255, flat=0, open_jaw=False):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + crouch + flat
        # 8 legs with a knee joint and a darker far side
        for k, side in enumerate((-1, 1)):
            for j in range(4):
                x0 = 11 + side * (2 + j)
                lift = ((leg + j + k) % 2) * 2
                knee = (x0 + side * 4, cy - 4 - lift + flat)
                foot = (x0 + side * 6, 13)
                col = rgba(sh(chit, 0.75 if (j + k) % 2 else 1.0), alpha)
                d.line((x0, cy, knee[0], knee[1]), fill=col)
                d.line((knee[0], knee[1], foot[0], foot[1]), fill=col)
                d.point(knee, fill=rgba(sh(chit, 1.5), alpha))
        # abdomen with a red hourglass, cephalothorax, eyes, fangs
        ab = mask(fw, fh, lambda dd: dd.ellipse((4, cy - 5 + flat, 13, cy + 3), fill=FULL))
        lit(im, ab, (86, 58, 80), 7, cy - 3, 5, 4, alpha)
        ce = mask(fw, fh, lambda dd: dd.ellipse((12, cy - 3 + flat, 18, cy + 2), fill=FULL))
        lit(im, ce, chit, 14, cy - 2, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        d.point((8, cy - 2 + flat), fill=(220, 50, 50, alpha))
        d.point((8, cy - 1 + flat), fill=(160, 30, 30, alpha))
        d.point((8, cy + flat), fill=(220, 50, 50, alpha))
        for k in range(3):  # hair bristles
            d.point((5 + k * 2, cy - 5 + flat), fill=rgba(sh(chit, 1.4), alpha))
        e = rgba(eyes, alpha)
        for x, y in ((16, cy - 1 + flat), (17, cy - 2 + flat), (15, cy - 2 + flat), (17, cy)):
            d.point((x, y), fill=e)
        d.point((18, cy + 1), fill=(225, 220, 200, alpha))
        if open_jaw:
            d.line((18, cy, 20, cy + 2), fill=(225, 220, 200, alpha))
            d.line((17, cy + 1, 19, cy + 3), fill=(225, 220, 200, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(leg=i % 2)
        if name == "walk":
            return body(leg=i)
        if name == "windup":
            return body(crouch=1 + i // 2, eyes=(255, 200, 40))
        if name == "attack":
            return body(open_jaw=True)
        if name == "hurt":
            return body(eyes=(255, 255, 255))
        return body(flat=min(4, i + 1), alpha=255 - i * 45)

    return lay, fn, None


# ===================================================================== golem
def golem():
    fw, fh = 28, 30
    lay = gs.monster_layout("golem_layout", fw, fh, (14, 30), counts={"windup": 3, "attack": 3, "death": 6})
    stone = (112, 106, 100)

    def block(im, box, base, cx=None, cy=None):
        x0, y0, x1, y1 = box
        m = mask(fw, fh, lambda d: d.rectangle(box, fill=FULL))
        lit(im, m, base, cx if cx is not None else x0, cy if cy is not None else y0, (x1 - x0 + 2), (y1 - y0 + 2), flat=0.5)
        d = ImageDraw.Draw(im)
        d.line((x0, y0, x1, y0), fill=sh(base, 1.35))
        d.line((x1, y0, x1, y1), fill=sh(base, 0.62))
        d.line((x0, y1, x1, y1), fill=sh(base, 0.55))

    def body(step=0, arms_up=0, crouch=0, core=(80, 220, 255), crumble=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if crumble:
            rnd = random.Random(crumble)
            for k in range(crumble + 4):
                x = 2 + (k * 7) % 21
                y = 29 - (k % 3) * 2
                d.rectangle((x, y - 3, x + 4, y), fill=sh(stone, 0.75 + rnd.random() * 0.4))
                d.line((x, y - 3, x + 4, y - 3), fill=sh(stone, 1.3))
            d.point((13, 27), fill=rgba(core) if crumble < 3 else sh(stone, 0.5))
            return im
        y0 = crouch
        block(im, (7 + step, 22 + y0, 12 + step, 29), sh(stone, 0.85))  # legs
        block(im, (15 - step, 22 + y0, 20 - step, 29), stone)
        block(im, (5, 9 + y0, 22, 23 + y0), stone, 8, 11 + y0)  # torso
        block(im, (9, 3 + y0, 18, 10 + y0), sh(stone, 1.08), 11, 4 + y0)  # head
        d = ImageDraw.Draw(im)
        # cracks and moss
        d.line((7, 12 + y0, 10, 16 + y0, 9, 20 + y0), fill=sh(stone, 0.5))
        d.line((19, 10 + y0, 17, 14 + y0), fill=sh(stone, 0.5))
        for x, y in ((6, 9 + y0), (7, 9 + y0), (12, 3 + y0), (20, 9 + y0)):
            d.point((x, y), fill=(90, 150, 70, 255))
        # glowing eye slit, rune lines and the core with a ring
        cc = rgba(core)
        d.rectangle((13, 5 + y0, 17, 6 + y0), fill=(30, 30, 35, 255))
        d.point((14, 5 + y0), fill=cc)
        d.point((16, 5 + y0), fill=cc)
        d.ellipse((11, 13 + y0, 16, 18 + y0), fill=sh(core, 0.6))
        d.ellipse((12, 14 + y0, 15, 17 + y0), fill=cc)
        d.point((13, 15 + y0), fill=(255, 255, 255, 255))
        d.line((16, 16 + y0, 20, 16 + y0, 20, 20 + y0), fill=sh(core, 0.8))
        d.line((6, 21 + y0, 10, 21 + y0), fill=sh(core, 0.8))
        # boulder fists
        ay = 12 + y0 - arms_up * 8
        for x0 in (1, 22):
            block(im, (x0, ay, x0 + 4, ay + 7), sh(stone, 0.92))
            fist = mask(fw, fh, lambda dd, x0=x0: dd.ellipse((x0 - 1, ay + 6, x0 + 5, ay + 11), fill=FULL))
            lit(im, fist, sh(stone, 0.95), x0 + 1, ay + 7, 3, 3)
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(crouch=[0, 0, 1, 1][i])
        if name == "walk":
            return body(step=[-1, 0, 1, 1, 0, -1][i], crouch=i % 2)
        if name == "windup":
            return body(arms_up=1, crouch=-i, core=(255, 200, 80))
        if name == "attack":
            return body(arms_up=0, crouch=[2, 3, 1][i], core=(255, 120, 60))
        if name == "hurt":
            return body(core=(255, 255, 255))
        return body(crumble=i) if i > 1 else body(crouch=2 + i * 2, core=(60, 60, 60))

    return lay, fn, None


# ===================================================================== ghost
def ghost():
    fw, fh = 18, 22
    lay = gs.monster_layout("ghost_layout", fw, fh, (9, 18), "fly", {"idle": 4, "fly": 4, "windup": 3, "attack": 3, "death": 5})
    mist = (200, 222, 244)

    def body(phase=0.0, alpha=170, mouth=False, eyes=(180, 230, 255), dis=0):
        im = blank(fw, fh)
        m = mask(fw, fh, lambda d: (d.pieslice((2, 1, 15, 16), 180, 360, fill=FULL), d.rectangle((2, 8, 15, 15), fill=FULL)))
        d = ImageDraw.Draw(m)
        for k in range(4):
            x = 2 + k * 4
            off = int(math.sin(phase + k) * 2)
            d.polygon([(x, 15), (x + 4, 15), (x + 2 + off // 2, 19 + off)], fill=FULL)
        lit(im, m, mist, 6, 5, 7, 9, 255)
        # transparency fades towards the tail
        px = im.load()
        for y in range(fh):
            for x in range(fw):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = (r, g, b, int(alpha * (1.0 - max(0, y - 10) * 0.07)))
        d = ImageDraw.Draw(im)
        for k in range(3):  # inner wisps
            yy = 9 + k * 3
            d.arc((4 + k, yy - 2, 12 - k, yy + 2), 200 + int(phase * 20) % 40, 330, fill=(240, 248, 255, alpha // 2))
        # hollow eyes with a glow, sorrowful brow
        for ex in (5, 10):
            d.rectangle((ex, 6, ex + 1, 8), fill=(20, 24, 50, 230))
            d.point((ex + 1, 7), fill=(eyes[0], eyes[1], eyes[2], 255))
        d.line((4, 5, 6, 4), fill=(150, 170, 200, alpha))
        d.line((11, 4, 13, 5), fill=(150, 170, 200, alpha))
        if mouth:
            d.ellipse((6, 10, 10, 14), fill=(20, 20, 40, 230))
        else:
            d.arc((6, 11, 10, 13), 200, 340, fill=(60, 70, 110, alpha))
        if dis:
            dissolve(im, dis, seed=3)
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body(i * 1.5)
        if name == "windup":
            return body(i, 200 + i * 15, False, (255, 120, 120))
        if name == "attack":
            return body(i, 240, True, (255, 80, 80))
        if name == "hurt":
            return body(0, 255, True, (255, 255, 255))
        return body(i, 170 - i * 30, dis=1 + i * 2)

    return lay, fn, None


# ================================================================== summoner
def summoner():
    fw, fh = 24, 28
    lay = gs.monster_layout("summoner_layout", fw, fh, (12, 28), counts={"windup": 4, "attack": 3})
    robe_body = robed(fw, fh, (42, 74, 52), hood_in=(14, 22, 16), eye=(130, 255, 150), trim=(225, 220, 200), sigil=False)

    def body(sway=0, staff_up=0, glow=0, alpha=255, dis=0):
        im = robe_body(sway=sway, hands=(17, 15 - staff_up * 3), alpha=alpha)
        d = ImageDraw.Draw(im)
        # bone necklace
        for k, x in enumerate((10, 12, 14)):
            d.point((x, 12 + (k % 2)), fill=(230, 225, 205, alpha))
        # staff with a skull, glowing sockets
        sy = 6 - staff_up * 4
        d.line((19, sy, 19, 27), fill=(110, 80, 50, alpha))
        d.line((20, sy + 2, 20, 27), fill=(75, 52, 34, alpha))
        d.point((19, sy + 8), fill=(160, 120, 80, alpha))  # binding
        d.ellipse((17, sy - 3, 21, sy + 1), fill=(228, 222, 202, alpha))
        d.point((18, sy - 2), fill=(250, 248, 235, alpha))
        socket = (140, 255, 160, alpha) if glow else (30, 40, 30, alpha)
        d.point((18, sy - 1), fill=socket)
        d.point((20, sy - 1), fill=socket)
        d.line((18, sy + 1, 20, sy + 1), fill=(150, 145, 130, alpha))
        if glow:
            d.ellipse((19 - glow, sy - 1 - glow, 19 + glow, sy - 1 + glow), outline=(140, 255, 160, alpha))
            d.point((19 + glow, sy - 1), fill=(220, 255, 225, alpha))
        if dis:
            dissolve(im, dis, color=(140, 255, 160, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i])
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i])
        if name == "windup":
            return body(staff_up=1, glow=1 + i)
        if name == "attack":
            return body(staff_up=1, glow=[5, 3, 1][i])
        if name == "hurt":
            return body(sway=-2)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    return lay, fn, None


# ================================================================ drowned
def drowned():
    """A bloated drowned corpse: rot-green flesh, seaweed skirt, driftwood club."""
    fw, fh = 24, 28
    lay = gs.monster_layout("drowned_layout", fw, fh, (12, 28))  # skeleton frame size
    skin = (118, 148, 118)
    weed = (56, 108, 76)
    race = dict(leg=7, torso=8)

    def body(p, alpha=255, eye=(150, 255, 190), pile=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(skin, alpha)
        dark = sh(skin, 0.62, alpha)
        if pile:
            d.ellipse((7, 22, 18, 27), fill=c)
            d.point((11, 24), fill=(18, 40, 30, alpha))
            d.point((14, 25), fill=sh(skin, 1.2, alpha))
            return im
        s = gs.skel(p, race, cx=12, ground=27)
        for side in ("l", "r"):
            col = c if side == "r" else dark
            d.line([s["hip"], s[side + "knee"]], fill=col)
            d.line([s[side + "knee"], s[side + "foot"]], fill=col)
            fx, fy = s[side + "foot"]
            d.line((fx, fy, fx + 2, fy), fill=col)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        d.line((hx - 2, hy, hx + 2, hy), fill=c)
        # bloated belly with a navel gash
        d.ellipse((hx - 4, ny + 3, hx + 4, hy + 4), fill=c)
        d.line((hx - 1, ny + 5, hx - 1, hy + 2), fill=dark)
        # seaweed skirt
        for k, x in enumerate((hx - 3, hx, hx + 3)):
            d.polygon([(x - 1, hy + 1), (x + 1, hy + 1), (x, hy + 5 + (k % 2))], fill=rgba(weed, alpha))
        # ribs showing through the skin
        for k in range(2):
            y = ny + 4 + k * 2
            d.arc((nx - 3, y, nx + 5, y + 2), 200, 320, fill=dark)
        d.line([s["shoulder"], s["lhand"]], fill=dark)
        # sunken head: algae crown, hollow sockets with glow, trailing drip
        sx, sy = s["head"]
        d.ellipse((sx - 3, sy - 3, sx + 3, sy + 2), fill=c)
        d.point((sx - 2, sy - 3), fill=rgba(weed, alpha))
        d.point((sx + 1, sy - 4), fill=rgba(weed, alpha))
        d.point((sx + 3, sy - 2), fill=rgba(weed, alpha))
        d.rectangle((sx, sy - 1, sx + 1, sy), fill=(16, 34, 26, alpha))
        d.rectangle((sx + 2, sy - 1, sx + 3, sy), fill=(16, 34, 26, alpha))
        d.point((sx + 1, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 3, sy - 1), fill=rgba(eye, alpha))
        d.line((sx - 1, sy + 2, sx + 3, sy + 2), fill=dark)
        d.point((sx - 1, sy + 3), fill=(120, 200, 170, alpha))  # water drip
        d.line([s["shoulder"], s["rhand"]], fill=c)
        # driftwood club
        rx, ry = s["rhand"]
        d.ellipse((rx - 2, ry - 6, rx + 4, ry + 1), fill=(96, 74, 54, alpha))
        d.line((rx, ry, rx + 1, ry + 3), fill=(78, 58, 44, alpha))
        d.point((rx - 1, ry - 4), fill=(130, 104, 78, alpha))
        return im

    P = gs.P

    def fn(name, i, n):
        if name == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(2, 6)))
        if name == "walk":
            lx = [-3, -1, 1, 3, 1, -1][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(2 + lx // 2, 6)))
        if name == "windup":
            return body(P(lean=-1 - i, ra=(-2, -6 - i)), eye=(255, 200, 120))
        if name == "attack":
            return body(P(lean=2, lf=(-3, 0), rf=(4, 0), ra=[(4, -3), (7, 1), (6, 4)][i]), eye=(220, 255, 200))
        if name == "hurt":
            return body(P(lean=-3, by=1, ra=(3, 3)), eye=(255, 255, 255))
        return body(P(), pile=1, alpha=255 - i * 30)

    return lay, fn, None


# ============================================================ leech swarm
def leech():
    """A blood leech: a fast flat worm with sucker maw and segment rings."""
    fw, fh = 20, 16
    lay = gs.monster_layout("leech_layout", fw, fh, (10, 16))  # slime frame size
    base = (146, 58, 50)

    def body(w, h, dx=0, dy=0, alpha=255, eyes=True, mouth=False):
        im = blank(fw, fh)
        x0 = 10 - w / 2 + dx
        m = mask(fw, fh, lambda d: d.ellipse((x0, 10 + dy, x0 + w - 1, 15 + dy), fill=FULL))
        lit(im, m, base, 10 + dx, 12 + dy, w * 0.5, h * 0.7, alpha)
        d = ImageDraw.Draw(im)
        # segment rings
        for k in range(3):
            sx = x0 + w * (0.3 + k * 0.18)
            d.arc((sx - 1, 10 + dy + 1, sx + 2, 15 + dy), 250, 290, fill=rgba(sh(base, 0.55), alpha))
        # sucker maw on the leading edge
        mx = 10 + dx + w // 2 - 1
        d.ellipse((mx - 1, 12 + dy - 1, mx + 2, 12 + dy + 2), fill=(70, 22, 20, alpha))
        if mouth:
            d.ellipse((mx, 12 + dy, mx + 2, 12 + dy + 2), fill=(180, 40, 40, alpha))
            for fy in (11 + dy, 12 + dy, 13 + dy):
                d.point((mx + 2, fy), fill=(255, 220, 210, alpha))
        ey = 12 + dy - 1
        dark = (30, 8, 8, alpha)
        if eyes:
            d.point((mx - 3, ey), fill=(255, 190, 180, alpha))
            d.point((mx - 1, ey), fill=(255, 190, 180, alpha))
            d.point((mx - 3, ey + 1), fill=dark)
            d.point((mx - 1, ey + 1), fill=dark)
        d.line((x0 + 1, 15 + dy, x0 + w - 2, 15 + dy), fill=sh(base, 0.55, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            k = [0, 1, 0, -1][i]
            return body(13 - k, 4 + k, dy=k // 2)
        if name == "walk":
            sq = [0, 2, 3, 2, 0, -2][i]
            return body(14 - sq, 5 + sq // 2, dx=[0, 1, 2, 1, 0, -1][i], dy=[0, -1, -1, 0, 0, 1][i])
        if name == "windup":
            return body(12, 6, dx=1, dy=-1)
        if name == "attack":
            return body(15, 5, dx=2, mouth=True)
        if name == "hurt":
            return body(13, 5, eyes=False)
        return body(14 - i, 4, dy=i, alpha=255 - i * 35)

    return lay, fn, None


# ========================================================== drowned priest
def drowned_priest():
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    body = robed(fw, fh, (26, 96, 88), hood_in=(8, 36, 32), eye=(150, 255, 230),
                 trim=(96, 180, 160), sigil=True)

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i], orb_col=(90, 230, 200))
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i], hands=(14, 15 + (i % 2)), orb_col=(90, 230, 200))
        if name == "windup":
            return body(hands=(14, 13), orb=1 + i, lean=-1, orb_col=(120, 255, 220))
        if name == "attack":
            return body(hands=(16, 13), orb=[3, 1, 0][i], flash=i == 0, lean=1, orb_col=(120, 255, 220))
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30, orb_col=(90, 230, 200))

    return lay, fn, None


MONSTERS = {
    # name: (builder, sheet file, write the layout .tres, outline)
    "slime": (slime, "slime", True, True),
    "skeleton": (skeleton, "skeleton", True, True),
    "bat": (bat, "bat", True, True),
    "cultist": (cultist, "cultist", True, True),
    "spider": (spider, "spider", True, True),
    "golem": (golem, "golem", True, True),
    "ghost": (ghost, "ghost", True, False),
    "summoner": (summoner, "summoner", True, True),
    "frost_imp": (frost_imp, "frost_imp", False, True),  # uses cultist_layout
    "bog_spitter": (bog_spitter, "bog_spitter", False, True),  # uses slime_layout
    "drowned": (drowned, "drowned", False, True),  # uses skeleton_layout
    "leech": (leech, "leech", False, True),  # uses slime_layout
    "drowned_priest": (drowned_priest, "drowned_priest", False, True),  # uses cultist_layout
}


def main():
    for name, (builder, file, write_layout, outline) in MONSTERS.items():
        lay, fn, _ = builder()
        gs.render_sheet(lay, fn, "sprites/enemies/%s_sheet.png" % file, do_outline=outline)
        if write_layout:
            lay.write_tres()
        # static icon (bestiary, fallback): the first idle frame
        sheet = Image.open(os.path.join(A, "sprites/enemies/%s_sheet.png" % file))
        sheet.crop((0, 0, lay.fw, lay.fh)).save(os.path.join(A, "sprites/enemies/%s.png" % file))
    print("monsters generated")


if __name__ == "__main__":
    main()
