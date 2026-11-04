#!/usr/bin/env python3
"""Own sprite sheets for the monsters that used to borrow a recoloured
dungeon sheet:

  crow           — a black crow with a blue sheen (was the bat, tinted);
  forest_spider  — a hairy brown wolf spider with moss spots (was the
                   dungeon spider, tinted green);
  night_wraith   — a will-o'-the-wisp spirit: a ragged see-through shroud
                   with a lantern of cold fire (was the ghost, tinted);
  leech_swarm    — a writhing knot of small leeches (was one leech).

Drawn with the dungeon toolkit (tools/gen_monsters.py: volume lit from the
top left in four dithered tones, readable eyes, outline, crumbling death).
Each keeps the frame size and animation rows of the sheet it replaces
(bat_layout, spider_layout, ghost_layout, slime_layout), so hitboxes,
origins and AI timings stay valid; the layouts themselves are not
rewritten. Writes assets/sprites/enemies/<id>_sheet.png and <id>.png.
Run from the project root:  python3 tools/gen_own_monsters.py
"""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import gen_monsters as gm  # noqa: E402
import gen_sheets as gs  # noqa: E402

blank, mask, lit, sh, rgba, FULL, dissolve = gm.blank, gm.mask, gm.lit, gm.sh, gm.rgba, gm.FULL, gm.dissolve


def _fade(im, alpha):
    if alpha >= 255:
        return im
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, a * alpha // 255)
    return im


# ===================================================================== crow
def crow():
    """Side view facing right, 20×16 (bat_layout: idle 4, fly 4, windup 2,
    attack 3, hurt 2, death 5)."""
    fw, fh = 20, 16
    lay = gs.monster_layout("bat_layout", fw, fh, (10, 12), "fly", {"idle": 4, "fly": 4, "windup": 2, "attack": 3, "death": 5})
    ink = (36, 36, 46)
    sheen = (70, 84, 128)
    beak = (58, 56, 60)

    def wing(d, im, sx, sy, lift, alpha, far):
        """A wing from the shoulder: primaries fan out, lit leading edge."""
        col = sh(ink, 0.7 if far else 1.0)
        tip = (sx - 7, sy - lift)
        mid = (sx - 4, sy - lift * 0.6 - 1)
        pts = [(sx + 1, sy), mid, tip, (tip[0] + 1, tip[1] + 2), (sx - 5, sy + 2), (sx - 2, sy + 2)]
        d.polygon(pts, fill=rgba(col, alpha))
        # primaries: feather tips at the trailing edge
        for k in range(4):
            t = k / 3
            fx = tip[0] + 1 + t * 5
            fy = tip[1] + 2 + t * (sy + 2 - tip[1] - 2)
            d.point((fx, fy + 1), fill=rgba(sh(col, 0.75), alpha))
        if not far:
            d.line((sx + 1, sy, mid[0], mid[1], tip[0], tip[1]), fill=rgba(sheen, alpha))
            d.point(mid, fill=rgba(sh(sheen, 1.4), alpha))

    def body(lift=3, dy=0, rot=0, alpha=255, beak_open=False, claws=False, eye=(250, 236, 200), ruffle=False, dis=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + dy
        wing(d, im, 9, cy - 1, lift + 1, alpha, True)  # far wing, behind
        # tail fan
        d.polygon([(5, cy), (1, cy + 1), (1, cy + 3), (5, cy + 2)], fill=rgba(sh(ink, 0.9), alpha))
        d.line((1, cy + 2, 5, cy + 1), fill=rgba(sh(sheen, 0.8), alpha))
        # body and head, lit
        m = mask(fw, fh, lambda dd: dd.ellipse((4, cy - 3, 13, cy + 3), fill=FULL))
        lit(im, m, ink, 7, cy - 2, 5, 4, alpha)
        hm = mask(fw, fh, lambda dd: dd.ellipse((11, cy - 5, 16, cy), fill=FULL))
        lit(im, hm, ink, 12.5, cy - 4, 3, 3, alpha)
        d = ImageDraw.Draw(im)
        d.point((8, cy - 2), fill=rgba(sheen, alpha))
        d.point((13, cy - 4), fill=rgba(sh(sheen, 1.3), alpha))
        d.line((9, cy + 2, 11, cy + 2), fill=rgba(sh(ink, 0.6), alpha))  # belly shadow
        # beak
        if beak_open:
            d.line((16, cy - 3, 19, cy - 4), fill=rgba(beak, alpha))
            d.line((16, cy - 2, 18, cy - 1), fill=rgba(sh(beak, 0.7), alpha))
            d.point((17, cy - 2), fill=(170, 40, 40, alpha))
        else:
            d.polygon([(16, cy - 4), (19, cy - 3), (16, cy - 2)], fill=rgba(beak, alpha))
            d.point((16, cy - 4), fill=rgba(sh(beak, 1.6), alpha))
        # eye: a pale ring, a black pupil, a glint
        d.point((14, cy - 4), fill=rgba(eye, alpha))
        d.point((15, cy - 4), fill=(10, 10, 14, alpha))
        # legs
        if claws:
            d.line((10, cy + 3, 13, cy + 5), fill=(70, 66, 64, alpha))
            d.line((13, cy + 5, 15, cy + 5), fill=(70, 66, 64, alpha))
            d.line((13, cy + 5, 14, cy + 6), fill=(70, 66, 64, alpha))
        else:
            d.line((9, cy + 3, 8, cy + 4), fill=(70, 66, 64, alpha))
        if ruffle:
            for x, y in ((6, cy - 4), (9, cy - 4), (12, cy - 6)):
                d.point((x, y), fill=rgba(sh(ink, 1.2), alpha))
        wing(d, im, 10, cy - 1, lift, alpha, False)  # near wing in front
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST, center=(10, 8))
        if dis:
            dissolve(im, dis, seed=5)
        return im

    def fn(name, i, n):
        flap = [5, 2, -2, 2]
        if name in ("idle", "fly"):
            return body(flap[i], dy=[0, 0, 1, 1][i] if name == "idle" else [0, 1, 1, 0][i])
        if name == "windup":
            return body(7, dy=-1 - i, rot=8 + i * 6, ruffle=True)
        if name == "attack":
            return body(-1, dy=1, rot=[-25, -38, -28][i], beak_open=True, claws=True)
        if name == "hurt":
            return body(4, ruffle=True, eye=(255, 255, 255), rot=10)
        return body(-3, dy=i, rot=i * 50, alpha=255 - i * 40, dis=1 + i * 2)

    return lay, fn, True


# =========================================================== forest spider
def forest_spider():
    """A hairy wolf spider facing right, 22×14 (spider_layout)."""
    fw, fh = 22, 14
    lay = gs.monster_layout("spider_layout", fw, fh, (11, 14), counts={"windup": 3, "attack": 3, "death": 5})
    fur = (134, 100, 64)
    dark = (70, 50, 32)
    moss = (96, 128, 60)

    def legs(d, cy, leg, flat, alpha, far_pass):
        """8 hairy legs fanned out like a real spider's: two pairs reach
        forward, two back, knees high above the body; the far four behind
        the body and darker, the near four over it. Dark joint bands and
        bristles."""
        for j, dirx in enumerate((1.7, 0.7, -0.7, -1.7)):
            lift = ((leg + j + (1 if far_pass else 0)) % 2) * 2
            off = -1 if far_pass else 0
            root = (12.5 + (0.5 if j < 2 else -1.0) + off, cy - 1 + flat)
            knee = (root[0] + dirx * 3.2, max(0, cy - 7 - lift + flat + abs(j - 1.5) // 1))
            foot = (root[0] + dirx * 5.6 + (1 if dirx > 0 else -1), 13)
            col = sh(fur, 0.6 if far_pass else 1.18)
            d.line((root[0], root[1], knee[0], knee[1]), fill=rgba(col, alpha))
            d.line((knee[0], knee[1], foot[0], foot[1]), fill=rgba(col, alpha))
            d.point(knee, fill=rgba(sh(dark, 0.7), alpha))
            mx, my = (knee[0] + foot[0]) / 2, (knee[1] + foot[1]) / 2
            d.point((mx, my), fill=rgba(dark, alpha))
            if not far_pass:
                d.point((knee[0], knee[1] - 1), fill=rgba(sh(fur, 1.55), alpha))

    def body(leg=0, crouch=0, eyes=(150, 230, 120), alpha=255, flat=0, open_jaw=False, dis=0):
        im = blank(fw, fh)
        d = ImageDraw.Draw(im)
        cy = 8 + crouch + flat
        legs(d, cy, leg, flat, alpha, True)
        # abdomen: lit, a dark chevron stripe and moss spots, fuzzy rim
        ab = mask(fw, fh, lambda dd: dd.ellipse((4, cy - 4 + flat, 12, cy + 2), fill=FULL))
        lit(im, ab, fur, 5, cy - 3, 6, 4.5, alpha)
        ce = mask(fw, fh, lambda dd: dd.ellipse((11, cy - 3 + flat, 16, cy + 1), fill=FULL))
        lit(im, ce, sh(fur, 0.95)[:3], 13, cy - 3, 4, 3, alpha)
        px = im.load()
        for y in range(fh):
            for x in range(fw):
                r, g, b, a = px[x, y]
                if a and ab.getpixel((x, y))[3]:
                    if abs(y - (cy - 1 + flat * 0.5)) < 1 and 3 < x < 11:
                        px[x, y] = rgba(sh(dark, 0.9), alpha)
                    elif (x * 7 + y * 3) % 11 == 0:
                        px[x, y] = rgba(sh(moss, 1.0 if y < cy else 0.8), alpha)
        d = ImageDraw.Draw(im)
        for x in (4, 6, 8, 10):  # chevrons
            d.point((x, cy - 3 + flat), fill=rgba(sh(dark, 0.8), alpha))
        rnd = random.Random(leg * 13 + crouch + flat)
        for _ in range(9):  # fuzzy outline hairs
            a = rnd.uniform(math.pi * 0.9, math.pi * 2.1)
            x = 8 + math.cos(a) * 4.5
            y = cy - 1 + math.sin(a) * 3.5
            if 0 <= x < fw and 0 <= y < fh:
                d.point((x, y), fill=rgba(sh(fur, 1.35 if math.sin(a) < 0 else 0.8), alpha))
        legs(d, cy, leg, flat, alpha, False)
        # eyes: two big front eyes catching the light, a row of small ones
        e = rgba(eyes, alpha)
        d.point((15, cy - 2 + flat), fill=e)
        d.point((16, cy - 2 + flat), fill=e)
        d.point((15, cy - 3 + flat), fill=(250, 255, 240, alpha))
        d.point((14, cy - 3 + flat), fill=rgba(sh(eyes, 0.6), alpha))
        d.point((17, cy - 1 + flat), fill=rgba(sh(eyes, 0.6), alpha))
        # pedipalps and fangs
        d.point((17, cy + flat), fill=rgba(sh(fur, 1.2), alpha))
        d.point((17, cy + 1), fill=(220, 210, 180, alpha))
        if open_jaw:
            d.line((18, cy, 20, cy + 2), fill=(225, 220, 200, alpha))
            d.line((17, cy + 1, 19, cy + 3), fill=(225, 220, 200, alpha))
            d.point((20, cy + 3), fill=(170, 230, 120, alpha))  # a drop of venom
        if dis:
            dissolve(im, dis, seed=9)
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(leg=i % 2, crouch=[0, 0, 1, 0][i])
        if name == "walk":
            return body(leg=i)
        if name == "windup":
            return body(crouch=1 + i // 2, eyes=(240, 220, 80))
        if name == "attack":
            return body(open_jaw=True, crouch=-1 if i == 1 else 0)
        if name == "hurt":
            return body(eyes=(255, 255, 255))
        return body(flat=min(4, i + 1), alpha=255 - i * 40, dis=1 + i)

    return lay, fn, True


# ============================================================ night wraith
def night_wraith():
    """A will-o'-the-wisp: a ragged hooded shroud that fades into mist and a
    lantern of cold fire in its hand, 18×22 (ghost_layout)."""
    fw, fh = 18, 22
    lay = gs.monster_layout("ghost_layout", fw, fh, (9, 18), "fly", {"idle": 4, "fly": 4, "windup": 3, "attack": 3, "death": 5})
    shroud = (150, 180, 196)
    fire = ((70, 160, 200), (120, 220, 230), (200, 250, 250), (255, 255, 255))

    def body(phase=0.0, alpha=190, sway=0, raise_=0, flare=0, mouth=False, eye=(160, 240, 255), dis=0):
        im = blank(fw, fh)
        # the shroud: a hood and a body that tears into tatters below
        m = mask(fw, fh, lambda dd: (dd.pieslice((3, 1, 14, 12), 180, 360, fill=FULL), dd.polygon([(3, 6), (14, 6), (15, 14), (2, 14)], fill=FULL)))
        dm = ImageDraw.Draw(m)
        for k in range(4):
            x = 2 + k * 3.4
            off = math.sin(phase + k * 1.3) * 1.6
            dm.polygon([(x, 14), (x + 3.4, 14), (x + 1.7 + off, 19 + off * 0.8)], fill=FULL)
        lit(im, m, shroud, 6, 4, 7, 9, 255)
        px = im.load()
        for y in range(fh):
            for x in range(fw):
                r, g, b, a = px[x, y]
                if a:
                    fade = 1.0 - max(0, y - 9) * 0.075
                    if (x + y) % 3 == 0 and y > 12:
                        fade *= 0.6  # mist breaking up
                    px[x, y] = (r, g, b, int(alpha * max(0.15, fade)))
        d = ImageDraw.Draw(im)
        # folds and torn edges
        d.line((6, 7, 5, 13), fill=rgba(sh(shroud, 0.7), alpha))
        d.line((11, 7, 12, 13), fill=rgba(sh(shroud, 0.75), alpha))
        d.arc((3, 1, 14, 12), 200, 260, fill=rgba(sh(shroud, 1.4), alpha))
        # the dark hollow of the hood with two cold eyes
        d.ellipse((5, 3, 12, 9), fill=(12, 18, 30, 235))
        d.point((7, 6), fill=rgba(eye, 255))
        d.point((10, 6), fill=rgba(eye, 255))
        if mouth:
            d.ellipse((7, 7, 10, 9), fill=(4, 8, 16, 255))
        # an arm reaching out with the lantern on a hook
        lx, ly = 15 + sway, 10 - raise_
        d.line((12, 9, lx - 1, ly - 2), fill=rgba(sh(shroud, 0.9), alpha))
        d.line((lx, ly - 3, lx, ly - 1), fill=(110, 110, 120, 255))
        d.rectangle((lx - 1, ly - 1, lx + 1, ly + 3), fill=rgba(fire[0], 255))
        d.line((lx - 1, ly - 1, lx + 1, ly - 1), fill=(150, 156, 170, 255))
        d.line((lx - 1, ly + 3, lx + 1, ly + 3), fill=(80, 84, 96, 255))
        # cold flame inside the lantern (and above it when it flares)
        d.point((lx, ly), fill=rgba(fire[2], 255))
        d.point((lx, ly + 1), fill=rgba(fire[3], 255))
        d.point((lx, ly + 2), fill=rgba(fire[1], 255))
        if flare:
            for k in range(flare):
                d.point((lx + (k % 2) - (k // 2) % 2, ly - 2 - k), fill=rgba(fire[min(3, 1 + k)], 230 - k * 40))
        # a halo around the lantern (three alpha steps)
        rad = 4.5 + flare
        for y in range(fh):
            for x in range(fw):
                dd = math.hypot(x - lx, (y - ly - 1) * 1.1) / rad
                if dd >= 1.0 or px[x, y][3] >= 90:
                    continue
                ha = 120 if dd < 0.45 else (70 if dd < 0.75 else 30)
                if ha > px[x, y][3]:
                    px[x, y] = (110, 210, 235, ha)
        # a few drifting sparks
        rnd = random.Random(int(phase * 10))
        for _ in range(2):
            sx, sy = rnd.randint(2, 15), rnd.randint(14, 20)
            d.point((sx, sy), fill=rgba(fire[1], 150))
        if dis:
            dissolve(im, dis, seed=3, color=(150, 240, 250, 200))
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body(i * 1.5, sway=[0, 0, -1, 0][i], raise_=[0, 1, 1, 0][i])
        if name == "windup":
            return body(i, 210, raise_=2 + i, flare=1 + i, eye=(220, 255, 255))
        if name == "attack":
            return body(i, 235, sway=1, raise_=1, flare=3, mouth=True, eye=(255, 255, 255))
        if name == "hurt":
            return body(0, 240, eye=(255, 255, 255), mouth=True)
        return body(i, 190 - i * 30, flare=max(0, 2 - i), dis=1 + i * 2)

    # no outline: a spirit of mist (like the dungeon ghost)
    return lay, fn, False


# ============================================================ leech swarm
def leech_swarm():
    """Five small leeches knotted together that writhe and lunge, 20×16
    (slime_layout: idle 4, walk 6, windup 3, attack 3, hurt 2, death 6)."""
    fw, fh = 20, 16
    lay = gs.monster_layout("slime_layout", fw, fh, (10, 16))
    base = (156, 58, 60)
    belly = (196, 120, 96)
    # each leech: anchor x, y, length, phase offset, direction
    WORMS = [(3, 14, 7, 0.0, 1), (8, 14, 7, 1.4, 1), (16, 14, 7, 2.6, -1), (6, 12, 6, 3.7, 1), (13, 12, 6, 5.0, -1)]
    TONES = [1.0, 0.72, 1.12, 0.85, 0.95]
    REAR = [0.0, 4.0, 0.5, 2.5, 5.0]

    def worm(dst, ax, ay, ln, ph, dr, wave, rear, alpha, mouth, tone):
        im = blank(fw, fh)
        pts = []
        segs = 4
        for k in range(segs):
            t = k / (segs - 1)
            x = ax + dr * t * ln * 0.8
            y = ay - math.sin(t * math.pi * 1.3 + wave + ph) * 1.3 - rear * t * t
            pts.append((x, y, 1.2 + 0.4 * math.sin(t * math.pi)))
        for k, (x, y, r) in enumerate(pts):
            m = mask(fw, fh, lambda dd, x=x, y=y, r=r: dd.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=FULL))
            lit(im, m, sh(base, tone * (0.9 + 0.05 * k))[:3], x - 0.8, y - 0.8, r, r, alpha)
        d = ImageDraw.Draw(im)
        for k, (x, y, r) in enumerate(pts[:-1]):
            d.point((x, y - r * 0.6), fill=rgba((214, 132, 70), alpha) if k == 1 else sh(base, 1.35, alpha))
            d.point((x, y + r * 0.6), fill=rgba(belly, alpha))
        hx, hy, hr = pts[-1]
        d.point((hx + dr * hr, hy), fill=(60, 16, 20, alpha))
        if mouth:
            d.point((hx + dr * (hr + 1), hy - 1), fill=(255, 236, 220, alpha))
            d.point((hx + dr * (hr + 1), hy + 1), fill=(255, 236, 220, alpha))
        d.point((hx, hy - hr * 0.7), fill=(255, 210, 120, alpha))
        dst.alpha_composite(gm.gp.outline(im, (30, 8, 12, alpha)))

    def body(wave=0.0, rear=0.0, dx=0, spread=1.0, alpha=255, mouth=False, eyes=True, dis=0):
        im = blank(fw, fh)
        # a slimy puddle under the knot
        d = ImageDraw.Draw(im)
        d.ellipse((2 + dx, 14, 17 + dx, 16), fill=(90, 30, 34, int(alpha * 0.6)))
        order = sorted(range(len(WORMS)), key=lambda k: WORMS[k][1])  # back rows first
        for k in order:
            ax, ay, ln, ph, dr = WORMS[k]
            cx = 10 + (ax - 10) * spread + dx
            worm(im, cx, ay, ln, ph, dr, wave, REAR[k] + rear * (1.0 if k in (1, 4) else 0.4), alpha, mouth and k in (1, 4), TONES[k])
        if not eyes:
            px = im.load()
            for y in range(fh):
                for x in range(fw):
                    r, g, b, a = px[x, y]
                    if a and r > 240 and g > 190:
                        px[x, y] = (255, 255, 255, a)
        d = ImageDraw.Draw(im)
        if dis:
            dissolve(im, dis, color=(200, 40, 40, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(wave=i * math.pi / 2)
        if name == "walk":
            return body(wave=i * math.pi / 3, dx=[0, 1, 1, 0, -1, -1][i], spread=[1.0, 1.05, 1.1, 1.05, 1.0, 0.95][i])
        if name == "windup":
            return body(wave=i, rear=2 + i, spread=0.9, dx=-1)
        if name == "attack":
            return body(wave=i * 2, rear=1, spread=1.15, dx=1, mouth=True)
        if name == "hurt":
            return body(rear=1, eyes=False, spread=1.1)
        return body(wave=i, alpha=255 - i * 30, spread=1.0 + i * 0.12, dis=2 + i * 2 if i < 4 else 9)

    return lay, fn, True


MONSTERS = {
    "crow": crow,
    "forest_spider": forest_spider,
    "night_wraith": night_wraith,
    "leech_swarm": leech_swarm,
}


def main():
    for file, builder in MONSTERS.items():
        lay, fn, outline = builder()
        gs.render_sheet(lay, fn, "sprites/enemies/%s_sheet.png" % file, do_outline=outline)
        sheet = Image.open(os.path.join(gm.A, "sprites/enemies/%s_sheet.png" % file))
        sheet.crop((0, 0, lay.fw, lay.fh)).save(os.path.join(gm.A, "sprites/enemies/%s.png" % file))
    print("own monster sheets: %s" % ", ".join(MONSTERS))


if __name__ == "__main__":
    main()
