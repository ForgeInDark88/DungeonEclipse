#!/usr/bin/env python3
"""Item catalogue (stage 6): writes data/items/**/<id>.tres, data/sets/*.tres
and the placeholder icons assets/sprites/items/<id>.png for every item below.

The .tres files are ordinary Godot resources: edit them in the editor if you
like, but running this script again overwrites the items it lists (other
items are never touched). After a run: python3 tools/gen_loot_tables.py.

    python3 tools/gen_items.py
"""
from __future__ import annotations

import math
import os

from PIL import ImageDraw

import gen_placeholders as gp

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(ROOT, "data")

# WeaponType / Pattern / DamageType / Rarity indices (see the GDScript enums).
SW, AX, SP, DG, BW, ST, MC, CB, WD = range(9)
ARC, THRUST, SHOOT = 0, 1, 2
PHYS, FIRE, ICE, POISON, MAGIC = range(5)
C, R, E, L = range(4)
EQUIP, USABLE, MATERIAL, RELIC = range(4)


# ------------------------------------------------------------- serializer
class SN(str):
    """StringName literal."""


class Ext:
    def __init__(self, key):
        self.key = key


class Sub:
    def __init__(self, key):
        self.key = key


def lit(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, SN):
        return '&"%s"' % v
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".") if v != int(v) else "%.1f" % v
    if isinstance(v, int):
        return str(v)
    if isinstance(v, Ext):
        return 'ExtResource("%s")' % v.key
    if isinstance(v, Sub):
        return 'SubResource("%s")' % v.key
    if isinstance(v, tuple) and v[0] == "V2":
        return "Vector2(%s, %s)" % (lit(float(v[1])), lit(float(v[2])))
    if isinstance(v, tuple) and v[0] == "COL":
        return "Color(%s, %s, %s, %s)" % tuple(lit(float(x)) for x in v[1:])
    if isinstance(v, tuple) and v[0] == "ARR":  # ("ARR", type_literal, [values])
        return "Array[%s]([%s])" % (v[1], ", ".join(lit(x) for x in v[2]))
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join('"%s": %s' % (k, lit(x)) for k, x in sorted(v.items())) + "\n}"
    raise TypeError(v)


class Tres:
    def __init__(self, script_class):
        self.script_class = script_class
        self.ext = []  # (type, path, key)
        self.subs = []  # (key, [(prop, value)])

    def ext_res(self, typ, path):
        for t, p, k in self.ext:
            if p == path:
                return Ext(k)
        key = "e%d" % (len(self.ext) + 1)
        self.ext.append((typ, path, key))
        return Ext(key)

    def sub(self, script_path, props):
        key = "s%d" % (len(self.subs) + 1)
        self.subs.append((key, [("script", self.ext_res("Script", script_path))] + list(props)))
        return Sub(key)

    def write(self, path, props):
        lines = ['[gd_resource type="Resource" script_class="%s" load_steps=%d format=3]' % (
            self.script_class, len(self.ext) + len(self.subs) + 1), ""]
        for t, p, k in self.ext:
            lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, k))
        lines.append("")
        for key, sp in self.subs:
            lines.append('[sub_resource type="Resource" id="%s"]' % key)
            for k, v in sp:
                lines.append("%s = %s" % (k, lit(v)))
            lines.append("")
        lines.append("[resource]")
        for k, v in props:
            lines.append("%s = %s" % (k, lit(v)))
        lines.append("")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))


ICONS = {}  # id -> PIL image


def icon_path(item_id):
    return "res://assets/sprites/items/%s.png" % item_id


def base_props(t, item_id, name, desc, item_type, rarity, level, stack, bonuses, price=0, unique=False):
    return [
        ("id", SN(item_id)), ("display_name", name), ("description", desc),
        ("icon", t.ext_res("Texture2D", icon_path(item_id))),
        ("item_type", item_type), ("rarity", rarity), ("item_level", level), ("unique", unique),
        ("max_stack", stack), ("stat_bonuses", bonuses), ("price", price), ("currency_value", 0),
    ]


# ----------------------------------------------------------------- writers
def hit_effects(t, specs):
    refs = []
    hit_script = t.ext_res("Script", "res://scripts/combat/hit_effect.gd")
    for spec in specs:
        if spec[0] == "steal":
            refs.append(t.sub("res://scripts/combat/life_steal_hit_effect.gd", [("percent", spec[1]), ("chance", spec[2])]))
        else:
            status, duration, power, chance = spec
            refs.append(t.sub("res://scripts/combat/status_hit_effect.gd", [
                ("status", SN(status)), ("duration", float(duration)), ("power", float(power)), ("chance", float(chance))]))
    return ("ARR", 'ExtResource("%s")' % hit_script.key, refs)


PROJECTILES = {"arrow": "res://assets/sprites/fx/arrow.png", "bolt": "res://assets/sprites/fx/magic_bolt.png",
               "fire": "res://assets/sprites/fx/fireball.png", "dark": "res://assets/sprites/fx/dark_bolt.png"}
TYPE_DEFAULTS = {  # pattern, two_handed, held_angle, grip, durability
    SW: (ARC, False, -45.0, (3, 12), 150), AX: (ARC, False, -45.0, (3, 12), 160), MC: (ARC, False, -45.0, (3, 12), 170),
    SP: (THRUST, True, -45.0, (4, 11), 150), DG: (THRUST, False, -45.0, (4, 11), 120), BW: (SHOOT, True, 0.0, (8, 8), 180),
    ST: (SHOOT, True, -45.0, (3, 12), 180), CB: (SHOOT, True, 0.0, (8, 8), 200), WD: (SHOOT, False, -45.0, (3, 12), 140),
}


def weapon(item_id, name, gender, wtype, rarity, level, dmg, speed, reach, desc, dtype=PHYS, bonuses=None,
           proj=None, proj_speed=280.0, pierce=0, blast=0.0, hits=(), knock=None, unique=False):
    pattern, two, angle, grip, dur = TYPE_DEFAULTS[wtype]
    t = Tres("WeaponItemData")
    script = t.ext_res("Script", "res://scripts/data/weapon_item_data.gd")
    props = [("script", script), ("weapon_type", wtype), ("base_damage", float(dmg)), ("attack_speed", float(speed)),
             ("reach", float(reach)), ("knockback", float(knock if knock is not None else (200 if wtype in (MC, AX) else 120))),
             ("attack_pattern", pattern), ("two_handed", two), ("damage_type", dtype)]
    if proj:
        props.append(("projectile_texture", t.ext_res("Texture2D", PROJECTILES[proj])))
    props += [("projectile_speed", float(proj_speed)), ("projectile_pierce", pierce), ("projectile_blast_radius", float(blast)),
              ("on_hit_effects", hit_effects(t, hits)), ("held_angle", angle), ("grip_pixel", ("V2",) + grip),
              ("gender", gender), ("slot_type", SN("weapon"))]
    props += base_props(t, item_id, name, desc, EQUIP, rarity, level, 1, bonuses or {}, unique=unique)
    props += [("has_durability", True), ("max_durability", dur)]
    t.write(os.path.join(DATA, "items", "equipment", item_id + ".tres"), props)


VISUALS = {"cap": ("equip_leather_cap", "head"), "helm": ("equip_iron_helm", "head"), "crown": ("equip_crown_of_shadows", "head"),
           "leather": ("equip_leather_armor", "armor"), "chain": ("equip_chainmail", "armor"), "robe": ("equip_mage_robe", "armor"),
           "lgloves": ("equip_leather_gloves", "gloves"), "gauntlets": ("equip_gauntlets", "gloves"),
           "lboots": ("equip_leather_boots", "boots"), "swift": ("equip_swift_boots", "boots")}


def equip(item_id, name, slot, rarity, level, bonuses, desc, visual=None, durability=None, set_id="", unique=False):
    t = Tres("EquipmentItemData")
    props = [("script", t.ext_res("Script", "res://scripts/data/equipment_item_data.gd")), ("slot_type", SN(slot))]
    if visual:
        sheet, layer = VISUALS[visual]
        props += [("visual_sheet", t.ext_res("Texture2D", "res://assets/sprites/player/%s.png" % sheet)), ("visual_layer", SN(layer))]
    if set_id:
        props.append(("set_id", SN(set_id)))
    props += base_props(t, item_id, name, desc, EQUIP, rarity, level, 1, bonuses, unique=unique)
    if durability:
        props += [("has_durability", True), ("max_durability", durability)]
    t.write(os.path.join(DATA, "items", "equipment", item_id + ".tres"), props)


def usable(item_id, name, rarity, level, desc, effects, stack=10, price=0, consume=True, cooldown=0.4,
           anim="use", sound="item_use"):
    t = Tres("UsableItemData")
    base = t.ext_res("Script", "res://scripts/effects/item_effect.gd")
    refs = []
    for script, fields in effects:
        resolved = []
        for k, v in fields:
            if isinstance(v, tuple) and v and v[0] == "SKILL":  # nested skill effect resource
                skill_fields = []
                for sk, sv in v[2]:
                    if isinstance(sv, tuple) and sv and sv[0] == "TEX":
                        sv = t.ext_res("Texture2D", sv[1])
                    skill_fields.append((sk, sv))
                v = t.sub(v[1], skill_fields)
            resolved.append((k, v))
        refs.append(t.sub("res://scripts/effects/%s.gd" % script, resolved))
    props = [("script", t.ext_res("Script", "res://scripts/data/usable_item_data.gd")),
             ("effects", ("ARR", 'ExtResource("%s")' % base.key, refs)), ("consume_on_use", consume),
             ("cooldown", float(cooldown)), ("use_animation", SN(anim)), ("use_sound", SN(sound))]
    props += base_props(t, item_id, name, desc, USABLE, rarity, level, stack, {}, price)
    t.write(os.path.join(DATA, "items", "usable", item_id + ".tres"), props)


def material(item_id, name, rarity, level, desc, price, stack=20):
    t = Tres("ItemData")
    props = [("script", t.ext_res("Script", "res://scripts/data/item_data.gd"))]
    props += base_props(t, item_id, name, desc, MATERIAL, rarity, level, stack, {}, price)
    t.write(os.path.join(DATA, "items", "materials", item_id + ".tres"), props)


def relic(item_id, name, rarity, level, desc, bonuses=None, heal_on_kill=0, second_chance=False, unique=False):
    t = Tres("RelicItemData")
    props = [("script", t.ext_res("Script", "res://scripts/data/relic_item_data.gd")),
             ("heal_on_kill", heal_on_kill), ("second_chance", second_chance), ("revive_percent", 0.5)]
    props += base_props(t, item_id, name, desc, RELIC, rarity, level, 1, bonuses or {}, unique=unique)
    t.write(os.path.join(DATA, "items", "relics", item_id + ".tres"), props)


def item_set(set_id, name, items, bonuses):
    t = Tres("ItemSetData")
    props = [("script", t.ext_res("Script", "res://scripts/data/item_set_data.gd")), ("id", SN(set_id)),
             ("display_name", name), ("items", ("ARR", "StringName", [SN(i) for i in items])),
             ("bonuses", {str(k): v for k, v in bonuses.items()})]
    t.write(os.path.join(DATA, "sets", set_id + ".tres"), props)


# ------------------------------------------------------------------ icons
def col(rgb, a=255):
    return (rgb[0], rgb[1], rgb[2], a)


def _img():
    im = gp.new(16, 16)
    return im, ImageDraw.Draw(im)


def ic_crossbow(wood, metal=(170, 170, 185)):
    im, d = _img()
    d.line((2, 8, 14, 8), fill=col(wood), width=2)
    d.arc((4, 2, 12, 14), 100, 260, fill=col(metal), width=2)
    d.line((5, 3, 5, 13), fill=(230, 225, 205, 255))
    d.rectangle((12, 9, 14, 12), fill=gp.shade(col(wood), 0.7))
    return im


def ic_wand(gem, shaft=(120, 80, 45)):
    im, d = _img()
    d.line((3, 13, 11, 5), fill=col(shaft), width=1)
    d.line((4, 13, 11, 6), fill=gp.shade(col(shaft), 0.7))
    d.polygon([(11, 2), (14, 5), (11, 8), (8, 5)], fill=col(gem))
    d.point((11, 4), fill=(255, 255, 255, 255))
    return im


def ic_hammer(head):
    im, d = _img()
    d.line((3, 14, 10, 7), fill=(120, 80, 40, 255), width=2)
    d.polygon([(7, 3), (11, 1), (15, 5), (11, 9)], fill=col(head))
    d.line((11, 1, 15, 5), fill=gp.shade(col(head), 1.3))
    return im


def ic_trident(head):
    im = gp.icon_spear(col(head))
    d = ImageDraw.Draw(im)
    d.line((9, 2, 12, 2), fill=col(head))
    d.line((14, 5, 14, 8), fill=col(head))
    return im


def ic_saber(blade):
    im, d = _img()
    for i in range(9):
        d.point((5 + i, 10 - i + (1 if 3 < i < 7 else 0)), fill=col(blade))
        d.point((6 + i, 10 - i + (1 if 3 < i < 7 else 0)), fill=gp.shade(col(blade), 0.75))
    d.arc((1, 9, 7, 15), 200, 340, fill=gp.GOLD_D)
    d.line((2, 13, 4, 11), fill=(100, 60, 30, 255))
    return im


def ic_hood(c):
    im, d = _img()
    d.polygon([(8, 1), (14, 9), (13, 15), (3, 15), (2, 9)], fill=col(c))
    d.ellipse((5, 7, 11, 13), fill=(30, 20, 20, 255))
    return im


def ic_plate(c):
    im = gp.icon_armor(col(c))
    d = ImageDraw.Draw(im)
    for p in ((5, 4), (11, 4), (5, 12), (11, 12)):
        d.point(p, fill=(250, 240, 200, 255))
    d.line((4, 7, 12, 7), fill=gp.shade(col(c), 0.7))
    return im


def ic_robe(c, trim=(230, 200, 90)):
    im, d = _img()
    d.polygon([(5, 2), (11, 2), (13, 15), (3, 15)], fill=col(c))
    d.line((8, 3, 8, 15), fill=col(trim))
    d.line((3, 15, 13, 15), fill=col(trim))
    return im


def ic_potion(liquid):
    return gp.icon_potion(col(liquid))


def ic_scroll(seal):
    im = gp.icon_scroll()
    d = ImageDraw.Draw(im)
    d.ellipse((7, 7, 10, 10), fill=col(seal))
    return im


def ic_bomb(body, spark=(255, 200, 60)):
    im, d = _img()
    d.ellipse((3, 5, 13, 15), fill=col(body))
    d.ellipse((5, 7, 7, 9), fill=gp.shade(col(body), 1.6))
    d.line((10, 5, 12, 2), fill=(150, 120, 80, 255))
    d.point((13, 1), fill=col(spark))
    return im


def ic_bread():
    im, d = _img()
    d.ellipse((2, 6, 14, 13), fill=(200, 140, 70, 255))
    for x in (5, 8, 11):
        d.line((x, 7, x - 1, 10), fill=(150, 95, 45, 255))
    return im


def ic_cheese():
    im, d = _img()
    d.polygon([(2, 12), (14, 12), (14, 6), (2, 10)], fill=(240, 205, 80, 255))
    d.ellipse((6, 9, 8, 11), fill=(200, 160, 50, 255))
    d.point((11, 9), fill=(200, 160, 50, 255))
    return im


def ic_meat():
    im, d = _img()
    d.ellipse((5, 3, 14, 11), fill=(170, 70, 50, 255))
    d.ellipse((7, 5, 11, 9), fill=(210, 110, 80, 255))
    d.line((2, 14, 6, 10), fill=(235, 230, 215, 255), width=2)
    return im


def ic_lockpick():
    im, d = _img()
    d.line((3, 13, 12, 4), fill=(190, 190, 205, 255))
    d.line((12, 4, 14, 4), fill=(190, 190, 205, 255))
    d.rectangle((2, 12, 4, 14), fill=(120, 80, 40, 255))
    return im


def ic_pickaxe(head):
    im, d = _img()
    d.line((4, 14, 10, 5), fill=(120, 80, 40, 255), width=2)
    d.arc((3, 1, 15, 11), 200, 340, fill=col(head), width=2)
    return im


def ic_rope_long():
    im = gp.icon_rope()
    d = ImageDraw.Draw(im)
    d.line((12, 2, 12, 15), fill=(150, 110, 60, 255))
    return im


def ic_feather(c):
    im, d = _img()
    d.polygon([(13, 1), (15, 4), (6, 13), (3, 12)], fill=col(c))
    d.line((14, 2, 2, 15), fill=gp.shade(col(c), 0.6))
    return im


def ic_talisman(c):
    im, d = _img()
    d.arc((4, 0, 12, 8), 180, 360, fill=gp.GOLD_D)
    d.polygon([(8, 5), (13, 10), (8, 15), (3, 10)], fill=col(c))
    d.point((8, 10), fill=(255, 255, 255, 255))
    return im


def ic_fang(c=(235, 230, 210)):
    im, d = _img()
    d.polygon([(4, 2), (12, 2), (9, 14), (8, 14)], fill=col(c))
    d.line((5, 3, 8, 13), fill=gp.shade(col(c), 0.75))
    return im


def ic_coin(c):
    im, d = _img()
    d.ellipse((3, 3, 13, 13), fill=col(c))
    d.ellipse((5, 5, 11, 11), outline=gp.shade(col(c), 0.7))
    d.point((8, 8), fill=(255, 255, 255, 255))
    return im


def ic_heart(c):
    im, d = _img()
    d.ellipse((2, 3, 8, 9), fill=col(c))
    d.ellipse((8, 3, 14, 9), fill=col(c))
    d.polygon([(2, 7), (14, 7), (8, 14)], fill=col(c))
    d.point((5, 5), fill=(255, 220, 220, 255))
    return im


def ic_cloth(c):
    im, d = _img()
    d.rectangle((3, 4, 13, 12), fill=col(c))
    d.line((3, 6, 13, 6), fill=gp.shade(col(c), 0.8))
    d.line((3, 10, 13, 10), fill=gp.shade(col(c), 0.8))
    return im


def ic_leather(c):
    im, d = _img()
    d.polygon([(3, 4), (12, 2), (14, 9), (9, 14), (2, 11)], fill=col(c))
    d.line((5, 6, 11, 10), fill=gp.shade(col(c), 0.7))
    return im


def ic_gel(c):
    im, d = _img()
    d.pieslice((2, 4, 14, 18), 180, 360, fill=col(c, 220))
    d.point((6, 7), fill=(255, 255, 255, 255))
    return im


def ic_orb(c):
    im, d = _img()
    d.ellipse((3, 3, 13, 13), fill=col(c))
    d.ellipse((5, 5, 9, 9), fill=gp.shade(col(c), 1.5))
    return im


def ic_ore(c):
    im, d = _img()
    d.polygon([(2, 12), (5, 4), (11, 3), (14, 10), (9, 14)], fill=(110, 100, 95, 255))
    for p in ((6, 7), (9, 6), (10, 10), (5, 11)):
        d.rectangle((p[0], p[1], p[0] + 1, p[1] + 1), fill=col(c))
    return im


SHAPES = {
    "sword": lambda c, g=None: gp.icon_sword(col(c), guard=col(g) if g else gp.GOLD_D),
    "saber": ic_saber, "dagger": lambda c: gp.icon_dagger(col(c)), "axe": lambda c: gp.icon_axe(col(c)),
    "mace": lambda c, spikes=True: gp.icon_club(col(c), spikes=spikes), "hammer": ic_hammer,
    "spear": lambda c, wide=False: gp.icon_spear(col(c), wide=wide), "trident": ic_trident,
    "bow": lambda c: gp.icon_bow(col(c)), "crossbow": ic_crossbow, "staff": lambda c: gp.icon_staff(col(c)),
    "wand": ic_wand, "helmet": lambda c: gp.icon_helmet(col(c)), "hood": ic_hood, "crown": lambda c: gp.icon_crown(col(c)),
    "armor": lambda c: gp.icon_armor(col(c)), "plate": ic_plate, "robe": ic_robe,
    "gloves": lambda c: gp.icon_gloves(col(c)), "boots": lambda c: gp.icon_boots(col(c)),
    "ring": lambda c, band=None: gp.icon_ring(col(c), band=col(band) if band else gp.GOLD_D),
    "amulet": lambda c: gp.icon_amulet(col(c)), "potion": ic_potion, "scroll": ic_scroll, "bomb": ic_bomb,
    "bread": ic_bread, "cheese": ic_cheese, "meat": ic_meat, "lockpick": ic_lockpick, "pickaxe": ic_pickaxe,
    "rope": ic_rope_long, "feather": ic_feather, "talisman": ic_talisman, "fang": ic_fang, "coin": ic_coin,
    "heart": ic_heart, "cloth": ic_cloth, "leather": ic_leather, "gel": ic_gel, "orb": ic_orb, "ore": ic_ore,
}


def icon(item_id, shape, *args):
    ICONS[item_id] = SHAPES[shape](*args)


# --------------------------------------------------------------- catalogue
def build():
    # ---- swords
    weapon("bronze_sword", "Бронзовый меч", "m", SW, C, 2, 9, 2.1, 24, "Мягкий металл, зато не ржавеет.")
    icon("bronze_sword", "sword", (205, 140, 70))
    weapon("steel_saber", "Стальная сабля", "f", SW, R, 4, 12, 2.4, 26, "Изогнутый клинок для быстрых ударов.", bonuses={"agility": 2})
    icon("steel_saber", "saber", (215, 220, 235))
    weapon("runeblade", "Рунный клинок", "m", SW, E, 7, 15, 2.1, 26, "Руны на лезвии горят фиолетовым.", dtype=MAGIC,
           bonuses={"intellect": 3, "strength": 2})
    icon("runeblade", "sword", (170, 110, 255), (90, 220, 255))
    # ---- axes
    weapon("woodsman_axe", "Топор лесоруба", "m", AX, C, 1, 9, 1.4, 22, "Рубил деревья, теперь рубит кости.")
    icon("woodsman_axe", "axe", (160, 160, 165))
    weapon("bearded_axe", "Бородовидная секира", "f", AX, R, 4, 14, 1.3, 24, "Широкое лезвие цепляет щиты.", bonuses={"strength": 2})
    icon("bearded_axe", "axe", (200, 205, 215))
    weapon("frost_axe", "Ледяная секира", "f", AX, E, 7, 18, 1.25, 24, "Изморозь не тает даже в лаве.", dtype=ICE,
           hits=[("slow", 2.0, 0.4, 0.4)], bonuses={"strength": 3})
    icon("frost_axe", "axe", (150, 220, 255))
    # ---- maces
    weapon("iron_mace", "Железная булава", "f", MC, C, 2, 10, 1.5, 20, "Простая и надёжная.", bonuses={"vitality": 1})
    icon("iron_mace", "mace", (160, 165, 175), False)
    weapon("flanged_mace", "Шестопёр", "m", MC, R, 4, 13, 1.45, 22, "Перья шестопёра мнут любые латы.", bonuses={"strength": 2}, knock=240)
    icon("flanged_mace", "mace", (190, 195, 205), True)
    weapon("holy_hammer", "Молот света", "m", MC, E, 7, 17, 1.3, 24, "Каждый удар звенит, как колокол.", dtype=MAGIC,
           hits=[("stun", 0.6, 1, 0.2)], bonuses={"res_magic": 0.1, "vitality": 2})
    icon("holy_hammer", "hammer", (255, 230, 140))
    # ---- spears
    weapon("iron_spear", "Железное копьё", "n", SP, C, 2, 10, 1.7, 40, "Держит врагов на расстоянии.")
    icon("iron_spear", "spear", (180, 180, 190))
    weapon("trident", "Трезубец", "m", SP, R, 5, 13, 1.6, 42, "Трофей утонувшего стражника.", bonuses={"agility": 2})
    icon("trident", "trident", (110, 200, 210))
    weapon("dragon_lance", "Драконье копьё", "n", SP, E, 8, 17, 1.6, 46, "Наконечник выкован из драконьей чешуи.", dtype=FIRE,
           hits=[("burn", 3.0, 4, 0.5)], bonuses={"strength": 2, "res_fire": 0.1})
    icon("dragon_lance", "spear", (255, 120, 40), True)
    # ---- daggers
    weapon("stiletto", "Стилет", "m", DG, C, 2, 6, 4.2, 18, "Узкий клинок находит щели в доспехах.", bonuses={"crit_chance": 0.04})
    icon("stiletto", "dagger", (220, 220, 230))
    weapon("kris", "Крис", "m", DG, R, 4, 8, 4.0, 18, "Волнистое лезвие оставляет рваные раны.", hits=[("bleed", 3.0, 2, 0.3)],
           bonuses={"agility": 2, "crit_chance": 0.06})
    icon("kris", "dagger", (200, 160, 90))
    # ---- bows
    weapon("longbow", "Длинный лук", "m", BW, R, 4, 12, 1.3, 260, "Тяжело натянуть, зато бьёт далеко.", proj="arrow",
           proj_speed=380, pierce=1, bonuses={"agility": 1})
    icon("longbow", "bow", (150, 105, 60))
    weapon("elven_bow", "Эльфийский лук", "m", BW, E, 7, 15, 1.8, 260, "Тетива поёт, как струна арфы.", proj="arrow",
           proj_speed=420, pierce=2, bonuses={"agility": 4, "crit_chance": 0.05})
    icon("elven_bow", "bow", (230, 220, 160))
    # ---- crossbows (new weapon type)
    weapon("light_crossbow", "Лёгкий арбалет", "m", CB, C, 2, 11, 1.0, 240, "Медленно перезаряжается, но болт летит прямо.",
           proj="arrow", proj_speed=420)
    icon("light_crossbow", "crossbow", (140, 95, 55))
    weapon("heavy_crossbow", "Тяжёлый арбалет", "m", CB, R, 5, 18, 0.7, 260, "Болт пробивает двоих и отбрасывает.",
           proj="arrow", proj_speed=460, pierce=2, knock=220)
    icon("heavy_crossbow", "crossbow", (90, 65, 45), (120, 125, 140))
    weapon("repeater", "Многозарядный арбалет", "m", CB, E, 7, 11, 2.4, 240, "Механизм гномов: болт за болтом.",
           proj="arrow", proj_speed=440, pierce=1, bonuses={"crit_chance": 0.05, "agility": 2})
    icon("repeater", "crossbow", (170, 130, 70), (230, 200, 90))
    # ---- staffs
    weapon("thorn_staff", "Посох шипов", "m", ST, R, 4, 10, 1.3, 180, "Снаряды отравляют врагов.", dtype=POISON, proj="bolt",
           proj_speed=230, hits=[("poison", 4.0, 3, 0.6)], bonuses={"intellect": 3})
    icon("thorn_staff", "staff", (110, 220, 80))
    weapon("frost_staff", "Посох стужи", "m", ST, R, 5, 11, 1.2, 190, "Ледяные стрелы замедляют.", dtype=ICE, proj="bolt",
           proj_speed=240, hits=[("slow", 2.5, 0.5, 0.5)], bonuses={"intellect": 3, "max_mana": 10})
    icon("frost_staff", "staff", (150, 220, 255))
    # ---- wands (new weapon type)
    weapon("apprentice_wand", "Жезл ученика", "m", WD, C, 1, 5, 2.4, 160, "Лёгкий жезл для первых заклинаний.", dtype=MAGIC,
           proj="bolt", proj_speed=260, bonuses={"intellect": 1})
    icon("apprentice_wand", "wand", (140, 170, 255))
    weapon("fire_wand", "Огненный жезл", "m", WD, R, 4, 8, 2.2, 170, "Искры поджигают всё вокруг.", dtype=FIRE, proj="fire",
           proj_speed=250, blast=14, hits=[("burn", 3.0, 3, 0.3)], bonuses={"intellect": 2})
    icon("fire_wand", "wand", (255, 120, 40), (90, 55, 35))
    weapon("storm_wand", "Жезл бури", "m", WD, E, 7, 10, 2.6, 200, "Молнии прошивают врагов насквозь.", dtype=MAGIC,
           proj="bolt", proj_speed=340, pierce=2, bonuses={"intellect": 4, "crit_chance": 0.05})
    icon("storm_wand", "wand", (230, 230, 120), (70, 70, 90))
    # ---- legendary uniques
    weapon("sun_blade", "Солнечный клинок", "m", SW, L, 10, 21, 2.1, 28, "Выкован в день, когда солнце ещё светило в подземелье.",
           dtype=FIRE, hits=[("burn", 3.0, 6, 0.6)], bonuses={"strength": 4, "max_hp": 20}, unique=True)
    icon("sun_blade", "sword", (255, 200, 60), (255, 120, 30))
    weapon("frost_heart", "Сердце стужи", "n", ST, L, 10, 16, 1.4, 200, "Посох, внутри которого бьётся ледяное сердце.",
           dtype=ICE, proj="bolt", proj_speed=260, blast=30, hits=[("slow", 3.0, 0.6, 1.0)],
           bonuses={"intellect": 6, "max_mana": 30}, unique=True)
    icon("frost_heart", "staff", (180, 240, 255))
    weapon("viper_sting", "Жало гадюки", "n", DG, L, 9, 11, 4.5, 19, "Яд гадюки-королевы не знает противоядия.", dtype=POISON,
           hits=[("poison", 5.0, 5, 1.0)], bonuses={"agility": 5, "crit_chance": 0.08}, unique=True)
    icon("viper_sting", "dagger", (80, 255, 90))
    weapon("bloodthirster", "Кровопийца", "m", AX, L, 10, 24, 1.3, 25, "Топор пьёт кровь врагов и делится ею с хозяином.",
           hits=[("steal", 0.12, 1.0)], bonuses={"strength": 5, "vitality": 3}, unique=True)
    icon("bloodthirster", "axe", (200, 30, 40))

    # ---- armor sets
    equip("wanderer_hood", "Капюшон странника", "helmet", C, 2, {"armor": 1, "agility": 1}, "Глубокий капюшон прячет лицо.",
          "cap", 70, "wanderer")
    icon("wanderer_hood", "hood", (110, 120, 90))
    equip("wanderer_coat", "Куртка странника", "chest", C, 2, {"armor": 3, "agility": 1}, "Много карманов, мало веса.",
          "leather", 80, "wanderer")
    icon("wanderer_coat", "armor", (120, 110, 80))
    equip("wanderer_gloves", "Перчатки странника", "gloves", C, 2, {"armor": 1, "agility": 1}, "Тонкая кожа не мешает пальцам.",
          "lgloves", 70, "wanderer")
    icon("wanderer_gloves", "gloves", (130, 115, 85))
    equip("wanderer_boots", "Сапоги странника", "boots", C, 2, {"armor": 1, "speed": 6}, "Стоптаны тысячей дорог.",
          "lboots", 70, "wanderer")
    icon("wanderer_boots", "boots", (110, 95, 70))
    item_set("wanderer", "Странник", ["wanderer_hood", "wanderer_coat", "wanderer_gloves", "wanderer_boots"],
             {2: {"speed": 6}, 3: {"agility": 2}, 4: {"crit_chance": 0.05}})

    equip("guardian_helm", "Шлем стража", "helmet", R, 5, {"armor": 5, "vitality": 1}, "Забрало в форме львиной пасти.",
          "helm", 150, "guardian")
    icon("guardian_helm", "helmet", (190, 195, 210))
    equip("guardian_plate", "Латы стража", "chest", R, 5, {"armor": 10, "vitality": 2, "speed": -4}, "Тяжёлые, но удар держат.",
          "chain", 180, "guardian")
    icon("guardian_plate", "plate", (185, 190, 205))
    equip("guardian_gauntlets", "Рукавицы стража", "gloves", R, 5, {"armor": 3, "strength": 1}, "Стальные пластины на каждом пальце.",
          "gauntlets", 150, "guardian")
    icon("guardian_gauntlets", "gloves", (180, 185, 200))
    equip("guardian_greaves", "Поножи стража", "boots", R, 5, {"armor": 3, "vitality": 1, "speed": -2}, "Гремят на каждом шаге.",
          "lboots", 150, "guardian")
    icon("guardian_greaves", "boots", (170, 175, 190))
    item_set("guardian", "Страж", ["guardian_helm", "guardian_plate", "guardian_gauntlets", "guardian_greaves"],
             {2: {"armor": 4}, 3: {"max_hp": 25}, 4: {"res_fire": 0.1, "res_ice": 0.1, "res_poison": 0.1, "res_magic": 0.1}})

    equip("sorcerer_hat", "Шляпа чародея", "helmet", R, 4, {"intellect": 2, "max_mana": 10}, "Звёзды на полях складываются в руны.",
          "cap", 90, "sorcerer")
    icon("sorcerer_hat", "hood", (80, 70, 170))
    equip("sorcerer_robe", "Мантия чародея", "chest", R, 4, {"armor": 2, "intellect": 3, "max_mana": 15}, "Шёлк, пропитанный маной.",
          "robe", 100, "sorcerer")
    icon("sorcerer_robe", "robe", (80, 70, 170))
    equip("sorcerer_gloves", "Перчатки чародея", "gloves", R, 4, {"intellect": 2, "res_magic": 0.05}, "Пальцы покалывает от силы.",
          "lgloves", 90, "sorcerer")
    icon("sorcerer_gloves", "gloves", (90, 80, 180))
    item_set("sorcerer", "Чародей", ["sorcerer_hat", "sorcerer_robe", "sorcerer_gloves"],
             {2: {"max_mana": 20}, 3: {"intellect": 4, "res_magic": 0.1}})

    equip("eclipse_helm", "Шлем Затмения", "helmet", E, 8, {"armor": 5, "crit_chance": 0.03}, "Чёрный металл поглощает свет.",
          "crown", 200, "eclipse")
    icon("eclipse_helm", "helmet", (70, 40, 110))
    equip("eclipse_armor", "Доспех Затмения", "chest", E, 8, {"armor": 9, "strength": 2, "agility": 2}, "Лёгкий, как тень.",
          "chain", 220, "eclipse")
    icon("eclipse_armor", "plate", (80, 45, 120))
    equip("eclipse_gloves", "Перчатки Затмения", "gloves", E, 8, {"armor": 3, "crit_chance": 0.03}, "Пальцы не дрожат никогда.",
          "gauntlets", 200, "eclipse")
    icon("eclipse_gloves", "gloves", (85, 50, 125))
    equip("eclipse_boots", "Сапоги Затмения", "boots", E, 8, {"armor": 2, "speed": 10}, "Шаги в них не слышны.",
          "swift", 200, "eclipse")
    icon("eclipse_boots", "boots", (75, 45, 115))
    item_set("eclipse", "Затмение", ["eclipse_helm", "eclipse_armor", "eclipse_gloves", "eclipse_boots"],
             {2: {"crit_chance": 0.05}, 3: {"damage": 3}, 4: {"strength": 3, "res_fire": 0.1, "res_ice": 0.1, "res_poison": 0.1, "res_magic": 0.1}})

    # ---- more armor
    equip("cloth_hood", "Тканевый капюшон", "helmet", C, 1, {"intellect": 1, "max_mana": 5}, "Защищает от сквозняка, не от меча.", "cap", 60)
    icon("cloth_hood", "hood", (150, 140, 120))
    equip("iron_greaves", "Железные поножи", "boots", C, 3, {"armor": 3, "speed": -2}, "Крепкие и тяжёлые.", "lboots", 120)
    icon("iron_greaves", "boots", (150, 150, 160))
    equip("ember_cloak", "Плащ углей", "chest", R, 5, {"armor": 4, "res_fire": 0.25}, "Пахнет дымом и не горит.", "robe", 120)
    icon("ember_cloak", "robe", (170, 60, 30), (255, 160, 60))
    equip("plate_armor", "Латный доспех", "chest", R, 6, {"armor": 14, "vitality": 2, "speed": -8}, "Неприступен, как крепость.", "chain", 220)
    icon("plate_armor", "plate", (200, 205, 215))
    equip("leaping_boots", "Сапоги прыгуна", "boots", E, 6, {"armor": 2, "agility": 2, "extra_jumps": 1}, "Позволяют оттолкнуться прямо от воздуха.",
          "swift", 150)
    icon("leaping_boots", "boots", (90, 200, 180))

    # ---- rings and amulets
    equip("iron_ring", "Железное кольцо", "ring", C, 2, {"armor": 1, "strength": 1}, "Грубое, но крепкое.")
    icon("iron_ring", "ring", (160, 160, 170), (120, 120, 130))
    equip("ring_of_precision", "Кольцо меткости", "ring", R, 4, {"crit_chance": 0.06}, "Глаз видит слабые места.")
    icon("ring_of_precision", "ring", (255, 230, 90))
    equip("ring_of_regeneration", "Кольцо восстановления", "ring", R, 5, {"hp_regen": 1.0}, "Раны затягиваются сами.")
    icon("ring_of_regeneration", "ring", (90, 230, 120))
    equip("ring_of_haste", "Кольцо проворства", "ring", R, 4, {"speed": 15}, "Ноги сами несут вперёд.")
    icon("ring_of_haste", "ring", (120, 210, 255))
    equip("ring_of_fortune", "Кольцо удачи", "ring", R, 3, {"gold_find": 0.25}, "Монеты так и липнут к рукам.")
    icon("ring_of_fortune", "ring", (240, 200, 60), (200, 160, 40))
    equip("flame_amulet", "Огненный амулет", "amulet", R, 4, {"res_fire": 0.25, "max_hp": 10}, "Тёплый камень гасит жар.")
    icon("flame_amulet", "amulet", (255, 110, 40))
    equip("serpent_amulet", "Змеиный амулет", "amulet", R, 3, {"res_poison": 0.3}, "Змея кусает свой хвост — и яд ей не страшен.")
    icon("serpent_amulet", "amulet", (90, 200, 80))
    equip("feather_amulet", "Амулет пера", "amulet", E, 6, {"extra_jumps": 1, "agility": 2}, "Лёгкий, как пух: можно прыгнуть ещё раз в воздухе.")
    icon("feather_amulet", "amulet", (220, 230, 255))

    # ---- consumables
    usable("small_health_potion", "Малое зелье лечения", C, 1, "Глоток, чтобы дотянуть до следующей комнаты.",
           [("heal_effect", [("amount", 18), ("percent", 0.0)])], stack=15, price=12, cooldown=0.3, sound="potion_drink")
    icon("small_health_potion", "potion", (230, 80, 90))
    usable("mana_potion", "Зелье маны", C, 1, "Синяя жидкость пахнет грозой.",
           [("mana_effect", [("amount", 30)])], stack=10, price=20, cooldown=0.3, sound="potion_drink")
    icon("mana_potion", "potion", (70, 110, 240))
    usable("speed_potion", "Зелье скорости", R, 2, "Сердце стучит вдвое чаще.",
           [("buff_item_effect", [("key", "speed"), ("bonuses", {"speed": 35}), ("duration", 20.0), ("tint", ("COL", 0.7, 0.9, 1.0, 1.0))])],
           stack=5, price=45, sound="potion_drink")
    icon("speed_potion", "potion", (90, 220, 255))
    usable("strength_potion", "Зелье силы", R, 3, "Мышцы наливаются сталью.",
           [("buff_item_effect", [("key", "strength"), ("bonuses", {"strength": 4, "damage": 2}), ("duration", 30.0), ("tint", ("COL", 1.0, 0.75, 0.6, 1.0))])],
           stack=5, price=55, sound="potion_drink")
    icon("strength_potion", "potion", (230, 120, 40))
    usable("defense_potion", "Зелье защиты", R, 3, "Кожа становится твёрдой, как кора.",
           [("buff_item_effect", [("key", "defense"), ("bonuses", {"armor": 10}), ("duration", 30.0), ("tint", ("COL", 0.8, 0.85, 1.0, 1.0))])],
           stack=5, price=55, sound="potion_drink")
    icon("defense_potion", "potion", (160, 165, 185))
    usable("invisibility_potion", "Зелье невидимости", R, 4, "Монстры не видят вас, пока вы не нападёте или не столкнётесь с ними.",
           [("status_self_effect", [("status", SN("invisible")), ("duration", 12.0), ("power", 1.0)])], stack=3, price=80, sound="potion_drink")
    icon("invisibility_potion", "potion", (210, 220, 240))
    usable("teleport_scroll", "Свиток телепорта", R, 2, "Переносит в случайное безопасное место этажа.",
           [("teleport_effect", [("to_exit", False)])], stack=5, price=50, anim="attack_cast", sound="portal")
    icon("teleport_scroll", "scroll", (160, 90, 230))
    usable("portal_scroll", "Свиток возврата", R, 5, "Мгновенно переносит к двери на следующий этаж.",
           [("teleport_effect", [("to_exit", True)])], stack=3, price=120, anim="attack_cast", sound="portal")
    icon("portal_scroll", "scroll", (80, 200, 230))
    usable("fireball_scroll", "Свиток огненного шара", R, 3, "Заклинание для тех, кто не учился магии.",
           [("cast_skill_effect", [("level", 2), ("skill_effect", ("SKILL", "res://scripts/skills/projectile_skill.gd", [
               ("texture", ("TEX", "res://assets/sprites/fx/fireball.png")), ("speed", 240.0), ("damage_multiplier", 2.5),
               ("damage_per_level", 0.4), ("count", 1), ("blast_radius", 30.0), ("damage_type", FIRE), ("color", ("COL", 1.0, 0.5, 0.15, 1.0))]))])],
           stack=5, price=45, anim="attack_cast", sound="skill_cast")
    icon("fireball_scroll", "scroll", (240, 90, 40))
    usable("detection_scroll", "Свиток обнаружения", C, 2, "Карта этажа проступает на пергаменте.",
           [("detect_effect", [("duration", 30.0)])], stack=5, price=35, anim="attack_cast", sound="skill_cast")
    icon("detection_scroll", "scroll", (90, 200, 120))
    usable("healing_scroll", "Свиток исцеления", R, 3, "Молитва, записанная святым отшельником.",
           [("heal_effect", [("amount", 10), ("percent", 0.5)])], stack=5, price=60, anim="attack_cast", sound="skill_cast")
    icon("healing_scroll", "scroll", (255, 230, 120))
    usable("fire_bomb", "Огненная бомба", R, 2, "Поджигает всё в радиусе взрыва. Стены не ломает.",
           [("throw_bomb_effect", [("damage", 35), ("radius_tiles", 2.4), ("damage_type", FIRE), ("status", SN("burn")),
                                   ("status_duration", 4.0), ("status_power", 4.0), ("breaks_tiles", False), ("color", ("COL", 1.0, 0.45, 0.1, 1.0))])],
           stack=10, price=30, anim="attack_quick")
    icon("fire_bomb", "bomb", (170, 50, 30))
    usable("ice_bomb", "Ледяная бомба", R, 3, "Замораживает врагов: они еле двигаются.",
           [("throw_bomb_effect", [("damage", 25), ("radius_tiles", 2.6), ("damage_type", ICE), ("status", SN("slow")),
                                   ("status_duration", 4.0), ("status_power", 0.6), ("breaks_tiles", False), ("color", ("COL", 0.6, 0.85, 1.0, 1.0))])],
           stack=10, price=35, anim="attack_quick")
    icon("ice_bomb", "bomb", (80, 150, 210))
    usable("poison_bomb", "Ядовитая бомба", R, 3, "Облако яда разъедает врагов изнутри.",
           [("throw_bomb_effect", [("damage", 15), ("radius_tiles", 2.8), ("damage_type", POISON), ("status", SN("poison")),
                                   ("status_duration", 6.0), ("status_power", 4.0), ("breaks_tiles", False), ("color", ("COL", 0.5, 0.9, 0.3, 1.0))])],
           stack=10, price=35, anim="attack_quick")
    icon("poison_bomb", "bomb", (70, 140, 50))
    usable("sticky_bomb", "Липкая бомба", C, 2, "Прилипает к первой поверхности — удобно для стен и потолка.",
           [("throw_bomb_effect", [("damage", 40), ("radius_tiles", 2.2), ("sticky", True), ("breaks_tiles", True)])],
           stack=10, price=20, anim="attack_quick")
    icon("sticky_bomb", "bomb", (110, 90, 50))
    usable("bread", "Хлеб", C, 1, "Чёрствый, но сытный.",
           [("status_self_effect", [("status", SN("regen")), ("duration", 10.0), ("power", 1.0)])], stack=10, price=8)
    icon("bread", "bread")
    usable("cheese", "Сыр", C, 1, "Пахнет так, что монстры оборачиваются.",
           [("status_self_effect", [("status", SN("regen")), ("duration", 8.0), ("power", 2.0)])], stack=10, price=10)
    icon("cheese", "cheese")
    usable("roast_meat", "Жареное мясо", C, 2, "Горячее и сочное.",
           [("heal_effect", [("amount", 25), ("percent", 0.0)]), ("status_self_effect", [("status", SN("regen")), ("duration", 6.0), ("power", 2.0)])],
           stack=10, price=18)
    icon("roast_meat", "meat")
    usable("lockpick", "Отмычка", C, 1, "Можно вскрыть запертый сундук — если повезёт.",
           [("unlock_effect", [("range_px", 40.0), ("success_chance", 0.6)])], stack=10, price=15, anim="interact")
    icon("lockpick", "lockpick")
    usable("long_rope", "Длинная верёвка", C, 2, "Вдвое длиннее обычной.",
           [("rope_effect", [("max_length", 18)])], stack=5, price=18)
    icon("long_rope", "rope")
    usable("steel_pickaxe", "Стальная кирка", R, 3, "Достаёт кирпич через одну клетку.",
           [("dig_effect", [("reach_tiles", 2), ("bricks_per_use", 1)])], stack=1, price=70, consume=False, cooldown=0.3, anim="attack_slash")
    icon("steel_pickaxe", "pickaxe", (200, 205, 215))
    usable("mithril_pickaxe", "Мифриловая кирка", E, 6, "Прорубает тоннель в три кирпича за удар.",
           [("dig_effect", [("reach_tiles", 3), ("bricks_per_use", 3)])], stack=1, price=200, consume=False, cooldown=0.3, anim="attack_slash")
    icon("mithril_pickaxe", "pickaxe", (170, 230, 255))

    # ---- relics (work from the backpack)
    relic("jumper_talisman", "Талисман прыгуна", R, 4, "Можно оттолкнуться от воздуха ещё раз.", {"extra_jumps": 1})
    icon("jumper_talisman", "talisman", (120, 220, 255))
    relic("wolf_fang", "Клык волка", R, 5, "Каждая победа придаёт сил.", heal_on_kill=4)
    icon("wolf_fang", "fang")
    relic("lucky_coin", "Счастливая монета", R, 3, "Всегда падает орлом. Монстры роняют больше золота.", {"gold_find": 0.3})
    icon("lucky_coin", "coin", (255, 215, 70))
    relic("golem_heart", "Сердце голема", E, 7, "Каменное сердце медленно стучит рядом с вашим.", {"max_hp": 30, "hp_regen": 0.8})
    icon("golem_heart", "heart", (150, 140, 130))
    relic("phoenix_feather", "Перо феникса", L, 9, "Второй шанс: при гибели вы восстанете, а перо сгорит.", second_chance=True, unique=True)
    icon("phoenix_feather", "feather", (255, 140, 40))

    # ---- materials (crafting and selling)
    material("leather_scrap", "Обрывки кожи", C, 1, "Пригодятся для ремонта и ремесла.", 5)
    icon("leather_scrap", "leather", (140, 90, 50))
    material("cloth_roll", "Рулон ткани", C, 1, "Прочная ткань из заброшенной кладовой.", 6)
    icon("cloth_roll", "cloth", (190, 170, 130))
    material("slime_gel", "Слизь", C, 1, "Липкая и подозрительно тёплая.", 4)
    icon("slime_gel", "gel", (110, 220, 120))
    material("monster_fang", "Клык чудовища", C, 2, "Острый трофей. Алхимики платят за такие.", 10)
    icon("monster_fang", "fang", (220, 210, 190))
    material("gold_ore", "Золотая руда", R, 3, "Блестит даже без света.", 25)
    icon("gold_ore", "ore", (250, 210, 60))
    material("ember_essence", "Эссенция углей", R, 4, "Сгусток огня в стеклянном шаре.", 40)
    icon("ember_essence", "orb", (255, 110, 40))
    material("frost_essence", "Эссенция стужи", R, 4, "От шара тянет холодом.", 40)
    icon("frost_essence", "orb", (130, 210, 255))
    material("moon_crystal", "Лунный кристалл", R, 5, "Светится мягким голубым светом.", 60)
    icon("moon_crystal", "orb", (170, 180, 255))


def main():
    build()
    for item_id, im in ICONS.items():
        gp.save(im, "sprites/items/%s.png" % item_id)
    print("items generated: %d" % len(ICONS))


if __name__ == "__main__":
    main()
