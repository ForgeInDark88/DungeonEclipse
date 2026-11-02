#!/usr/bin/env python3
"""Monsters of the open surface (stage 16), drawn like the dungeon's
(tools/gen_monsters.py): volume shading lit from the top left in four
dithered tones, materials (fur, hide, leather, cloth, steel, skin),
readable eyes, a dark outline, a crumbling death.

  beasts  — wolf, boar, deer (quadrupeds), snake;
  people  — bandit swordsman, bandit archer, thief, goblin, ghoul (night);
  the ogre (big).

Layouts are written to data/animations/ (beast_layout, deer_layout,
snake_layout, surface_human_layout, ogre_layout): idle 4, walk 6,
windup 3, attack 3, hurt 2, death 6.
Run from the project root:  python3 tools/gen_surface_monsters.py
"""
from __future__ import annotations

import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import gen_monsters as gm  # noqa: E402
import gen_sheets as gs  # noqa: E402

blank, mask, lit, sh, rgba, FULL, dissolve, _limb = gm.blank, gm.mask, gm.lit, gm.sh, gm.rgba, gm.FULL, gm.dissolve, gm._limb
P = gs.P


# =================================================================== beasts
def quadruped(name, fw, fh, fur, belly, *, snout=4, ears="point", tusks=False, antlers=False,
              tail="brush", leg=6, body_w=15, body_h=7, mane=None, spots=None, eye=(250, 220, 90)):
    """A four-legged beast like the ember hound: far legs darker behind the
    body, a lit barrel of a body, near legs with a lit edge, a head with a
    muzzle, ears and eyes; mouth opens to bite."""
    lay = gs.monster_layout(name, fw, fh, (fw // 2, fh))
    g0 = fh - 1

    def body(gait=0, crouch=0, alpha=255, eyes=True, jaw=0, pile=0, lunge=0, head_dip=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            m = mask(fw, fh, lambda dd: dd.ellipse((4, fh - 7, fw - 6, fh), fill=FULL))
            lit(im, m, fur, fw // 2 - 3, fh - 6, (fw - 10) // 2, 3, alpha)
            d = ImageDraw.Draw(im)
            d.line((6, fh - 2, fw - 8, fh - 2), fill=sh(belly, 0.8, alpha))
            return im
        L = lunge
        x0 = (fw - body_w) // 2 - 2 + L
        by = g0 - leg - body_h // 2 + crouch  # back line
        # tail
        tx, ty = x0 + 1, by + 1
        if tail == "brush":
            for k in range(4):
                d.line((tx - k, ty + k // 2 + gait // 2, tx - k - 1, ty + k // 2 + 1 + gait // 2), fill=sh(fur, 0.9 - k * 0.05, alpha), width=2)
            d.point((tx - 4, ty + 3 + gait // 2), fill=sh(belly, 1.1, alpha))
        elif tail == "stub":
            d.line((tx, ty, tx - 2, ty + 1 + gait // 2), fill=sh(fur, 0.8, alpha))
        # far legs
        legs = [(x0 + 3, -gait), (x0 + body_w - 4, gait)]
        for lx, ph in legs:
            _limb(d, (lx, by + body_h // 2), (lx - 1 + ph, g0 - leg // 2), sh(fur, 0.58)[:3], alpha)
            _limb(d, (lx - 1 + ph, g0 - leg // 2), (lx + ph, g0), sh(fur, 0.58)[:3], alpha)
        # the body
        tm = mask(fw, fh, lambda dd: dd.ellipse((x0, by - body_h // 2, x0 + body_w, by + body_h // 2 + 1), fill=FULL))
        lit(im, tm, fur, x0 + body_w // 3, by - 1, body_w // 2, body_h // 2 + 1, alpha)
        d = ImageDraw.Draw(im)
        d.line((x0 + 2, by + body_h // 2, x0 + body_w - 2, by + body_h // 2), fill=sh(belly, 0.85, alpha))  # belly
        if spots:
            for k in range(4):
                d.point((x0 + 3 + k * 3, by - 1 + k % 2), fill=rgba(spots, alpha))
        if mane:
            for k in range(5):  # bristles along the back
                x = x0 + body_w // 2 + k * 2 - 2
                d.line((x, by - body_h // 2, x + 1, by - body_h // 2 - 2 - (k % 2)), fill=rgba(mane, alpha))
        # near legs (lit edge), hooves / claws
        for lx, ph in legs:
            _limb(d, (lx + 2, by + body_h // 2), (lx + 1 - ph, g0 - leg // 2), fur, alpha, sh(fur, 1.25)[:3])
            _limb(d, (lx + 1 - ph, g0 - leg // 2), (lx + 2 - ph, g0), sh(fur, 0.9)[:3], alpha)
            d.point((lx + 3 - ph, g0), fill=sh(fur, 0.4, alpha))
        # the head: a lit skull, a muzzle, ears, eyes
        hx, hy = x0 + body_w + 1, by - body_h // 2 + 1 + crouch // 2 + head_dip
        hm = mask(fw, fh, lambda dd: dd.ellipse((hx - 4, hy - 3, hx + 3, hy + 3), fill=FULL))
        lit(im, hm, fur, hx - 2, hy - 2, 4, 3, alpha)
        d = ImageDraw.Draw(im)
        d.polygon([(hx + 1, hy - 1), (hx + 1 + snout, hy), (hx + 1 + snout, hy + 2), (hx + 1, hy + 3)], fill=sh(fur, 1.05, alpha))
        d.line((hx + 2, hy + 3, hx + snout, hy + 2), fill=sh(fur, 0.6, alpha))  # jaw line
        d.point((hx + 1 + snout, hy), fill=(24, 18, 16, alpha))  # nose
        if ears == "point":
            d.polygon([(hx - 3, hy - 2), (hx - 4, hy - 6), (hx - 1, hy - 3)], fill=sh(fur, 0.85, alpha))
            d.point((hx - 3, hy - 4), fill=sh(belly, 0.9, alpha))
        elif ears == "round":
            d.ellipse((hx - 4, hy - 5, hx - 1, hy - 2), fill=sh(fur, 0.85, alpha))
        if antlers:
            for side in (-1, 1):
                bx = hx - 2 + side
                d.line((bx, hy - 3, bx - 1, hy - 9), fill=(150, 116, 74, alpha))
                d.line((bx - 1, hy - 7, bx - 3 + side, hy - 9), fill=(170, 134, 88, alpha))
                d.line((bx - 1, hy - 9, bx + 1, hy - 11), fill=(190, 154, 104, alpha))
        if tusks:
            d.line((hx + snout - 1, hy + 2, hx + snout + 1, hy), fill=(240, 232, 210, alpha))
        if jaw:
            d.polygon([(hx + 1, hy + 3), (hx + 1 + snout, hy + 3 + jaw), (hx + 1, hy + 4)], fill=sh(fur, 0.7, alpha))
            d.line((hx + 2, hy + 3, hx + snout, hy + 3 + jaw // 2), fill=(170, 40, 40, alpha))
            d.point((hx + snout - 1, hy + 3), fill=(250, 246, 230, alpha))  # fang
        if eyes:
            d.point((hx, hy - 1), fill=rgba(eye, alpha))
            d.point((hx - 1, hy - 1), fill=(20, 14, 12, alpha))
        return im

    def fn(anim, i, n):
        if anim == "idle":
            return body(crouch=[0, 0, 1, 1][i], head_dip=[0, 1, 1, 0][i])
        if anim == "walk":
            return body(gait=[-2, -1, 1, 2, 1, -1][i], crouch=[0, 1, 0, 0, 1, 0][i])
        if anim == "windup":
            return body(crouch=1 + i // 2, jaw=1, lunge=-1 - (i > 0))
        if anim == "attack":
            return body(gait=2, jaw=[3, 2, 1][i], lunge=[2, 3, 1][i])
        if anim == "hurt":
            return body(crouch=1, eyes=False, lunge=-1)
        if i < 2:
            return body(crouch=2 + i * 2, eyes=False)
        im = body(pile=i, alpha=255 - (i - 2) * 30)
        return dissolve(im, (i - 2) * 2.2, seed=i)

    return lay, fn


def snake():
    """A grass snake: a lit, scaled body in a sine, a raised head that strikes,
    a flicking tongue; yellow eyes."""
    fw, fh = 28, 14
    lay = gs.monster_layout("snake_layout", fw, fh, (fw // 2, fh))
    skin = (96, 140, 60)
    belly = (190, 196, 120)

    def body(phase=0.0, rise=0, strike=0, alpha=255, eyes=True, pile=0, tongue=False):
        im = blank(fw, fh)
        if pile:
            m = mask(fw, fh, lambda dd: dd.ellipse((4, fh - 5, fw - 4, fh), fill=FULL))
            lit(im, m, skin, fw // 2 - 3, fh - 4, fw // 2 - 4, 2, alpha)
            return im
        pts = []
        for x in range(2, fw - 6 + strike):
            y = fh - 4 + math.sin(x / 3.5 + phase) * 1.6
            if x > fw - 11 + strike:
                y -= (x - (fw - 11 + strike)) * (0.5 + rise * 0.3)
            pts.append((x, y))
        m = mask(fw, fh, lambda dd: [dd.ellipse((x - 1.6, y - 1.6, x + 1.6, y + 1.6), fill=FULL) for x, y in pts])
        lit(im, m, skin, fw // 2 - 4, fh - 6, fw // 2, 3, alpha)
        d = ImageDraw.Draw(im)
        for k, (x, y) in enumerate(pts):
            if k % 3 == 0:
                d.point((x, y), fill=sh(skin, 0.6, alpha))  # scale pattern
            d.point((x, y + 1), fill=rgba(belly, alpha))
        hx, hy = pts[-1]
        hm = mask(fw, fh, lambda dd: dd.ellipse((hx - 1, hy - 2, hx + 3, hy + 1), fill=FULL))
        lit(im, hm, sh(skin, 1.05)[:3], hx, hy - 1, 2, 2, alpha)
        d = ImageDraw.Draw(im)
        if eyes:
            d.point((hx + 1, hy - 1), fill=(250, 220, 60, alpha))
        if tongue:
            d.line((hx + 3, hy, hx + 5, hy), fill=(200, 40, 50, alpha))
            d.point((hx + 5, hy - 1), fill=(200, 40, 50, alpha))
        return im

    def fn(anim, i, n):
        if anim == "idle":
            return body(phase=i * 0.4, tongue=i == 2)
        if anim == "walk":
            return body(phase=i * math.tau / 6)
        if anim == "windup":
            return body(rise=1 + i, strike=-1, tongue=True)
        if anim == "attack":
            return body(rise=[3, 2, 1][i], strike=[3, 4, 2][i])
        if anim == "hurt":
            return body(eyes=False, phase=1.0)
        im = body(pile=i, alpha=255 - i * 25) if i >= 2 else body(eyes=False, phase=0.5)
        return dissolve(im, i * 1.6, seed=i)

    return lay, fn


# =================================================================== people
def person(name, fw, fh, *, skin, tunic, pants, hair=None, hood=None, helmet=None, beard=None,
           vest=None, weapon="sword", eye=(30, 20, 18), glow_eye=None, leg=7, torso=8, cx=None,
           ground=None, big=False, claws=False, ears=False, layout=None):
    """A person on the hero's skeleton (gs.skel): boots and trousers, a lit
    tunic with a belt (a leather vest over it), a lit head with hair, hood or
    helmet, the far arm behind, the near arm with the weapon in front."""
    cx = cx if cx is not None else fw // 2
    ground = ground if ground is not None else fh - 1
    lay = layout or gs.monster_layout(name, fw, fh, (fw // 2, fh))
    race = dict(leg=leg, torso=torso)
    k = 1.5 if big else 1.0

    def body(p, alpha=255, pile=0, flash=False, draw=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        if pile:
            m = mask(fw, fh, lambda dd: dd.ellipse((cx - 8 * k, fh - 5, cx + 8 * k, fh), fill=FULL))
            lit(im, m, tunic, cx - 3, fh - 4, 7 * k, 2, alpha)
            d = ImageDraw.Draw(im)
            d.line((cx - 6 * k, fh - 2, cx + 6 * k, fh - 2), fill=sh(pants, 0.8, alpha))
            return im
        s = gs.skel(p, race, cx=cx, ground=ground)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        w = 1 if not big else 2
        # far leg and arm
        _limb(d, (hx - 1, hy + 1), s["lknee"], sh(pants, 0.62)[:3], alpha)
        _limb(d, s["lknee"], s["lfoot"], sh(pants, 0.62)[:3], alpha)
        fx, fy = s["lfoot"]
        d.line((fx - 1, fy, fx + 2, fy), fill=sh((60, 44, 34), 0.8, alpha), width=w)
        _limb(d, s["shoulder"], s["lhand"], sh(skin if claws else tunic, 0.62)[:3], alpha)
        # near leg with a lit edge, a boot
        _limb(d, (hx + 1, hy + 1), s["rknee"], pants, alpha, sh(pants, 1.25)[:3])
        _limb(d, s["rknee"], s["rfoot"], pants, alpha)
        if big:  # tree-trunk legs
            for a, b in (((hx - 2, hy + 1), s["lknee"]), (s["lknee"], s["lfoot"]), ((hx + 2, hy + 1), s["rknee"]), (s["rknee"], s["rfoot"])):
                d.line((a[0] + 1, a[1], b[0] + 1, b[1]), fill=rgba(skin if a[1] > hy + 2 else pants, alpha), width=2)
        fx, fy = s["rfoot"]
        d.line((fx - 1, fy, fx + 2, fy), fill=rgba((60, 44, 34), alpha), width=w)
        d.point((fx + 2, fy - 1), fill=rgba((96, 70, 50), alpha))
        # torso
        tw = int(4 * k)
        if big:
            # a bare, barrel-chested brute: a lit belly, a loincloth, a rope belt
            bm = mask(fw, fh, lambda dd: dd.ellipse((hx - 8, ny - 1, hx + 8, hy + 3), fill=FULL))
            lit(im, bm, skin, hx - 3, ny + 3, 8, (hy - ny) // 2 + 2, alpha)
            d = ImageDraw.Draw(im)
            d.line((hx - 2, ny + 4, hx + 1, ny + 5), fill=sh(skin, 0.7, alpha))  # chest line
            d.point((hx - 4, hy - 5), fill=sh(skin, 0.6, alpha))  # navel
            lm = mask(fw, fh, lambda dd: dd.polygon([(hx - 7, hy - 1), (hx + 7, hy - 1), (hx + 5, hy + 5), (hx - 5, hy + 5)], fill=FULL))
            lit(im, lm, tunic, hx - 3, hy, 6, 3, alpha, flat=0.3)
            d = ImageDraw.Draw(im)
            d.line((hx - 7, hy - 1, hx + 7, hy - 1), fill=rgba((150, 120, 70), alpha))
        else:
            tm = mask(fw, fh, lambda dd: dd.polygon([(nx - tw, ny), (nx + tw, ny), (hx + tw, hy + 1), (hx - tw, hy + 1)], fill=FULL))
            lit(im, tm, tunic, nx - 2, ny + 2, tw + 1, (hy - ny) // 2 + 2, alpha, flat=0.25)
        d = ImageDraw.Draw(im)
        if vest:
            vm = mask(fw, fh, lambda dd: dd.polygon([(nx - tw, ny), (nx - 1, ny), (hx - 1, hy - 1), (hx - tw, hy - 1)], fill=FULL))
            lit(im, vm, vest, nx - 3, ny + 2, tw, (hy - ny) // 2, alpha, flat=0.2)
            d = ImageDraw.Draw(im)
            d.point((nx - 2, ny + 2), fill=sh(vest, 1.4, alpha))  # stud
        if not big:
            d.line((hx - tw, hy - 1, hx + tw, hy - 1), fill=rgba((70, 46, 30), alpha))  # belt
            d.point((hx, hy - 1), fill=rgba((210, 180, 90), alpha))  # buckle
        # head
        sx, sy = s["head"]
        r = int(3 * k) + (1 if big else 0)
        hm = mask(fw, fh, lambda dd: dd.ellipse((sx - r, sy - r - 1, sx + r, sy + r - 1), fill=FULL))
        lit(im, hm, skin, sx - 1, sy - 2, r, r, alpha)
        d = ImageDraw.Draw(im)
        if ears:
            d.polygon([(sx - r, sy - 2), (sx - r - 3, sy - 4), (sx - r, sy)], fill=sh(skin, 0.9, alpha))
        if hair:
            d.pieslice((sx - r, sy - r - 1, sx + r, sy + r - 3), 180, 360, fill=rgba(hair, alpha))
            d.line((sx - r, sy - 2, sx - r, sy), fill=rgba(hair, alpha))
        if beard:
            d.polygon([(sx - 1, sy + 1), (sx + r, sy + 1), (sx + 1, sy + r + 1)], fill=rgba(beard, alpha))
        if hood:
            hm2 = mask(fw, fh, lambda dd: dd.polygon([(sx - r - 1, sy + r), (sx - r, sy - r), (sx, sy - r - 2), (sx + r + 1, sy - r + 1), (sx + r, sy - 1)], fill=FULL))
            lit(im, hm2, hood, sx - 2, sy - 3, r + 1, r + 1, alpha)
            d = ImageDraw.Draw(im)
            d.polygon([(sx, sy - 2), (sx + r, sy - 2), (sx + r, sy + 1), (sx, sy + 1)], fill=sh(hood, 0.35, alpha))  # shadowed face
        if helmet:
            hm3 = mask(fw, fh, lambda dd: dd.pieslice((sx - r - 1, sy - r - 2, sx + r + 1, sy + r - 2), 180, 360, fill=FULL))
            lit(im, hm3, helmet, sx - 2, sy - 3, r + 1, r, alpha)
            d = ImageDraw.Draw(im)
            d.line((sx - r - 1, sy - 2, sx + r + 1, sy - 2), fill=sh(helmet, 0.6, alpha))
        e = glow_eye or eye
        d.point((sx + 1, sy - 1), fill=(255, 255, 255, alpha) if flash else rgba(e, alpha))
        if big:
            d.point((sx + 2, sy - 1), fill=rgba(e, alpha))
        # near arm and the weapon
        rx, ry = s["rhand"]
        arm_col = skin if (claws or big) else tunic
        _limb(d, s["shoulder"], (rx, ry), arm_col, alpha, sh(arm_col, 1.2)[:3])
        if big:  # a thick forearm
            d.line((s["shoulder"][0] + 1, s["shoulder"][1] + 1, rx + 1, ry + 1), fill=rgba(sh(skin, 0.85)[:3], alpha), width=2)
        d.rectangle((rx, ry, rx + 1, ry + 1), fill=rgba(skin, alpha))
        steel = (196, 200, 210)
        if weapon == "sword":
            ang = math.radians(p.get("ang", -50))
            ex, ey = rx + math.cos(ang) * 9, ry + math.sin(ang) * 9
            d.line((rx, ry, ex, ey), fill=rgba(steel, alpha), width=2)
            d.line((rx, ry - 1, ex, ey - 1), fill=sh(steel, 1.25, alpha))
            d.line((rx - 2, ry + 1, rx + 2, ry - 1), fill=rgba((150, 110, 50), alpha))  # guard
        elif weapon == "dagger":
            ang = math.radians(p.get("ang", -30))
            d.line((rx, ry, rx + math.cos(ang) * 5, ry + math.sin(ang) * 5), fill=rgba(steel, alpha))
        elif weapon == "bow":
            top, bot = (rx + 1, ry - 7), (rx + 1, ry + 7)
            d.arc((rx - 3, ry - 7, rx + 5, ry + 7), 270, 90, fill=rgba((120, 82, 46), alpha), width=1)
            string_x = rx - 1 - draw
            d.line((top[0] - 1, top[1], string_x, ry, ), fill=(220, 214, 196, alpha))
            d.line((string_x, ry, bot[0] - 1, bot[1]), fill=(220, 214, 196, alpha))
            if draw:
                d.line((string_x, ry, rx + 7, ry), fill=rgba((170, 130, 80), alpha))  # arrow
                d.point((rx + 7, ry), fill=rgba(steel, alpha))
        elif weapon == "club":
            ang = math.radians(p.get("ang", -60))
            ex, ey = rx + math.cos(ang) * 13, ry + math.sin(ang) * 13
            cm = mask(fw, fh, lambda dd: dd.line((rx, ry, ex, ey), fill=FULL, width=4))
            lit(im, cm, (112, 82, 54), (rx + ex) / 2 - 1, (ry + ey) / 2 - 1, 5, 5, alpha)
            d = ImageDraw.Draw(im)
            d.point((int(ex), int(ey)), fill=rgba((150, 150, 156), alpha))  # a spike
        elif weapon == "claws":
            for kk in range(3):
                d.point((rx + 2, ry - 1 + kk), fill=(230, 226, 210, alpha))
        return im

    def fn(anim, i, n):
        if anim == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(2, 6), ang=-60))
        if anim == "walk":
            lx = [-3, -1, 1, 3, 1, -1][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(2 - lx // 2, 6), ang=-55))
        if anim == "windup":
            if weapon == "bow":
                return body(P(lean=-1, ra=(5, 2)), draw=1 + i)
            return body(P(lean=-1 - i // 2, ra=(-2, -4 - i), ang=-110))
        if anim == "attack":
            if weapon == "bow":
                return body(P(lean=1, ra=(5, 2)), draw=0)
            return body(P(lean=2, lf=(-3, 0), rf=(4, 0), ra=[(4, -2), (7, 1), (6, 4)][i], ang=[-40, 0, 30][i]))
        if anim == "hurt":
            return body(P(lean=-3, by=1, ra=(1, 4)), flash=True)
        if i < 2:
            return body(P(crouch=2 + i * 2, by=1 + i, ra=(4, 5)))
        im = body(P(), pile=i, alpha=255 - (i - 2) * 30)
        return dissolve(im, (i - 2) * 2.0, seed=i)

    return lay, fn


# ===================================================================== main
def main():
    human = gs.monster_layout("surface_human_layout", 24, 28, (12, 28))
    out = {
        "wolf": quadruped("beast_layout", 32, 22, (118, 118, 126), (186, 186, 192), snout=4, ears="point", tail="brush", eye=(240, 210, 80)),
        "boar": quadruped("beast_layout", 32, 22, (104, 74, 54), (150, 118, 90), snout=4, ears="round", tusks=True, tail="stub", body_h=8, leg=5, mane=(70, 50, 36)),
        "deer": quadruped("deer_layout", 32, 26, (164, 116, 72), (226, 200, 160), snout=4, ears="point", antlers=True, tail="stub", leg=8, body_w=14, body_h=6, spots=(236, 220, 190)),
        "snake": snake(),
        "bandit": person("bandit", 24, 28, skin=(214, 170, 130), tunic=(132, 60, 48), pants=(76, 66, 60), hair=(70, 46, 30),
                         beard=(70, 46, 30), vest=(96, 70, 44), weapon="sword", layout=human),
        "bandit_archer": person("bandit_archer", 24, 28, skin=(214, 170, 130), tunic=(86, 98, 58), pants=(70, 64, 54),
                                hood=(74, 90, 52), weapon="bow", layout=human),
        "thief": person("thief", 24, 28, skin=(214, 170, 130), tunic=(52, 52, 62), pants=(44, 44, 52), hood=(40, 40, 50),
                        weapon="dagger", layout=human),
        "goblin": person("goblin", 24, 28, skin=(112, 162, 80), tunic=(110, 80, 50), pants=(84, 64, 44), ears=True,
                         weapon="dagger", leg=5, torso=6, glow_eye=(250, 220, 60), layout=human),
        "ghoul": person("ghoul", 24, 28, skin=(150, 162, 150), tunic=(70, 72, 80), pants=(56, 56, 62), hair=(40, 40, 44),
                        weapon="claws", claws=True, glow_eye=(255, 70, 60), layout=human),
        "ogre": person("ogre_layout", 36, 40, skin=(150, 160, 110), tunic=(116, 90, 60), pants=(130, 140, 96),
                       weapon="club", leg=11, torso=13, big=True, glow_eye=(230, 200, 60), beard=None, cx=16),
    }
    written = set()
    for file, (lay, fn) in out.items():
        gs.render_sheet(lay, fn, "sprites/enemies/%s_sheet.png" % file, do_outline=True)
        if lay.name not in written:
            lay.write_tres()
            written.add(lay.name)
        sheet = Image.open(os.path.join(gm.A, "sprites/enemies/%s_sheet.png" % file))
        sheet.crop((0, 0, lay.fw, lay.fh)).save(os.path.join(gm.A, "sprites/enemies/%s.png" % file))
    print("surface monsters: ok (%s)" % ", ".join(sorted(written)))


if __name__ == "__main__":
    main()
