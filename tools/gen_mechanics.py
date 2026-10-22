#!/usr/bin/env python3
"""Placeholders for stage 15 mechanics: status icons, traps, merchant,
bosses, new monsters, events, minimap / sanctum UI bits.
Called from gen_placeholders.py."""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw

import gen_placeholders as gp
import gen_sheets as gs

A = gp.A


def c4(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a)


# -------------------------------------------------------------- status icons
def status_icons():
    out = {}

    def base():
        im = gp.new(8, 8)
        return im, ImageDraw.Draw(im)

    im, d = base()  # poison drop
    d.polygon([(4, 0), (7, 5), (4, 7), (1, 5)], fill=(90, 220, 70, 255))
    d.point((3, 4), fill=(200, 255, 190, 255))
    out["poison"] = im
    im, d = base()  # burn flame
    d.polygon([(1, 7), (2, 3), (4, 0), (6, 3), (7, 7)], fill=(255, 120, 30, 255))
    d.polygon([(3, 7), (4, 3), (5, 7)], fill=(255, 230, 90, 255))
    out["burn"] = im
    im, d = base()  # bleed
    d.polygon([(4, 0), (7, 5), (4, 7), (1, 5)], fill=(200, 20, 30, 255))
    d.point((3, 4), fill=(255, 120, 120, 255))
    out["bleed"] = im
    im, d = base()  # stun stars
    for x, y in ((1, 2), (5, 1), (4, 5)):
        d.point((x, y), fill=(255, 240, 80, 255))
        d.point((x + 1, y), fill=(255, 240, 80, 255))
        d.point((x, y + 1), fill=(255, 240, 80, 255))
        d.point((x + 1, y + 1), fill=(255, 255, 200, 255))
    out["stun"] = im
    im, d = base()  # slow snowflake
    c = (150, 210, 255, 255)
    d.line((4, 0, 4, 7), fill=c)
    d.line((0, 4, 7, 4), fill=c)
    d.line((1, 1, 6, 6), fill=c)
    d.line((6, 1, 1, 6), fill=c)
    out["slow"] = im
    im, d = base()  # regen plus
    d.rectangle((3, 0, 4, 7), fill=(80, 230, 100, 255))
    d.rectangle((0, 3, 7, 4), fill=(80, 230, 100, 255))
    out["regen"] = im
    im, d = base()  # shield
    d.polygon([(0, 0), (7, 0), (7, 4), (4, 7), (3, 7), (0, 4)], fill=(120, 170, 255, 255))
    d.point((3, 2), fill=(230, 240, 255, 255))
    out["shield"] = im
    im, d = base()  # curse skull
    d.ellipse((1, 0, 6, 5), fill=(170, 80, 220, 255))
    d.rectangle((2, 5, 5, 7), fill=(170, 80, 220, 255))
    d.point((2, 2), fill=(20, 0, 30, 255))
    d.point((5, 2), fill=(20, 0, 30, 255))
    out["curse"] = im
    for name, im in out.items():
        gp.save(im, f"ui/status/{name}.png")
    # Shield bubble around creatures.
    bub = gp.new(28, 32)
    d = ImageDraw.Draw(bub)
    d.ellipse((0, 0, 27, 31), outline=(140, 190, 255, 200), width=1)
    d.ellipse((2, 2, 25, 29), fill=(120, 170, 255, 50))
    d.arc((4, 3, 14, 13), 180, 270, fill=(230, 240, 255, 220))
    bub.save(os.path.join(A, "sprites/fx/shield_bubble.png"))


# ------------------------------------------------------------------- traps
def traps():
    lay = gs.simple_layout("spikes_layout", 16, 16, (8, 16), [("hidden", 1, 1, False), ("rise", 3, 20, False), ("up", 1, 1, False), ("retract", 3, 12, False)])

    def spikes(name, i, n):
        im = gp.new(16, 16)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 13, 15, 15), fill=(70, 66, 72, 255))
        h = {"hidden": 0, "up": 9}.get(name, [3, 6, 9][i] if name == "rise" else [6, 3, 1][i])
        for x in (1, 5, 9, 13):
            if h:
                d.polygon([(x, 13), (x + 1, 13 - h), (x + 2, 13)], fill=(200, 200, 210, 255))
                d.point((x + 1, 13 - h), fill=(255, 255, 255, 255))
        return im

    gs.render_sheet(lay, spikes, "sprites/traps/spikes_sheet.png")
    lay = gs.simple_layout("acid_layout", 16, 8, (8, 8), [("bubble", 4, 6, True)])

    def acid(name, i, n):
        im = gp.new(16, 8)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 3, 15, 7), fill=(90, 200, 60, 220))
        d.line((0, 3, 15, 3), fill=(170, 255, 120, 255))
        for k in range(3):
            x = (k * 6 + i * 3) % 16
            d.ellipse((x, 1 + (i + k) % 2, x + 2, 3 + (i + k) % 2), outline=(190, 255, 150, 255))
        return im

    gs.render_sheet(lay, acid, "sprites/traps/acid_sheet.png", do_outline=False)
    lay = gs.simple_layout("plate_layout", 16, 4, (8, 4), [("up", 1, 1, False), ("down", 1, 1, False)])

    def plate(name, i, n):
        im = gp.new(16, 4)
        d = ImageDraw.Draw(im)
        top = 1 if name == "up" else 2
        d.rectangle((2, top, 13, 3), fill=(130, 120, 110, 255))
        d.line((2, top, 13, top), fill=(180, 170, 150, 255))
        return im

    gs.render_sheet(lay, plate, "sprites/traps/plate_sheet.png")
    lay = gs.simple_layout("arrow_trap_layout", 16, 16, (8, 16), [("idle", 1, 1, False), ("fire", 3, 14, False)])

    def arrow_trap(name, i, n):
        im = gp.new(16, 16)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 15, 15), fill=(80, 76, 84, 255))
        d.rectangle((1, 1, 14, 14), outline=(60, 56, 64, 255))
        d.ellipse((9, 5, 14, 10), fill=(20, 15, 20, 255))
        if name == "fire":
            d.ellipse((10, 6, 13, 9), fill=(255, 200, 120, 255 - i * 70))
        d.point((4, 4), fill=(140, 40, 40, 255))
        return im

    gs.render_sheet(lay, arrow_trap, "sprites/traps/arrow_trap_sheet.png")
    rock = gp.new(14, 14)
    d = ImageDraw.Draw(rock)
    d.polygon([(2, 3), (7, 0), (12, 3), (13, 9), (8, 13), (2, 11), (0, 7)], fill=(110, 100, 95, 255))
    d.line((4, 4, 8, 3), fill=(150, 140, 130, 255))
    gp.save(rock, "sprites/traps/rock.png")
    crack = gp.new(16, 4)
    d = ImageDraw.Draw(crack)
    for x in range(0, 16, 3):
        d.line((x, 0, x + 1, 3), fill=(40, 30, 30, 255))
    crack.save(os.path.join(A, "sprites/traps/ceiling_crack.png"))


# ----------------------------------------------------------------- merchant
def merchant():
    lay = gs.simple_layout("merchant_layout", 24, 28, (12, 28), [("idle", 4, 4, True), ("greet", 3, 8, False)])

    def fn(name, i, n):
        im = gp.new(24, 28)
        d = ImageDraw.Draw(im)
        robe = (70, 60, 110, 255)
        bob = [0, 0, 1, 1][i] if name == "idle" else 0
        d.polygon([(6, 12 + bob), (17, 12 + bob), (20, 27), (3, 27)], fill=robe)
        d.line((4, 26, 19, 26), fill=gp.shade(robe, 0.7))
        d.polygon([(6, 13 + bob), (9, 3 + bob), (15, 3 + bob), (18, 13 + bob)], fill=gp.shade(robe, 0.8))
        d.rectangle((9, 7 + bob, 15, 11 + bob), fill=(225, 180, 140, 255))
        d.point((13, 8 + bob), fill=(20, 20, 20, 255))
        d.polygon([(9, 11 + bob), (15, 11 + bob), (14, 15 + bob), (10, 15 + bob)], fill=(200, 200, 205, 255))  # beard
        # backpack and lantern
        d.rectangle((2, 13 + bob, 6, 22 + bob), fill=(120, 80, 45, 255))
        arm_y = 16 + bob - (i * 3 if name == "greet" else 0)
        d.line((17, 14 + bob, 20, arm_y), fill=gp.shade(robe, 0.9), width=2)
        d.rectangle((19, arm_y, 22, arm_y + 4), fill=(255, 210, 90, 255))
        d.point((20, arm_y + 1), fill=(255, 250, 200, 255))
        return im

    gs.render_sheet(lay, fn, "sprites/npc/merchant_sheet.png")
    # Shop rug under the merchant.
    rug = gp.new(40, 4)
    d = ImageDraw.Draw(rug)
    d.rectangle((0, 1, 39, 3), fill=(120, 30, 40, 255))
    for x in range(2, 38, 4):
        d.point((x, 2), fill=(230, 190, 80, 255))
    rug.save(os.path.join(A, "sprites/npc/rug.png"))
    coin = gp.new(8, 8)
    d = ImageDraw.Draw(coin)
    d.ellipse((0, 0, 7, 7), fill=gp.GOLD)
    d.ellipse((2, 2, 5, 5), outline=gp.GOLD_D)
    coin.save(os.path.join(A, "ui/coin.png"))


# ------------------------------------------------------------------- bosses
def bosses():
    # Bone King: big armoured skeleton with a crown and a great sword (48x48).
    fw, fh = 48, 48
    lay = gs.monster_layout("bone_king_layout", fw, fh, (24, 48), counts={"windup": 3, "attack": 3, "death": 6})
    bone = (230, 225, 205)
    race = dict(leg=13, torso=15)

    def king(p, sword_ang=40, alpha=255, pile=0, glow=False):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = (bone[0], bone[1], bone[2], alpha)
        if pile:
            for k in range(pile + 3):
                x = 6 + (k * 7) % 34
                d.line((x, 47 - (k % 2), x + 7, 45 + (k % 2)), fill=c, width=2)
            d.ellipse((18, 36, 28, 46), fill=c)
            d.polygon([(19, 36), (21, 31), (23, 35), (25, 31), (27, 36)], fill=(220, 180, 40, alpha))
            return im
        s = gs.skel(p, race, cx=24, ground=47)
        for side in ("l", "r"):
            d.line([s["hip"], s[side + "knee"], s[side + "foot"]], fill=c if side == "r" else gp.shade(c, 0.8), width=3)
        hx, hy = s["hip"]
        nx, ny = s["neck"]
        # rusty armour on the torso
        d.polygon([(hx - 7, hy), (hx + 7, hy), (nx + 8, ny), (nx - 8, ny)], fill=(110, 80, 70, alpha))
        for k in range(4):
            y = ny + 3 + k * 3
            d.line((nx - 6, y, nx + 6, y), fill=(80, 55, 45, alpha))
        d.line([s["shoulder"], s["lhand"]], fill=gp.shade(c, 0.8), width=3)
        hx2, hy2 = s["head"]
        d.ellipse((hx2 - 6, hy2 - 6, hx2 + 6, hy2 + 5), fill=c)
        eye = (255, 60, 30, alpha) if not glow else (255, 255, 120, alpha)
        d.rectangle((hx2 + 1, hy2 - 2, hx2 + 2, hy2 - 1), fill=eye)
        d.rectangle((hx2 + 4, hy2 - 2, hx2 + 5, hy2 - 1), fill=eye)
        d.polygon([(hx2 - 6, hy2 - 5), (hx2 - 5, hy2 - 11), (hx2 - 2, hy2 - 7), (hx2 + 1, hy2 - 12), (hx2 + 3, hy2 - 7), (hx2 + 6, hy2 - 11), (hx2 + 6, hy2 - 5)], fill=(220, 180, 40, alpha))
        d.line([s["shoulder"], s["rhand"]], fill=c, width=3)
        rx, ry = s["rhand"]
        a = math.radians(sword_ang)
        d.line((rx, ry, rx + 20 * math.cos(a), ry + 20 * math.sin(a)), fill=(150, 140, 150, alpha), width=3)
        d.line((rx - 3 * math.sin(a), ry + 3 * math.cos(a), rx + 3 * math.sin(a), ry - 3 * math.cos(a)), fill=(200, 160, 40, alpha), width=2)
        return im

    def fn(name, i, n):
        P = gs.P
        if name == "idle":
            return king(P(by=[0, 0, 1, 1][i], ra=(4, 10)), 70)
        if name == "walk":
            lx = [-5, -2, 2, 5, 2, -2][i]
            return king(P(lean=1, lf=(lx, 0), rf=(-lx, 0), by=[0, 1, 0, 0, 1, 0][i], ra=(4, 10)), 60)
        if name == "windup":
            return king(P(lean=-2 - i, crouch=i, ra=(-3, -10 - i * 2)), -120 - i * 12, glow=True)
        if name == "attack":
            return king(P(lean=4, lf=(-5, 0), rf=(7, 0), crouch=2, ra=[(8, -4), (12, 2), (10, 8)][i]), [-30, 25, 70][i])
        if name == "hurt":
            return king(P(lean=-4, by=2, ra=(4, 6)), 80)
        if i < 2:
            return king(P(crouch=3 + i * 3, by=2 + i, ra=(7, 8)), 90)
        return king(P(), pile=i, alpha=255 - (i - 2) * 25)

    gs.render_sheet(lay, fn, "sprites/bosses/bone_king_sheet.png")
    lay.write_tres()

    # Flame Witch: floating robed figure with a fire halo (40x44).
    fw, fh = 40, 44
    lay = gs.monster_layout("flame_witch_layout", fw, fh, (20, 44), "fly", {"idle": 4, "fly": 4, "windup": 4, "attack": 3, "death": 6})

    def witch(phase=0.0, hands_up=0, orb=0, alpha=255, dissolve=0, flash=False):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        dy = int(math.sin(phase) * 2)
        robe = (150, 30, 20, alpha)
        for k in range(6):
            a = phase + k * math.tau / 6
            x, y = 20 + math.cos(a) * 12, 12 + dy + math.sin(a) * 5
            d.ellipse((x - 2, y - 3, x + 2, y + 1), fill=(255, 140 + k * 15, 40, alpha))
        d.polygon([(14, 16 + dy), (26, 16 + dy), (31, 40 + dy), (24, 37 + dy), (20, 42 + dy), (16, 37 + dy), (9, 40 + dy)], fill=robe)
        d.polygon([(14, 17 + dy), (17, 6 + dy), (23, 6 + dy), (26, 17 + dy)], fill=gp.shade(robe, 0.8))
        d.rectangle((17, 9 + dy, 23, 15 + dy), fill=(250, 220, 200, alpha))
        eye = (255, 255, 255, alpha) if flash else (255, 200, 40, alpha)
        d.point((19, 11 + dy), fill=eye)
        d.point((22, 11 + dy), fill=eye)
        hy = 22 + dy - hands_up * 6
        d.line((14, 19 + dy, 8, hy), fill=gp.shade(robe, 0.9), width=2)
        d.line((26, 19 + dy, 32, hy), fill=gp.shade(robe, 0.9), width=2)
        if orb:
            for x in (8, 32):
                d.ellipse((x - orb, hy - orb, x + orb, hy + orb), fill=(255, 170, 40, alpha))
                d.point((x, hy), fill=(255, 255, 200, alpha))
        if dissolve:
            px = im.load()
            for y in range(fh):
                for x in range(fw):
                    if (x * 7 + y * 11) % 10 < dissolve:
                        px[x, y] = (0, 0, 0, 0)
        return im

    def fn2(name, i, n):
        if name in ("idle", "fly"):
            return witch(i * math.tau / 4)
        if name == "windup":
            return witch(i, hands_up=1, orb=1 + i)
        if name == "attack":
            return witch(i, hands_up=2, orb=[4, 2, 0][i], flash=i == 0)
        if name == "hurt":
            return witch(0, flash=True)
        return witch(i, dissolve=1 + i * 2, alpha=255 - i * 30)

    gs.render_sheet(lay, fn2, "sprites/bosses/flame_witch_sheet.png")
    lay.write_tres()
    # Projectiles and key item.
    shard = gp.new(8, 4)
    d = ImageDraw.Draw(shard)
    d.polygon([(0, 2), (6, 0), (7, 2), (6, 3)], fill=(230, 225, 205, 255))
    gp.save(shard, "sprites/fx/bone_shard.png")
    seal = gp.new(16, 16)
    d = ImageDraw.Draw(seal)
    d.ellipse((2, 2, 13, 13), fill=(120, 40, 160, 255))
    d.ellipse((4, 4, 11, 11), fill=(20, 10, 30, 255))
    d.arc((4, 4, 11, 11), 200, 340, fill=(240, 200, 60, 255), width=2)
    d.point((7, 7), fill=(255, 240, 150, 255))
    gp.save(seal, "sprites/items/guardian_seal.png")


# ------------------------------------------------------------ new monsters
def new_monsters():
    # Spider 22x14
    fw, fh = 22, 14
    lay = gs.monster_layout("spider_layout", fw, fh, (11, 14), counts={"windup": 3, "attack": 3, "death": 5})

    def spider(leg=0, crouch=0, eyes=(255, 40, 40), alpha=255, flat=0, open_jaw=False):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        body = (60, 40, 55, alpha)
        cy = 8 + crouch + flat
        for k, side in enumerate((-1, 1)):
            for j in range(3):
                x0 = 11 + side * (3 + j)
                lift = ((leg + j + k) % 2) * 2
                d.line((x0, cy, x0 + side * 5, cy - 3 - lift + flat), fill=body)
                d.line((x0 + side * 5, cy - 3 - lift + flat, x0 + side * 7, 13), fill=body)
        d.ellipse((5, cy - 4 + flat, 14, cy + 3), fill=(80, 55, 75, alpha))
        d.ellipse((12, cy - 3 + flat, 18, cy + 2), fill=(70, 45, 65, alpha))
        d.point((16, cy - 1 + flat), fill=(eyes[0], eyes[1], eyes[2], alpha))
        d.point((17, cy - 2 + flat), fill=(eyes[0], eyes[1], eyes[2], alpha))
        if open_jaw:
            d.line((18, cy, 20, cy + 2), fill=(220, 220, 200, alpha))
        d.point((8, cy - 3 + flat), fill=(200, 60, 60, alpha))
        return im

    def sp(name, i, n):
        if name == "idle":
            return spider(leg=i % 2)
        if name == "walk":
            return spider(leg=i)
        if name == "windup":
            return spider(crouch=1 + i // 2, eyes=(255, 200, 40))
        if name == "attack":
            return spider(open_jaw=True)
        if name == "hurt":
            return spider(eyes=(255, 255, 255))
        return spider(flat=min(4, i + 1), alpha=255 - i * 45)

    gs.render_sheet(lay, sp, "sprites/enemies/spider_sheet.png")
    lay.write_tres()

    # Golem 28x30
    fw, fh = 28, 30
    lay = gs.monster_layout("golem_layout", fw, fh, (14, 30), counts={"windup": 3, "attack": 3, "death": 6})

    def golem(step=0, arms_up=0, crouch=0, core=(80, 220, 255), alpha=255, crumble=0):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        stone = (110, 105, 100, alpha)
        if crumble:
            for k in range(crumble + 3):
                x = 3 + (k * 7) % 20
                y = 29 - (k % 3) * 2
                d.rectangle((x, y - 3, x + 4, y), fill=gp.shade(stone, 0.8 + (k % 2) * 0.2))
            return im
        y0 = crouch
        d.rectangle((7 + step, 22 + y0, 12 + step, 29), fill=gp.shade(stone, 0.85))
        d.rectangle((15 - step, 22 + y0, 20 - step, 29), fill=stone)
        d.rectangle((5, 9 + y0, 22, 23 + y0), fill=stone)
        d.rectangle((9, 3 + y0, 18, 10 + y0), fill=gp.shade(stone, 1.1))
        d.rectangle((14, 5 + y0, 16, 6 + y0), fill=(core[0], core[1], core[2], alpha))
        d.ellipse((11, 13 + y0, 16, 18 + y0), fill=(core[0], core[1], core[2], alpha))
        ay = 12 + y0 - arms_up * 8
        d.rectangle((1, ay, 5, ay + 10), fill=gp.shade(stone, 0.9))
        d.rectangle((22, ay, 26, ay + 10), fill=gp.shade(stone, 0.9))
        d.line((7, 12 + y0, 11, 20 + y0), fill=gp.shade(stone, 0.7))
        return im

    def gm(name, i, n):
        if name == "idle":
            return golem(crouch=[0, 0, 1, 1][i])
        if name == "walk":
            return golem(step=[-1, 0, 1, 1, 0, -1][i], crouch=i % 2)
        if name == "windup":
            return golem(arms_up=1, crouch=-i, core=(255, 200, 80))
        if name == "attack":
            return golem(arms_up=0, crouch=[2, 3, 1][i], core=(255, 120, 60))
        if name == "hurt":
            return golem(core=(255, 255, 255))
        return golem(crumble=i, alpha=255) if i > 1 else golem(crouch=2 + i * 2, core=(60, 60, 60))

    gs.render_sheet(lay, gm, "sprites/enemies/golem_sheet.png")
    lay.write_tres()

    # Ghost 18x22 (flyer)
    fw, fh = 18, 22
    lay = gs.monster_layout("ghost_layout", fw, fh, (9, 18), "fly", {"idle": 4, "fly": 4, "windup": 3, "attack": 3, "death": 5})

    def ghost(phase=0.0, alpha=170, mouth=False, eyes=(180, 230, 255), dissolve=0):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        c = (200, 220, 240, alpha)
        d.pieslice((2, 1, 15, 16), 180, 360, fill=c)
        d.rectangle((2, 8, 15, 15), fill=c)
        for k in range(4):
            x = 2 + k * 4
            off = int(math.sin(phase + k) * 2)
            d.polygon([(x, 15), (x + 4, 15), (x + 2, 19 + off)], fill=c)
        d.rectangle((5, 6, 6, 8), fill=(eyes[0], eyes[1], eyes[2], 255))
        d.rectangle((10, 6, 11, 8), fill=(eyes[0], eyes[1], eyes[2], 255))
        if mouth:
            d.ellipse((7, 10, 10, 13), fill=(20, 20, 40, 230))
        if dissolve:
            px = im.load()
            for y in range(fh):
                for x in range(fw):
                    if (x * 5 + y * 9) % 10 < dissolve:
                        px[x, y] = (0, 0, 0, 0)
        return im

    def gh(name, i, n):
        if name in ("idle", "fly"):
            return ghost(i * 1.5)
        if name == "windup":
            return ghost(i, 200 + i * 15, False, (255, 120, 120))
        if name == "attack":
            return ghost(i, 240, True, (255, 80, 80))
        if name == "hurt":
            return ghost(0, 255, True, (255, 255, 255))
        return ghost(i, 170 - i * 30, dissolve=1 + i * 2)

    gs.render_sheet(lay, gh, "sprites/enemies/ghost_sheet.png", do_outline=False)
    lay.write_tres()

    # Summoner 24x28
    fw, fh = 24, 28
    lay = gs.monster_layout("summoner_layout", fw, fh, (12, 28), counts={"windup": 4, "attack": 3})

    def summoner(sway=0, staff_up=0, glow=0, alpha=255, dissolve=0):
        im = gp.new(fw, fh)
        d = ImageDraw.Draw(im)
        robe = (40, 70, 50, alpha)
        d.polygon([(8, 10), (15, 10), (18 + sway, 27), (5 + sway, 27)], fill=robe)
        d.polygon([(8, 11), (10, 2), (15, 3), (16, 11)], fill=gp.shade(robe, 0.8))
        d.rectangle((11, 5, 15, 9), fill=(20, 25, 20, alpha))
        d.point((12, 7), fill=(120, 255, 140, alpha))
        d.point((14, 7), fill=(120, 255, 140, alpha))
        sy = 6 - staff_up * 4
        d.line((19, sy, 19, 27), fill=(110, 80, 50, alpha), width=1)
        d.ellipse((17, sy - 3, 21, sy + 1), fill=(225, 220, 200, alpha))  # skull
        if glow:
            d.ellipse((19 - glow, sy - 1 - glow, 19 + glow, sy - 1 + glow), outline=(140, 255, 160, alpha))
        if dissolve:
            px = im.load()
            for y in range(fh):
                for x in range(fw):
                    if (x * 7 + y * 13) % 10 < dissolve:
                        px[x, y] = (0, 0, 0, 0)
        return im

    def sm(name, i, n):
        if name == "idle":
            return summoner(sway=[0, 1, 0, -1][i])
        if name == "walk":
            return summoner(sway=[1, 2, 1, -1, -2, -1][i])
        if name == "windup":
            return summoner(staff_up=1, glow=1 + i)
        if name == "attack":
            return summoner(staff_up=1, glow=[5, 3, 1][i])
        if name == "hurt":
            return summoner(sway=-2)
        return summoner(dissolve=2 + i * 2 if i < 4 else 9, alpha=255 - i * 30)

    gs.render_sheet(lay, sm, "sprites/enemies/summoner_sheet.png")
    lay.write_tres()
    web = gp.new(8, 8)
    d = ImageDraw.Draw(web)
    d.line((0, 4, 7, 4), fill=(230, 230, 240, 255))
    d.line((4, 0, 4, 7), fill=(230, 230, 240, 255))
    d.line((1, 1, 6, 6), fill=(230, 230, 240, 200))
    d.line((6, 1, 1, 6), fill=(230, 230, 240, 200))
    d.ellipse((2, 2, 5, 5), outline=(255, 255, 255, 255))
    web.save(os.path.join(A, "sprites/fx/web.png"))
    for name, src in (("spider", "spider_sheet"), ("golem", "golem_sheet"), ("ghost", "ghost_sheet"), ("summoner", "summoner_sheet")):
        sheet = Image.open(os.path.join(A, f"sprites/enemies/{src}.png"))
        lay_w = {"spider": 22, "golem": 28, "ghost": 18, "summoner": 24}[name]
        lay_h = {"spider": 14, "golem": 30, "ghost": 22, "summoner": 28}[name]
        sheet.crop((0, 0, lay_w, lay_h)).save(os.path.join(A, f"sprites/enemies/{name}.png"))


# ------------------------------------------------------------------ events
def events():
    out = "sprites/events/"
    # Altar 20x16
    lay = gs.simple_layout("altar_layout", 20, 18, (10, 18), [("idle", 4, 6, True), ("used", 1, 1, False)])

    def altar(name, i, n):
        im = gp.new(20, 18)
        d = ImageDraw.Draw(im)
        stone = (90, 85, 95, 255)
        d.rectangle((2, 10, 17, 17), fill=stone)
        d.rectangle((0, 8, 19, 10), fill=gp.shade(stone, 1.2))
        d.rectangle((4, 12, 15, 15), fill=gp.shade(stone, 0.8))
        if name == "idle":
            glow = (200, 40, 60, 255) if i % 2 == 0 else (255, 80, 90, 255)
            d.polygon([(10, 1 + (i % 2)), (13, 5), (10, 8), (7, 5)], fill=glow)
            d.line((7, 13, 12, 14), fill=glow)
        else:
            d.line((7, 13, 12, 14), fill=(60, 50, 60, 255))
        return im

    gs.render_sheet(lay, altar, out + "altar_sheet.png")
    # Fountain 24x28
    lay = gs.simple_layout("fountain_layout", 24, 28, (12, 28), [("flow", 4, 8, True), ("dry", 1, 1, False)])

    def fountain(name, i, n):
        im = gp.new(24, 28)
        d = ImageDraw.Draw(im)
        stone = (140, 135, 130, 255)
        d.rectangle((1, 20, 22, 27), fill=stone)
        d.rectangle((0, 19, 23, 21), fill=gp.shade(stone, 1.2))
        d.rectangle((10, 6, 13, 20), fill=stone)
        d.ellipse((6, 3, 17, 9), fill=gp.shade(stone, 1.1))
        if name == "flow":
            w = (90, 170, 240, 255)
            d.rectangle((3, 21, 20, 23), fill=w)
            for k in range(3):
                y = 4 + ((i + k) % 4) * 4
                d.point((5 + k, y + 6), fill=(200, 230, 255, 255))
                d.point((18 - k, y + 6), fill=(200, 230, 255, 255))
            d.arc((2, 4, 21, 26), 200, 340, fill=w)
        return im

    gs.render_sheet(lay, fountain, out + "fountain_sheet.png")
    # Lever 10x14
    lay = gs.simple_layout("lever_layout", 10, 14, (5, 14), [("up", 1, 1, False), ("down", 1, 1, False)])

    def lever(name, i, n):
        im = gp.new(10, 14)
        d = ImageDraw.Draw(im)
        d.rectangle((1, 10, 8, 13), fill=(90, 85, 95, 255))
        if name == "up":
            d.line((5, 10, 2, 2), fill=(150, 110, 70, 255), width=2)
            d.ellipse((0, 0, 3, 3), fill=(200, 60, 60, 255))
        else:
            d.line((5, 10, 8, 2), fill=(150, 110, 70, 255), width=2)
            d.ellipse((6, 0, 9, 3), fill=(80, 220, 90, 255))
        return im

    gs.render_sheet(lay, lever, out + "lever_sheet.png")
    # Rune symbols 8x8 (puzzle)
    runes = gp.new(8 * 4, 8)
    d = ImageDraw.Draw(runes)
    c = (120, 220, 255, 255)
    d.line((1, 1, 6, 6), fill=c)
    d.line((6, 1, 1, 6), fill=c)  # X
    d.ellipse((8 + 1, 1, 8 + 6, 6), outline=c)  # O
    d.polygon([(16 + 3, 0), (16 + 7, 7), (16 + 0, 7)], outline=c)  # triangle
    d.rectangle((24 + 1, 1, 24 + 6, 6), outline=c)  # square
    runes.save(os.path.join(A, out + "runes.png"))
    # Barrier 16x32
    lay = gs.simple_layout("barrier_layout", 16, 32, (8, 32), [("hum", 4, 8, True)])

    def barrier(name, i, n):
        im = gp.new(16, 32)
        d = ImageDraw.Draw(im)
        for y in range(0, 32, 2):
            a = 90 + int(60 * math.sin(y * 0.4 + i * 1.5))
            d.line((1, y, 14, y), fill=(140, 90, 255, a))
        d.rectangle((0, 0, 15, 31), outline=(200, 160, 255, 220))
        return im

    gs.render_sheet(lay, barrier, out + "barrier_sheet.png", do_outline=False)
    # Cage with a prisoner 20x26
    lay = gs.simple_layout("cage_layout", 20, 26, (10, 26), [("idle", 2, 2, True), ("open", 1, 1, False)])

    def cage(name, i, n):
        im = gp.new(20, 26)
        d = ImageDraw.Draw(im)
        if name == "idle":
            # prisoner
            d.rectangle((7, 12 + i, 12, 22), fill=(110, 100, 90, 255))
            d.ellipse((7, 6 + i, 12, 11 + i), fill=(220, 180, 150, 255))
            d.point((11, 8 + i), fill=(20, 20, 20, 255))
            for x in range(1, 20, 4):
                d.line((x, 2, x, 24), fill=(120, 120, 130, 255))
        else:
            for x in (1, 17):
                d.line((x, 2, x, 24), fill=(120, 120, 130, 255))
        d.rectangle((0, 0, 19, 2), fill=(90, 90, 100, 255))
        d.rectangle((0, 24, 19, 25), fill=(90, 90, 100, 255))
        return im

    gs.render_sheet(lay, cage, out + "cage_sheet.png")


# ----------------------------------------------------- sanctum (meta) icons
def meta_icons():
    os.makedirs(os.path.join(A, "sprites/meta"), exist_ok=True)

    def icon(name, draw):
        im = gp.new(16, 16)
        d = ImageDraw.Draw(im)
        d.ellipse((0, 0, 15, 15), fill=(40, 25, 55, 255), outline=(150, 90, 210, 255))
        draw(d)
        gp.save(im, "sprites/meta/%s.png" % name)

    icon("vitality", lambda d: (d.ellipse((3, 4, 8, 9), fill=(200, 40, 50, 255)),
                                d.ellipse((7, 4, 12, 9), fill=(200, 40, 50, 255)),
                                d.polygon([(3, 7), (12, 7), (8, 12)], fill=(200, 40, 50, 255)),
                                d.point((5, 5), fill=(255, 160, 160, 255))))
    icon("might", lambda d: (d.line((4, 11, 11, 4), fill=(210, 210, 225, 255), width=2),
                             d.line((4, 8, 7, 11), fill=(150, 110, 60, 255), width=2)))
    icon("wisdom", lambda d: (d.ellipse((4, 4, 11, 11), fill=(60, 110, 230, 255)),
                              d.ellipse((5, 5, 7, 7), fill=(190, 220, 255, 255))))
    icon("eye", lambda d: (d.ellipse((2, 5, 13, 10), fill=(230, 220, 180, 255)),
                           d.ellipse((6, 5, 9, 10), fill=(150, 60, 200, 255)),
                           d.point((7, 7), fill=(0, 0, 0, 255))))
    icon("bulwark", lambda d: (d.polygon([(4, 3), (11, 3), (11, 8), (7, 13), (4, 8)], fill=(140, 140, 160, 255)),
                               d.line((7, 4, 7, 11), fill=(220, 180, 60, 255))))
    icon("purse", lambda d: (d.ellipse((3, 5, 12, 13), fill=(150, 100, 50, 255)),
                             d.rectangle((6, 3, 9, 5), fill=(120, 80, 40, 255)),
                             d.ellipse((6, 8, 9, 11), fill=(240, 200, 60, 255))))
    icon("satchel", lambda d: (d.rectangle((4, 4, 11, 12), fill=(200, 40, 60, 255)),
                               d.rectangle((6, 2, 9, 4), fill=(160, 140, 120, 255)),
                               d.point((6, 6), fill=(255, 190, 190, 255))))
    icon("explorer", lambda d: (d.rectangle((3, 4, 12, 11), fill=(225, 205, 160, 255)),
                                d.line((5, 6, 10, 9), fill=(120, 80, 40, 255)),
                                d.point((10, 9), fill=(200, 40, 40, 255))))
    # Paladin skill: holy light
    im = gp.new(16, 16)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 15), fill=(60, 50, 20, 255))
    for a in range(8):
        ang = a * math.pi / 4
        d.line((8, 8, 8 + 7 * math.cos(ang), 8 + 7 * math.sin(ang)), fill=(255, 230, 140, 255))
    d.ellipse((5, 5, 10, 10), fill=(255, 250, 220, 255))
    gp.save(im, "sprites/skills/holy_light.png")


# ------------------------------------------------------- achievement icons
def achievement_icons():
    """16x16 medal: ring colour = tier (bronze/silver/gold), glyph = category."""
    tiers = {"bronze": (190, 120, 60, 255), "silver": (200, 205, 215, 255), "gold": (240, 200, 70, 255)}
    ink = (40, 25, 20, 255)

    def skull(d):
        d.ellipse((5, 4, 10, 9), fill=(235, 230, 215, 255))
        d.rectangle((6, 9, 9, 11), fill=(235, 230, 215, 255))
        d.point((6, 6), fill=ink); d.point((9, 6), fill=ink)

    def crown(d):
        d.polygon([(4, 10), (4, 5), (6, 7), (8, 4), (10, 7), (12, 5), (12, 10)], fill=(250, 220, 90, 255), outline=ink)

    def stairs(d):
        for i in range(3):
            d.rectangle((4 + i * 3, 10 - i * 2, 12, 11 - i * 2), fill=(120, 90, 70, 255))

    def chest(d):
        d.rectangle((4, 6, 11, 11), fill=(140, 90, 40, 255), outline=ink)
        d.line((4, 8, 11, 8), fill=ink)
        d.point((8, 9), fill=(250, 220, 90, 255))

    def gem(d):
        d.polygon([(8, 4), (12, 8), (8, 12), (4, 8)], fill=(170, 80, 240, 255), outline=ink)

    def coin(d):
        d.ellipse((5, 5, 10, 10), fill=(250, 210, 70, 255), outline=ink)

    def gear(d):
        d.polygon([(4, 11), (8, 4), (12, 11)], fill=(150, 150, 160, 255), outline=ink)

    def star(d):
        d.polygon([(8, 3), (9, 7), (13, 7), (10, 9), (11, 13), (8, 10), (5, 13), (6, 9), (3, 7), (7, 7)],
                  fill=(255, 245, 190, 255))

    def book(d):
        d.rectangle((4, 4, 11, 11), fill=(120, 40, 40, 255), outline=ink)
        d.line((6, 4, 6, 11), fill=(230, 200, 120, 255))

    def bag(d):
        d.ellipse((4, 6, 11, 12), fill=(150, 100, 50, 255), outline=ink)
        d.rectangle((6, 4, 9, 6), fill=(120, 80, 40, 255))

    glyphs = {"skull": skull, "crown": crown, "stairs": stairs, "chest": chest, "gem": gem, "coin": coin,
              "trap": gear, "star": star, "book": book, "bag": bag}
    for tier, col in tiers.items():
        for gname, fn in glyphs.items():
            im = gp.new(16, 16)
            d = ImageDraw.Draw(im)
            d.ellipse((0, 0, 15, 15), fill=c4(gp.shade(col, 0.55)), outline=c4(col))
            d.ellipse((1, 1, 14, 14), outline=c4(gp.shade(col, 1.2)))
            fn(d)
            gp.save(im, "sprites/achievements/%s_%s.png" % (gname, tier))


def main():
    os.makedirs(os.path.join(A, "ui/status"), exist_ok=True)
    status_icons()
    traps()
    merchant()
    bosses()
    new_monsters()
    events()
    meta_icons()
    achievement_icons()
    print("mechanics generated")


if __name__ == "__main__":
    main()
