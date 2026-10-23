#!/usr/bin/env python3
"""Skill trees of the classes: three branches of five tiers each.

Writes the new skills to data/skills/*.tres (icons: recoloured existing skill
icons) and puts the layout into data/classes/<class>.tres
(ClassData.branch_names, tree_layout and the skills list).

Tiers (TIERS below): top of each branch is known from the start; deeper tiers
need points spent in that branch and a hero level; tiers 2 and 4 are a choice
of one of two skills ("choice" group), so a build cannot take everything.
Run:  python3 tools/gen_skill_trees.py
"""
from __future__ import annotations

import colorsys
import os
import re

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SKILLS = os.path.join(ROOT, "data", "skills")
ICONS = os.path.join(ROOT, "assets", "sprites", "skills")
CLASSES = os.path.join(ROOT, "data", "classes")

PHYS, FIRE, ICE, POISON, MAGIC = range(5)
# tier -> (points spent in the branch, hero level)
TIERS = {0: (0, 1), 1: (1, 2), 2: (3, 4), 3: (6, 6), 4: (9, 9), 5: (12, 12)}


# ------------------------------------------------------------------ writing
def lit(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        if v.startswith("&"):
            return '&"%s"' % v[1:]
        return '"%s"' % v
    if isinstance(v, tuple) and v[0] == "COL":
        return "Color(%s, %s, %s, 1)" % v[1:4]
    if isinstance(v, tuple) and v[0] == "RAW":
        return v[1]
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join('"%s": %s' % (k, lit(x)) for k, x in v.items()) + "\n}"
    if isinstance(v, list):
        return "Array[int]([%s])" % ", ".join(str(x) for x in v)
    raise ValueError(v)


def write_skill(sid, name, desc, effect, fields, mana=0, cd=0.0, max_level=4, anim="attack_cast",
                synergy=(), texture=None, hit=None):
    ext = ['[ext_resource type="Script" path="res://scripts/data/skill_data.gd" id="skill"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/skills/%s.png" id="icon"]' % sid,
           '[ext_resource type="Script" path="res://scripts/skills/%s.gd" id="eff"]' % effect]
    subs = []
    fields = list(fields)
    if texture:
        ext.append('[ext_resource type="Texture2D" path="res://assets/sprites/fx/%s.png" id="tex"]' % texture)
        fields.insert(0, ("texture", ("RAW", 'ExtResource("tex")')))
    if hit:
        script, hf = hit
        ext.append('[ext_resource type="Script" path="res://scripts/combat/%s.gd" id="hit"]' % script)
        subs.append('[sub_resource type="Resource" id="Hit"]\nscript = ExtResource("hit")\n'
                    + "\n".join("%s = %s" % (k, lit(v)) for k, v in hf))
        fields.append(("hit_effect", ("RAW", 'SubResource("Hit")')))
    subs.append('[sub_resource type="Resource" id="Effect"]\nscript = ExtResource("eff")\n'
                + "\n".join("%s = %s" % (k, lit(v)) for k, v in fields))
    res = [("script", ("RAW", 'ExtResource("skill")')), ("id", "&" + sid), ("display_name", name),
           ("description", desc), ("icon", ("RAW", 'ExtResource("icon")')), ("mana_cost", mana),
           ("cooldown", float(cd)), ("max_level", max_level), ("effect", ("RAW", 'SubResource("Effect")')),
           ("cast_animation", "&" + anim), ("synergy_weapons", list(synergy)), ("synergy_power", 0.3)]
    text = '[gd_resource type="Resource" script_class="SkillData" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1)
    text += "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n[resource]\n"
    text += "\n".join("%s = %s" % (k, lit(v)) for k, v in res) + "\n"
    with open(os.path.join(SKILLS, sid + ".tres"), "w", encoding="utf-8") as f:
        f.write(text)


def recolor(sid, base, hue, sat=1.0, bright=1.0):
    im = Image.open(os.path.join(ICONS, base + ".png")).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            r2, g2, b2 = colorsys.hsv_to_rgb((h + hue) % 1.0, min(1.0, s * sat), min(1.0, v * bright))
            px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    im.save(os.path.join(ICONS, sid + ".png"))


# --------------------------------------------------------------- skill kinds
def passive(sid, name, desc, icon, per_level, base=None, max_level=4, hit=None, chance=(0.1, 0.05), synergy=()):
    fields = [("bonuses", base or {}), ("bonuses_per_level", per_level)]
    if hit:
        fields += [("hit_chance", chance[0]), ("hit_chance_per_level", chance[1])]
    write_skill(sid, name, desc, "passive_skill", fields, max_level=max_level, hit=hit, synergy=synergy)
    recolor(sid, *icon)


def buff(sid, name, desc, icon, key, bonuses, per_level, duration, mana, cd, tint, heal=0.0, anim="attack_cast"):
    write_skill(sid, name, desc, "buff_skill", [
        ("key", key), ("bonuses", bonuses), ("bonuses_per_level", per_level), ("duration", float(duration)),
        ("duration_per_level", 1.0), ("tint", ("COL",) + tint), ("heal_percent", float(heal))],
        mana=mana, cd=cd, anim=anim)
    recolor(sid, *icon)


def blast(sid, name, desc, icon, radius, dmg, per_level, mana, cd, color, dtype=PHYS, stun=0.0, knockback=140.0,
          anim="attack_heavy", synergy=()):
    write_skill(sid, name, desc, "area_blast_skill", [
        ("radius", float(radius)), ("radius_per_level", 5.0), ("damage_multiplier", dmg), ("damage_per_level", per_level),
        ("knockback", float(knockback)), ("breaks_tiles", False), ("stun_time", float(stun)), ("damage_type", dtype),
        ("color", ("COL",) + color)], mana=mana, cd=cd, anim=anim, synergy=synergy)
    recolor(sid, *icon)


def missile(sid, name, desc, icon, texture, speed, dmg, per_level, mana, cd, color, dtype=PHYS, count=1,
            spread=10.0, pierce=0, blast_r=0.0, extra_every=0, synergy=()):
    write_skill(sid, name, desc, "projectile_skill", [
        ("speed", float(speed)), ("damage_multiplier", dmg), ("damage_per_level", per_level), ("count", count),
        ("extra_every_levels", extra_every), ("spread_degrees", float(spread)), ("pierce", pierce),
        ("blast_radius", float(blast_r)), ("damage_type", dtype), ("color", ("COL",) + color)],
        mana=mana, cd=cd, texture=texture, synergy=synergy)
    recolor(sid, *icon)


def dash(sid, name, desc, icon, speed, dmg, mana, cd):
    write_skill(sid, name, desc, "dash_skill", [("speed", float(speed)), ("duration", 0.2),
                ("duration_per_level", 0.03), ("damage_multiplier", dmg)], mana=mana, cd=cd, anim="")
    recolor(sid, *icon)


def status(sid, name, desc, icon, st, duration, power, per_level, mana, cd):
    write_skill(sid, name, desc, "status_skill", [("status", "&" + st), ("duration", float(duration)),
                ("duration_per_level", 1.0), ("power", float(power)), ("power_per_level", float(per_level))],
                mana=mana, cd=cd)
    recolor(sid, *icon)


BLEED = ("status_hit_effect", [("status", "&bleed"), ("duration", 3.0), ("power", 2.0)])
BURN = ("status_hit_effect", [("status", "&burn"), ("duration", 3.0), ("power", 2.0)])
SLOW = ("status_hit_effect", [("status", "&slow"), ("duration", 2.0), ("power", 0.4)])
LEECH = ("life_steal_hit_effect", [("percent", 0.15), ("chance", 1.0)])
ALL_RES = lambda v: {"res_fire": v, "res_ice": v, "res_poison": v, "res_magic": v}


def new_skills():
    # ---- warrior
    blast("w_whirlwind", "Вихрь", "Круговой удар оружием по всем вокруг.", ("earthquake", 0.55), 44, 1.4, 0.3, 14, 6.0,
          (0.9, 0.9, 1.0), synergy=(0, 1))
    passive("w_executioner", "Палач", "Каждый удар может стать последним.", ("blade_master", 0.9),
            {"damage": 2, "crit_chance": 0.03})
    buff("w_berserk", "Берсерк", "Слепая ярость: больше урона и скорости.", ("haste", 0.95, 1.2),
         "berserk", {"damage": 6, "speed": 20}, {"damage": 3}, 8, 25, 25.0, (1.0, 0.45, 0.4), anim="attack_heavy")
    passive("w_shield_wall", "Стена щитов", "Броня и стойкость к стихиям.", ("iron_skin", 0.6),
            dict({"armor": 3}, **ALL_RES(0.04)))
    buff("w_second_wind", "Второе дыхание", "Исцеляет и ненадолго укрепляет доспех.", ("toughness", 0.3),
         "second_wind", {"armor": 4}, {"armor": 2}, 6, 20, 30.0, (0.6, 1.0, 0.6), heal=0.25)
    passive("w_unbreakable", "Несокрушимый", "Раны затягиваются сами.", ("toughness", 0.15),
            {"max_hp": 25, "hp_regen": 0.4})
    passive("w_titan_grip", "Хватка титана", "Сила и выносливость великана.", ("blade_master", 0.4),
            {"strength": 2, "vitality": 2})
    passive("w_battle_lust", "Жажда боя", "Лёгкие ноги и быстрые руки.", ("haste", 0.4), {"agility": 1, "speed": 5})
    missile("w_axe_throw", "Бросок топора", "Тяжёлый топор пробивает врагов насквозь.", ("power_strike", 0.12),
            "shard", 260, 1.8, 0.35, 12, 3.5, (0.8, 0.8, 0.85), pierce=2, synergy=(1,))
    dash("w_charge", "Натиск", "Рывок, сбивающий врагов с ног.", ("haste", 0.2), 400, 1.2, 12, 5.0)
    passive("w_rage_leech", "Кровавая ярость", "Удары возвращают часть урона здоровьем.", ("bloodletting", 0.1),
            {}, hit=LEECH, chance=(0.25, 0.1))
    blast("w_blade_storm", "Буря клинков", "Шквал ударов разрывает всё вокруг.", ("earthquake", 0.7), 70, 2.4, 0.4, 30, 14.0,
          (1.0, 0.6, 0.6), synergy=(0, 1))
    buff("w_battle_trance", "Боевой транс", "Время замедляется: точность и скорость.", ("haste", 0.65),
         "trance", {"crit_chance": 0.15, "speed": 30}, {"crit_chance": 0.03}, 10, 25, 28.0, (0.8, 0.7, 1.0))
    # ---- mage
    passive("m_pyromania", "Пиромания", "Удары поджигают врагов.", ("fireball", 0.05), {"intellect": 1}, hit=BURN,
            chance=(0.15, 0.08))
    blast("m_fire_nova", "Огненное кольцо", "Кольцо пламени вокруг мага.", ("frost_nova", 0.5), 52, 1.5, 0.3, 16, 6.0,
          (1.0, 0.5, 0.15), dtype=FIRE, anim="attack_cast")
    missile("m_flame_volley", "Огненный залп", "Три огненных шара веером.", ("fireball", 0.92), "fireball", 230, 1.1, 0.25,
            18, 5.0, (1.0, 0.5, 0.15), dtype=FIRE, count=3, spread=14.0, blast_r=18.0)
    passive("m_inferno", "Сердце пламени", "Огонь не жжёт, а усиливает.", ("meteor", 0.08),
            {"damage": 2, "res_fire": 0.08})
    buff("m_combustion", "Возгорание", "Магия разгорается до предела.", ("fireball", 0.85, 1.2, 1.1),
         "combustion", {"damage": 8, "intellect": 4}, {"damage": 3}, 8, 30, 30.0, (1.0, 0.6, 0.3))
    missile("m_ice_lance", "Ледяное копьё", "Пробивает врагов и морозит.", ("frost_nova", 0.05), "snowball", 300, 1.6, 0.3,
            12, 3.0, (0.6, 0.85, 1.0), dtype=ICE, pierce=2)
    buff("m_frost_armor", "Ледяная броня", "Корка льда защищает от ударов.", ("arcane_shield", 0.1),
         "frost_armor", {"armor": 8, "res_ice": 0.2}, {"armor": 3}, 12, 18, 20.0, (0.6, 0.85, 1.0))
    passive("m_glacier", "Вечная мерзлота", "Удары замедляют врагов.", ("frost_nova", 0.9), {"intellect": 1},
            hit=SLOW, chance=(0.2, 0.08))
    blast("m_blizzard", "Буран", "Ледяная буря замораживает всех вокруг.", ("frost_nova", 0.12, 1.3), 76, 1.8, 0.35, 32, 16.0,
          (0.7, 0.9, 1.0), dtype=ICE, stun=1.0, anim="attack_cast")
    status("m_ice_block", "Ледяная глыба", "Мощный щит изо льда.", ("arcane_shield", 0.85), "shield", 6, 80, 30, 28, 22.0)
    passive("m_mana_flow", "Поток маны", "Мана течёт свободнее.", ("arcane_mind", 0.3), {"max_mana": 10, "intellect": 1})
    missile("m_arcane_orb", "Тайная сфера", "Медленная сфера взрывается чистой магией.", ("chain_lightning", 0.6),
            "magic_bolt", 150, 2.6, 0.45, 24, 7.0, (0.8, 0.5, 1.0), dtype=MAGIC, blast_r=36.0)
    passive("m_archmage", "Архимаг", "Вершина тайного искусства.", ("arcane_mind", 0.6), {"intellect": 3, "crit_chance": 0.03})
    # ---- rogue
    passive("r_lacerate", "Рваные раны", "Удары вызывают кровотечение.", ("venom_blades", 0.9), {"agility": 1},
            hit=BLEED, chance=(0.2, 0.08))
    buff("r_flurry", "Шквал", "Серия молниеносных ударов.", ("evasion", 0.6), "flurry",
         {"agility": 4, "crit_chance": 0.1}, {"agility": 2}, 6, 16, 18.0, (1.0, 0.9, 0.5))
    passive("r_assassin", "Убийца", "Бьёт туда, где больнее всего.", ("keen_eye", 0.9), {"damage": 2, "crit_chance": 0.04})
    blast("r_deadly_dance", "Смертельный танец", "Вихрь клинков вокруг разбойника.", ("knife_fan", 0.5), 42, 2.0, 0.35,
          22, 10.0, (0.9, 0.9, 0.7), knockback=40.0, synergy=(3, 4))
    status("r_vanish", "Исчезновение", "Растворяется в тенях: враги теряют из виду.", ("smoke_bomb", 0.6), "invisible",
           3, 1, 0, 18, 20.0)
    passive("r_nimble", "Проворство", "Двигается быстрее, чем видит глаз.", ("shadow_step", 0.5), {"agility": 2, "speed": 6})
    passive("r_shadow_lord", "Повелитель теней", "Тьма бережёт своего.", ("shadow_step", 0.2),
            dict({"max_hp": 10}, **ALL_RES(0.05)))
    dash("r_phantom", "Фантомный рывок", "Проходит сквозь врагов, раня их.", ("dash", 0.7), 460, 1.6, 14, 4.0)
    passive("r_steady_hand", "Твёрдая рука", "Каждый бросок точен.", ("throw_knives", 0.5), {"damage": 1, "agility": 1})
    missile("r_poison_dart", "Отравленный дротик", "Яд и пробивание.", ("throw_knives", 0.3), "knife", 320, 1.3, 0.3, 8, 2.5,
            (0.5, 0.9, 0.3), dtype=POISON, pierce=1, synergy=(7,))
    passive("r_quiver", "Глаз ястреба", "Слабые места видны издалека.", ("keen_eye", 0.3), {"crit_chance": 0.03, "agility": 1})
    missile("r_blade_rain", "Дождь клинков", "Семь ножей широким веером.", ("knife_fan", 0.8), "knife", 300, 0.9, 0.2, 24, 8.0,
            (0.9, 0.9, 1.0), count=7, spread=30.0, synergy=(3, 7))
    missile("r_fire_flask", "Зажигательная склянка", "Взрывается огнём при попадании.", ("smoke_bomb", 0.05), "fireball",
            220, 2.2, 0.4, 20, 7.0, (1.0, 0.55, 0.2), dtype=FIRE, blast_r=40.0)
    # ---- paladin
    passive("p_healer", "Целитель", "Свет медленно исцеляет раны.", ("holy_light", 0.3), {"hp_regen": 0.4, "max_hp": 8})
    buff("p_sanctuary", "Святилище", "Сильное исцеление и защита.", ("holy_light", 0.85), "sanctuary",
         {"armor": 8}, {"armor": 3}, 6, 28, 26.0, (1.0, 1.0, 0.6), heal=0.35)
    passive("p_saint", "Святой", "Тело и дух закалены верой.", ("blessing", 0.4), {"vitality": 2, "intellect": 2})
    status("p_divine_shield", "Божественный щит", "Сияющий купол поглощает урон.", ("arcane_shield", 0.15), "shield",
           6, 100, 35, 30, 24.0)
    passive("p_bulwark", "Бастион", "Доспех становится частью тела.", ("iron_skin", 0.1), {"armor": 2})
    passive("p_guardian", "Страж", "Защита от стихий.", ("light_aura", 0.5), ALL_RES(0.04))
    passive("p_fortress", "Крепость", "Несгибаемая стойкость.", ("iron_skin", 0.85), {"max_hp": 15})
    buff("p_aegis", "Эгида", "Неприступная броня на время.", ("iron_skin", 0.15, 1.2), "aegis",
         {"armor": 20}, {"armor": 6}, 8, 24, 26.0, (0.8, 0.9, 1.0))
    passive("p_martyr", "Мученик", "Карая врага, исцеляет себя.", ("blessing", 0.9), {}, hit=LEECH, chance=(0.25, 0.1))
    passive("p_zeal", "Рвение", "Каждый удар — во славу света.", ("holy_strike", 0.4), {"strength": 1, "damage": 1})
    missile("p_smite_bolt", "Луч кары", "Сгусток света пробивает врагов.", ("holy_strike", 0.1), "magic_bolt", 280, 1.5, 0.3,
            12, 3.5, (1.0, 0.95, 0.5), dtype=MAGIC, pierce=1)
    blast("p_judgment", "Суд", "Свет обрушивается на всех рядом.", ("righteous_wrath", 0.6), 54, 1.7, 0.35, 20, 9.0,
          (1.0, 0.9, 0.5), dtype=MAGIC, stun=0.5, synergy=(6,))
    passive("p_crusader", "Крестоносец", "Меч и вера бьют без промаха.", ("holy_strike", 0.75), {"damage": 2, "crit_chance": 0.04})

    # ---- tier-5 capstones: one per branch, the crown of each path
    blast("w_execution", "Казнь", "Один удар — и бой окончен.", ("earthquake", 0.85), 60, 3.2, 0.5, 35, 20.0,
          (1.0, 0.35, 0.3), synergy=(0, 1))
    passive("w_iron_oath", "Железный обет", "Клятва крепче любой брони.", ("iron_skin", 0.4, 0.7),
            dict({"armor": 5, "max_hp": 30, "hp_regen": 0.6}, **ALL_RES(0.08)))
    buff("w_frenzy", "Неистовство", "Ярость без границ: урон, скорость, точность.", ("haste", 0.0, 1.3, 1.1),
         "frenzy", {"damage": 12, "speed": 25, "crit_chance": 0.1}, {"damage": 4}, 10, 30, 30.0, (1.0, 0.3, 0.3))
    blast("m_supernova", "Сверхновая", "Звезда рождается и умирает в одно мгновение.", ("meteor", 0.02), 85, 2.6, 0.45, 40, 22.0,
          (1.0, 0.6, 0.2), dtype=FIRE, stun=0.6, anim="attack_cast")
    blast("m_absolute_zero", "Абсолютный ноль", "Всё замирает. Совсем.", ("frost_nova", 0.5, 1.2), 70, 2.0, 0.4, 35, 20.0,
          (0.7, 0.95, 1.0), dtype=ICE, stun=2.0, anim="attack_cast")
    passive("m_mind_domination", "Власть разума", "Мысль острым любого клинка.", ("arcane_mind", 0.55, 1.15),
            {"intellect": 4, "damage": 3, "crit_chance": 0.05, "max_mana": 20})
    blast("r_death_waltz", "Смертельный вальс", "Танец, после которого не аплодируют.", ("knife_fan", 0.12, 1.2), 60, 2.6, 0.4,
          30, 14.0, (0.95, 0.5, 0.9), knockback=60.0, synergy=(0, 3))
    passive("r_child_of_dark", "Дитя тьмы", "Тьма — твой дом и твой щит.", ("shadow_step", 0.12),
            dict({"agility": 3, "crit_chance": 0.05, "speed": 8}, **ALL_RES(0.06)))
    missile("r_thousand_blades", "Тысяча клинков", "Веер стали, от которого не уйти.", ("throw_knives", 0.08, 1.25),
            "knife", 300, 1.0, 0.2, 35, 16.0, (0.95, 0.95, 1.0), count=9, spread=40.0, pierce=1, synergy=(3, 7))
    buff("p_ascension", "Вознесение", "Свет исцеляет и облекает в броню.", ("holy_light", 0.06, 1.1),
         "ascension", {"armor": 15}, {"armor": 5}, 8, 35, 30.0, (1.0, 1.0, 0.7), heal=0.5)
    passive("p_unbroken_vow", "Нерушимый завет", "Обет, который не возьмёт даже смерть.", ("blessing", 0.35, 0.8),
            {"max_hp": 40, "armor": 5, "hp_regen": 0.5})
    blast("p_heavens_wrath", "Гнев небес", "Небеса падают на нечестивых.", ("righteous_wrath", 0.05), 66, 2.6, 0.45, 35, 18.0,
          (1.0, 0.9, 0.5), dtype=MAGIC, stun=1.2)


# tiers: list of 5 entries per branch, each a skill id or a (a, b) choice pair
TREES = {
    "warrior": (["Оружие", "Стойкость", "Ярость"], [
        ["power_strike", "blade_master", ("w_whirlwind", "bloodletting"), "earthquake", ("w_executioner", "w_berserk"), "w_execution"],
        ["iron_skin", "toughness", ("w_shield_wall", "w_second_wind"), "war_cry", ("w_unbreakable", "w_titan_grip"), "w_iron_oath"],
        ["haste", "w_battle_lust", ("w_axe_throw", "w_charge"), "w_rage_leech", ("w_blade_storm", "w_battle_trance"), "w_frenzy"],
    ]),
    "mage": (["Огонь", "Лёд", "Тайное"], [
        ["fireball", "m_pyromania", ("m_fire_nova", "m_flame_volley"), "meteor", ("m_inferno", "m_combustion"), "m_supernova"],
        ["frost_nova", "elemental_ward", ("m_ice_lance", "m_frost_armor"), "m_glacier", ("m_blizzard", "m_ice_block"), "m_absolute_zero"],
        ["arcane_shield", "arcane_mind", ("blink", "m_mana_flow"), "chain_lightning", ("m_arcane_orb", "m_archmage"), "m_mind_domination"],
    ]),
    "rogue": (["Клинки", "Тени", "Метание"], [
        ["dash", "keen_eye", ("venom_blades", "r_lacerate"), "r_flurry", ("r_assassin", "r_deadly_dance"), "r_death_waltz"],
        ["evasion", "shadow_step", ("smoke_bomb", "r_vanish"), "r_nimble", ("r_shadow_lord", "r_phantom"), "r_child_of_dark"],
        ["throw_knives", "r_steady_hand", ("knife_fan", "r_poison_dart"), "r_quiver", ("r_blade_rain", "r_fire_flask"), "r_thousand_blades"],
    ]),
    "paladin": (["Свет", "Щит", "Кара"], [
        ["holy_light", "blessing", ("light_aura", "p_healer"), "p_sanctuary", ("p_saint", "p_divine_shield"), "p_ascension"],
        ["iron_skin", "p_bulwark", ("arcane_shield", "p_guardian"), "p_fortress", ("p_aegis", "p_martyr"), "p_unbroken_vow"],
        ["power_strike", "p_zeal", ("holy_strike", "p_smite_bolt"), "p_judgment", ("righteous_wrath", "p_crusader"), "p_heavens_wrath"],
    ]),
}


def patch_class(cid, names, branches):
    path = os.path.join(CLASSES, cid + ".tres")
    s = open(path, encoding="utf-8").read()
    head, res = s.split("[resource]", 1)
    skill_script = re.search(r'^skills = Array\[ExtResource\("([^"]+)"\)\]', res, re.M).group(1)
    head = re.sub(r'^\[ext_resource type="Resource" path="res://data/skills/[a-z_]+\.tres" id="tree_[a-z_]+"\]\n', "", head,
                  flags=re.M)
    order, layout = [], {}
    for b, tiers in enumerate(branches):
        for row, entry in enumerate(tiers):
            ids = entry if isinstance(entry, tuple) else (entry,)
            points, level = TIERS[row]
            for sid in ids:
                assert os.path.exists(os.path.join(SKILLS, sid + ".tres")), sid
                order.append(sid)
                layout[sid] = {"branch": b, "row": row, "points": points, "level": level,
                               "choice": "%s_%d_%d" % (cid, b, row) if len(ids) > 1 else ""}
    ext = "".join('[ext_resource type="Resource" path="res://data/skills/%s.tres" id="tree_%s"]\n' % (sid, sid) for sid in order)
    head = head.rstrip("\n") + "\n" + ext + "\n"
    res = re.sub(r"^(branch_names|tree_layout) = .*?(?=^\w+ = |\Z)", "", res, flags=re.M | re.S)
    res = re.sub(r"^skills = .*$", 'skills = Array[ExtResource("%s")]([%s])' % (
        skill_script, ", ".join('ExtResource("tree_%s")' % sid for sid in order)), res, flags=re.M)
    lay = "{\n" + ",\n".join('"%s": {"branch": %d, "row": %d, "points": %d, "level": %d, "choice": "%s"}' % (
        sid, v["branch"], v["row"], v["points"], v["level"], v["choice"]) for sid, v in layout.items()) + "\n}"
    res = res.rstrip("\n") + "\nbranch_names = Array[String]([%s])\ntree_layout = %s\n" % (
        ", ".join('"%s"' % n for n in names), lay)
    with open(path, "w", encoding="utf-8") as f:
        f.write(head + "[resource]" + res)


def main():
    new_skills()
    for cid, (names, branches) in TREES.items():
        patch_class(cid, names, branches)
    print("skill trees generated")


if __name__ == "__main__":
    main()
