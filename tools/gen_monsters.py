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
def glow_dot(g, x, y, r, col, a):
	"""Local bloom (gen_structures imports this module - keep it standalone)."""
	px = g.load()
	w, h = g.size
	for yy in range(max(0, int(y - r - 1)), min(h, int(y + r + 2))):
		for xx in range(max(0, int(x - r - 1)), min(w, int(x + r + 2))):
			dx, dy = xx - x, yy - y
			d2 = dx * dx + dy * dy
			if d2 > r * r:
				continue
			t = 1.0 - (d2 / (r * r)) * 0.7
			src = px[xx, yy]
			px[xx, yy] = (min(255, int(src[0] + col[0] * t * a)),
					min(255, int(src[1] + col[1] * t * a)),
					min(255, int(src[2] + col[2] * t * a)), src[3])

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
            # hashed noise (no diagonal stripes); the top crumbles first
            v = ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) % 1000 / 100.0
            v += (y / h - 0.5) * 2.0
            if v < amount:
                px[x, y] = (0, 0, 0, 0)
            elif color and amount > 2 and v < amount + 0.7:
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
def _limb(d, a, b, col, alpha, hi=None):
    """Two-pixel limb with a lit upper edge (like the skeleton / imp limbs)."""
    d.line((a[0], a[1], b[0], b[1]), fill=rgba(col, alpha), width=2)
    if hi:
        d.line((a[0], a[1] - 1, b[0], b[1] - 1), fill=rgba(hi, alpha))


def drowned():
    """A bloated drowned corpse: swollen grey-green flesh with lit volume,
    torn sailor's shirt, kelp in the hair and on the hips, barnacles,
    a dripping anchor-chain club."""
    fw, fh = 24, 28
    lay = gs.monster_layout("drowned_layout", fw, fh, (12, 28))  # skeleton frame size
    skin = (122, 150, 124)
    shirt = (84, 96, 112)
    weed = (52, 104, 70)
    race = dict(leg=7, torso=8)

    def body(p, alpha=255, eye=(150, 255, 190), pile=0, jaw=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            # a puddle with kelp and the shirt left behind
            m = mask(fw, fh, lambda dd: dd.ellipse((5, 24, 20, 28), fill=FULL))
            lit(im, m, (70, 110, 120), 9, 25, 7, 2, alpha, flat=0.4)
            d = ImageDraw.Draw(im)
            d.rectangle((8, 23 - pile // 2, 15, 26), fill=rgba(shirt, alpha))
            d.line((8, 23 - pile // 2, 15, 23 - pile // 2), fill=sh(shirt, 1.3, alpha))
            for x in (7, 17):
                d.line((x, 26, x + 1, 22), fill=rgba(weed, alpha))
            d.point((12, 25), fill=(170, 230, 210, alpha))
            return im
        s = gs.skel(p, race, cx=12, ground=27)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # legs: swollen shins, bare feet
        for side in ("l", "r"):
            col = sh(skin, 0.7 if side == "l" else 0.95)[:3]
            _limb(d, (hx + (-1 if side == "l" else 1), hy + 1), s[side + "knee"], col, alpha, sh(skin, 1.15)[:3] if side == "r" else None)
            _limb(d, s[side + "knee"], s[side + "foot"], col, alpha)
            fx, fy = s[side + "foot"]
            d.line((fx, fy, fx + 2, fy), fill=rgba(sh(col, 0.85), alpha))
        # back arm
        _limb(d, s["shoulder"], s["lhand"], sh(skin, 0.65)[:3], alpha)
        # bloated torso: lit belly bulging out of the torn shirt
        tm = mask(fw, fh, lambda dd: dd.ellipse((hx - 5, ny, hx + 5, hy + 3), fill=FULL))
        lit(im, tm, skin, hx - 2, ny + 3, 5, 6, alpha)
        d = ImageDraw.Draw(im)
        sm = mask(fw, fh, lambda dd: dd.polygon([(nx - 4, ny), (nx + 4, ny), (nx + 3, ny + 5), (nx - 1, ny + 3), (nx - 4, ny + 6)], fill=FULL))
        lit(im, sm, shirt, nx - 2, ny + 1, 4, 3, alpha, flat=0.3)
        d = ImageDraw.Draw(im)
        d.line((nx - 4, ny + 6, nx - 2, ny + 4), fill=sh(shirt, 0.6, alpha))  # torn edge
        d.line((hx, ny + 5, hx + 1, hy), fill=sh(skin, 0.6, alpha))  # stretched seam of the belly
        d.point((hx + 2, hy - 3), fill=sh(skin, 1.3, alpha))
        # barnacles
        for bx, by in ((hx - 3, hy - 1), (hx + 3, ny + 7)):
            d.point((bx, by), fill=(220, 214, 196, alpha))
            d.point((bx + 1, by), fill=(150, 140, 126, alpha))
        # kelp belt
        for k, x in enumerate((hx - 4, hx - 1, hx + 2, hx + 4)):
            d.line((x, hy + 1, x + (k % 2), hy + 5 + (k % 2)), fill=rgba(sh(weed, 0.8 + 0.2 * (k % 2)), alpha))
        d.line((hx - 4, hy + 1, hx + 4, hy + 1), fill=rgba(weed, alpha))
        # sunken head: lit skull-like face, hollow glowing eyes, slack jaw, kelp hair
        sx, sy = s["head"]
        hm = mask(fw, fh, lambda dd: dd.ellipse((sx - 3, sy - 4, sx + 3, sy + 2), fill=FULL))
        lit(im, hm, sh(skin, 1.05)[:3], sx - 1, sy - 2, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        d.rectangle((sx, sy - 1, sx + 1, sy), fill=(16, 34, 26, alpha))
        d.rectangle((sx + 2, sy - 1, sx + 3, sy), fill=(16, 34, 26, alpha))
        d.point((sx + 1, sy - 1), fill=rgba(eye, alpha))
        d.point((sx + 3, sy - 1), fill=rgba(eye, alpha))
        d.rectangle((sx, sy + 2, sx + 3, sy + 2 + jaw), fill=(30, 46, 38, alpha))  # open mouth
        d.line((sx - 1, sy + 3 + jaw, sx + 3, sy + 3 + jaw), fill=sh(skin, 0.7, alpha))  # jaw
        for k, (kx, ln) in enumerate(((sx - 3, 6), (sx - 2, 4))):  # kelp hair at the back of the head
            d.line((kx, sy - 4, kx - 1, sy - 4 + ln), fill=rgba(sh(weed, 1.1 if k % 2 else 0.85), alpha))
        d.point((sx, sy - 4), fill=rgba(weed, alpha))
        d.point((sx + 4, sy + 1), fill=(150, 220, 200, alpha))  # water drip
        # front arm and the club: driftwood with a rusty chain
        rx, ry = s["rhand"]
        _limb(d, s["shoulder"], (rx, ry), skin, alpha, sh(skin, 1.2)[:3])
        cm = mask(fw, fh, lambda dd: dd.ellipse((rx - 2, ry - 7, rx + 3, ry + 1), fill=FULL))
        lit(im, cm, (104, 80, 58), rx - 1, ry - 5, 3, 4, alpha)
        d = ImageDraw.Draw(im)
        d.line((rx, ry - 6, rx + 1, ry - 1), fill=(78, 58, 44, alpha))  # grain
        for k in range(3):
            d.point((rx + 2, ry - 5 + k * 2), fill=(150, 90, 60, alpha))  # chain links
        d.point((rx - 1, ry - 6), fill=(220, 214, 196, alpha))  # barnacle
        return im

    P = gs.P

    def fn(name, i, n):
        if name == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(2, 6)), jaw=[0, 0, 1, 1][i])
        if name == "walk":
            lx = [-3, -1, 1, 3, 1, -1][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(2 + lx // 2, 6)))
        if name == "windup":
            return body(P(lean=-1 - i, ra=(-2, -6 - i)), eye=(220, 255, 200), jaw=1)
        if name == "attack":
            return body(P(lean=2, lf=(-3, 0), rf=(4, 0), ra=[(4, -3), (7, 1), (6, 4)][i]), eye=(255, 255, 220), jaw=1)
        if name == "hurt":
            return body(P(lean=-3, by=1, ra=(3, 3)), eye=(255, 255, 255), jaw=1)
        if i < 2:
            return body(P(crouch=2 + i * 2, by=1 + i, ra=(5, 5)), eye=(60, 110, 90))
        return body(P(), pile=i, alpha=255 - (i - 2) * 30)

    return lay, fn, None


# ============================================================ leech swarm
def leech():
    """A blood leech (slime frame layout): a glossy segmented worm that
    rears up, dorsal stripes, a round sucker with a ring of teeth."""
    fw, fh = 20, 16
    lay = gs.monster_layout("leech_layout", fw, fh, (10, 16))
    base = (138, 50, 52)
    belly = (196, 120, 96)

    def body(w=14, rear=0, wave=0.0, dx=0, alpha=255, eyes=True, mouth=False, dis=0):
        im = blank(fw, fh)
        x0 = 10 - w / 2 + dx
        # segments along a wave: each one a small lit ellipse, tail to head
        segs = 6
        pts = []
        for k in range(segs):
            t = k / (segs - 1)
            x = x0 + 1 + t * (w - 3)
            y = 13 - math.sin(t * math.pi + wave) * 1.2 - (rear * t * t)
            r = 2.0 + 0.6 * math.sin(t * math.pi)
            pts.append((x, y, r))
        for k, (x, y, r) in enumerate(pts):
            m = mask(fw, fh, lambda dd, x=x, y=y, r=r: dd.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.9), fill=FULL))
            lit(im, m, sh(base, 0.9 + 0.04 * k)[:3], x - 1, y - 1, r, r * 0.9, alpha)
        d = ImageDraw.Draw(im)
        for k, (x, y, r) in enumerate(pts[:-1]):
            d.point((x + r * 0.6, y + r * 0.5), fill=sh(base, 0.55, alpha))  # ring groove
            d.point((x, y - r * 0.6), fill=rgba((230, 150, 70), alpha) if k % 2 else sh(base, 1.35, alpha))  # dorsal stripe
            d.point((x, y + r * 0.7), fill=rgba(belly, alpha))  # pale belly
        hx, hy, hr = pts[-1]
        # sucker: dark disc, pale lip, teeth when attacking
        d.ellipse((hx + hr - 2, hy - 2, hx + hr + 1, hy + 1), fill=(60, 16, 20, alpha))
        d.arc((hx + hr - 2, hy - 2, hx + hr + 1, hy + 1), 270, 90, fill=rgba(belly, alpha))
        if mouth:
            for ty in (hy - 1, hy, hy + 1):
                d.point((hx + hr, ty), fill=(255, 236, 220, alpha))
        if eyes:
            d.point((hx - 1, hy - hr * 0.7), fill=(255, 210, 120, alpha))
            d.point((hx + 1, hy - hr * 0.7), fill=(255, 210, 120, alpha))
        d.point((x0 + w * 0.4, 13 - hr), fill=(255, 220, 220, alpha))  # gloss
        if dis:
            dissolve(im, dis, color=(200, 40, 40, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(14, wave=i * math.pi / 2)
        if name == "walk":
            sq = [0, 2, 3, 2, 0, -1][i]
            return body(15 - sq, wave=i * math.pi / 3, dx=[0, 1, 2, 1, 0, -1][i])
        if name == "windup":
            return body(12, rear=3, dx=-1)
        if name == "attack":
            return body(16, rear=1, dx=2, mouth=True)
        if name == "hurt":
            return body(13, rear=1, eyes=False)
        return body(14 - i, wave=i, alpha=255 - i * 30, dis=2 + i * 2 if i < 4 else 9)

    return lay, fn, None


# ========================================================== drowned priest
def drowned_priest():
    """Priest of the sunken temple (cultist frame layout): a sodden robe
    hung with kelp, a coral mitre, a drowned lantern-orb; water drips."""
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    robe = (34, 92, 92)
    base = robed(fw, fh, robe, hood_in=(6, 28, 30), eye=(150, 255, 230), trim=(186, 160, 96), sigil=False)
    coral = (232, 118, 104)

    def body(sway=0, hands=(14, 15), orb=0, flash=False, dis=0, alpha=255, lean=0, drip=0):
        im = base(sway=sway, hands=hands, orb=orb, flash=flash, dis=0, alpha=alpha, lean=lean, orb_col=(110, 240, 210))
        d = ImageDraw.Draw(im)
        L = lean
        # coral mitre with branching tips
        mm = mask(fw, fh, lambda dd: dd.polygon([(10 + L, 4), (12 + L, -1), (14 + L, 4)], fill=FULL))
        lit(im, mm, coral, 11 + L, 1, 2, 3, alpha)
        d = ImageDraw.Draw(im)
        for tx, ty in ((9 + L, 1), (15 + L, 0), (12 + L, -1)):
            d.line((12 + L, 3, tx, ty), fill=rgba(coral, alpha))
            d.point((tx, ty), fill=(255, 190, 170, alpha))
        # kelp hanging from the shoulders and the sash
        for k, (kx, ln) in enumerate(((7 + L, 9), (9 + L, 6), (16 + L, 8))):
            d.line((kx, 11, kx + (1 if k % 2 else -1) + sway // 2, 11 + ln), fill=rgba((52, 110, 70) if k % 2 else (70, 130, 80), alpha))
        # shells on the sash and a fish-bone sigil
        d.point((10 + L, 17), fill=(240, 226, 200, alpha))
        d.point((14 + L, 17), fill=(240, 226, 200, alpha))
        d.line((11 + L, 20, 14 + L, 20), fill=rgba((214, 210, 190), alpha))
        for x in (12, 13):
            d.point((x + L, 19), fill=rgba((214, 210, 190), alpha))
            d.point((x + L, 21), fill=rgba((214, 210, 190), alpha))
        # dripping water from the hem
        for k, x in enumerate((7, 12, 16)):
            y = 27 - ((drip + k * 2) % 4)
            if y < 27:
                d.point((x + sway, y + 1), fill=(140, 220, 230, alpha))
        if dis:
            dissolve(im, dis, color=(140, 240, 220, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i], drip=i)
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i], hands=(14, 15 + (i % 2)), drip=i)
        if name == "windup":
            return body(hands=(14, 13), orb=1 + i, lean=-1, drip=i)
        if name == "attack":
            return body(hands=(16, 13), orb=[3, 1, 0][i], flash=i == 0, lean=1)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    return lay, fn, None


# ============================================================== sporeling
def sporeling():
    """Fungal puffball creature (slime frame layout): a lit spotted cap with
    gills under the rim, a pale stem body with stubby feet and eyes,
    spores drifting off; bursts into a cloud when it attacks."""
    fw, fh = 20, 16
    lay = gs.monster_layout("sporeling_layout", fw, fh, (10, 16))
    cap = (150, 78, 160)
    stem = (226, 210, 180)
    spot = (240, 220, 250)

    def body(squash=0, dx=0, dy=0, alpha=255, eyes="o", burst=0, puff=0, step=0, dis=0):
        im = blank(fw, fh)
        cx = 10 + dx
        top = 2 + dy + squash
        # stem body with feet
        sm = mask(fw, fh, lambda d: d.rounded_rectangle((cx - 4, top + 6, cx + 3, 14 + dy // 2), 2, fill=FULL))
        lit(im, sm, stem, cx - 2, top + 8, 4, 4, alpha, flat=0.2)
        d = ImageDraw.Draw(im)
        for fx in (cx - 3 + step, cx + 1 - step):
            d.rectangle((fx, 14, fx + 1, 15), fill=sh(stem, 0.75, alpha))
        # cap: wide dome with a rim
        cm = mask(fw, fh, lambda d: d.chord((cx - 8, top, cx + 7, top + 12 - squash), 180, 360, fill=FULL))
        lit(im, cm, cap, cx - 3, top + 1, 8, 5, alpha)
        d = ImageDraw.Draw(im)
        rim = top + 6 - squash // 2
        d.line((cx - 8, rim, cx + 7, rim), fill=sh(cap, 0.55, alpha))
        for gx in range(cx - 6, cx + 6, 2):
            d.point((gx, rim + 1), fill=sh(stem, 0.7, alpha))  # gills
        for sx, sy, r in ((cx - 4, top + 3, 1), (cx + 2, top + 2, 1), (cx + 5, top + 4, 0), (cx - 1, top + 1, 0)):
            d.ellipse((sx - r, sy - r, sx + r, sy + r), fill=rgba(spot, alpha))
        d.point((cx - 5, top + 2), fill=(255, 255, 255, alpha))  # gloss
        # face on the stem
        ey = rim + 3
        dark = (40, 20, 30, alpha)
        if eyes == "o":
            for e in (cx - 3, cx + 1):
                d.rectangle((e, ey - 1, e + 1, ey), fill=(255, 255, 240, alpha))
                d.point((e + 1, ey), fill=dark)
        else:
            for e in (cx - 3, cx + 1):
                d.line((e, ey, e + 1, ey - 1), fill=dark)
        d.point((cx - 1, ey + 2), fill=dark)
        # spores
        rnd = random.Random(puff + burst * 7)
        count = 3 + burst * 5
        for k in range(count):
            if burst:
                a = k * math.tau / count
                r = 3 + burst * 1.6
                px_, py_ = cx + math.cos(a) * r * 1.2, top + 5 + math.sin(a) * r * 0.8
            else:
                px_, py_ = cx + rnd.randint(-7, 7), top - (puff + k * 2) % 5
            d.point((px_, py_), fill=(200, 240, 170, alpha) if k % 2 else (170, 210, 140, int(alpha * 0.8)))
        if dis:
            dissolve(im, dis, color=(190, 240, 160, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(squash=[0, 1, 0, 0][i], puff=i)
        if name == "walk":
            return body(dy=[0, -2, -3, -2, 0, 0][i], squash=[1, 0, 0, 0, 1, 2][i], step=i % 2, puff=i)
        if name == "windup":
            return body(squash=2, eyes="x", puff=i)
        if name == "attack":
            return body(burst=1 + i, eyes="x")
        if name == "hurt":
            return body(squash=1, eyes="x")
        return body(squash=min(3, i), alpha=255 - i * 30, dis=2 + i * 2 if i < 4 else 9, burst=1)

    return lay, fn, None


# ============================================================ ember hound
def ember_hound():
    """Lava hound: lean basalt-skinned quadruped with glowing cracks, a mane of
    live coals, a burning tail and molten jaws (sets heroes on fire)."""
    fw, fh = 24, 28
    lay = gs.monster_layout("ember_hound_layout", fw, fh, (12, 28))
    hide = (70, 46, 44)
    lava = (255, 140, 40)
    hot = (255, 220, 120)

    def body(gait=0, crouch=0, alpha=255, eyes=True, jaw=0, pile=0, lunge=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        g0 = 27
        if pile:
            m = mask(fw, fh, lambda dd: dd.ellipse((4, 22, 20, 28), fill=FULL))
            lit(im, m, (60, 50, 50), 9, 23, 8, 3, alpha)
            d = ImageDraw.Draw(im)
            for k in range(4 - min(3, pile // 2)):
                d.point((7 + k * 3, 24 + k % 2), fill=rgba(lava, alpha))
            return im
        L = lunge
        by = 18 + crouch  # back line
        # tail: burning tip
        d.line((5 + L, by + 1, 2 + L, by + 1 + gait // 2, 1 + L, by - 2 + gait // 2), fill=rgba(hide, alpha), width=2)
        d.point((0 + L, by - 3 + gait // 2), fill=rgba(lava, alpha))
        d.point((1 + L, by - 4 + gait // 2), fill=rgba(hot, alpha))
        d.point((0 + L, by - 5 + gait // 2), fill=rgba(lava, alpha))
        # far legs (darker), then body, then near legs
        legs = [(7, -gait), (16, gait)]
        for lx, ph in legs:
            _limb(d, (lx + L, by + 3), (lx + L - 1 + ph, by + 6), sh(hide, 0.6)[:3], alpha)
            _limb(d, (lx + L - 1 + ph, by + 6), (lx + L + ph, g0), sh(hide, 0.6)[:3], alpha)
        tm = mask(fw, fh, lambda dd: dd.ellipse((4 + L, by - 1, 19 + L, by + 6), fill=FULL))
        lit(im, tm, hide, 8 + L, by, 8, 4, alpha)
        d = ImageDraw.Draw(im)
        # glowing cracks in the hide
        for (x0, y0, x1, y1) in ((7, by + 2, 10, by + 4), (12, by + 1, 14, by + 4), (15, by + 3, 17, by + 2)):
            d.line((x0 + L, y0, x1 + L, y1), fill=rgba(lava, alpha))
        d.point((10 + L, by + 4), fill=rgba(hot, alpha))
        d.line((5 + L, by + 5, 18 + L, by + 5), fill=sh(hide, 0.5, alpha))  # belly shadow
        # mane of coals along the neck and back
        for k in range(5):
            x = 9 + k * 2 + L
            h = 2 + (k % 2) + (1 if k == 3 else 0)
            d.polygon([(x - 1, by), (x, by - h - (gait % 2)), (x + 1, by)], fill=rgba(lava, alpha))
            d.point((x, by - h - (gait % 2)), fill=rgba(hot, alpha))
        for lx, ph in legs:
            _limb(d, (lx + L + 2, by + 3), (lx + L + 1 - ph, by + 6), hide, alpha, sh(hide, 1.25)[:3])
            _limb(d, (lx + L + 1 - ph, by + 6), (lx + L + 2 - ph, g0), hide, alpha)
            d.point((lx + L + 3 - ph, g0), fill=rgba(lava, alpha))  # hot claw
        # head: long muzzle, swept ears, molten jaws
        hx, hy = 19 + L, by - 2 + crouch // 2
        hm = mask(fw, fh, lambda dd: dd.ellipse((hx - 3, hy - 3, hx + 3, hy + 2), fill=FULL))
        lit(im, hm, hide, hx - 2, hy - 2, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        d.polygon([(hx + 1, hy - 1), (hx + 5, hy), (hx + 5, hy + 1), (hx + 1, hy + 2)], fill=rgba(sh(hide, 1.1), alpha))  # muzzle
        d.point((hx + 5, hy), fill=(30, 20, 20, alpha))  # nose
        d.polygon([(hx - 3, hy - 2), (hx - 5, hy - 6), (hx - 1, hy - 3)], fill=rgba(sh(hide, 0.85), alpha))  # ear
        d.point((hx - 4, hy - 5), fill=rgba(lava, alpha))
        if jaw:
            d.polygon([(hx + 1, hy + 2), (hx + 5, hy + 2 + jaw), (hx + 1, hy + 3)], fill=rgba(sh(hide, 0.8), alpha))
            d.line((hx + 2, hy + 2, hx + 4, hy + 2 + jaw // 2), fill=rgba(lava, alpha))
            d.point((hx + 4, hy + 2), fill=(255, 250, 230, alpha))  # fang
        if eyes:
            d.point((hx + 1, hy - 1), fill=rgba(hot, alpha))
            d.point((hx + 2, hy - 1), fill=rgba(lava, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(gait=0, crouch=[0, 0, 1, 1][i])
        if name == "walk":
            return body(gait=[-2, -1, 1, 2, 1, -1][i], crouch=[0, 1, 0, 0, 1, 0][i])
        if name == "windup":
            return body(crouch=2, jaw=1, lunge=-1)
        if name == "attack":
            return body(gait=2, jaw=[3, 2, 1][i], lunge=[2, 3, 1][i])
        if name == "hurt":
            return body(crouch=1, eyes=False, lunge=-1)
        if i < 2:
            return body(crouch=2 + i * 2, eyes=False)
        return body(pile=i, alpha=255 - (i - 2) * 30)

    return lay, fn, None


# ========================================================== runite sentinel
def runite_sentinel():
    """Ruins guardian: an ancient carved sentinel of bevelled stone blocks,
    a crested helm with a visor slit, rune channels that glow, moss and
    cracks, boulder fists that slam the ground."""
    fw, fh = 28, 32
    lay = gs.monster_layout("runite_layout", fw, fh, (14, 32))
    stone = (118, 120, 140)
    rune = (110, 200, 255)

    def block(im, box, base, alpha):
        x0, y0, x1, y1 = box
        m = mask(fw, fh, lambda d: d.rectangle(box, fill=FULL))
        lit(im, m, base, x0, y0, (x1 - x0 + 2), (y1 - y0 + 2), alpha, flat=0.5)
        d = ImageDraw.Draw(im)
        d.line((x0, y0, x1, y0), fill=sh(base, 1.35, alpha))
        d.line((x1, y0, x1, y1), fill=sh(base, 0.62, alpha))
        d.line((x0, y1, x1, y1), fill=sh(base, 0.55, alpha))

    def body(step=0, bob=0, arms=0, alpha=255, eye=rune, crumble=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if crumble:
            rnd = random.Random(crumble + 3)
            for k in range(crumble + 5):
                x = 3 + (k * 6) % 21
                y = 31 - (k % 3) * 2
                d.rectangle((x, y - 3, x + 4, y), fill=sh(stone, 0.75 + rnd.random() * 0.35, alpha))
                d.line((x, y - 3, x + 4, y - 3), fill=sh(stone, 1.3, alpha))
            if crumble < 4:
                d.point((13, 29), fill=rgba(rune, alpha))
            return im
        y = bob
        # legs: thick pillars with a band
        block(im, (8 + step, 24 + y, 12 + step, 31), sh(stone, 0.8)[:3], alpha)
        block(im, (16 - step, 24 + y, 20 - step, 31), sh(stone, 0.95)[:3], alpha)
        d = ImageDraw.Draw(im)
        for lx in (8 + step, 16 - step):
            d.line((lx, 28, lx + 4, 28), fill=sh(stone, 0.6, alpha))
        # torso: broad chest block and a waist block
        block(im, (9, 19 + y, 19, 24 + y), sh(stone, 0.9)[:3], alpha)
        block(im, (5, 9 + y, 23, 19 + y), stone, alpha)
        d = ImageDraw.Draw(im)
        # rune channels on the chest and the waist
        rc = rgba(eye, alpha)
        d.line((9, 12 + y, 12, 12 + y, 12, 16 + y, 16, 16 + y), fill=rc)
        d.line((19, 11 + y, 19, 14 + y), fill=rc)
        d.ellipse((13, 11 + y, 16, 14 + y), outline=rc)
        d.point((14, 12 + y), fill=(240, 250, 255, alpha))
        d.line((11, 21 + y, 17, 21 + y), fill=sh(eye, 0.7, alpha))
        # cracks and moss
        d.line((21, 10 + y, 19, 13 + y, 21, 17 + y), fill=sh(stone, 0.45, alpha))
        d.line((7, 15 + y, 9, 18 + y), fill=sh(stone, 0.45, alpha))
        for mx, my in ((5, 9 + y), (6, 9 + y), (7, 10 + y), (22, 9 + y), (12, 24 + y)):
            d.point((mx, my), fill=(86, 140, 70, alpha))
        # head: crested helm with a visor slit
        block(im, (10, 2 + y, 18, 9 + y), sh(stone, 1.05)[:3], alpha)
        d = ImageDraw.Draw(im)
        d.polygon([(13, 2 + y), (14, -1 + y), (15, 2 + y)], fill=sh(stone, 1.2, alpha))  # crest
        d.rectangle((11, 5 + y, 17, 6 + y), fill=(16, 20, 34, alpha))
        d.line((12, 5 + y, 16, 5 + y), fill=rc)
        d.point((14, 4 + y), fill=rc)  # brow rune
        # shoulders and arms with boulder fists
        ay = 10 + y - arms * 7
        for x0, f in ((1, 0.82), (22, 0.95)):
            block(im, (x0, ay, x0 + 5, ay + 8), sh(stone, f)[:3], alpha)
            fm = mask(fw, fh, lambda dd, x0=x0: dd.ellipse((x0 - 1, ay + 7, x0 + 6, ay + 13), fill=FULL))
            lit(im, fm, sh(stone, f - 0.05)[:3], x0 + 1, ay + 8, 4, 3, alpha)
            d = ImageDraw.Draw(im)
            d.point((x0 + 2, ay + 3), fill=rc)  # rune on the shoulder
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(bob=[0, 0, 1, 1][i])
        if name == "walk":
            return body(step=[-1, 0, 1, 1, 0, -1][i], bob=i % 2)
        if name == "windup":
            return body(arms=1, bob=-i, eye=(180, 240, 255))
        if name == "attack":
            return body(arms=0, bob=[2, 3, 1][i], eye=(255, 255, 255) if i == 0 else (180, 240, 255))
        if name == "hurt":
            return body(bob=1, eye=(255, 255, 255))
        return body(crumble=i) if i > 1 else body(bob=2 + i * 2, eye=(50, 70, 90))

    return lay, fn, None


# =============================================================== ash husk
def ash_husk():
    """Ashen halls husk (cultist frame layout): a hunched charred body with
    cracked skin over a glowing core, ash flaking from the shoulders, a
    tattered veil, a cinder held in the claw."""
    fw, fh = 24, 28
    lay = gs.monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    char = (66, 58, 60)
    ember = (255, 130, 50)
    hot = (255, 214, 130)
    veil = (110, 100, 98)

    def body(sway=0, hand=(17, 17), cinder=1, flash=False, dis=0, alpha=255, lean=0, step=0, flake=0):
        im = blank(fw, fh)
        L = lean
        d = ImageDraw.Draw(im)
        # legs: thin, burned
        for k, x in enumerate((10 + step, 13 - step)):
            col = sh(char, 0.7 if k == 0 else 0.95)[:3]
            _limb(d, (x + L, 20), (x - 1 + L, 24), col, alpha)
            _limb(d, (x - 1 + L, 24), (x + L, 27), col, alpha)
            d.point((x + 1 + L, 27), fill=rgba(sh(char, 0.6), alpha))
        # back arm
        _limb(d, (9 + L, 12), (7 + L + sway, 19), sh(char, 0.6)[:3], alpha)
        # hunched torso with cracks over the core
        tm = mask(fw, fh, lambda dd: dd.ellipse((7 + L, 9, 17 + L, 22), fill=FULL))
        lit(im, tm, char, 9 + L, 11, 5, 7, alpha)
        d = ImageDraw.Draw(im)
        core = rgba(hot, alpha) if flash else rgba(ember, alpha)
        d.ellipse((11 + L, 14, 14 + L, 17), fill=core)
        d.point((12 + L, 15), fill=rgba(hot, alpha))
        for (x0, y0, x1, y1) in ((12, 13, 10, 11), (14, 16, 16, 19), (11, 17, 9, 20), (13, 13, 15, 11)):
            d.line((x0 + L, y0, x1 + L, y1), fill=rgba(sh(ember, 0.85), alpha))
        # tattered ash veil over the head and back
        vm = mask(fw, fh, lambda dd: dd.polygon([(7 + L, 13), (9 + L, 3), (14 + L, 2), (17 + L, 6), (16 + L, 10), (12 + L, 9),
                                                 (10 + L, 15)], fill=FULL))
        lit(im, vm, veil, 10 + L, 4, 5, 6, alpha, flat=0.2)
        d = ImageDraw.Draw(im)
        for k in range(3):
            d.point((7 + L + k, 14 + k % 2), fill=sh(veil, 0.6, alpha))  # torn hem
        # burned face under the veil: hollow mouth, ember eyes
        d.polygon([(12 + L, 5), (16 + L, 6), (15 + L, 10), (12 + L, 10)], fill=(26, 18, 18, alpha))
        e = (255, 255, 255, alpha) if flash else rgba(hot, alpha)
        d.point((13 + L, 7), fill=e)
        d.point((15 + L, 7), fill=e)
        d.line((13 + L, 9, 14 + L, 9), fill=rgba(ember, alpha))
        # ash flakes rising off the shoulders
        for k in range(3):
            fy = 9 - ((flake + k * 2) % 6)
            d.point((8 + k * 3 + L, fy), fill=(170, 160, 156, alpha) if k % 2 else (120, 112, 110, alpha))
        # front arm with claw and the cinder
        hx, hy = hand
        _limb(d, (14 + L, 12), (hx + L, hy), char, alpha, sh(char, 1.3)[:3])
        d.point((hx + 1 + L, hy + 1), fill=rgba(sh(char, 0.5), alpha))
        if cinder:
            r = cinder
            cm = mask(fw, fh, lambda dd: dd.ellipse((hx + 1 + L - r, hy - 1 - r, hx + 1 + L + r, hy - 1 + r), fill=FULL))
            lit(im, cm, ember, hx + L, hy - 2, r, r, alpha)
            d = ImageDraw.Draw(im)
            d.point((hx + 1 + L, hy - 1), fill=rgba(hot, alpha))
            d.point((hx + 2 + L, hy - 3 - r), fill=rgba(ember, alpha))  # flame lick
        if dis:
            dissolve(im, dis, color=(150, 140, 136, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(sway=[0, 1, 0, -1][i], flake=i)
        if name == "walk":
            return body(sway=[1, 2, 1, -1, -2, -1][i], step=[-1, 0, 1, 1, 0, -1][i], flake=i)
        if name == "windup":
            return body(hand=(15, 11 - i), cinder=1 + i // 2, lean=-1, flake=i)
        if name == "attack":
            return body(hand=[(17, 10), (19, 13), (18, 16)][i], cinder=[2, 0, 0][i], flash=i == 0, lean=1)
        if name == "hurt":
            return body(lean=-2, flash=True)
        return body(dis=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30, cinder=0)

    return lay, fn, None


# ========================================================== glass stalker
def glass_stalker():
    """Mirror halls: a razor-glass moth, faceted wings in light and shadow
    panes with a reflection streak, a shard body with a cutting tail,
    a cold blue eye."""
    fw, fh = 20, 16
    lay = gs.monster_layout("glass_layout", fw, fh, (10, 12), "fly", {"idle": 4, "fly": 4, "windup": 2, "attack": 3, "death": 5})
    glass = (176, 206, 224)
    deep = (92, 120, 150)

    def body(wing, dy=0, rot=0, eyes=True, alpha=255, tilt=0, shatter=0, flash=False):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + dy
        wy = cy - wing
        for side in (-1, 1):
            back = side < 0
            root = (10 + side, cy - 1)
            tip = (10 + side * 9, wy)
            mid = (10 + side * 6, wy - 1)
            low = (10 + side * 7, cy + 3)
            # two facets per wing: upper lit, lower shaded
            d.polygon([root, mid, tip, (10 + side * 5, cy)], fill=rgba(sh(glass, 0.82 if back else 1.12), alpha))
            d.polygon([root, (10 + side * 5, cy), tip, low, (10 + side * 2, cy + 2)], fill=rgba(sh(deep, 0.85 if back else 1.0), alpha))
            d.line((root[0], root[1], tip[0], tip[1]), fill=rgba(sh(glass, 1.3), alpha))  # leading edge
            d.line((10 + side * 3, cy - 2, 10 + side * 5, wy), fill=(255, 255, 255, int(alpha * 0.9)))  # reflection
            d.point(tip, fill=(255, 255, 255, alpha))
        # shard body: diamond with a long cutting tail
        bm = mask(fw, fh, lambda dd: dd.polygon([(10, cy - 4 + tilt), (12, cy + tilt), (10, cy + 5 + tilt), (8, cy + tilt)], fill=FULL))
        lit(im, bm, glass, 9, cy - 1, 2.5, 4, alpha)
        d = ImageDraw.Draw(im)
        d.line((10, cy + 5 + tilt, 10, cy + 7 + tilt), fill=rgba(deep, alpha))
        d.point((10, cy + 7 + tilt), fill=(255, 255, 255, alpha))
        d.point((9, cy - 3 + tilt), fill=(255, 255, 255, alpha))
        if eyes:
            e = (255, 255, 255, alpha) if flash else (90, 210, 255, alpha)
            d.point((10, cy + tilt), fill=e)
            d.point((10, cy + 1 + tilt), fill=(30, 60, 90, alpha))
        if shatter:
            rnd = random.Random(shatter)
            px = im.load()
            out = blank(fw, fh)
            op = out.load()
            for y in range(fh):
                for x in range(fw):
                    if px[x, y][3]:
                        dx = int((x - 10) * shatter * 0.12) + rnd.randint(-1, 1) * (shatter > 2)
                        dy2 = int((y - 8) * shatter * 0.12) + shatter
                        nx, ny = x + dx, y + dy2
                        if 0 <= nx < fw and 0 <= ny < fh and (x + y + shatter) % (shatter + 1):
                            op[nx, ny] = px[x, y]
            im = out
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST, center=(10, 8))
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body([4, 1, -3, 1][i], dy=[0, 0, 1, 1][i] if name == "idle" else 0)
        if name == "windup":
            return body(5 + i, dy=-1 - i, flash=i == 1)
        if name == "attack":
            return body(-2, dy=1, rot=[-20, -35, -25][i], tilt=1)
        if name == "hurt":
            return body(2, eyes=False, flash=True)
        return body(-2, shatter=i + 1, eyes=False, alpha=255 - i * 40)

    return lay, fn, None


# ========================================================= crystal crawler
def crystal_crawler():
    """Crystal depths ambusher: a low beetle with a lit chitin shell grown
    over with faceted crystals (two-tone faces), six jointed legs, mandibles
    and a pale glowing eye cluster."""
    fw, fh = 24, 28
    lay = gs.monster_layout("crawler_layout", fw, fh, (12, 28))
    shell = (70, 84, 120)
    shard = (150, 210, 245)

    def crystal(d, x, base_y, h, w, alpha, lean=0):
        top = (x + lean, base_y - h)
        d.polygon([(x - w, base_y), top, (x, base_y)], fill=rgba(sh(shard, 1.15), alpha))  # lit face
        d.polygon([(x, base_y), top, (x + w, base_y)], fill=rgba(sh(shard, 0.7), alpha))  # shaded face
        d.point(top, fill=(255, 255, 255, alpha))

    def body(gait=0, crouch=0, alpha=255, eyes=True, jaw=0, pile=0, lunge=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        g0 = 27
        if pile:
            for k in range(4):
                crystal(d, 7 + k * 4, 27, 3 + (k % 2) * 2 - min(2, pile // 3), 2, alpha, lean=(k % 2) * 2 - 1)
            m = mask(fw, fh, lambda dd: dd.ellipse((6, 24, 19, 28), fill=FULL))
            lit(im, m, shell, 9, 25, 6, 2, alpha)
            return im
        L = lunge
        by = 21 + crouch
        # far legs
        for k, lx in enumerate((6, 11, 16)):
            ph = gait if k % 2 else -gait
            d.line((lx + L, by + 2, lx + L - 2 + ph, by + 3, lx + L - 3 + ph, g0), fill=rgba(sh(shell, 0.5), alpha))
        # shell
        sm = mask(fw, fh, lambda dd: dd.chord((3 + L, by - 5, 19 + L, by + 6), 180, 360, fill=FULL))
        lit(im, sm, shell, 7 + L, by - 3, 8, 4, alpha)
        d = ImageDraw.Draw(im)
        d.line((3 + L, by + 1, 19 + L, by + 1), fill=sh(shell, 0.5, alpha))
        d.line((11 + L, by - 5, 11 + L, by), fill=sh(shell, 0.6, alpha))  # wing-case seam
        # crystal growths
        for x, h, lean in ((6, 5, -1), (9, 9, 0), (12, 7, 1), (15, 10, 1), (17, 4, 2)):
            crystal(d, x + L, by - 3 if x in (6, 17) else by - 4, h, 2, alpha, lean)
        # near legs, jointed, with crystal tips
        for k, lx in enumerate((7, 12, 17)):
            ph = -gait if k % 2 else gait
            d.line((lx + L, by + 2, lx + L + 2 + ph, by + 3, lx + L + 2 + ph, g0), fill=rgba(sh(shell, 0.85), alpha))
            d.point((lx + L + 2 + ph, by + 3), fill=rgba(sh(shell, 1.3), alpha))
            d.point((lx + L + 2 + ph, g0), fill=rgba(shard, alpha))
        # head with mandibles and an eye cluster
        hx, hy = 20 + L, by
        hm = mask(fw, fh, lambda dd: dd.ellipse((hx - 3, hy - 3, hx + 2, hy + 2), fill=FULL))
        lit(im, hm, sh(shell, 1.1)[:3], hx - 2, hy - 2, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        for jy, s_ in ((hy - 1, -1), (hy + 1, 1)):
            d.line((hx + 2, jy, hx + 4, jy + s_ * jaw, hx + 3, jy + s_ * (jaw + 1)), fill=rgba(sh(shard, 0.9), alpha))
        if eyes:
            for ex, ey in ((hx, hy - 2), (hx + 1, hy - 1), (hx - 1, hy - 1)):
                d.point((ex, ey), fill=(170, 240, 255, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(gait=0, crouch=[0, 0, 1, 1][i], jaw=[0, 1, 1, 0][i])
        if name == "walk":
            return body(gait=[-1, 0, 1, 1, 0, -1][i], crouch=i % 2)
        if name == "windup":
            return body(crouch=2, jaw=2, lunge=-1)
        if name == "attack":
            return body(jaw=[0, 1, 2][i], lunge=[2, 3, 1][i])
        if name == "hurt":
            return body(crouch=1, eyes=False, lunge=-1)
        if i < 2:
            return body(crouch=2 + i, eyes=False)
        return body(pile=i, alpha=255 - (i - 2) * 30)

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
    "sporeling": (sporeling, "sporeling", False, True),  # uses slime_layout
    "ember_hound": (ember_hound, "ember_hound", True, True),
    "runite_sentinel": (runite_sentinel, "runite_sentinel", True, True),
    "ash_husk": (ash_husk, "ash_husk", False, True),  # uses cultist_layout
    "glass_stalker": (glass_stalker, "glass_stalker", True, True),
    "crystal_crawler": (crystal_crawler, "crystal_crawler", True, True),
}


def main():
    for name, (builder, file, write_layout, outline) in MONSTERS.items():
        lay, fn, _ = builder()
        gs.render_sheet(lay, fn, "sprites/enemies/%s_sheet.png" % file, do_outline=outline)
        if write_layout:
            lay.write_tres()
        sheet = Image.open(os.path.join(A, "sprites/enemies/%s_sheet.png" % file))
        sheet.crop((0, 0, lay.fw, lay.fh)).save(os.path.join(A, "sprites/enemies/%s.png" % file))
    print("monsters generated")


if __name__ == "__main__":
    main()
