#!/usr/bin/env python3
"""The Necromancer class: skills (3 branches x 6 tiers, pairs at 2 and 4),
32px glyph icons, data/classes/necromancer.tres, in-game hero layers and
portraits.

Branches:
  Легион - raised servants (SummonSkill: skeleton warriors, archers, a bone
           golem, the army of the dead) and the power to command them;
  Порча  - plague and curses (poison / magic bolts and clouds);
  Кость  - bone spears and shards, bone armour, the lich form.
Run from tools/:  python3 gen_necromancer.py
"""
from __future__ import annotations

import os
import re

import gen_skill_icons32 as gi
import gen_skill_trees as gst

PHYS, FIRE, ICE, POISON, MAGIC = range(5)
NECRO = (110, 230, 140)
PLAGUE = (160, 220, 70)
BONE = (226, 218, 196)
SOUL = (150, 120, 255)
ROOT = os.path.join(os.path.dirname(__file__), "..")


def summon(sid, name, desc, kind, count, extra_every, max_alive, per_level, dmg, dmg_lvl, life, life_lvl, mana, cd):
    gst.write_skill(sid, name, desc, "summon_skill", [
        ("kind", kind), ("count", count), ("extra_every_levels", extra_every), ("max_alive", max_alive),
        ("max_alive_per_level", per_level), ("damage_multiplier", dmg), ("damage_per_level", dmg_lvl),
        ("lifetime", float(life)), ("lifetime_per_level", float(life_lvl))], mana=mana, cd=cd)


def skills():
    W, A, G = 0, 1, 2  # Minion.Kind
    # ---- Легион
    summon("n_raise_skeleton", "Поднять скелета", "Из земли встаёт скелет-воин и бьётся за вас.", W, 1, 2, 2, 1, 0.6, 0.1, 20, 3, 18, 6.0)
    gst.passive("n_bone_bond", "Узы костей", "Тёмная воля питает некроманта.", ("fireball", 0.4), {"intellect": 2, "vitality": 1})
    summon("n_skeleton_archer", "Скелет-лучник", "Скелет с луком держится позади и стреляет костяными стрелами.", A, 1, 3, 2, 1, 0.5, 0.1, 22, 3, 22, 8.0)
    summon("n_grave_call", "Зов могил", "Двое скелетов вырываются из земли ненадолго.", W, 2, 2, 4, 1, 0.55, 0.08, 9, 1, 26, 10.0)
    summon("n_bone_golem", "Костяной голем", "Огромный голем из костей бьёт по площади.", G, 1, 0, 1, 0, 1.1, 0.2, 30, 5, 40, 18.0)
    gst.buff("n_dark_frenzy", "Тёмное неистовство", "Мощь некроманта растёт, удары чаще находят цель.", ("fireball", 0.4),
             "n_frenzy", {"intellect": 4, "crit_chance": 0.05}, {"intellect": 2}, 8.0, 20, 18.0, (0.5, 1.0, 0.6))
    gst.blast("n_corpse_blast", "Взрыв трупов", "Тела вокруг взрываются зелёным пламенем.", ("meteor", 0.35), 58, 2.0, 0.4, 28, 9.0,
              (0.45, 1.0, 0.55), dtype=MAGIC, vfx="explosion")
    summon("n_army_of_dead", "Армия мёртвых", "Мёртвые встают отрядом и идут за вами.", W, 4, 1, 6, 1, 0.7, 0.1, 16, 2, 60, 40.0)
    # ---- Порча
    gst.missile("n_plague_bolt", "Чумной сгусток", "Сгусток заразы отравляет врага.", ("fireball", 0.3), "goo", 230, 1.2, 0.25, 8, 0.0,
                (0.6, 1.0, 0.3), dtype=POISON)
    gst.passive("n_rot", "Гниль", "Порча сильнее: яд и магия бьют больнее.", ("fireball", 0.3), {"intellect": 1, "res_poison": 0.04})
    gst.blast("n_poison_cloud", "Ядовитое облако", "Облако заразы вокруг некроманта.", ("meteor", 0.3), 54, 1.3, 0.3, 18, 7.0,
              (0.55, 0.95, 0.3), dtype=POISON, knockback=20.0, vfx="explosion")
    gst.missile("n_soul_bolt", "Стрела душ", "Тёмная стрела пронзает нескольких врагов.", ("fireball", 0.75), "dark_bolt", 280, 1.4, 0.3, 12, 2.5,
                (0.6, 0.45, 1.0), dtype=MAGIC, pierce=2)
    gst.buff("n_life_drain", "Похищение жизни", "Некромант выпивает силы: лечение и прилив мощи.", ("fireball", 0.75), "n_drain",
             {"intellect": 3}, {"intellect": 1}, 6.0, 22, 14.0, (0.7, 0.3, 0.4), heal=0.18)
    gst.blast("n_pestilence", "Мор", "Широкая волна чумы.", ("meteor", 0.3), 84, 1.8, 0.35, 32, 12.0, (0.6, 1.0, 0.3), dtype=POISON,
              knockback=40.0, vfx="ring")
    gst.blast("n_doom", "Рок", "Проклятие замораживает врагов вокруг и терзает их.", ("meteor", 0.75), 60, 1.2, 0.3, 30, 14.0,
              (0.55, 0.4, 1.0), dtype=MAGIC, stun=1.6, knockback=0.0, vfx="ring")
    gst.blast("n_death_mark", "Печать смерти", "Знак смерти выжигает всё вокруг.", ("meteor", 0.8), 96, 4.0, 0.6, 55, 30.0,
              (0.6, 0.45, 1.0), dtype=MAGIC, stun=0.8, vfx="sun")
    # ---- Кость
    gst.missile("n_bone_spear", "Костяное копьё", "Острое копьё из кости пробивает врагов.", ("power_strike", 0.2), "bone_shard", 300, 1.3, 0.3,
                10, 0.0, (0.95, 0.92, 0.85), dtype=PHYS, pierce=1)
    gst.buff("n_bone_armor", "Костяной доспех", "Кости смыкаются вокруг тела.", ("iron_skin", 0.2), "n_bone_armor",
             {"armor": 6, "vitality": 2}, {"armor": 2}, 10.0, 16, 16.0, (0.9, 0.88, 0.8))
    gst.missile("n_bone_shards", "Осколки костей", "Веер острых осколков.", ("power_strike", 0.2), "bone_shard", 260, 0.8, 0.18, 14, 3.0,
                (0.95, 0.92, 0.85), dtype=PHYS, count=5, spread=40.0)
    gst.passive("n_marrow", "Костный мозг", "Тело некроманта крепнет.", ("iron_skin", 0.2), {"vitality": 2, "hp_regen": 0.3})
    gst.blast("n_bone_prison", "Костяная тюрьма", "Кости вырываются из пола и сковывают врагов.", ("earthquake", 0.2), 56, 1.0, 0.25, 22, 11.0,
              (0.95, 0.9, 0.8), stun=1.8, knockback=0.0, vfx="quake")
    gst.passive("n_ossuary", "Склеп", "Вечный покой охраняет хозяина.", ("iron_skin", 0.2), {"armor": 3, "res_magic": 0.04, "res_poison": 0.04})
    gst.blast("n_bone_storm", "Костяная буря", "Вихрь осколков рвёт всех вокруг.", ("earthquake", 0.2), 64, 2.2, 0.4, 30, 10.0,
              (0.95, 0.92, 0.85), vfx="blades")
    gst.buff("n_lich_form", "Облик лича", "Некромант становится личом: мощь, стойкость и исцеление.", ("arcane_shield", 0.35), "n_lich",
             {"intellect": 10, "armor": 6, "res_magic": 0.2, "res_poison": 0.3}, {"intellect": 3}, 12.0, 45, 45.0,
             (0.55, 1.0, 0.7), heal=0.3)


TREE = (["Легион", "Порча", "Кость"], [
    ["n_raise_skeleton", "n_bone_bond", ("n_skeleton_archer", "n_grave_call"), "n_bone_golem", ("n_dark_frenzy", "n_corpse_blast"), "n_army_of_dead"],
    ["n_plague_bolt", "n_rot", ("n_poison_cloud", "n_soul_bolt"), "n_life_drain", ("n_pestilence", "n_doom"), "n_death_mark"],
    ["n_bone_spear", "n_bone_armor", ("n_bone_shards", "n_marrow"), "n_bone_prison", ("n_ossuary", "n_bone_storm"), "n_lich_form"],
])

ICONS = {
    "n_raise_skeleton": ({"bg": "dark", "s": ("skull", {})}, NECRO),
    "n_bone_bond": ({"bg": "runes", "s": ("chains", {})}, NECRO),
    "n_skeleton_archer": ({"bg": "glowline", "s": ("arrow", {})}, NECRO),
    "n_grave_call": ({"bg": "storm", "s": ("figure", {})}, NECRO),
    "n_bone_golem": ({"bg": "wash", "s": ("fist", {"burst": 1})}, BONE),
    "n_dark_frenzy": ({"bg": "storm", "s": ("frenzy", {})}, NECRO),
    "n_corpse_blast": ({"bg": "rays", "s": ("bomb", {"smoke": 1})}, NECRO),
    "n_army_of_dead": ({"bg": "rays", "s": ("skull", {"id": "executioner"})}, NECRO),
    "n_plague_bolt": ({"bg": "wash", "s": ("poison", {"drops": 1})}, PLAGUE),
    "n_rot": ({"bg": "particles", "s": ("thorns", {})}, PLAGUE),
    "n_poison_cloud": ({"bg": "storm", "s": ("nova", {})}, PLAGUE),
    "n_soul_bolt": ({"bg": "dark", "s": ("bolt", {"fork": 1})}, SOUL),
    "n_life_drain": ({"bg": "dark", "s": ("blood", {"splashes": 1})}, (220, 70, 100)),
    "n_pestilence": ({"bg": "rays", "s": ("poison", {"drops": 2})}, PLAGUE),
    "n_doom": ({"bg": "dark", "s": ("hourglass", {"hold": 1})}, SOUL),
    "n_death_mark": ({"bg": "rays", "s": ("eye", {"lashes": 1})}, SOUL),
    "n_bone_spear": ({"bg": "glowline", "s": ("arrow", {"count": 1})}, BONE),
    "n_bone_armor": ({"bg": "wash", "s": ("shield", {"herald": "boss"})}, BONE),
    "n_bone_shards": ({"bg": "rays", "s": ("fan", {"count": 5})}, BONE),
    "n_marrow": ({"bg": "wash", "s": ("heart", {"pulse": 1})}, BONE),
    "n_bone_prison": ({"bg": "runes", "s": ("wall", {})}, BONE),
    "n_ossuary": ({"bg": "orbit", "s": ("cross", {"halo": 1})}, BONE),
    "n_bone_storm": ({"bg": "storm", "s": ("whirl", {"arms": 4})}, BONE),
    "n_lich_form": ({"bg": "rays", "s": ("skull", {"id": "child_of_dark"})}, NECRO),
}


CLASS_TRES = '''[gd_resource type="Resource" script_class="ClassData" load_steps=7 format=3]

[ext_resource type="Texture2D" path="res://assets/sprites/portraits/class_mage.png" id="1_portrait"]
[ext_resource type="Script" path="res://scripts/data/class_data.gd" id="2_script"]
[ext_resource type="Script" path="res://scripts/data/skill_data.gd" id="3_skill"]
[ext_resource type="Texture2D" path="res://assets/sprites/player/mage.png" id="8_sprite"]
[ext_resource type="Texture2D" path="res://assets/sprites/player/head_necromancer.png" id="sheet_head"]
[ext_resource type="Texture2D" path="res://assets/sprites/player/outfit_necromancer.png" id="sheet_outfit"]

[resource]
script = ExtResource("2_script")
id = &"necromancer"
display_name = "Некромант"
order = 4
description = "Повелитель мёртвых: поднимает скелетов, насылает мор и прячется за костяным доспехом. Урон зависит от Интеллекта."
portrait_overlay = ExtResource("1_portrait")
sprite = ExtResource("8_sprite")
outfit_sheet = ExtResource("sheet_outfit")
head_sheet = ExtResource("sheet_head")
base_stats = {
"agility": 4,
"intellect": 8,
"strength": 2,
"vitality": 5
}
growth_per_level = {
"agility": 1,
"intellect": 3,
"strength": 0,
"vitality": 2
}
main_attribute = "intellect"
base_damage = 2
attack_range = 18.0
attack_cooldown = 0.45
starting_items = {
"apprentice_wand": 1,
"cloth_hood": 1,
"health_potion": 3,
"mana_crystal": 2,
"bomb": 2,
"rope": 1
}
starting_equipment = Array[StringName]([&"apprentice_wand", &"cloth_hood"])
starting_quick_bar = Array[StringName]([&"bomb", &"mana_crystal", &"health_potion", &"rope"])
skills = Array[ExtResource("3_skill")]([])
allowed_weapon_types = Array[int]([5, 8, 3])
unlock_shards = 25
unlock_gold = 350
'''


def write_class():
    path = os.path.join(gst.CLASSES, "necromancer.tres")
    with open(path, "w", encoding="utf-8") as f:
        f.write(CLASS_TRES)
    gst.patch_class("necromancer", *TREE)


def main():
    skills()
    for sid, (spec, accent) in ICONS.items():
        gi.draw(spec, accent).save(os.path.join(gst.ICONS, sid + ".png"))
    write_class()
    print("necromancer: %d skills, class written" % len(ICONS))


if __name__ == "__main__":
    main()
