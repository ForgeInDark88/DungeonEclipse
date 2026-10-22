#!/usr/bin/env python3
"""Generates data/loot_tables/*.tres from the items in data/items/.

All loot balance lives in TABLES below: per table the number of rolls, the
rarity weights on floor 1, their growth per floor, the first floor of each
rarity, the item-level bonus (better chests) and which item groups it holds.
Items take part by their own data: rarity, item_level, unique, item_type.
Run after adding items, then check the balance:
    python3 tools/gen_loot_tables.py
    godot --headless --path . res://tests/loot_sim.tscn   (writes docs/BALANCE.md)
"""
from __future__ import annotations

import glob
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "loot_tables")
NEVER = 99  # rarity_min_floor for "never from this table"

# Rarity order: common, rare, epic, legendary.
TABLES = {
    # Wooden chest: weak loot, one item, sometimes a supply.
    "chest_common": dict(rolls=(1, 1), weights=[85, 14, 0.5, 0], per_floor=[0, 2.5, 1.0, 0],
                         min_floor=[1, 1, 5, NEVER], bonus=0.0, groups={"gear": 1.0, "material": 0.4},
                         extra=["supplies_small"], gold=(5, 15)),
    # Iron chest: better odds, +1 item level.
    "chest_rare": dict(rolls=(1, 2), weights=[65, 32, 1.5, 0], per_floor=[0, 3.0, 1.5, 0],
                       min_floor=[1, 1, 4, NEVER], bonus=1.0, groups={"gear": 1.0, "material": 0.3},
                       extra=["supplies_small"], gold=(15, 35)),
    # Golden chest: the best of what this floor allows (+2 levels), legendary only deep.
    "chest_epic": dict(rolls=(1, 2), weights=[35, 55, 6, 0], per_floor=[0, 3.0, 3.0, 0.15],
                       min_floor=[1, 1, 3, 8], bonus=2.0, groups={"gear": 1.0, "unique": 0.5},
                       extra=["supplies"], gold=(40, 90)),
    "enemy_common": dict(rolls=(1, 1), weights=[88, 11, 0.3, 0], per_floor=[0, 2.0, 0.6, 0],
                         min_floor=[1, 1, 6, NEVER], bonus=0.0, groups={"gear": 0.6, "supply": 1.0, "material": 1.2},
                         extra=[], gold=(0, 0)),
    "enemy_rare": dict(rolls=(1, 2), weights=[70, 27, 1.5, 0], per_floor=[0, 3.0, 1.2, 0.08],
                       min_floor=[1, 1, 5, 9], bonus=1.0, groups={"gear": 1.0, "supply": 0.6, "material": 0.6, "unique": 0.3},
                       extra=[], gold=(0, 0)),
    "merchant": dict(rolls=(2, 3), weights=[50, 42, 4, 0], per_floor=[0, 3.0, 1.5, 0],
                     min_floor=[1, 1, 4, NEVER], bonus=1.0, groups={"gear": 1.0, "supply": 0.5},
                     extra=[], gold=(0, 0)),
    # Boss reward chest: strong, the main source of legendary items.
    "boss": dict(rolls=(2, 2), weights=[0, 45, 45, 6], per_floor=[0, 0, 3.0, 0.8],
                 min_floor=[1, 1, 1, 5], bonus=3.0, groups={"gear": 1.0, "unique": 1.0},
                 extra=["supplies"], gold=(80, 160)),
    # Special rooms (altar, prisoner, cursed chest).
    "special": dict(rolls=(1, 1), weights=[20, 60, 18, 1.5], per_floor=[0, 2.0, 2.0, 0.3],
                    min_floor=[1, 1, 3, 4], bonus=2.0, groups={"gear": 1.0, "unique": 0.6},
                    extra=[], gold=(20, 50)),
    # Supplies are rolled separately from gear, so a chest is never "only potions".
    "supplies": dict(rolls=(1, 1), weights=[70, 28, 2, 0], per_floor=[0, 2.0, 0.5, 0],
                     min_floor=[1, 1, 4, NEVER], bonus=1.0, groups={"supply": 1.0}, extra=[], gold=(0, 0)),
    "supplies_small": dict(rolls=(0, 1), weights=[80, 20, 0, 0], per_floor=[0, 2.0, 0, 0],
                           min_floor=[1, 1, NEVER, NEVER], bonus=0.0, groups={"supply": 1.0}, extra=[], gold=(0, 0)),
}
# Never dropped from tables: currency and boss / elite trophies.
EXCLUDE = {"gold_coin", "eclipse_shard", "guardian_seal"}
# Supplies that come in stacks.
STACKS = {"bomb": (1, 2), "rope": (1, 2), "health_potion": (1, 2), "mana_crystal": (1, 2), "bone": (1, 3), "iron_ore": (1, 2)}


def read_items():
    items = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "items", "**", "*.tres"), recursive=True)):
        s = open(path, encoding="utf-8").read()
        res = s.split("[resource]", 1)[1]

        def val(key, default):
            m = re.search(r"^%s = (.*)$" % key, res, re.M)
            return m.group(1) if m else default
        item_id = re.search(r'^id = &"(\w+)"', res, re.M).group(1)
        if item_id in EXCLUDE:
            continue
        item_type = int(val("item_type", "0"))
        unique = val("unique", "false") == "true"
        group = "unique" if unique else {0: "gear", 1: "supply", 2: "material"}[item_type]
        items.append(dict(id=item_id, path="res://" + os.path.relpath(path, ROOT).replace(os.sep, "/"),
                          rarity=int(val("rarity", "0")), level=int(val("item_level", "1")), group=group))
    return items


def fmt_floats(values):
    return "Array[float]([%s])" % ", ".join("%.2f" % v for v in values)


def fmt_ints(values):
    return "Array[int]([%s])" % ", ".join(str(v) for v in values)


def write_table(name, cfg, items):
    chosen = [it for it in items if it["group"] in cfg["groups"]]
    ext = ['[ext_resource type="Script" path="res://scripts/data/loot_table.gd" id="table"]',
           '[ext_resource type="Script" path="res://scripts/data/loot_entry.gd" id="entry"]']
    subs = []
    refs = []
    for it in chosen:
        ext.append('[ext_resource type="Resource" path="%s" id="i_%s"]' % (it["path"], it["id"]))
        lo, hi = STACKS.get(it["id"], (1, 1))
        subs.append("\n".join([
            '[sub_resource type="Resource" id="e_%s"]' % it["id"],
            'script = ExtResource("entry")',
            'item = ExtResource("i_%s")' % it["id"],
            "weight = %.2f" % cfg["groups"][it["group"]],
            "min_count = %d" % lo,
            "max_count = %d" % hi,
            "min_floor = 1",
            "max_floor = 0",
        ]))
        refs.append('SubResource("e_%s")' % it["id"])
    for x in cfg["extra"]:
        ext.append('[ext_resource type="Resource" path="res://data/loot_tables/%s.tres" id="x_%s"]' % (x, x))
    lines = ['[gd_resource type="Resource" script_class="LootTable" load_steps=%d format=3]' % (len(ext) + len(subs) + 1), ""]
    lines += ext + [""]
    for sub in subs:
        lines += [sub, ""]
    lines += [
        "[resource]",
        'script = ExtResource("table")',
        "rolls_min = %d" % cfg["rolls"][0],
        "rolls_max = %d" % cfg["rolls"][1],
        "rarity_weights = " + fmt_floats(cfg["weights"]),
        "rarity_per_floor = " + fmt_floats(cfg["per_floor"]),
        "rarity_min_floor = " + fmt_ints(cfg["min_floor"]),
        "item_level_base = 1.0",
        "item_level_per_floor = 0.75",
        "item_level_bonus = %.1f" % cfg["bonus"],
        'entries = Array[ExtResource("entry")]([%s])' % ", ".join(refs),
        'extra_tables = Array[ExtResource("table")]([%s])' % ", ".join('ExtResource("x_%s")' % x for x in cfg["extra"]),
        "gold_min = %d" % cfg["gold"][0],
        "gold_max = %d" % cfg["gold"][1],
        "",
    ]
    with open(os.path.join(OUT, name + ".tres"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return len(chosen)


def main():
    items = read_items()
    for name, cfg in TABLES.items():
        n = write_table(name, cfg, items)
        print("%-15s %3d entries" % (name, n))


if __name__ == "__main__":
    main()
