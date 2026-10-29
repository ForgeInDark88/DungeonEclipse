#!/usr/bin/env python3
"""Relics that change how the hero fights (RelicPowers): 22 of them.

Writes the 16x16 icons (assets/sprites/items/<id>.png), the item resources
(data/items/relics/<id>.tres) and adds them to the loot tables (rare ones to
rare chests / rare monsters / the merchant, epic ones to epic chests, bosses
and special rooms). Run from tools/:  python3 gen_relics.py
"""
from __future__ import annotations

import math
import os
import re

from PIL import ImageDraw

import gen_placeholders as gp
from gen_monsters import blank, lit, mask, rgba, sh, FULL
from gen_structures import finish, glow_dot

ROOT = os.path.join(gp.A, "..")
ITEMS = os.path.join(gp.A, "sprites", "items")
RELICS = os.path.join(ROOT, "data", "items", "relics")
LOOT = os.path.join(ROOT, "data", "loot_tables")

GOLD = (220, 170, 60)
IRON = (120, 118, 130)
BONE = (226, 218, 196)


def _gem(d, g, x, y, col, r=2):
    d.ellipse((x - r, y - r, x + r, y + r), fill=rgba(col))
    d.point((x - r // 2, y - r // 2), fill=rgba((255, 255, 255)))
    glow_dot(g, x, y, r + 3, col, 0.55)


# ------------------------------------------------------------------ icons
def stone(col, glyph):
    """A rune stone with a glowing glyph (shared by a few relics)."""
    def fn():
        im, g = blank(16, 16), blank(16, 16)
        m = mask(16, 16, lambda dd: dd.polygon([(3, 4), (8, 1), (13, 4), (13, 12), (8, 15), (3, 12)], fill=FULL))
        lit(im, m, (86, 84, 96), 6, 5, 6, 6)
        d = ImageDraw.Draw(im)
        d.line(glyph, fill=rgba(col), width=1)
        for x, y in glyph[::2]:
            glow_dot(g, x, y, 3, col, 0.5)
        return finish(im, g)
    return fn


def i_chain_lightning():
    return stone((140, 200, 255), [(9, 3), (6, 8), (9, 8), (6, 13)])()


def i_blood_pact():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.rectangle((3, 2, 12, 14), fill=FULL))
    lit(im, m, (214, 196, 160), 5, 4, 5, 7, flat=0.3)  # parchment
    d = ImageDraw.Draw(im)
    for y in (5, 7, 9):
        d.line((5, y, 10, y), fill=rgba((120, 96, 80)))
    d.ellipse((8, 10, 13, 15), fill=rgba((170, 20, 30)))  # blood seal
    d.point((9, 11), fill=rgba((240, 110, 110)))
    glow_dot(g, 10, 12, 4, (220, 40, 50), 0.5)
    return finish(im, g)


def i_phantom_blade():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for off, a in ((2, 110), (0, 255)):
        d.polygon([(3 + off, 13), (12 + off, 2), (14 + off, 4), (5 + off, 15)], fill=rgba((170, 150, 240), a))
        d.line((4 + off, 13, 13 + off, 3), fill=rgba((235, 225, 255), a))
    d.line((2, 11, 6, 15), fill=rgba(GOLD))
    glow_dot(g, 9, 8, 6, (170, 140, 255), 0.5)
    return finish(im, g)


def i_volcano():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.polygon([(1, 15), (6, 5), (10, 5), (15, 15)], fill=FULL))
    lit(im, m, (90, 60, 52), 6, 8, 7, 6)
    d = ImageDraw.Draw(im)
    d.polygon([(6, 5), (10, 5), (9, 8), (7, 8)], fill=rgba((255, 140, 40)))
    d.line((8, 8, 7, 14), fill=rgba((255, 110, 30)))
    for x, y in ((7, 2), (9, 1), (10, 3)):
        d.point((x, y), fill=rgba((255, 200, 90)))
    glow_dot(g, 8, 5, 5, (255, 130, 40), 0.7)
    return finish(im, g)


def i_thorn_mail():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    vine = (80, 120, 50)
    d.ellipse((2, 4, 13, 12), outline=rgba(vine), width=2)
    for k in range(8):
        a = k * math.tau / 8
        x, y = 7.5 + math.cos(a) * 6, 8 + math.sin(a) * 4.5
        d.line((x, y, x + math.cos(a) * 2.5, y + math.sin(a) * 2.5), fill=rgba((200, 210, 150)))
    d.point((5, 5), fill=rgba((180, 40, 40)))
    return finish(im, g)


def i_executioner_mark():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.ellipse((2, 2, 13, 13), fill=FULL))
    lit(im, m, (60, 40, 44), 5, 5, 6, 6)  # a black coin
    d = ImageDraw.Draw(im)
    d.line((4, 4, 11, 11), fill=rgba((220, 40, 40)), width=2)
    d.line((11, 4, 4, 11), fill=rgba((220, 40, 40)), width=2)
    glow_dot(g, 8, 8, 5, (230, 50, 50), 0.5)
    return finish(im, g)


def i_glass_heart():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: (dd.ellipse((2, 3, 8, 9), fill=FULL), dd.ellipse((7, 3, 13, 9), fill=FULL),
                                 dd.polygon([(2, 7), (13, 7), (8, 14)], fill=FULL)))
    lit(im, m, (190, 230, 250), 5, 5, 6, 6, alpha=210)
    d = ImageDraw.Draw(im)
    d.line((8, 4, 7, 8, 9, 10), fill=rgba((90, 140, 170)))  # the crack
    d.point((4, 5), fill=rgba((255, 255, 255)))
    glow_dot(g, 7, 8, 5, (170, 230, 255), 0.5)
    return finish(im, g)


def i_vampire_fang():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for x in (5, 10):
        m = mask(16, 16, lambda dd, x=x: dd.polygon([(x - 2, 2), (x + 2, 2), (x, 13)], fill=FULL))
        lit(im, m, BONE, x - 1, 4, 2, 6)
    d = ImageDraw.Draw(im)
    d.point((5, 14), fill=rgba((200, 20, 30)))
    d.point((10, 14), fill=rgba((200, 20, 30)))
    d.line((3, 2, 12, 2), fill=rgba((120, 20, 30)))
    glow_dot(g, 8, 12, 4, (220, 30, 40), 0.4)
    return finish(im, g)


def i_corpse_bomb():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.ellipse((3, 5, 13, 15), fill=FULL))
    lit(im, m, (120, 100, 70), 6, 7, 5, 5)  # a pouch
    d = ImageDraw.Draw(im)
    d.line((6, 5, 10, 5), fill=rgba((80, 60, 40)), width=2)
    d.line((8, 5, 8, 2), fill=rgba((80, 60, 40)))
    d.point((7, 10), fill=rgba((30, 20, 20)))
    d.point((9, 10), fill=rgba((30, 20, 20)))
    for x, y in ((12, 3), (4, 2), (13, 7)):
        d.point((x, y), fill=rgba((150, 255, 100)))
    glow_dot(g, 8, 4, 5, (140, 255, 90), 0.5)
    return finish(im, g)


def i_frost_core():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.polygon([(8, 1), (14, 8), (8, 15), (2, 8)], fill=FULL))
    lit(im, m, (120, 200, 250), 6, 5, 5, 6)
    d = ImageDraw.Draw(im)
    d.line((8, 3, 8, 13), fill=rgba((230, 250, 255)))
    d.line((4, 8, 12, 8), fill=rgba((230, 250, 255)))
    glow_dot(g, 8, 8, 6, (150, 220, 255), 0.6)
    return finish(im, g)


def i_echo_bell():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.polygon([(5, 4), (11, 4), (13, 12), (3, 12)], fill=FULL))
    lit(im, m, GOLD, 6, 6, 5, 5)
    d = ImageDraw.Draw(im)
    d.line((8, 1, 8, 4), fill=rgba(sh(GOLD, 0.7)))
    d.point((8, 13), fill=rgba((240, 230, 200)))
    d.arc((0, 3, 4, 13), 100, 260, fill=rgba((170, 210, 255)))
    d.arc((12, 3, 16, 13), 280, 80, fill=rgba((170, 210, 255)))
    glow_dot(g, 8, 8, 5, (180, 210, 255), 0.4)
    return finish(im, g)


def i_berserk_totem():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.rectangle((4, 1, 11, 15), fill=FULL))
    lit(im, m, (130, 86, 54), 6, 4, 4, 7, flat=0.2)
    d = ImageDraw.Draw(im)
    d.line((5, 5, 7, 6), fill=rgba((30, 16, 12)))
    d.line((10, 5, 8, 6), fill=rgba((30, 16, 12)))
    d.point((6, 7), fill=rgba((255, 60, 40)))
    d.point((9, 7), fill=rgba((255, 60, 40)))
    d.rectangle((6, 10, 9, 12), fill=rgba((40, 16, 14)))
    d.line((6, 10, 9, 10), fill=rgba(BONE))
    glow_dot(g, 8, 7, 4, (255, 60, 40), 0.5)
    return finish(im, g)


def i_momentum_boots():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.polygon([(5, 2), (10, 2), (10, 10), (14, 11), (14, 14), (4, 14)], fill=FULL))
    lit(im, m, (150, 90, 50), 6, 5, 5, 6)
    d = ImageDraw.Draw(im)
    for y in (6, 9, 12):
        d.line((0, y, 3, y), fill=rgba((255, 210, 120)))
    d.line((5, 14, 14, 14), fill=rgba((70, 40, 24)))
    glow_dot(g, 2, 9, 4, (255, 200, 110), 0.4)
    return finish(im, g)


def i_greed_idol():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: (dd.ellipse((4, 1, 11, 8), fill=FULL), dd.polygon([(4, 7), (11, 7), (13, 15), (2, 15)], fill=FULL)))
    lit(im, m, GOLD, 6, 4, 5, 7)
    d = ImageDraw.Draw(im)
    d.point((6, 4), fill=rgba((180, 30, 40)))
    d.point((9, 4), fill=rgba((180, 30, 40)))
    d.line((6, 6, 9, 6), fill=rgba(sh(GOLD, 0.5)))
    glow_dot(g, 7, 5, 6, (255, 210, 90), 0.4)
    return finish(im, g)


def i_storm_crown():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    m = mask(16, 16, lambda dd: dd.polygon([(2, 13), (2, 6), (5, 9), (8, 4), (11, 9), (14, 6), (14, 13)], fill=FULL))
    lit(im, m, (170, 170, 190), 6, 7, 6, 4)
    d = ImageDraw.Draw(im)
    for x in (2, 8, 14):
        _gem(d, g, x, 5 if x != 8 else 3, (140, 200, 255), 1)
    d.line((7, 9, 9, 11, 7, 12), fill=rgba((180, 230, 255)))
    return finish(im, g)


def i_holy_aegis():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.polygon([(2, 2), (14, 2), (14, 8), (8, 15), (2, 8)], fill=FULL))
    lit(im, m, (220, 210, 170), 6, 5, 6, 6)
    d = ImageDraw.Draw(im)
    d.line((8, 4, 8, 12), fill=rgba(GOLD), width=2)
    d.line((4, 7, 12, 7), fill=rgba(GOLD), width=2)
    glow_dot(g, 8, 7, 7, (255, 240, 170), 0.5)
    return finish(im, g)


def i_mirror_shard():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.polygon([(5, 1), (12, 4), (10, 15), (3, 11)], fill=FULL))
    lit(im, m, (200, 210, 235), 6, 4, 5, 6, flat=0.4)
    d = ImageDraw.Draw(im)
    d.line((6, 4, 9, 11), fill=rgba((255, 255, 255)))
    d.line((5, 7, 7, 12), fill=rgba((150, 160, 200)))
    glow_dot(g, 8, 6, 5, (210, 220, 255), 0.5)
    return finish(im, g)


def i_leech_charm():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((8, 1, 8, 4), fill=rgba(IRON))
    pts = [(4, 6), (7, 5), (10, 7), (12, 10), (10, 13), (6, 13)]
    d.line(pts, fill=rgba((90, 40, 70)), width=4)
    d.line(pts, fill=rgba((150, 80, 120)), width=1)
    _gem(d, g, 8, 9, (110, 150, 255), 1)
    return finish(im, g)


def i_war_drum():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.rectangle((2, 5, 13, 14), fill=FULL))
    lit(im, m, (150, 70, 40), 5, 7, 6, 5)
    d = ImageDraw.Draw(im)
    d.ellipse((2, 3, 13, 7), fill=rgba((220, 200, 160)))
    for x in (4, 7, 10, 13):
        d.line((x - 2, 7, x, 13), fill=rgba(GOLD))
    d.line((11, 0, 15, 4), fill=rgba((120, 80, 50)), width=2)
    return finish(im, g)


def i_comet_tail():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    d.line((1, 15, 9, 7), fill=rgba((255, 110, 30), 170), width=3)
    d.line((2, 14, 9, 7), fill=rgba((255, 200, 80)))
    m = mask(16, 16, lambda dd: dd.ellipse((8, 2, 14, 8), fill=FULL))
    lit(im, m, (255, 190, 90), 10, 4, 3, 3)
    glow_dot(g, 11, 5, 6, (255, 150, 50), 0.7)
    return finish(im, g)


def i_gravity_well():
    im, g = blank(16, 16), blank(16, 16)
    m = mask(16, 16, lambda dd: dd.ellipse((4, 4, 12, 12), fill=FULL))
    lit(im, m, (60, 40, 90), 6, 6, 4, 4)
    d = ImageDraw.Draw(im)
    d.arc((1, 1, 15, 15), 200, 320, fill=rgba((170, 120, 255)))
    d.arc((1, 1, 15, 15), 20, 140, fill=rgba((170, 120, 255)))
    d.point((7, 7), fill=rgba((220, 190, 255)))
    glow_dot(g, 8, 8, 7, (150, 100, 255), 0.5)
    return finish(im, g)


def i_lucky_clover():
    im, g = blank(16, 16), blank(16, 16)
    d = ImageDraw.Draw(im)
    for dx, dy in ((-3, -3), (3, -3), (-3, 3), (3, 3)):
        m = mask(16, 16, lambda dd, dx=dx, dy=dy: dd.ellipse((8 + dx - 3, 7 + dy - 3, 8 + dx + 3, 7 + dy + 3), fill=FULL))
        lit(im, m, (80, 180, 80), 7 + dx, 6 + dy, 3, 3)
    d = ImageDraw.Draw(im)
    d.line((8, 8, 10, 15), fill=rgba((60, 120, 50)))
    glow_dot(g, 8, 7, 6, (120, 255, 120), 0.35)
    return finish(im, g)


# (id, name, description, rarity 1 rare / 2 epic, power, a, b, stats, item level)
RELICS_LIST = [
    ("chain_lightning", "Грозовой камень", "Каждый 4-й удар — молния прыгает на 3 врагов рядом (50% урона).", 1, "chain_lightning", 4, 0.5, {}, 4),
    ("blood_pact", "Кровавый договор", "Урон +60%. Лечение больше не действует — зато каждое убийство возвращает 3% здоровья.", 2, "blood_pact", 1.6, 0.03, {}, 8),
    ("phantom_blade", "Призрачный клинок", "После парирования или переката призрачный двойник трижды бьёт перед вами (70% урона).", 2, "phantom_blade", 0.7, 0, {}, 8),
    ("volcano", "Сердце вулкана", "Приземление с высоты взрывается огнём вокруг (140% урона). Прыгайте на врагов!", 1, "volcano", 1.4, 0, {}, 5),
    ("thorn_mail", "Терновый венец", "Полученный урон ×1,5 возвращается врагам рядом.", 1, "thorn_mail", 1.5, 0, {"armor": 3}, 4),
    ("executioner_mark", "Метка палача", "Удар по врагу слабее 25% здоровья — второй критический удар.", 1, "executioner_mark", 0.25, 0, {}, 5),
    ("glass_heart", "Стеклянное сердце", "Урон ×1,8, но получаемый урон ×1,5. Для смелых.", 2, "glass_heart", 1.8, 1.5, {}, 8),
    ("vampire_fang", "Клык вампира", "8% нанесённого урона возвращается здоровьем.", 1, "vampire_fang", 0.08, 0, {}, 5),
    ("corpse_bomb", "Чумной мешочек", "Убитые враги взрываются ядом (90% урона вокруг).", 1, "corpse_bomb", 0.9, 0, {}, 5),
    ("frost_core", "Ледяное ядро", "Удары замедляют (30%), каждый 6-й — замораживает на секунду.", 1, "frost_core", 0.3, 0, {}, 4),
    ("echo_bell", "Колокольчик эха", "После навыка следующий удар наносит двойной урон.", 1, "echo_bell", 0, 0, {"max_mana": 10}, 4),
    ("berserk_totem", "Тотем берсерка", "Чем меньше здоровья, тем сильнее удар: до +90% урона.", 1, "berserk_totem", 0.9, 0, {}, 5),
    ("momentum_boots", "Сапоги разгона", "1,5 секунды бега — следующий удар двойной. Скорость +10.", 1, "momentum_boots", 2.0, 0, {"speed": 10}, 3),
    ("greed_idol", "Идол жадности", "Золото +60%, но враги бьют на 25% сильнее.", 1, "greed_idol", 0, 1.25, {"gold_find": 0.6}, 3),
    ("storm_crown", "Корона бури", "Каждые 7 секунд молния бьёт врага рядом (200% урона).", 2, "storm_crown", 7.0, 2.0, {}, 9),
    ("holy_aegis", "Эгида рассвета", "Каждые 12 секунд — щит на 15% здоровья.", 1, "holy_aegis", 12.0, 0.15, {}, 5),
    ("mirror_shard", "Осколок зеркала", "15% вражеских ударов проходят мимо.", 1, "mirror_shard", 0.15, 0, {}, 5),
    ("leech_charm", "Амулет пиявки", "Каждое убийство возвращает 6 маны.", 1, "leech_charm", 6, 0, {}, 3),
    ("war_drum", "Боевой барабан", "Убийство: скорость атаки +8% на 6 секунд (до 5 раз).", 1, "war_drum", 0, 0, {}, 5),
    ("comet_tail", "Хвост кометы", "После парирования или переката 1,6 секунды за вами горит след (35% урона).", 1, "comet_tail", 0.35, 0, {}, 5),
    ("gravity_well", "Камень тяготения", "Каждый 5-й удар стягивает врагов к цели и оглушает их.", 2, "gravity_well", 0, 0, {}, 7),
    ("lucky_clover", "Четырёхлистник", "10% ударов наносят тройной урон.", 1, "lucky_clover", 0.1, 0, {"crit_chance": 0.02}, 3),
]


def tres(r):
    rid, name, desc, rarity, power, a, b, stats, lvl = r
    stat_lines = ",\n".join('"%s": %s' % (k, v) for k, v in stats.items())
    return """[gd_resource type="Resource" script_class="RelicItemData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/data/relic_item_data.gd" id="e1"]
[ext_resource type="Texture2D" path="res://assets/sprites/items/%s.png" id="e2"]

[resource]
script = ExtResource("e1")
heal_on_kill = 0
second_chance = false
revive_percent = 0.5
power = &"%s"
power_a = %s
power_b = %s
id = &"%s"
display_name = "%s"
description = "%s"
icon = ExtResource("e2")
item_type = 3
rarity = %d
item_level = %d
unique = true
max_stack = 1
stat_bonuses = {%s}
price = %d
currency_value = 0
""" % (rid, power, float(a), float(b), rid, name, desc, rarity, lvl, ("\n" + stat_lines + "\n") if stats else "",
       120 if rarity == 1 else 300)


def add_to_table(path, ids, weight):
    s = open(path, encoding="utf-8").read()
    for rid in ids:
        if 'id="i_%s"' % rid in s:
            continue
        ext = '[ext_resource type="Resource" path="res://data/items/relics/%s.tres" id="i_%s"]\n' % (rid, rid)
        i = s.index("\n[sub_resource")
        s = s[:i + 1] + ext + s[i + 1:]
        entry = ('[sub_resource type="Resource" id="e_%s"]\nscript = ExtResource("entry")\nitem = ExtResource("i_%s")\n'
                 "weight = %.2f\nmin_count = 1\nmax_count = 1\nmin_floor = 1\nmax_floor = 0\n\n") % (rid, rid, weight)
        j = s.index("[resource]")
        s = s[:j] + entry + s[j:]
        s = re.sub(r'(entries = Array\[ExtResource\("entry"\)\]\(\[)(.*?)(\]\))',
                   lambda m: m.group(1) + m.group(2) + ', SubResource("e_%s")' % rid + m.group(3), s, count=1, flags=re.S)
    open(path, "w", encoding="utf-8", newline="\n").write(s)


def main():
    for r in RELICS_LIST:
        globals()["i_" + r[0]]().save(os.path.join(ITEMS, r[0] + ".png"))
        with open(os.path.join(RELICS, r[0] + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write(tres(r))
    rare = [r[0] for r in RELICS_LIST if r[3] == 1]
    epic = [r[0] for r in RELICS_LIST if r[3] == 2]
    for t in ("chest_rare.tres", "enemy_rare.tres", "merchant.tres"):
        add_to_table(os.path.join(LOOT, t), rare, 0.35)
    for t in ("chest_epic.tres", "boss.tres", "special.tres"):
        add_to_table(os.path.join(LOOT, t), rare, 0.4)
        add_to_table(os.path.join(LOOT, t), epic, 0.5)
    print("relics:", len(RELICS_LIST))


if __name__ == "__main__":
    main()
