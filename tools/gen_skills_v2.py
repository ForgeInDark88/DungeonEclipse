#!/usr/bin/env python3
"""Skill roster v2: archetype branches, redrawn glyph icons for every skill.

Trees: 3 branches x 6 tiers (pairs at 2 and 4, capstone at 5). Reuses the
handcrafted originals and v1/v2 generated skills where they fit, adds six
new skills, and REGENERATES EVERY ICON from pixel glyphs (no recolors).
Also patches data/classes/*.tres (branch names, layout, skill lists).

Run from tools/: python gen_skills_v2.py
"""
from __future__ import annotations

import os

import gen_skill_icons32 as gi  # 32px volume-lit icons (v4)
import gen_skill_trees as gst

PHYS, FIRE, ICE, POISON, MAGIC = range(5)
RED = (226, 64, 64)
GREEN = (84, 204, 110)
ORANGE = (255, 168, 64)
FLAME = (255, 118, 48)
FROST = (118, 198, 255)
VOID = (168, 108, 255)
GOLD = (255, 218, 120)
SHADOW = (148, 104, 232)
STEEL_A = (168, 186, 214)
POISON_A = (138, 220, 82)
BLOOD_A = (216, 58, 74)

# ---------------------------------------------------------------- new skills
BLEED = ("status_hit_effect", [("status", "&bleed"), ("duration", 3.0), ("power", 2.0)])
LEECH = ("life_steal_hit_effect", [("percent", 0.15), ("chance", 1.0)])
ALL_RES = lambda v: {"res_fire": v, "res_ice": v, "res_poison": v, "res_magic": v}


def new_skills():
    gst.blast("w_cleave", "Рассечение", "Широкий взмах рассекает всё перед воином.", ("power_strike", 0.0), 40, 1.6, 0.3, 8, 4.0,
              (0.95, 0.5, 0.45), knockback=90.0, synergy=(0, 1), vfx="slash")
    gst.blast("w_omnislash", "Веер клинков", "Серия молниеносных ударов по всем вокруг.", ("earthquake", 0.0), 62, 2.6, 0.4, 26, 13.0,
              (1.0, 0.55, 0.5), stun=0.3, synergy=(0, 1), vfx="blades")
    gst.blast("w_shield_bash", "Удар щитом", "Оглушающий тычок щитом.", ("iron_skin", 0.0), 26, 1.1, 0.25, 6, 5.0,
              (0.75, 0.85, 0.95), stun=1.4, knockback=170.0, vfx="ring")
    gst.dash("m_void_step", "Шаг бездны", "Короткий прыжок сквозь пространство.", ("dash", 0.0), 420, 0.6, 8, 4.0)
    gst.blast("r_backstab", "Удар в спину", "Кровавый выпад в слепую зону врага.", ("dash", 0.0), 28, 1.9, 0.4, 10, 5.0,
              (0.9, 0.4, 0.5), knockback=30.0, synergy=(0, 3), vfx="slash")
    gst.passive("r_umbral", "Полумрак", "Сумерки укрывают и ускоряют.", ("evasion", 0.15),
                dict({"agility": 2, "speed": 5}, **ALL_RES(0.05)))


# ------------------------------------------------------------------- trees
# tier lists per branch; ids reference existing or newly written skills
TREES = {
    "warrior": (["Палач", "Страж", "Берсерк"], [
        ["power_strike", "blade_master", ("w_cleave", "bloodletting"), "earthquake", ("w_executioner", "w_omnislash"), "w_execution"],
        ["w_shield_bash", "toughness", ("w_shield_wall", "w_second_wind"), "war_cry", ("w_unbreakable", "w_titan_grip"), "w_iron_oath"],
        ["dash", "w_battle_lust", ("w_axe_throw", "w_charge"), "w_rage_leech", ("w_berserk", "w_battle_trance"), "w_frenzy"],
    ]),
    "mage": (["Пламя", "Стужа", "Бездна"], [
        ["fireball", "m_pyromania", ("m_fire_nova", "m_flame_volley"), "meteor", ("m_inferno", "m_combustion"), "m_supernova"],
        ["frost_nova", "elemental_ward", ("m_ice_lance", "m_frost_armor"), "m_glacier", ("m_blizzard", "m_ice_block"), "m_absolute_zero"],
        ["blink", "arcane_mind", ("m_mana_flow", "m_void_step"), "chain_lightning", ("m_arcane_orb", "m_archmage"), "m_mind_domination"],
    ]),
    "rogue": (["Клинок", "Тень", "Метатель"], [
        ["r_backstab", "keen_eye", ("venom_blades", "r_lacerate"), "r_flurry", ("r_assassin", "r_deadly_dance"), "r_death_waltz"],
        ["smoke_bomb", "shadow_step", ("r_vanish", "r_nimble"), "r_phantom", ("r_shadow_lord", "r_umbral"), "r_child_of_dark"],
        ["throw_knives", "r_steady_hand", ("knife_fan", "r_poison_dart"), "r_quiver", ("r_blade_rain", "r_fire_flask"), "r_thousand_blades"],
    ]),
    "paladin": (["Свет", "Бастион", "Кара"], [
        ["holy_light", "blessing", ("light_aura", "p_healer"), "p_sanctuary", ("p_saint", "p_divine_shield"), "p_ascension"],
        ["iron_skin", "p_bulwark", ("arcane_shield", "p_guardian"), "p_fortress", ("p_aegis", "p_martyr"), "p_unbroken_vow"],
        ["power_strike", "p_zeal", ("holy_strike", "p_smite_bolt"), "p_judgment", ("righteous_wrath", "p_crusader"), "p_heavens_wrath"],
    ]),
}

# ------------------------------------------------------- icons for everyone
# skill id -> (spec, accent); spec = {"bg", "s": (subject, params), "fx"}
# every skill of a branch gets its own subject; repeats elsewhere always
# change params / backdrop / accent so nothing looks copy-pasted.
ICONS = {
    # warrior - Палач
    "power_strike": ({"bg": "glowline", "s": ("blade", {})}, RED),
    "blade_master": ({"bg": "runes", "s": ("blade", {"edge": "blood", "guard": "none"})}, BLOOD_A),
    "w_cleave": ({"bg": "wash", "s": ("slash", {"double": 1})}, BLOOD_A),
    "bloodletting": ({"bg": "dark", "s": ("blood", {"splashes": 1})}, BLOOD_A),
    "earthquake": ({"bg": "storm", "s": ("hammer", {"w": 10, "glow": 1})}, RED),
    "w_executioner": ({"bg": "dark", "s": ("skull", {"crown": 1})}, BLOOD_A),
    "w_omnislash": ({"bg": "rays", "s": ("whirl", {"arms": 4})}, RED),
    "w_execution": ({"bg": "rays", "s": ("axe", {"spike": 1})}, BLOOD_A),
    # warrior - Страж
    "w_shield_bash": ({"bg": "wash", "s": ("shield", {"herald": "boss"})}, STEEL_A),
    "toughness": ({"bg": "wash", "s": ("heart", {"pulse": 1})}, GREEN),
    "w_shield_wall": ({"bg": "runes", "s": ("wall", {})}, GREEN),
    "w_second_wind": ({"bg": "orbit", "s": ("wing", {})}, GREEN),
    "war_cry": ({"bg": "rays", "s": ("impact", {"rays": 8})}, GREEN),
    "w_unbreakable": ({"bg": "wash", "s": ("figure", {"aura": 1})}, GREEN),
    "w_titan_grip": ({"bg": "storm", "s": ("fist", {"burst": 1})}, GREEN),
    "w_iron_oath": ({"bg": "runes", "s": ("chains", {})}, GREEN),
    # warrior - Берсерк
    "dash": ({"bg": "glowline", "s": ("boot", {"wings": 1})}, ORANGE),
    "w_battle_lust": ({"bg": "storm", "s": ("fist", {})}, ORANGE),
    "w_axe_throw": ({"bg": "glowline", "s": ("axe", {})}, ORANGE),
    "w_charge": ({"bg": "storm", "s": ("arrow", {"count": 3})}, ORANGE),
    "w_rage_leech": ({"bg": "dark", "s": ("blood", {})}, ORANGE),
    "w_berserk": ({"bg": "storm", "s": ("figure", {"aura": 1})}, ORANGE),
    "w_battle_trance": ({"bg": "dark", "s": ("eye", {"lashes": 1})}, ORANGE),
    "w_frenzy": ({"bg": "rays", "s": ("frenzy", {})}, ORANGE),
    # mage - Пламя
    "fireball": ({"bg": "wash", "s": ("flame", {"big": 1})}, FLAME),
    "m_pyromania": ({"bg": "wash", "s": ("blade", {"edge": "flame", "len": "short", "guard": "none"})}, FLAME),
    "m_fire_nova": ({"bg": "rays", "s": ("nova", {})}, FLAME),
    "m_flame_volley": ({"bg": "glowline", "s": ("arrow", {"count": 3})}, FLAME),
    "meteor": ({"bg": "dark", "s": ("meteor", {})}, FLAME),
    "m_inferno": ({"bg": "wash", "s": ("heart", {})}, FLAME),
    "m_combustion": ({"bg": "storm", "s": ("bomb", {"smoke": 1})}, FLAME),
    "m_supernova": ({"bg": "rays", "s": ("sun", {"wave": 1})}, (255, 140, 60)),
    # mage - Стужа
    "frost_nova": ({"bg": "wash", "s": ("snowflake", {"arms": 6})}, FROST),
    "elemental_ward": ({"bg": "orbit", "s": ("shield", {"herald": "wings"})}, FROST),
    "m_ice_lance": ({"bg": "glowline", "s": ("arrow", {})}, FROST),
    "m_frost_armor": ({"bg": "orbit", "s": ("wall", {"cren": 0})}, FROST),
    "m_glacier": ({"bg": "wash", "s": ("thorns", {})}, FROST),
    "m_blizzard": ({"bg": "storm", "s": ("fan", {"count": 7})}, FROST),
    "m_ice_block": ({"bg": "orbit", "s": ("orb", {})}, FROST),
    "m_absolute_zero": ({"bg": "particles", "s": ("hourglass", {"hold": 1})}, (220, 245, 255)),
    # mage - Бездна
    "blink": ({"bg": "dark", "s": ("arrow", {})}, VOID),
    "arcane_mind": ({"bg": "orbit", "s": ("eye", {})}, VOID),
    "m_mana_flow": ({"bg": "particles", "s": ("star", {"twinkle": 1})}, (140, 120, 255)),
    "m_void_step": ({"bg": "dark", "s": ("figure", {})}, VOID),
    "chain_lightning": ({"bg": "storm", "s": ("bolt", {"fork": 1})}, VOID),
    "m_arcane_orb": ({"bg": "orbit", "s": ("orb", {"ring": 1, "stars": 1})}, VOID),
    "m_archmage": ({"bg": "runes", "s": ("hat", {})}, VOID),
    "m_mind_domination": ({"bg": "dark", "s": ("frenzy", {})}, (210, 160, 255)),
    # rogue - Клинок
    "r_backstab": ({"bg": "dark", "s": ("dagger", {})}, BLOOD_A),
    "keen_eye": ({"bg": "particles", "s": ("eye", {})}, RED),
    "venom_blades": ({"bg": "wash", "s": ("blade", {"edge": "poison", "len": "short"})}, POISON_A),
    "r_lacerate": ({"bg": "wash", "s": ("slash", {})}, BLOOD_A),
    "r_flurry": ({"bg": "glowline", "s": ("whirl", {"arms": 2})}, RED),
    "r_assassin": ({"bg": "dark", "s": ("skull", {})}, RED),
    "r_deadly_dance": ({"bg": "glowline", "s": ("fan", {"count": 3})}, RED),
    "r_death_waltz": ({"bg": "rays", "s": ("impact", {"rays": 8})}, (255, 90, 120)),
    # rogue - Тень
    "smoke_bomb": ({"bg": "dark", "s": ("bomb", {"smoke": 1})}, SHADOW),
    "shadow_step": ({"bg": "glowline", "s": ("boot", {})}, SHADOW),
    "r_vanish": ({"bg": "dark", "s": ("cloak", {})}, (190, 150, 255)),
    "r_nimble": ({"bg": "particles", "s": ("wing", {})}, SHADOW),
    "r_phantom": ({"bg": "glowline", "s": ("figure", {})}, SHADOW),
    "r_shadow_lord": ({"bg": "dark", "s": ("eye", {"lashes": 1})}, SHADOW),
    "r_umbral": ({"bg": "runes", "s": ("hourglass", {})}, SHADOW),
    "r_child_of_dark": ({"bg": "dark", "s": ("skull", {"crown": 1})}, (170, 120, 255)),
    # rogue - Метатель
    "throw_knives": ({"bg": "wash", "s": ("dagger", {"twin": 1})}, ORANGE),
    "r_steady_hand": ({"bg": "wash", "s": ("star", {"twinkle": 1})}, ORANGE),
    "knife_fan": ({"bg": "rays", "s": ("fan", {"count": 5})}, ORANGE),
    "r_poison_dart": ({"bg": "wash", "s": ("poison", {"drops": 1})}, POISON_A),
    "r_quiver": ({"bg": "particles", "s": ("impact", {"rays": 6})}, (255, 200, 90)),
    "r_blade_rain": ({"bg": "storm", "s": ("arrow", {"count": 5})}, (255, 200, 90)),
    "r_fire_flask": ({"bg": "wash", "s": ("poison", {"drops": 2})}, FLAME),
    "r_thousand_blades": ({"bg": "storm", "s": ("fan", {"count": 9})}, (255, 190, 80)),
    # paladin - Свет
    "holy_light": ({"bg": "rays", "s": ("cross", {"halo": 1})}, GOLD),
    "blessing": ({"bg": "wash", "s": ("star", {"twinkle": 1})}, GOLD),
    "light_aura": ({"bg": "orbit", "s": ("nova", {})}, GOLD),
    "p_healer": ({"bg": "wash", "s": ("heart", {"pulse": 1})}, GOLD),
    "p_sanctuary": ({"bg": "wash", "s": ("figure", {"aura": 1})}, (255, 240, 170)),
    "p_saint": ({"bg": "orbit", "s": ("wing", {})}, (255, 240, 170)),
    "p_divine_shield": ({"bg": "orbit", "s": ("shield", {"herald": "boss"})}, GOLD),
    "p_ascension": ({"bg": "rays", "s": ("sun", {"wave": 1})}, GOLD),
    # paladin - Бастион
    "iron_skin": ({"bg": "wash", "s": ("figure", {"aura": 1})}, STEEL_A),
    "p_bulwark": ({"bg": "runes", "s": ("wall", {})}, STEEL_A),
    "arcane_shield": ({"bg": "orbit", "s": ("orb", {"ring": 1})}, STEEL_A),
    "p_guardian": ({"bg": "orbit", "s": ("eye", {"lashes": 1})}, STEEL_A),
    "p_fortress": ({"bg": "storm", "s": ("shield", {"herald": "boss"})}, (120, 220, 150)),
    "p_aegis": ({"bg": "rays", "s": ("shield", {"herald": "wings"})}, GREEN),
    "p_martyr": ({"bg": "dark", "s": ("heart", {})}, GREEN),
    "p_unbroken_vow": ({"bg": "runes", "s": ("chains", {"break": 1})}, (140, 230, 160)),
    # paladin - Кара
    "p_zeal": ({"bg": "rays", "s": ("fist", {"burst": 1})}, GOLD),
    "holy_strike": ({"bg": "rays", "s": ("hammer", {"glow": 1})}, (255, 190, 80)),
    "p_smite_bolt": ({"bg": "particles", "s": ("bolt", {})}, GOLD),
    "p_judgment": ({"bg": "storm", "s": ("nova", {})}, (255, 170, 70)),
    "righteous_wrath": ({"bg": "storm", "s": ("sun", {"wave": 1})}, (255, 150, 70)),
    "p_crusader": ({"bg": "runes", "s": ("blade", {"edge": "gold"})}, GOLD),
    "p_heavens_wrath": ({"bg": "rays", "s": ("impact", {"rays": 8})}, (255, 240, 160)),
    # shared extras that still live in data/skills
    "haste": ({"bg": "glowline", "s": ("boot", {"wings": 1})}, ORANGE),
    "evasion": ({"bg": "particles", "s": ("wing", {})}, SHADOW),
}


def main():
    new_skills()
    # Rewrite every icon as a fresh glyph (this includes the originals).
    for sid, (glyph, accent) in ICONS.items():
        gi.draw(glyph, accent).save(os.path.join(gst.ICONS, sid + ".png"))
    for cid, (names, branches) in TREES.items():
        gst.patch_class(cid, names, branches)
    print("roster v2: skills written, %d icons drawn, classes patched" % len(ICONS))


if __name__ == "__main__":
    main()
