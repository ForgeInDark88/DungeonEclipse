#!/usr/bin/env python3
"""Legendary weapons with a character - one per class, each a piece of the
story of the Eclipse (LegendHitEffect gives them their trick).

Writes the 16x16 icons (assets/sprites/items/<id>.png), the item resources
(data/items/equipment/<id>.tres) and adds them to the boss and epic chest
loot tables. Run from tools/:  python3 gen_legendaries.py
"""
from __future__ import annotations

import os
import re

from PIL import Image, ImageDraw

import gen_placeholders as gp
from gen_monsters import blank, rgba, sh
from gen_structures import finish, glow_dot

ROOT = os.path.join(gp.A, "..")
ITEMS = os.path.join(gp.A, "sprites", "items")
EQUIP = os.path.join(ROOT, "data", "items", "equipment")
LOOT = os.path.join(ROOT, "data", "loot_tables")


# ------------------------------------------------------------------ icons
def bell_hammer():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    wood = (110, 76, 50)
    d.line((3, 14, 9, 8), fill=rgba(wood), width=2)
    d.line((3, 13, 8, 8), fill=rgba(sh(wood, 1.3)))
    bronze = (190, 140, 70)
    d.polygon([(8, 3), (13, 3), (15, 10), (6, 10)], fill=rgba(bronze))  # a small bell as the head
    d.line((8, 3, 6, 10), fill=rgba(sh(bronze, 1.3)))
    d.line((13, 3, 15, 10), fill=rgba(sh(bronze, 0.7)))
    d.line((6, 10, 15, 10), fill=rgba(sh(bronze, 0.6)))
    d.point((10, 11), fill=rgba((240, 220, 160)))  # clapper
    d.arc((4, 0, 16, 12), 300, 360, fill=rgba((160, 255, 220), 200))
    glow_dot(g, 10, 7, 3, (160, 255, 220), 0.4)
    return finish(im, g)


def heart_shard():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((2, 14, 5, 11), fill=rgba((90, 80, 100)), width=2)  # grip
    d.line((4, 12, 7, 9), fill=rgba((150, 150, 170)), width=1)  # guard
    d.line((3, 9, 7, 13), fill=rgba((150, 150, 170)))
    d.polygon([(6, 10), (13, 1), (15, 3), (8, 12)], fill=rgba((110, 210, 240)))  # crystal blade
    d.line((7, 10, 14, 2), fill=rgba((220, 250, 255)))
    d.point((11, 5), fill=rgba((255, 255, 255)))
    glow_dot(g, 11, 5, 4, (130, 230, 255), 0.6)
    return finish(im, g)


def mirror_dagger():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((3, 13, 5, 11), fill=rgba((60, 40, 80)), width=2)
    d.line((4, 10, 7, 13), fill=rgba((230, 190, 80)))  # gold guard
    d.polygon([(5, 10), (13, 2), (14, 3), (6, 11)], fill=rgba((200, 210, 230)))  # mirror blade
    d.line((6, 10, 13, 3), fill=rgba((255, 255, 255)))
    d.point((10, 6), fill=rgba((230, 60, 90)))  # a diamond, like on his mask
    d.point((2, 14), fill=rgba((230, 60, 90)))
    glow_dot(g, 11, 4, 3, (210, 160, 255), 0.5)
    return finish(im, g)


def ilara_spark():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    wood = (70, 40, 34)
    d.line((3, 15, 10, 6), fill=rgba(wood), width=2)
    d.line((3, 14, 9, 6), fill=rgba(sh(wood, 1.4)))
    d.arc((8, 1, 15, 8), 90, 360, fill=rgba((200, 120, 60)), width=1)  # curled head
    d.ellipse((10, 2, 13, 5), fill=rgba((255, 170, 60)))  # the ember
    d.point((11, 3), fill=rgba((255, 250, 210)))
    d.point((13, 0), fill=rgba((255, 120, 40)))
    d.point((9, 1), fill=rgba((255, 200, 90)))
    glow_dot(g, 11, 3, 5, (255, 150, 60), 0.7)
    return finish(im, g)


def oldric_spade():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    wood = (100, 78, 56)
    d.line((3, 3, 10, 10), fill=rgba(wood), width=2)
    d.line((3, 2, 10, 9), fill=rgba(sh(wood, 1.3)))
    d.line((1, 4, 4, 1), fill=rgba(sh(wood, 0.9)), width=2)  # T-handle
    iron = (120, 120, 116)
    d.polygon([(9, 10), (12, 8), (15, 13), (13, 15)], fill=rgba(iron))  # the blade
    d.line((12, 8, 15, 13), fill=rgba(sh(iron, 1.4)))
    d.point((13, 13), fill=rgba((90, 70, 50)))  # grave dirt
    d.point((11, 11), fill=rgba((90, 70, 50)))
    d.point((14, 11), fill=rgba((120, 255, 150)))  # a green soul spark
    glow_dot(g, 14, 11, 3, (120, 255, 150), 0.5)
    return finish(im, g)


# (id, icon fn, name, description, weapon_type, damage, speed, reach, pattern, dtype, projectile, stats, effect, item_level)
WEAPONS = [
    ("bell_hammer", bell_hammer, "Колокольный молот звонаря",
     "Отлит из языка колокола Храма Солнца. Брат Оствин звонил им, пока вода не сомкнулась над головой.",
     6, 24.0, 1.4, 26.0, 0, 0, None, {"strength": 5, "vitality": 3},
     {"kind": 0, "every": 3, "power": 0.6, "radius": 46.0}, 12),
    ("heart_shard", heart_shard, "Осколок сердца горы",
     "Кусок, который рудокопы отбили от сердца Каменного. Он всё ещё бьётся — и лечит руку, что его держит.",
     0, 22.0, 1.6, 28.0, 0, 2, None, {"vitality": 5, "armor": 6},
     {"kind": 3, "every": 5, "power": 0.8, "radius": 50.0}, 12),
    ("mirror_dagger", mirror_dagger, "Зеркальный кинжал Пипа",
     "Шут спрятал в нём своё отражение. Каждый удар повторяет кто-то из зеркала.",
     3, 14.0, 3.0, 18.0, 1, 0, None, {"agility": 5, "crit_chance": 0.06},
     {"kind": 1, "power": 0.6, "chance": 0.4}, 12),
    ("ilara_spark", ilara_spark, "Искра Илары",
     "Посох с последней искрой нового солнца, которое чародейка зажгла на один миг.",
     5, 20.0, 1.5, 190.0, 2, 1, "res://assets/sprites/fx/fireball.png", {"intellect": 6, "max_mana": 20},
     {"kind": 2, "power": 0.5, "radius": 40.0, "chance": 0.35}, 12),
    ("oldric_spade", oldric_spade, "Лопата Олдрика",
     "Ею могильщик выкопал тысячу могил. Теперь она копает их сама — под теми, кому пора.",
     5, 18.0, 1.6, 26.0, 0, 0, None, {"intellect": 4, "vitality": 3},
     {"kind": 4, "cap": 2}, 12),
]


def tres(w):
    (wid, _fn, name, desc, wtype, dmg, spd, reach, pattern, dtype, proj, stats, eff, lvl) = w
    ext = ['[ext_resource type="Script" path="res://scripts/data/weapon_item_data.gd" id="e1"]',
           '[ext_resource type="Script" path="res://scripts/combat/hit_effect.gd" id="e2"]',
           '[ext_resource type="Script" path="res://scripts/combat/legend_hit_effect.gd" id="e3"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/items/%s.png" id="e4"]' % wid]
    if proj:
        ext.append('[ext_resource type="Texture2D" path="%s" id="e5"]' % proj)
    sub = ['[sub_resource type="Resource" id="s1"]', 'script = ExtResource("e3")']
    for k, v in eff.items():
        sub.append("%s = %s" % (k, repr(v) if isinstance(v, float) else v))
    stat_lines = ",\n".join('"%s": %s' % (k, v) for k, v in stats.items())
    res = [
        "[resource]", 'script = ExtResource("e1")', "weapon_type = %d" % wtype, "base_damage = %s" % dmg,
        "attack_speed = %s" % spd, "reach = %s" % reach, "knockback = 120.0", "attack_pattern = %d" % pattern,
        "two_handed = false", "damage_type = %d" % dtype,
    ]
    if proj:
        res.append('projectile_texture = ExtResource("e5")')
    res += [
        "projectile_speed = 280.0", "projectile_pierce = 0", "projectile_blast_radius = 0.0",
        'on_hit_effects = Array[ExtResource("e2")]([SubResource("s1")])', "held_angle = -45.0",
        "grip_pixel = Vector2(3.0, 12.0)", 'gender = "%s"' % ("m" if wid != "ilara_spark" else "f"),
        'slot_type = &"weapon"', 'id = &"%s"' % wid, 'display_name = "%s"' % name,
        'description = "%s"' % desc, 'icon = ExtResource("e4")', "item_type = 0", "rarity = 3",
        "item_level = %d" % lvl, "unique = true", "max_stack = 1", "stat_bonuses = {\n%s\n}" % stat_lines,
        "price = 0", "currency_value = 0", "has_durability = true", "max_durability = 160",
    ]
    head = '[gd_resource type="Resource" script_class="WeaponItemData" load_steps=%d format=3]' % (len(ext) + 2)
    return head + "\n\n" + "\n".join(ext) + "\n\n" + "\n".join(sub) + "\n\n" + "\n".join(res) + "\n"


def add_to_table(path, ids):
    s = open(path, encoding="utf-8").read()
    for wid in ids:
        if 'id="i_%s"' % wid in s:
            continue
        ext = '[ext_resource type="Resource" path="res://data/items/equipment/%s.tres" id="i_%s"]\n' % (wid, wid)
        i = s.index("\n[sub_resource")
        s = s[:i + 1] + ext + s[i + 1:]
        entry = ('[sub_resource type="Resource" id="e_%s"]\nscript = ExtResource("entry")\nitem = ExtResource("i_%s")\n'
                 "weight = 1.00\nmin_count = 1\nmax_count = 1\nmin_floor = 1\nmax_floor = 0\n\n") % (wid, wid)
        j = s.index("[resource]")
        s = s[:j] + entry + s[j:]
        s = re.sub(r'(entries = Array\[ExtResource\("entry"\)\]\(\[)(.*?)(\]\))',
                   lambda m: m.group(1) + m.group(2) + ', SubResource("e_%s")' % wid + m.group(3), s, count=1, flags=re.S)
    open(path, "w", encoding="utf-8", newline="\n").write(s)


def main():
    for w in WEAPONS:
        w[1]().save(os.path.join(ITEMS, w[0] + ".png"))
        with open(os.path.join(EQUIP, w[0] + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(tres(w))
        print("legendary:", w[0])
    for t in ("boss.tres", "chest_epic.tres"):
        add_to_table(os.path.join(LOOT, t), [w[0] for w in WEAPONS])
    print("loot tables updated")


if __name__ == "__main__":
    main()
