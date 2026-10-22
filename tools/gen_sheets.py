#!/usr/bin/env python3
"""Animated sprite sheets for DungeonEclipse (placeholders).

Called from gen_placeholders.py. Every sheet is a grid: one ROW per animation,
one COLUMN per frame, all frames of one sheet have the same size. The layout
(rows, frame counts, fps, loop, origin, hero hand points) is written to
data/animations/*.tres so the game and your replacement art agree on it.
See docs/ANIMATION_GUIDE.md.
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

import gen_placeholders as gp

ROOT = gp.ROOT
A = gp.A
LAYOUT_DIR = os.path.join(ROOT, "data", "animations")


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def shade(c, f):
    return gp.shade(rgba(c) if len(c) == 3 else c, f)


# ===================================================================== layout
class Layout:
    """Animation layout of one sheet family (written as SpriteSheetLayout .tres)."""

    def __init__(self, name, frame_w, frame_h, origin):
        self.name = name
        self.fw = frame_w
        self.fh = frame_h
        self.origin = origin  # pixel of the frame placed at the node origin
        self.anims = []  # (name, frames, fps, loop)
        self.hands = {}  # anim -> [(x, y)] relative to origin
        self.angles = {}  # anim -> [deg]

    def add(self, name, frames, fps, loop):
        self.anims.append((name, frames, fps, loop))

    def size(self):
        cols = max(a[1] for a in self.anims)
        return cols * self.fw, len(self.anims) * self.fh

    def row(self, name):
        return [a[0] for a in self.anims].index(name)

    def write_tres(self):
        os.makedirs(LAYOUT_DIR, exist_ok=True)
        lines = [
            '[gd_resource type="Resource" script_class="SpriteSheetLayout" load_steps=2 format=3]',
            "",
            '[ext_resource type="Script" path="res://scripts/data/sprite_sheet_layout.gd" id="1_layout"]',
            "",
            "[resource]",
            'script = ExtResource("1_layout")',
            f"frame_size = Vector2i({self.fw}, {self.fh})",
            f"origin = Vector2({self.origin[0]}, {self.origin[1]})",
        ]
        anim_items = []
        for i, (n, frames, fps, loop) in enumerate(self.anims):
            anim_items.append(f'"{n}": {{"fps": {float(fps)}, "frames": {frames}, "loop": {"true" if loop else "false"}, "row": {i}}}')
        lines.append("animations = {\n" + ",\n".join(anim_items) + "\n}")
        if self.hands:
            items = []
            for n, pts in self.hands.items():
                flat = ", ".join(f"{p[0]}, {p[1]}" for p in pts)
                items.append(f'"{n}": PackedVector2Array({flat})')
            lines.append("hand_points = {\n" + ",\n".join(items) + "\n}")
            items = []
            for n, angs in self.angles.items():
                flat = ", ".join(str(float(a)) for a in angs)
                items.append(f'"{n}": PackedFloat32Array({flat})')
            lines.append("hand_angles = {\n" + ",\n".join(items) + "\n}")
        with open(os.path.join(LAYOUT_DIR, self.name + ".tres"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def render_sheet(layout: Layout, draw_frame, rel_path, do_outline=True):
    """draw_frame(anim_name, index, count) -> Image(fw, fh)."""
    w, h = layout.size()
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for row, (name, frames, _fps, _loop) in enumerate(layout.anims):
        for i in range(frames):
            img = draw_frame(name, i, frames)
            if do_outline:
                img = gp.outline(img)
            sheet.alpha_composite(img, (i * layout.fw, row * layout.fh))
    path = os.path.join(A, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)


# ====================================================================== hero
HERO_FW, HERO_FH = 32, 32
CX, GROUND = 16, 31

RACES = {
    "human": dict(skin=(230, 185, 145), hair=(90, 55, 30), beard=None, ears=False, leg=7, torso=8, wide=0),
    # Same skeleton for every race so class/equipment layers line up;
    # height differences come from RaceData.sprite_scale in the game.
    "dwarf": dict(skin=(215, 160, 120), hair=(120, 70, 40), beard=(130, 75, 40), ears=False, leg=7, torso=8, wide=0),
    "elf": dict(skin=(240, 215, 185), hair=(230, 220, 150), beard=None, ears=True, leg=7, torso=8, wide=0),
    "orc": dict(skin=(110, 160, 80), hair=(30, 30, 30), beard=None, ears=False, leg=7, torso=8, wide=0, tusks=True),
}
# Heroines: same skeleton (equipment layers line up), long hair behind the
# head that swings against the lean (ponytail / braids / war braid).
RACES_F = {
    "human": dict(skin=(234, 186, 150), hair=(128, 54, 34), beard=None, ears=False, leg=7, torso=8, wide=0, female="tail"),
    "dwarf": dict(skin=(218, 160, 122), hair=(176, 90, 40), beard=None, ears=False, leg=7, torso=8, wide=0, female="braids"),
    "elf": dict(skin=(244, 220, 194), hair=(240, 232, 196), beard=None, ears=True, leg=7, torso=8, wide=0, female="long"),
    "orc": dict(skin=(118, 166, 88), hair=(44, 34, 48), beard=None, ears=False, leg=7, torso=8, wide=0, tusks=True, female="tail"),
}
PANTS = (70, 62, 66)
SHIRT = (120, 110, 100)
GLOVE = (96, 64, 40)


def P(**kw):
    p = dict(by=0, lean=0, crouch=0, lf=(-2, 0), rf=(2, 0), la=(-2, 7), ra=(2, 7), hd=0, back=False, rot=0, ang=-50)
    p.update(kw)
    return p


def hero_poses():
    """anim -> (fps, loop, [pose...]). `ang` is the held item angle (deg, 0 = pointing right)."""
    poses = {}
    poses["idle"] = (5, True, [P(by=0), P(by=0, la=(-2, 6), ra=(2, 6)), P(by=1), P(by=1, la=(-2, 8), ra=(2, 8))])
    run = []
    lx = [-4, -2, 1, 4, 2, -1]
    for i in range(6):
        rx = -lx[i]
        sw = math.sin(i / 6 * math.tau)
        run.append(P(lean=2, by=[0, 1, 0, 0, 1, 0][i],
                     lf=(lx[i], -2 if i in (1, 2) else 0), rf=(rx, -2 if i in (4, 5) else 0),
                     la=(int(-3 * sw) - 1, 6), ra=(int(3 * sw) + 2, 6), ang=-45 + int(10 * sw)))
    poses["run"] = (12, True, run)
    poses["jump"] = (8, False, [P(by=-1, lf=(-3, -3), rf=(2, -4), la=(-3, -2), ra=(4, -2), ang=-30),
                                P(by=-1, lf=(-3, -4), rf=(3, -5), la=(-4, -3), ra=(5, -3), ang=-40)])
    poses["fall"] = (8, True, [P(lf=(-2, -1), rf=(3, -2), la=(-4, 0), ra=(5, -1), ang=-20),
                               P(lf=(-3, -1), rf=(3, -1), la=(-5, -1), ra=(5, 0), ang=-15)])
    poses["land"] = (14, False, [P(crouch=3, by=1, lf=(-3, 0), rf=(3, 0), la=(-4, 5), ra=(4, 5)),
                                 P(crouch=2, by=1, lf=(-3, 0), rf=(3, 0), la=(-3, 6), ra=(3, 6)),
                                 P(crouch=1, lf=(-2, 0), rf=(2, 0))])
    climb = []
    for i in range(4):
        a, b = i % 2, (i + 1) % 2
        climb.append(P(back=True, lf=(-2, -2 * a), rf=(2, -2 * b), la=(-3, -7 + 2 * a), ra=(3, -7 + 2 * b), ang=-90))
    poses["climb"] = (8, True, climb)
    poses["dash"] = (14, True, [P(lean=4, by=1, crouch=1, lf=(-6, 0), rf=(4, -1), la=(-5, 2), ra=(-3, 3), ang=180),
                                P(lean=4, by=1, crouch=1, lf=(-6, -1), rf=(5, 0), la=(-6, 2), ra=(-4, 3), ang=180),
                                P(lean=3, by=1, crouch=1, lf=(-5, 0), rf=(4, 0), la=(-5, 3), ra=(-3, 4), ang=180)])
    # Attacks: body poses; the weapon follows the front hand point and angle.
    poses["attack_slash"] = (14, False, [P(lean=-1, ra=(-1, -7), ang=-130), P(ra=(2, -7), ang=-80),
                                         P(lean=2, lf=(-3, 0), rf=(4, 0), ra=(7, 0), ang=10),
                                         P(lean=2, lf=(-3, 0), rf=(4, 0), ra=(5, 3), ang=45)])
    poses["attack_thrust"] = (14, False, [P(lean=-1, ra=(-2, 2), ang=0), P(lean=-2, ra=(-3, 2), ang=0),
                                          P(lean=3, lf=(-4, 0), rf=(5, 0), ra=(9, 1), ang=0),
                                          P(lean=2, lf=(-3, 0), rf=(4, 0), ra=(6, 2), ang=5)])
    poses["attack_quick"] = (18, False, [P(ra=(2, 1), ang=-20), P(lean=2, ra=(9, 0), ang=0), P(lean=1, ra=(4, 2), ang=10)])
    poses["attack_heavy"] = (10, False, [P(lean=-1, ra=(-2, -8), ang=-150), P(lean=-2, by=-1, ra=(-3, -9), ang=-165),
                                         P(lean=1, ra=(3, -6), ang=-60), P(lean=3, crouch=1, lf=(-4, 0), rf=(5, 0), ra=(8, 2), ang=30),
                                         P(lean=3, crouch=2, by=1, lf=(-4, 0), rf=(5, 0), ra=(7, 4), ang=70)])
    poses["attack_shoot"] = (10, False, [P(ra=(7, -1), la=(4, -1), ang=0), P(lean=-1, ra=(7, -1), la=(1, -1), ang=0),
                                         P(lean=-1, ra=(7, -1), la=(0, -1), ang=0), P(ra=(7, -1), la=(5, -1), ang=0)])
    poses["attack_cast"] = (10, False, [P(ra=(3, -6), ang=-70), P(by=-1, ra=(4, -8), ang=-80),
                                        P(lean=2, ra=(7, -3), ang=-30), P(lean=1, ra=(6, 0), ang=-10)])
    poses["hurt"] = (10, False, [P(lean=-3, by=1, la=(-5, 2), ra=(3, 2), hd=1, ang=60), P(lean=-2, by=1, la=(-4, 3), ra=(3, 3), ang=50)])
    poses["death"] = (8, False, [P(lean=-2, crouch=2, by=1, ra=(4, 5), ang=60), P(lean=-1, crouch=4, by=2, ra=(5, 6), ang=80),
                                 P(crouch=5, by=3, ra=(6, 5), la=(-5, 5), ang=90),
                                 P(crouch=5, by=3, rot=40, ra=(6, 5), ang=90), P(crouch=4, by=2, rot=75, ang=90),
                                 P(crouch=3, by=1, rot=90, ang=90)])
    poses["use"] = (8, False, [P(ra=(3, 4), ang=-90), P(ra=(3, -1), ang=-100), P(hd=-1, ra=(2, -4), ang=-150), P(hd=-1, ra=(2, -4), ang=-160)])
    poses["interact"] = (8, False, [P(lean=2, crouch=1, ra=(6, 4)), P(lean=3, crouch=2, ra=(7, 5)),
                                    P(lean=3, crouch=2, ra=(7, 3)), P(lean=2, crouch=1, ra=(5, 4))])
    return poses


def skel(p, race, cx=CX, ground=GROUND):
    leg, torso = race["leg"], race["torso"]
    hip = (cx + p["lean"] * 0.4, ground - leg + p["crouch"])
    neck = (hip[0] + p["lean"], hip[1] - torso + p["by"])
    head = (neck[0] + (0 if p["back"] else 1), neck[1] - 4 + p["hd"])
    shoulder = (neck[0], neck[1] + 2)
    s = dict(hip=hip, neck=neck, head=head, shoulder=shoulder)
    for side in ("l", "r"):
        f = p[side + "f"]
        foot = (hip[0] + f[0], ground + f[1])
        bend = 1 + p["crouch"] * 0.6
        knee = ((hip[0] + foot[0]) / 2 + bend, (hip[1] + foot[1]) / 2)
        s[side + "foot"] = foot
        s[side + "knee"] = knee
        a = p[side + "a"]
        s[side + "hand"] = (shoulder[0] + a[0], shoulder[1] + a[1])
    return s


def _leg(d, s, side, color):
    """Two-pixel leg: thigh and shin with a lit front edge and a knee."""
    hip, knee, foot = s["hip"], s[side + "knee"], s[side + "foot"]
    d.line([hip, knee, foot], fill=color, width=2)
    d.line([(hip[0] + 1, hip[1]), (knee[0] + 1, knee[1]), (foot[0] + 1, foot[1] - 1)], fill=shade(color, 1.18))
    d.point((round(knee[0]), round(knee[1])), fill=shade(color, 0.78))


def _torso(d, s, color, wide=0, extra_top=0):
    hx, hy = s["hip"]
    nx, ny = s["neck"]
    w = 3 + wide
    d.polygon([(hx - w, hy), (hx + w - 1, hy), (nx + w - 1, ny - extra_top), (nx - w, ny - extra_top)], fill=color)
    # Shading: dark back edge, lit front edge, darker lower half, chest highlight.
    d.line((hx - w, hy, nx - w, ny - extra_top), fill=shade(color, 0.68))
    d.line((hx - w + 1, hy, nx - w + 1, ny - extra_top), fill=shade(color, 0.86))
    d.line((hx + w - 1, hy, nx + w - 1, ny - extra_top), fill=shade(color, 1.22))
    d.line((hx - w + 1, hy - 1, hx + w - 2, hy - 1), fill=shade(color, 0.84))
    d.point((nx + 1, ny + 2), fill=shade(color, 1.3))


def _arm(d, s, side, color, hand_color):
    sx, sy = s["shoulder"]
    hx, hy = s[side + "hand"]
    ex, ey = (sx + hx) / 2 - 0.5, (sy + hy) / 2 + 0.5
    d.line([(sx, sy), (ex, ey), (hx, hy)], fill=color, width=2)
    d.line([(sx, sy - 1), (ex, ey - 1)], fill=shade(color, 1.2))
    d.rectangle((hx - 1, hy - 1, hx, hy), fill=hand_color)
    d.point((hx, hy - 1), fill=shade(hand_color, 1.2))
    d.point((hx - 1, hy), fill=shade(hand_color, 0.75))


def _head(d, p, race, s):
    """7x7 head: shaded skin, eye with a white, brow, nose, mouth, hair with a
    sheen, race features."""
    hx, hy = s["head"]
    skin = rgba(race["skin"])
    hair = rgba(race["hair"])
    style = race.get("female")
    if style:
        # Long hair behind the head; the tip trails behind when leaning / running.
        trail = -1 - max(0, p["lean"])
        if p["back"]:
            d.rectangle((hx - 3, hy, hx + 2, hy + 6), fill=hair)
            d.line((hx - 1, hy + 1, hx - 1, hy + 6), fill=shade(hair, 0.7))
        elif style == "braids":
            d.line((hx - 3, hy, hx - 4 + trail // 2, hy + 6), fill=hair, width=2)
            d.point((hx - 4 + trail // 2, hy + 4), fill=(220, 180, 70, 255))
        else:
            tip = (hx - 4 + trail, hy + (7 if style == "long" else 5))
            d.polygon([(hx - 3, hy - 3), (hx - 1, hy - 2), (tip[0] + 1, tip[1]), tip], fill=hair)
            d.line((hx - 3, hy - 1, tip[0], tip[1] - 1), fill=shade(hair, 0.7))
    d.ellipse((hx - 3, hy - 3, hx + 3, hy + 3), fill=skin)
    d.line((hx - 3, hy - 1, hx - 3, hy + 2), fill=shade(skin, 0.78))  # back of the head
    d.point((hx - 2, hy + 3), fill=shade(skin, 0.75))
    d.point((hx + 2, hy + 3), fill=shade(skin, 0.82))  # jaw
    if p["back"]:
        d.ellipse((hx - 3, hy - 3, hx + 3, hy + 2), fill=hair)
        d.line((hx - 2, hy - 2, hx + 1, hy - 2), fill=shade(hair, 1.35))
        d.line((hx - 1, hy, hx - 1, hy + 2), fill=shade(hair, 0.7))
    else:
        d.pieslice((hx - 3, hy - 4, hx + 3, hy + 2), 180, 360, fill=hair)
        d.rectangle((hx - 3, hy - 1, hx - 2, hy + 2), fill=hair)
        d.line((hx - 1, hy - 3, hx + 1, hy - 3), fill=shade(hair, 1.4))  # sheen
        d.point((hx + 3, hy - 1), fill=hair)  # fringe
        d.point((hx - 3, hy + 2), fill=shade(hair, 0.7))
        # eye: white + pupil, brow, nose, mouth
        d.point((hx + 1, hy), fill=(235, 232, 225, 255))
        d.point((hx + 2, hy), fill=(25, 18, 18, 255))
        d.line((hx + 1, hy - 1, hx + 2, hy - 1), fill=shade(hair, 0.8))
        d.point((hx + 3, hy + 1), fill=shade(skin, 0.82))
        d.point((hx + 2, hy + 2), fill=(196, 84, 90, 255) if style else (150, 75, 70, 255))
        if style:
            d.point((hx + 3, hy - 1), fill=(30, 20, 24, 255))  # lashes
            d.point((hx - 3, hy + 3), fill=hair)  # hair down to the jaw
            d.point((hx - 2, hy + 3), fill=shade(hair, 0.8))
            if style == "braids":
                d.line((hx + 1, hy + 2, hx + 1, hy + 6), fill=hair)  # front braid
                d.point((hx + 1, hy + 5), fill=(220, 180, 70, 255))
        if race["beard"]:
            beard = rgba(race["beard"])
            d.polygon([(hx - 1, hy + 1), (hx + 3, hy + 1), (hx + 2, hy + 5), (hx, hy + 5)], fill=beard)
            d.line((hx, hy + 2, hx + 1, hy + 4), fill=shade(beard, 1.3))
            d.point((hx + 1, hy + 5), fill=(220, 180, 70, 255))  # clasp
    if race["ears"]:
        d.polygon([(hx - 2, hy), (hx - 6, hy - 3), (hx - 2, hy - 2)], fill=skin)
        d.point((hx - 4, hy - 2), fill=shade(skin, 0.8))
    if race.get("tusks") and not p["back"]:
        d.point((hx + 2, hy + 2), fill=(240, 240, 220, 255))
        d.point((hx, hy + 2), fill=(240, 240, 220, 255))


def draw_body(p, race):
    im = gp.new(HERO_FW, HERO_FH)
    d = ImageDraw.Draw(im)
    s = skel(p, race)
    skin = rgba(race["skin"])
    _arm(d, s, "l", shade(skin, 0.8), shade(skin, 0.8))
    _leg(d, s, "l", shade(rgba(PANTS), 0.8))
    _leg(d, s, "r", rgba(PANTS))
    _torso(d, s, rgba(SHIRT), race["wide"])
    _head(d, p, race, s)
    _arm(d, s, "r", skin, skin)
    return im


def _boots(d, s, color):
    for side in ("l", "r"):
        fx, fy = s[side + "foot"]
        c = color if side == "r" else shade(color, 0.8)
        d.rectangle((fx - 1, fy - 2, fx + 2, fy), fill=c)
        d.line((fx - 1, fy - 2, fx + 1, fy - 2), fill=shade(c, 1.3))  # cuff
        d.line((fx - 1, fy, fx + 2, fy), fill=shade(c, 0.6))  # sole
        d.point((fx + 2, fy - 1), fill=shade(c, 1.15))  # toe


OUTFITS = {
    # class: torso, trim, boots, sleeve, robe(bool), kind (details)
    "warrior": dict(torso=(140, 40, 40), trim=(90, 60, 30), boots=(80, 55, 35), sleeve=(150, 50, 45), robe=False,
                    kind="warrior"),
    "rogue": dict(torso=(50, 90, 50), trim=(40, 60, 40), boots=(55, 45, 35), sleeve=(45, 80, 45), robe=False,
                  kind="rogue"),
    "mage": dict(torso=(60, 50, 140), trim=(200, 170, 60), boots=(50, 40, 70), sleeve=(70, 60, 155), robe=True,
                 kind="mage"),
    "paladin": dict(torso=(220, 220, 230), trim=(220, 180, 60), boots=(120, 120, 135), sleeve=(200, 200, 215),
                    robe=False, kind="paladin"),
}


def draw_outfit(p, o, race=RACES["human"]):
    im = gp.new(HERO_FW, HERO_FH)
    d = ImageDraw.Draw(im)
    s = skel(p, race)
    torso = rgba(o["torso"])
    trim = rgba(o["trim"])
    _boots(d, s, rgba(o["boots"]))
    hx, hy = s["hip"]
    nx, ny = s["neck"]
    if o["robe"]:
        lf, rf = s["lfoot"], s["rfoot"]
        x0, x1 = min(lf[0], hx - 3) - 1, max(rf[0], hx + 3) + 1
        d.polygon([(hx - 3, hy - 1), (hx + 3, hy - 1), (x1, GROUND - 2), (x0, GROUND - 2)], fill=shade(torso, 0.85))
        d.line((x0, GROUND - 2, x1, GROUND - 2), fill=trim)  # hem
        d.line((hx, hy, (x0 + x1) / 2, GROUND - 3), fill=shade(torso, 0.65))  # fold
    _torso(d, s, torso)
    kind = o.get("kind")
    # Belt with a buckle.
    d.line((hx - 3, hy - 1, hx + 2, hy - 1), fill=trim)
    d.point((hx + 1, hy - 1), fill=(230, 200, 90, 255) if kind != "mage" else (255, 90, 110, 255))
    if not p["back"]:
        if kind == "warrior":
            d.line((nx - 2, ny + 1, hx + 2, hy - 2), fill=rgba((95, 62, 35)))  # strap
            d.point((nx + 1, ny + 3), fill=rgba((200, 170, 80)))
        elif kind == "rogue":
            d.line((nx - 2, ny + 1, hx + 2, hy - 2), fill=rgba((40, 32, 25)))
            d.rectangle((hx - 3, hy - 3, hx - 2, hy - 2), fill=rgba((90, 65, 40)))  # pouch
            d.line((nx - 1, ny, nx + 2, ny), fill=rgba((120, 40, 40)))  # scarf
        elif kind == "mage":
            d.line((nx, ny, nx, hy - 1), fill=trim)
            d.point((nx, ny + 3), fill=(120, 220, 255, 255))  # amulet
        elif kind == "paladin":
            d.rectangle((nx - 1, ny + 2, nx + 2, hy - 2), fill=rgba((240, 236, 225)))  # tabard
            d.line((nx + 1, ny + 2, nx + 1, hy - 2), fill=trim)
            d.line((nx, ny + 4, nx + 2, ny + 4), fill=trim)
        else:
            d.line((nx, ny, nx, ny + 4), fill=shade(torso, 1.25))
    # Shoulder pad for armoured classes.
    if kind in ("warrior", "paladin"):
        sx, sy = s["shoulder"]
        pad = rgba((120, 85, 50)) if kind == "warrior" else rgba((210, 210, 222))
        d.ellipse((sx - 2, sy - 2, sx + 2, sy + 1), fill=pad)
        d.point((sx - 1, sy - 2), fill=shade(pad, 1.35))
        if kind == "paladin":
            d.line((sx - 2, sy + 1, sx + 2, sy + 1), fill=trim)
    _arm(d, s, "r", rgba(o["sleeve"]), rgba(GLOVE))
    if kind == "mage":
        hx2, hy2 = s["rhand"]
        d.point((hx2 - 1, hy2 - 2), fill=trim)  # cuff
    return im


HEADGEAR = {
    "warrior": ("miner", (110, 85, 50)),
    "rogue": ("hood", (50, 75, 50)),
    "mage": ("wizard", (70, 50, 150)),
    "paladin": ("helm", (225, 215, 170)),
    "leather_cap": ("cap", (140, 95, 55)),
    "iron_helm": ("helm", (165, 170, 180)),
    "crown_of_shadows": ("crown", (200, 170, 40)),
}


def draw_head(p, kind, color):
    im = gp.new(HERO_FW, HERO_FH)
    d = ImageDraw.Draw(im)
    s = skel(p, RACES["human"])
    hx, hy = s["head"]
    c = rgba(color)
    hi, lo = shade(c, 1.35), shade(c, 0.68)
    if kind == "miner":
        d.pieslice((hx - 4, hy - 5, hx + 4, hy + 2), 180, 360, fill=c)
        d.line((hx - 3, hy - 4, hx, hy - 5), fill=hi)
        d.line((hx - 5, hy - 1, hx + 5, hy - 1), fill=lo)
        d.point((hx - 2, hy - 2), fill=hi)  # rivet
        if not p["back"]:
            d.rectangle((hx + 1, hy - 4, hx + 2, hy - 3), fill=(255, 240, 160, 255))
            d.point((hx + 3, hy - 4), fill=(255, 255, 220, 200))
    elif kind == "hood":
        d.polygon([(hx - 4, hy + 3), (hx - 4, hy - 2), (hx - 1, hy - 5), (hx + 3, hy - 4), (hx + 4, hy - 1), (hx + 2, hy - 2),
                   (hx - 2, hy + 3)], fill=c)
        d.line((hx - 3, hy - 2, hx - 1, hy - 4), fill=hi)
        d.line((hx - 4, hy, hx - 4, hy + 3), fill=lo)
        if p["back"]:
            d.ellipse((hx - 4, hy - 4, hx + 4, hy + 3), fill=c)
            d.line((hx - 2, hy - 3, hx + 1, hy - 3), fill=hi)
        else:
            d.point((hx + 1, hy - 1), fill=(20, 25, 20, 200))  # shadow over the eye
    elif kind == "wizard":
        d.polygon([(hx - 5, hy - 2), (hx + 5, hy - 2), (hx + 1, hy - 7), (hx - 3, hy - 10)], fill=c)
        d.line((hx - 2, hy - 8, hx - 3, hy - 3), fill=hi)
        d.line((hx - 5, hy - 2, hx + 5, hy - 2), fill=lo)
        d.line((hx - 4, hy - 3, hx + 4, hy - 3), fill=rgba(gp.GOLD))  # band
        d.point((hx, hy - 6), fill=(255, 245, 170, 255))  # star
    elif kind == "cap":
        d.pieslice((hx - 4, hy - 5, hx + 3, hy + 1), 180, 360, fill=c)
        d.line((hx - 3, hy - 4, hx - 1, hy - 5), fill=hi)
        d.line((hx, hy - 2, hx + 4, hy - 2), fill=lo)
        d.point((hx - 2, hy - 2), fill=lo)  # stitch
    elif kind == "helm":
        d.pieslice((hx - 4, hy - 5, hx + 4, hy + 3), 180, 360, fill=c)
        d.rectangle((hx - 4, hy - 1, hx - 2, hy + 2), fill=shade(c, 0.85))
        d.line((hx - 3, hy - 4, hx, hy - 5), fill=hi)
        d.line((hx - 4, hy - 1, hx + 4, hy - 1), fill=lo)
        if not p["back"]:
            d.line((hx + 1, hy - 4, hx + 1, hy + 1), fill=shade(c, 1.2))
            if color == (225, 215, 170):  # paladin: gold band and plume
                d.line((hx - 4, hy - 2, hx + 4, hy - 2), fill=rgba((225, 180, 60)))
                d.line((hx - 1, hy - 6, hx - 4, hy - 7), fill=rgba((190, 40, 45)))
                d.point((hx - 2, hy - 7), fill=rgba((230, 80, 80)))
    elif kind == "crown":
        d.polygon([(hx - 4, hy - 2), (hx - 4, hy - 6), (hx - 2, hy - 4), (hx, hy - 7), (hx + 2, hy - 4), (hx + 4, hy - 6),
                   (hx + 4, hy - 2)], fill=c)
        d.line((hx - 4, hy - 2, hx + 4, hy - 2), fill=lo)
        d.point((hx, hy - 4), fill=(160, 40, 220, 255))
        d.point((hx, hy - 6), fill=hi)
    return im


ARMOR_VISUALS = {
    "leather_armor": dict(torso=(140, 95, 55), trim=(100, 65, 35), sleeve=(130, 88, 50), pads=False),
    "chainmail": dict(torso=(160, 165, 175), trim=(110, 112, 120), sleeve=(150, 155, 165), pads=True),
    "mage_robe": dict(torso=(80, 60, 160), trim=(200, 170, 60), sleeve=(90, 70, 170), pads=False),
}


def draw_armor(p, a):
    im = gp.new(HERO_FW, HERO_FH)
    d = ImageDraw.Draw(im)
    s = skel(p, RACES["human"])
    torso = rgba(a["torso"])
    _torso(d, s, torso)
    hx, hy = s["hip"]
    nx, ny = s["neck"]
    d.line((hx - 3, hy - 1, hx + 2, hy - 1), fill=rgba(a["trim"]))
    if a["pads"]:
        sx, sy = s["shoulder"]
        d.ellipse((sx - 3, sy - 2, sx + 2, sy + 1), fill=shade(torso, 1.2))
        d.point((sx - 2, sy - 2), fill=shade(torso, 1.5))
        for y in range(int(ny) + 2, int(hy) - 1, 2):
            d.line((hx - 2 + p["lean"] * 0.5, y, hx + 2 + p["lean"] * 0.5, y), fill=shade(torso, 0.8))
            d.point((hx + p["lean"] * 0.5, y + 1), fill=shade(torso, 1.25))  # rings
    elif a["torso"] == (140, 95, 55):
        d.point((nx, ny + 3), fill=shade(torso, 0.7))  # stitched panels
        d.point((nx + 1, ny + 5), fill=shade(torso, 0.7))
        d.line((nx - 2, ny + 1, nx + 2, ny + 1), fill=shade(torso, 1.25))
    else:
        d.line((nx, ny, nx, hy - 1), fill=rgba(a["trim"]))
    _arm(d, s, "r", rgba(a["sleeve"]), rgba(GLOVE))
    return im


def apply_rot(im, p):
    if not p["rot"]:
        return im
    rot = p["rot"]
    dy = 8 * math.sin(math.radians(rot))
    return im.rotate(rot, resample=Image.NEAREST, center=(CX, GROUND - 11), translate=(0, dy))


def gen_hero():
    poses = hero_poses()
    lay = Layout("hero_layout", HERO_FW, HERO_FH, (CX, GROUND + 1))
    for name, (fps, loop, frames) in poses.items():
        lay.add(name, len(frames), fps, loop)
        lay.hands[name] = []
        lay.angles[name] = []
        for pz in frames:
            s = skel(pz, RACES["human"])
            hx, hy = s["rhand"]
            if pz["rot"]:
                # hand moves with the rotated body
                c = (CX, GROUND - 11)
                a = -math.radians(pz["rot"])
                dx, dy = hx - c[0], hy - c[1]
                hx = c[0] + dx * math.cos(a) - dy * math.sin(a)
                hy = c[1] + dx * math.sin(a) + dy * math.cos(a) + 8 * math.sin(math.radians(pz["rot"]))
            lay.hands[name].append((round(hx - CX), round(hy - GROUND - 1)))
            lay.angles[name].append(pz["ang"] - pz["rot"])
    lay.write_tres()

    def frame_fn(draw):
        def fn(name, i, _n):
            pz = poses[name][2][i]
            return apply_rot(draw(pz), pz)
        return fn

    for race_id, race in RACES.items():
        render_sheet(lay, frame_fn(lambda pz, r=race: draw_body(pz, r)), f"sprites/player/body_{race_id}.png")
    for race_id, race in RACES_F.items():
        render_sheet(lay, frame_fn(lambda pz, r=race: draw_body(pz, r)), f"sprites/player/body_{race_id}_f.png")
    for cls, o in OUTFITS.items():
        render_sheet(lay, frame_fn(lambda pz, o=o: draw_outfit(pz, o)), f"sprites/player/outfit_{cls}.png", do_outline=False)
    for key, (kind, color) in HEADGEAR.items():
        prefix = "head_" if key in OUTFITS else "equip_"
        render_sheet(lay, frame_fn(lambda pz, k=kind, c=color: draw_head(pz, k, c)), f"sprites/player/{prefix}{key}.png", do_outline=False)
    for key, a in ARMOR_VISUALS.items():
        render_sheet(lay, frame_fn(lambda pz, a=a: draw_armor(pz, a)), f"sprites/player/equip_{key}.png", do_outline=False)


# =================================================================== monsters
def monster_layout(name, fw, fh, origin, move_anim="walk", counts=None):
    counts = counts or {}
    lay = Layout(name, fw, fh, origin)
    lay.add("idle", counts.get("idle", 4), 6, True)
    lay.add(move_anim, counts.get(move_anim, 6), 10, True)
    lay.add("windup", counts.get("windup", 3), 8, False)
    lay.add("attack", counts.get("attack", 3), 12, False)
    lay.add("hurt", 2, 10, False)
    lay.add("death", counts.get("death", 6), 10, False)
    return lay


def gen_slime():
    fw, fh = 20, 16
    lay = monster_layout("slime_layout", fw, fh, (10, 16))
    base = (70, 190, 80)

    def body(w, h, dx=0, dy=0, eyes="o", alpha=255):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(base, alpha)
        x0 = 10 - w / 2 + dx
        d.pieslice((x0, 15 - 2 * h + dy, x0 + w - 1, 15 + dy), 180, 360, fill=c)
        d.rectangle((x0, 15 - 1 + dy, x0 + w - 1, 15 + dy), fill=shade(c, 0.75))
        d.point((x0 + 2, 15 - h + 2 + dy), fill=(190, 255, 200, alpha))
        ey = 15 - h // 2 - 1 + dy
        ex = 10 + dx
        if eyes == "o":
            d.point((ex - 2, ey), fill=(10, 30, 10, alpha))
            d.point((ex + 2, ey), fill=(10, 30, 10, alpha))
        elif eyes == "x":
            for e in (ex - 2, ex + 2):
                d.point((e - 1, ey - 1), fill=(10, 30, 10, alpha))
                d.point((e, ey), fill=(10, 30, 10, alpha))
                d.point((e - 1, ey + 1), fill=(10, 30, 10, alpha))
        elif eyes == "angry":
            d.line((ex - 3, ey - 1, ex - 1, ey), fill=(10, 30, 10, alpha))
            d.line((ex + 3, ey - 1, ex + 1, ey), fill=(10, 30, 10, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            k = [0, 1, 0, -1][i]
            return body(16 - k, 7 + k)
        if name == "walk":
            hop = [0, -2, -4, -4, -2, 0][i]
            sq = [2, -1, -2, -1, 0, 2][i]
            return body(16 + sq, 7 - sq // 2, dy=hop)
        if name == "windup":
            return body(16 + i * 1, 6 - i, eyes="angry")
        if name == "attack":
            return body([18, 19, 17][i], [6, 7, 7][i], dx=[2, 3, 1][i], eyes="angry")
        if name == "hurt":
            return body(17, 6 + i, eyes="x")
        k = i + 1
        return body(16 + k, max(1, 7 - k), eyes="x", alpha=255 - i * 35)

    render_sheet(lay, fn, "sprites/enemies/slime_sheet.png")
    lay.write_tres()


def gen_skeleton():
    fw, fh = 24, 28
    lay = monster_layout("skeleton_layout", fw, fh, (12, 28))
    bone = (225, 220, 200)
    race = dict(leg=7, torso=8)

    def body(p, sword_ang=30, pile=0, alpha=255):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(bone, alpha)
        if pile:
            # collapsed bones on the floor
            for k in range(pile):
                x = 4 + (k * 5) % 15
                d.line((x, 27 - (k % 2), x + 4, 26 + (k % 2)), fill=c)
            d.ellipse((9, 22 + max(0, 3 - pile // 2), 14, 27), fill=c)
            return im
        s = skel(p, race, cx=12, ground=27)
        for side in ("l", "r"):
            d.line([s["hip"], s[side + "knee"], s[side + "foot"]], fill=c if side == "r" else shade(c, 0.8))
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        d.line((hx, hy, nx, ny), fill=c, width=2)
        for k in range(3):
            y = ny + 2 + k * 2
            d.line((nx - 2 + (hx - nx) * k / 4, y, nx + 2 + (hx - nx) * k / 4, y), fill=c)
        d.line([s["shoulder"], s["lhand"]], fill=shade(c, 0.8))
        hx2, hy2 = s["head"]
        d.ellipse((hx2 - 3, hy2 - 3, hx2 + 3, hy2 + 2), fill=c)
        d.point((hx2 + 1, hy2 - 1), fill=(160, 20, 20, alpha))
        d.point((hx2 + 3, hy2 - 1), fill=(160, 20, 20, alpha))
        d.line((hx2, hy2 + 2, hx2 + 3, hy2 + 2), fill=shade(c, 0.6))
        d.line([s["shoulder"], s["rhand"]], fill=c)
        # rusty sword in the front hand
        rx, ry = s["rhand"]
        a = math.radians(sword_ang)
        d.line((rx, ry, rx + 8 * math.cos(a), ry + 8 * math.sin(a)), fill=(150, 125, 105, alpha), width=1)
        d.point((rx, ry), fill=(110, 80, 40, alpha))
        return im

    def fn(name, i, n):
        if name == "idle":
            return body(P(by=[0, 0, 1, 1][i], ra=(2, 6)), 70)
        if name == "walk":
            lx = [-3, -1, 1, 3, 1, -1][i]
            return body(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(2 + lx // 2, 6)), 60)
        if name == "windup":
            return body(P(lean=-1 - i, ra=(-2, -6 - i)), -120 - i * 10)
        if name == "attack":
            return body(P(lean=2, lf=(-3, 0), rf=(4, 0), ra=[(4, -3), (7, 1), (6, 4)][i]), [-40, 20, 60][i])
        if name == "hurt":
            return body(P(lean=-3, by=1, ra=(3, 3)), 80)
        if i < 2:
            return body(P(crouch=2 + i * 2, by=1 + i, ra=(5, 5)), 90)
        return body(P(), pile=2 + i, alpha=255 - (i - 2) * 30)

    render_sheet(lay, fn, "sprites/enemies/skeleton_sheet.png")
    lay.write_tres()


def gen_bat():
    fw, fh = 20, 16
    lay = monster_layout("bat_layout", fw, fh, (10, 12), "fly", {"idle": 4, "fly": 4, "windup": 2, "attack": 3, "death": 5})
    c0 = (90, 60, 110)

    def body(wing, dy=0, rot=0, eyes=True, alpha=255, tilt=0):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(c0, alpha)
        cy = 8 + dy
        wy = cy - wing
        d.polygon([(9, cy), (1, wy), (3, cy + 2), (6, cy + 1)], fill=c)
        d.polygon([(11, cy), (19, wy), (17, cy + 2), (14, cy + 1)], fill=c)
        d.ellipse((7, cy - 2 + tilt, 12, cy + 3 + tilt), fill=shade(c, 1.2))
        d.point((8, cy - 3 + tilt), fill=c)
        d.point((11, cy - 3 + tilt), fill=c)
        if eyes:
            d.point((9, cy + tilt), fill=(255, 60, 60, alpha))
            d.point((11, cy + tilt), fill=(255, 60, 60, alpha))
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST, center=(10, 8))
        return im

    def fn(name, i, n):
        if name in ("idle", "fly"):
            return body([4, 1, -3, 1][i], dy=[0, 0, 1, 1][i] if name == "idle" else 0)
        if name == "windup":
            return body(5 + i, dy=-1 - i)
        if name == "attack":
            return body(-2, dy=1, rot=[-20, -35, -25][i], tilt=1)
        if name == "hurt":
            return body(2, eyes=False)
        return body(-3, dy=i, rot=i * 60, eyes=False, alpha=255 - i * 40)

    render_sheet(lay, fn, "sprites/enemies/bat_sheet.png")
    lay.write_tres()


def gen_cultist():
    fw, fh = 24, 28
    lay = monster_layout("cultist_layout", fw, fh, (12, 28), counts={"windup": 4})
    robe = (110, 25, 40)

    def body(sway=0, hands=(14, 15), orb=0, flash=False, dissolve=0, alpha=255, lean=0):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = rgba(robe, alpha)
        d.polygon([(8 + lean, 10), (15 + lean, 10), (18 + sway, 27), (5 + sway, 27)], fill=c)
        d.line((6 + sway, 26, 17 + sway, 26), fill=shade(c, 0.7))
        d.polygon([(8 + lean, 11), (10 + lean, 3), (15 + lean, 4), (16 + lean, 11)], fill=shade(c, 0.8))
        d.rectangle((11 + lean, 6, 15 + lean, 9), fill=(20, 10, 15, alpha))
        eye = (255, 200, 40, alpha) if not flash else (255, 255, 255, alpha)
        d.point((12 + lean, 7), fill=eye)
        d.point((14 + lean, 7), fill=eye)
        hx, hy = hands
        d.rectangle((hx + lean, hy, hx + 2 + lean, hy + 1), fill=(200, 170, 150, alpha))
        if orb:
            d.ellipse((hx + 2 + lean - orb, hy - orb, hx + 2 + lean + orb, hy + orb), fill=(200, 90, 255, alpha))
            d.point((hx + 2 + lean, hy), fill=(255, 230, 255, alpha))
        if dissolve:
            px = im.load()
            for y in range(fh):
                for x in range(fw):
                    if (x * 7 + y * 13) % 10 < dissolve:
                        px[x, y] = (0, 0, 0, 0)
                    elif px[x, y][3] and (x + y) % 3 == 0 and dissolve > 2:
                        px[x, y] = (180, 80, 230, alpha)
        return im

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
        return body(dissolve=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    render_sheet(lay, fn, "sprites/enemies/cultist_sheet.png")
    lay.write_tres()


# ====================================================================== world
def simple_layout(name, fw, fh, origin, anims):
    lay = Layout(name, fw, fh, origin)
    for a in anims:
        lay.add(*a)
    lay.write_tres()
    return lay


def gen_torch():
    lay = simple_layout("torch_layout", 16, 16, (8, 16), [("burn", 6, 10, True)])

    def fn(name, i, n):
        im = gp.new(16, 16)
        d = ImageDraw.Draw(im)
        d.rectangle((7, 9, 8, 15), fill=(110, 75, 40, 255))
        d.rectangle((5, 8, 10, 9), fill=(80, 80, 90, 255))
        h = [5, 6, 5, 7, 6, 5][i]
        sx = [0, 1, 0, -1, 0, 1][i]
        d.polygon([(5, 8), (10, 8), (8 + sx, 8 - h)], fill=(255, 120, 20, 255))
        d.polygon([(6, 8), (9, 8), (8 + sx, 9 - h + 2)], fill=(255, 220, 80, 255))
        return im

    render_sheet(lay, fn, "sprites/props/torch_sheet.png")


def gen_chests():
    lay = simple_layout("chest_layout", 16, 16, (8, 16), [("closed", 1, 1, False), ("opening", 4, 12, False), ("open", 1, 1, False)])
    tiers = {"wood": ((120, 80, 45), (70, 50, 30)), "iron": ((95, 100, 110), (60, 62, 70)), "gold": ((110, 40, 120), gp.GOLD[:3])}
    for tier, (body, trim) in tiers.items():
        def fn(name, i, n, body=body, trim=trim):
            im = gp.new(16, 16)
            d = ImageDraw.Draw(im)
            b, t = rgba(body), rgba(trim)
            lid = 0 if name == "closed" else (3 if name == "open" else i)
            # lid rotates up: height shrinks then shows the inside
            lid_h = [5, 3, 1, 2][lid]
            top = 9 - lid_h - (0 if lid < 2 else 3)
            if lid >= 2:
                d.rectangle((2, 8, 13, 9), fill=(20, 12, 8, 255))
                d.rectangle((1, top, 14, top + lid_h), fill=shade(b, 0.7))
                if lid == 3:
                    d.rectangle((3, 7, 12, 8), fill=(255, 220, 90, 255))
            else:
                d.rectangle((1, 9 - lid_h, 14, 9), fill=shade(b, 1.15))
            d.rectangle((1, 9, 14, 15), fill=b)
            d.line((1, 9, 14, 9), fill=t)
            d.line((1, 15, 14, 15), fill=t)
            d.rectangle((7, 9 - (0 if lid >= 2 else 1), 8, 11), fill=t)
            return im

        render_sheet(lay, fn, f"sprites/props/chest_{tier}_sheet.png")


def gen_portal():
    lay = simple_layout("portal_layout", 24, 32, (12, 32), [("swirl", 8, 10, True)])

    def fn(name, i, n):
        im = gp.new(24, 32)
        d = ImageDraw.Draw(im)
        d.rectangle((1, 0, 22, 31), fill=(60, 56, 66, 255))
        d.rectangle((4, 5, 19, 31), fill=(12, 8, 18, 255))
        d.pieslice((4, 0, 19, 11), 180, 360, fill=(12, 8, 18, 255))
        for k in range(14):
            a = k * 0.9 + i * math.tau / 8
            r = 1 + k * 0.5
            x = 12 + math.cos(a) * r
            y = 17 + math.sin(a) * r * 1.4
            col = (120 + k * 9, 50 + k * 5, 230, 255)
            d.point((x, y), fill=col)
            d.point((x + 1, y), fill=col)
        for x, y in ((1, 0), (22, 0)):
            d.rectangle((x, y, x, y + 31), fill=(80, 76, 90, 255))
        return im

    render_sheet(lay, fn, "sprites/props/portal_sheet.png")


def gen_fx():
    lay = simple_layout("drop_layout", 8, 8, (4, 8), [("fall", 2, 8, True), ("splash", 4, 12, False)])

    def drop(name, i, n):
        im = gp.new(8, 8)
        d = ImageDraw.Draw(im)
        c = (90, 160, 230, 230)
        if name == "fall":
            d.ellipse((3, 2 + i, 4, 5 + i), fill=c)
        else:
            r = i + 1
            d.point((4 - r, 7 - (1 if i < 2 else 0)), fill=c)
            d.point((4 + r, 7 - (1 if i < 2 else 0)), fill=c)
            if i < 2:
                d.point((4, 6 - i), fill=c)
        return im

    render_sheet(lay, drop, "sprites/fx/drop_sheet.png", do_outline=False)

    lay = simple_layout("explosion_layout", 48, 48, (24, 24), [("boom", 7, 18, False)])

    def boom(name, i, n):
        im = gp.new(48, 48)
        d = ImageDraw.Draw(im)
        r = [6, 12, 17, 20, 21, 21, 20][i]
        cols = [(255, 255, 220), (255, 230, 120), (255, 160, 40), (230, 90, 20), (150, 60, 30), (90, 80, 80), (60, 60, 60)]
        a = [255, 255, 255, 240, 200, 150, 80][i]
        for k in range(10):
            ang = k * math.tau / 10 + i * 0.3
            rr = r * (0.75 + 0.25 * ((k * 7) % 3) / 2)
            x, y = 24 + math.cos(ang) * rr * 0.6, 24 + math.sin(ang) * rr * 0.6
            d.ellipse((x - rr * 0.5, y - rr * 0.5, x + rr * 0.5, y + rr * 0.5), fill=rgba(cols[i], a))
        if i < 4:
            d.ellipse((24 - r * 0.4, 24 - r * 0.4, 24 + r * 0.4, 24 + r * 0.4), fill=rgba(cols[max(0, i - 1)], 255))
        return im

    render_sheet(lay, boom, "sprites/fx/explosion_sheet.png", do_outline=False)

    lay = simple_layout("dust_layout", 12, 8, (6, 8), [("puff", 5, 14, False)])

    def dust(name, i, n):
        im = gp.new(12, 8)
        d = ImageDraw.Draw(im)
        a = 200 - i * 40
        c = (170, 150, 130, a)
        r = 1 + i * 0.6
        for x in (3, 6, 9):
            d.ellipse((x - r, 6 - r - i * 0.4, x + r, 6 + r - i * 0.4), fill=c)
        return im

    render_sheet(lay, dust, "sprites/fx/dust_sheet.png", do_outline=False)

    lay = simple_layout("hit_layout", 16, 16, (8, 8), [("hit", 4, 20, False)])

    def hit(name, i, n):
        im = gp.new(16, 16)
        d = ImageDraw.Draw(im)
        r = [3, 6, 7, 7][i]
        a = [255, 255, 180, 90][i]
        for k in range(6):
            ang = k * math.tau / 6 + 0.3
            d.line((8 + math.cos(ang) * (r - 3 if i else 0), 8 + math.sin(ang) * (r - 3 if i else 0),
                    8 + math.cos(ang) * r, 8 + math.sin(ang) * r), fill=(255, 245, 200, a))
        if i < 2:
            d.ellipse((6, 6, 9, 9), fill=(255, 255, 255, 255))
        return im

    render_sheet(lay, hit, "sprites/fx/hit_sheet.png", do_outline=False)

    shard = gp.new(4, 4)
    ImageDraw.Draw(shard).polygon([(0, 0), (3, 1), (2, 3)], fill=(255, 255, 255, 255))
    shard.save(os.path.join(A, "sprites/fx/shard.png"))


def main():
    gen_hero()
    # Monsters: the detailed versions (the old gen_slime / gen_skeleton /
    # gen_bat / gen_cultist are kept only as references).
    import gen_monsters
    gen_monsters.main()
    gen_torch()
    gen_chests()
    gen_portal()
    gen_fx()
    import gen_structures  # detailed chests, torch, portal over the ones above
    gen_structures.main()
    print("sheets generated")


if __name__ == "__main__":
    main()
