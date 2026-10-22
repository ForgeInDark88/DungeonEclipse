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


def main():
    os.makedirs(os.path.join(A, "ui/status"), exist_ok=True)
    status_icons()
    traps()
    merchant()
    bosses()
    print("mechanics generated")


if __name__ == "__main__":
    main()
