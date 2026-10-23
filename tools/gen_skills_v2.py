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

import gen_skill_icons as gi
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
              (0.95, 0.5, 0.45), knockback=90.0, synergy=(0, 1))
    gst.blast("w_omnislash", "Веер клинков", "Серия молниеносных ударов по всем вокруг.", ("earthquake", 0.0), 62, 2.6, 0.4, 26, 13.0,
              (1.0, 0.55, 0.5), stun=0.3, synergy=(0, 1))
    gst.blast("w_shield_bash", "Удар щитом", "Оглушающий тычок щитом.", ("iron_skin", 0.0), 26, 1.1, 0.25, 6, 5.0,
              (0.75, 0.85, 0.95), stun=1.4, knockback=170.0)
    gst.dash("m_void_step", "Шаг бездны", "Короткий прыжок сквозь пространство.", ("dash", 0.0), 420, 0.6, 8, 4.0)
    gst.blast("r_backstab", "Удар в спину", "Кровавый выпад в слепую зону врага.", ("dash", 0.0), 28, 1.9, 0.4, 10, 5.0,
              (0.9, 0.4, 0.5), knockback=30.0, synergy=(0, 3))
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
# skill id -> (glyph, accent)
ICONS = {
    # warrior - Палач
    "power_strike": ("sword", RED), "blade_master": ("greatsword", RED),
    "w_cleave": ("slash", BLOOD_A), "bloodletting": ("blood", BLOOD_A),
    "earthquake": ("hammer", RED), "w_executioner": ("skull", BLOOD_A),
    "w_omnislash": ("whirl", RED), "w_execution": ("axe", BLOOD_A),
    # warrior - Страж
    "w_shield_bash": ("shield", STEEL_A), "toughness": ("heart", GREEN),
    "w_shield_wall": ("wall", GREEN), "w_second_wind": ("heart", GREEN),
    "war_cry": ("star", GREEN), "w_unbreakable": ("chains", GREEN),
    "w_titan_grip": ("fist", GREEN), "w_iron_oath": ("wall", (120, 220, 150)),
    # warrior - Берсерк
    "dash": ("boot", ORANGE), "w_battle_lust": ("fist", ORANGE),
    "w_axe_throw": ("axe", ORANGE), "w_charge": ("arrow", ORANGE),
    "w_rage_leech": ("blood", ORANGE), "w_berserk": ("flame", ORANGE),
    "w_battle_trance": ("eye", ORANGE), "w_frenzy": ("whirl", (255, 120, 60)),
    # mage - Пламя
    "fireball": ("flame", FLAME), "m_pyromania": ("flame", (255, 90, 40)),
    "m_fire_nova": ("sun", FLAME), "m_flame_volley": ("fan", FLAME),
    "meteor": ("star", (255, 96, 40)), "m_inferno": ("orb", FLAME),
    "m_combustion": ("bomb", FLAME), "m_supernova": ("sun", (255, 140, 60)),
    # mage - Стужа
    "frost_nova": ("snowflake", FROST), "elemental_ward": ("shield", FROST),
    "m_ice_lance": ("arrow", FROST), "m_frost_armor": ("wall", FROST),
    "m_glacier": ("snowflake", (170, 220, 255)), "m_blizzard": ("snowflake", (90, 160, 230)),
    "m_ice_block": ("orb", FROST), "m_absolute_zero": ("snowflake", (220, 245, 255)),
    # mage - Бездна
    "blink": ("arrow", VOID), "arcane_mind": ("eye", VOID),
    "m_mana_flow": ("orb", (140, 120, 255)), "m_void_step": ("arrow", (190, 130, 255)),
    "chain_lightning": ("bolt", VOID), "m_arcane_orb": ("orb", VOID),
    "m_archmage": ("star", VOID), "m_mind_domination": ("eye", (210, 160, 255)),
    # rogue - Клинок
    "r_backstab": ("dagger", BLOOD_A), "keen_eye": ("eye", RED),
    "venom_blades": ("dagger", POISON_A), "r_lacerate": ("slash", BLOOD_A),
    "r_flurry": ("whirl", RED), "r_assassin": ("skull", RED),
    "r_deadly_dance": ("fan", RED), "r_death_waltz": ("whirl", (255, 90, 120)),
    # rogue - Тень
    "smoke_bomb": ("bomb", SHADOW), "shadow_step": ("cloak", SHADOW),
    "r_vanish": ("cloak", (190, 150, 255)), "r_nimble": ("boot", SHADOW),
    "r_phantom": ("cloak", VOID), "r_shadow_lord": ("eye", SHADOW),
    "r_umbral": ("hourglass", SHADOW), "r_child_of_dark": ("skull", (170, 120, 255)),
    # rogue - Метатель
    "throw_knives": ("dagger", ORANGE), "r_steady_hand": ("star", ORANGE),
    "knife_fan": ("fan", ORANGE), "r_poison_dart": ("poison", POISON_A),
    "r_quiver": ("arrow", (255, 200, 90)), "r_blade_rain": ("fan", (255, 200, 90)),
    "r_fire_flask": ("bomb", FLAME), "r_thousand_blades": ("fan", (255, 190, 80)),
    # paladin - Свет
    "holy_light": ("cross", GOLD), "blessing": ("star", GOLD),
    "light_aura": ("sun", GOLD), "p_healer": ("heart", GOLD),
    "p_sanctuary": ("cross", (255, 240, 170)), "p_saint": ("sun", (255, 240, 170)),
    "p_divine_shield": ("shield", GOLD), "p_ascension": ("wing", GOLD),
    # paladin - Бастион
    "iron_skin": ("shield", STEEL_A), "p_bulwark": ("wall", STEEL_A),
    "arcane_shield": ("orb", STEEL_A), "p_guardian": ("chains", GREEN),
    "p_fortress": ("wall", GREEN), "p_aegis": ("shield", (140, 230, 160)),
    "p_martyr": ("heart", GREEN), "p_unbroken_vow": ("chains", (140, 230, 160)),
    # paladin - Кара
    "holy_strike": ("hammer", (255, 190, 80)), "p_zeal": ("fist", GOLD),
    "p_smite_bolt": ("bolt", GOLD), "p_judgment": ("star", (255, 170, 70)),
    "righteous_wrath": ("sun", (255, 150, 70)), "p_crusader": ("sword", GOLD),
    "p_heavens_wrath": ("bolt", (255, 240, 160)),
    # shared leftovers that still exist in data/skills
    "haste": ("boot", ORANGE), "evasion": ("wing", SHADOW),
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
