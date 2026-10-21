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


def main():
    os.makedirs(os.path.join(A, "ui/status"), exist_ok=True)
    status_icons()
    traps()
    print("mechanics generated")


if __name__ == "__main__":
    main()
