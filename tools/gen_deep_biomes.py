#!/usr/bin/env python3
"""Two deep biomes beyond floor 15: the Ashen Halls and the Crystal Depths.

Generates only the new art (tilesets + parallax) and writes the two .tres
files, reusing existing decoration textures. Run from tools/.
"""
from __future__ import annotations

import os

import gen_biomes as gb

# ----------------------------------------------------------------- palettes
# Ashen Halls: a drowned-in-ash necropolis, grey violet, dying embers.
ASHEN = dict(stone=(98, 86, 96), bedrock=(42, 34, 44), mortar=(54, 44, 52), back=(68, 56, 66),
             top=(210, 150, 110), top_kind="dust", ore=(250, 160, 90), ore_glow=(255, 190, 120),
             wood=(110, 80, 64), sky=(34, 28, 40), far=(52, 42, 54), mid=(72, 58, 70), near=(94, 76, 88),
             accent=(230, 140, 90))
# Crystal Depths: sunless teal grottoes, growing cold crystals.
CRYSTAL = dict(stone=(54, 80, 92), bedrock=(22, 36, 44), mortar=(28, 44, 52), back=(38, 62, 70),
               top=(140, 230, 230), top_kind="crystal", ore=(120, 230, 240), ore_glow=(180, 250, 255),
               wood=(90, 100, 90), sky=(16, 30, 38), far=(28, 50, 60), mid=(40, 68, 78), near=(54, 88, 96),
               accent=(120, 220, 220))

# Decor reuses existing textures: (name, placement 0 floor / 1 ceiling / 2 wall, weight, light, unshaded, sway)
ASHEN_DECOR = [("charred_bones", 0, 1.5, None, False, False), ("urn", 0, 1.2, None, False, False),
               ("obsidian", 0, 1.0, (1.0, 0.5, 0.25), True, False), ("wall_shackles", 2, 1.0, None, False, False),
               ("tombstone", 0, 0.8, None, False, False), ("wall_lava_crack", 2, 1.0, (1.0, 0.45, 0.2), True, False),
               ("candles", 0, 0.8, (1.0, 0.8, 0.4), True, False)]
CRYSTAL_DECOR = [("crystals", 0, 1.8, (0.6, 1.0, 1.0), True, False), ("rune_crystal", 0, 1.2, (0.7, 1.0, 1.0), True, False),
                 ("mushroom_cluster", 0, 0.8, (0.5, 1.0, 0.95), True, False), ("wall_fungi", 2, 1.0, (0.6, 0.9, 1.0), True, False),
                 ("puffball", 0, 1.0, (0.7, 1.0, 1.0), True, False), ("wall_ivy", 2, 0.8, None, False, False)]

BIOME_META = {
    "ashen_halls": ("Пепельные чертоги", 5, None, ASHEN, ASHEN_DECOR,
                    dict(music="catacombs", particle="sparks", ore="iron_ore",
                         ambient="Color(0.92, 0.86, 0.92, 1)", back_mod="Color(0.8, 0.74, 0.8, 1)",
                         torch="Color(1.0, 0.62, 0.35, 1)", particles="Color(0.9, 0.7, 0.55, 1)",
                         fog="Color(0.45, 0.36, 0.44, 1)", fog_amount="0.12", tint="Color(1.0, 0.94, 0.9, 1)",
                         contrast="1.02", per_room="4.5", ore_chance="0.05")),
    "crystal_depths": ("Кристальные глубины", 6, None, CRYSTAL, CRYSTAL_DECOR,
                       dict(music="mirror_halls", particle="sparkles", ore="moon_crystal",
                            ambient="Color(0.88, 0.96, 1, 1)", back_mod="Color(0.74, 0.86, 0.9, 1)",
                            torch="Color(0.6, 0.9, 1, 1)", particles="Color(0.75, 0.95, 1, 1)",
                            fog="Color(0.3, 0.5, 0.6, 1)", fog_amount="0.1", tint="Color(0.95, 1.0, 1.02, 1)",
                            contrast="1.06", per_room="5.0", ore_chance="0.05")),
}


def write_tres(bid: str, title: str, order: int, decor, m: dict) -> None:
    ext = ['[ext_resource type="Script" path="res://scripts/data/decor_data.gd" id="decor_script"]',
           '[ext_resource type="Script" path="res://scripts/data/biome_data.gd" id="biome_script"]',
           '[ext_resource type="Texture2D" path="res://assets/sprites/tiles/tiles_%s.png" id="tiles"]' % bid]
    for layer in ("far", "mid", "near"):
        ext.append('[ext_resource type="Texture2D" path="res://assets/sprites/backgrounds/%s_%s.png" id="bg_%s"]' % (bid, layer, layer))
    subs = []
    for name, placement, weight, light, unshaded, sway in decor:
        ext.append('[ext_resource type="Texture2D" path="res://assets/sprites/decor/%s.png" id="dx_%s"]' % (name, name))
        subs.append(gb._decor_sub("Decor_" + name, "dx_" + name, placement, weight, light, unshaded, sway))
    res = """[resource]
script = ExtResource("biome_script")
music = &"%(music)s"
step_sound = &"step_stone"
id = &"%(bid)s"
display_name = "%(title)s"
order = %(order)d
tileset_texture = ExtResource("tiles")
parallax_far = ExtResource("bg_far")
parallax_mid = ExtResource("bg_mid")
parallax_near = ExtResource("bg_near")
ambient = %(ambient)s
back_wall_modulate = %(back_mod)s
torch_color = %(torch)s
ambient_particles = %(particles)s
particle_style = &"%(particle)s"
fog_color = %(fog)s
fog_amount = %(fog_amount)s
grade_tint = %(tint)s
saturation = 1.0
contrast = %(contrast)s
decorations = Array[ExtResource("decor_script")]([%(decos)s])
decor_per_room = %(per_room)s
ore_chance = %(ore_chance)s
ore_item = &"%(ore)s"
""" % dict(music=m["music"], bid=bid, title=title, order=order, ambient=m["ambient"], back_mod=m["back_mod"],
           torch=m["torch"], particles=m["particles"], particle=m["particle"], fog=m["fog"],
           fog_amount=m["fog_amount"], tint=m["tint"], contrast=m["contrast"], per_room=m["per_room"],
           ore_chance=m["ore_chance"], ore=m["ore"],
           decos=", ".join('SubResource("Decor_%s")' % n[0] for n in decor))
    text = '[gd_resource type="Resource" script_class="BiomeData" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1)
    text += "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n" + res
    with open(os.path.join(gb.DATA, bid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main() -> None:
    palettes = {"ashen_halls": ASHEN, "crystal_depths": CRYSTAL}
    os.makedirs(os.path.join(gb.A, "sprites/backgrounds"), exist_ok=True)
    for bid, pal in palettes.items():
        gb.tileset(bid, pal)
        gb.parallax(bid, pal)
    for bid, (title, order, _x, _p, decor, meta) in BIOME_META.items():
        write_tres(bid, title, order, decor, meta)
    print("deep biomes generated")


if __name__ == "__main__":
    main()
