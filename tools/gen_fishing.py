#!/usr/bin/env python3
"""Fishing in the Drowned Vaults: the catch (food items) and the spot.

* items: cave fish (heals), glow eel (mana and a little health), golden carp
  (a rare catch worth a lot of gold);
* assets/sprites/props/fishing_spot.png: a dark pool between stones with a
  rotten mooring post and a forgotten rod.
Run from tools/:  python3 gen_fishing.py
"""
from __future__ import annotations

import os

from PIL import ImageDraw

import gen_placeholders as gp
from gen_monsters import blank, lit, mask, rgba, sh, FULL
from gen_structures import finish, glow_dot

ITEMS = os.path.join(gp.A, "sprites", "items")
USABLE = os.path.join(gp.A, "..", "data", "items", "usable")


def fish(body, belly, fin, glow=None):
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda d: d.ellipse((2, 5, 12, 11), fill=FULL))
    lit(im, m, body, 5, 6, 5, 3)
    d = ImageDraw.Draw(im)
    d.line((4, 10, 10, 10), fill=rgba(belly))
    d.polygon([(12, 8), (15, 5), (15, 11)], fill=rgba(fin))  # tail
    d.polygon([(6, 5), (8, 3), (9, 5)], fill=rgba(fin))  # fin
    d.point((4, 7), fill=rgba((20, 20, 30)))  # eye
    d.point((3, 7), fill=rgba((240, 240, 240)))
    for x in (6, 8, 10):
        d.point((x, 7), fill=rgba(sh(body, 1.25)))  # scales
    if glow:
        glow_dot(g, 7, 8, 5, glow, 0.6)
    return finish(im, g)


def eel():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    pts = [(1, 9), (4, 7), (7, 9), (10, 7), (13, 9), (15, 8)]
    d.line(pts, fill=rgba((40, 90, 110)), width=3)
    d.line(pts, fill=rgba((120, 240, 230)), width=1)
    d.point((2, 8), fill=rgba((255, 255, 200)))
    glow_dot(g, 8, 8, 6, (120, 255, 230), 0.6)
    return finish(im, g)


def spot():
    """32x16: a dark pool sunk into the floor, a mooring post, a rod leaning on it."""
    im, g = blank(32, 16), blank(32, 16)
    d = ImageDraw.Draw(im)
    d.ellipse((1, 8, 30, 15), fill=rgba((40, 60, 58)))  # stone rim
    d.ellipse((3, 9, 28, 14), fill=rgba((14, 40, 50)))  # black water
    for x in (8, 14, 20):
        d.line((x, 11, x + 3, 11), fill=rgba((90, 180, 190), 200))  # ripples
    d.point((17, 12), fill=rgba((200, 250, 250)))
    post = (90, 70, 50)
    d.rectangle((26, 2, 28, 12), fill=rgba(post))
    d.line((26, 2, 26, 12), fill=rgba(sh(post, 1.3)))
    d.line((25, 6, 29, 6), fill=rgba((150, 140, 110)))  # rope
    d.line((20, 1, 27, 9), fill=rgba((150, 110, 70)))  # the rod
    d.line((20, 1, 12, 11), fill=rgba((220, 220, 220), 160))  # the line into the water
    d.point((12, 11), fill=rgba((230, 60, 50)))  # float
    glow_dot(g, 15, 12, 6, (90, 200, 200), 0.35)
    return finish(im, g)


def tres(fid, name, desc, effects, rarity, price, stack):
    ext = ['[ext_resource type="Script" path="res://scripts/effects/item_effect.gd" id="1_eff"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/items/%s.png" id="3_icon"]' % fid,
           '[ext_resource type="Script" path="res://scripts/data/usable_item_data.gd" id="4_use"]']
    subs = []
    refs = []
    for i, (script, fields) in enumerate(effects):
        ext.append('[ext_resource type="Script" path="res://scripts/effects/%s.gd" id="e%d"]' % (script, i))
        lines = ['[sub_resource type="Resource" id="s%d"]' % i, 'script = ExtResource("e%d")' % i]
        lines += ["%s = %s" % (k, v) for k, v in fields.items()]
        subs.append("\n".join(lines))
        refs.append('SubResource("s%d")' % i)
    res = """[resource]
script = ExtResource("4_use")
effects = Array[ExtResource("1_eff")]([%s])
consume_on_use = true
cooldown = 0.3
use_animation = &"use"
use_sound = &"potion_drink"
id = &"%s"
display_name = "%s"
description = "%s"
icon = ExtResource("3_icon")
item_type = 1
rarity = %d
item_level = 1
max_stack = %d
stat_bonuses = {}
price = %d
currency_value = 0
has_durability = false
max_durability = 100
""" % (", ".join(refs), fid, name, desc, rarity, stack, price)
    head = '[gd_resource type="Resource" script_class="UsableItemData" load_steps=%d format=3]' % (len(ext) + len(subs) + 1)
    return head + "\n\n" + "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n" + res


CATCH = [
    ("cave_fish", lambda: fish((110, 130, 140), (200, 210, 200), (80, 100, 110)), "Пещерная рыба",
     "Слепая и бледная, зато сытная. Жареная — лечит.", [("heal_effect", {"amount": 0, "percent": 0.25})], 0, 15, 10),
    ("glow_eel", eel, "Светящийся угорь",
     "Светится изнутри тем же светом, что грибы наверху. Возвращает ману и чуть сил.",
     [("mana_effect", {"amount": 40}), ("heal_effect", {"amount": 10, "percent": 0.0})], 1, 40, 10),
    ("golden_carp", lambda: fish((230, 180, 60), (255, 230, 150), (220, 120, 40), (255, 210, 90)), "Золотой карась",
     "Говорят, его чешуя — расплавленные монеты утонувших. Торговцы платят щедро.",
     [("heal_effect", {"amount": 0, "percent": 0.5})], 2, 150, 5),
]


def main():
    for fid, fn, name, desc, effects, rarity, price, stack in CATCH:
        fn().save(os.path.join(ITEMS, fid + ".png"))
        with open(os.path.join(USABLE, fid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(tres(fid, name, desc, effects, rarity, price, stack))
        print("catch:", fid)
    spot().save(os.path.join(gp.A, "sprites", "props", "fishing_spot.png"))
    print("fishing spot")


if __name__ == "__main__":
    main()
